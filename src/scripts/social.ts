/**
 * Botones de me gusta, guardar, seguir y compartir, y el "Ver más" de los
 * textos largos (un solo manejador para toda la página, así también funcionan
 * en las tarjetas que agrega "Cargar más").
 *
 * - Cambia el botón al instante y después confirma con el servidor; si falla,
 *   vuelve al estado anterior y avisa.
 * - Mantiene sincronizados todos los botones de la misma publicación o cuenta
 *   que haya en la página.
 * - Sin sesión, los botones son enlaces a /ingresar (no pasan por acá).
 */
import { actions } from "astro:actions";
import { openShareSheet } from "./share-sheet";

type Kind = "like" | "save" | "follow";

const numberFormat = new Intl.NumberFormat("es-AR");

function selectorFor(button: HTMLElement): string {
  const kind = button.dataset.social as Kind;
  return `button[data-social="${kind}"][data-id="${button.dataset.id}"]`;
}

function render(id: string, kind: Kind, active: boolean, count: number | null) {
  for (const button of document.querySelectorAll<HTMLButtonElement>(`button[data-social="${kind}"][data-id="${id}"]`)) {
    button.setAttribute("aria-pressed", String(active));
    const label = button.querySelector<HTMLElement>("[data-label]");
    if (label) label.textContent = active ? (button.dataset.labelOn ?? "") : (button.dataset.labelOff ?? "");
    const counter = button.querySelector<HTMLElement>("[data-count]");
    if (counter && count !== null) counter.textContent = count > 0 ? numberFormat.format(count) : "";
  }
  if (kind === "like" && count !== null) {
    for (const el of document.querySelectorAll<HTMLElement>(`[data-likes-for="${id}"]`)) el.textContent = numberFormat.format(count);
    for (const el of document.querySelectorAll<HTMLElement>(`[data-likes-wrap="${id}"]`)) el.hidden = count === 0;
  }
  if (kind === "follow" && count !== null) {
    for (const el of document.querySelectorAll<HTMLElement>(`[data-followers="${id}"]`)) {
      el.textContent = `${numberFormat.format(count)} ${count === 1 ? "seguidor" : "seguidores"}`;
    }
  }
}

function currentCount(button: HTMLElement, kind: Kind): number | null {
  if (kind === "follow") {
    const el = document.querySelector<HTMLElement>(`[data-followers="${button.dataset.id}"]`);
    return el ? Number.parseInt(el.textContent!.replace(/\D/g, ""), 10) || 0 : null;
  }
  const counter =
    button.querySelector<HTMLElement>("[data-count]") ??
    (kind === "like" ? document.querySelector<HTMLElement>(`[data-likes-for="${button.dataset.id}"]`) : null);
  return counter ? Number.parseInt(counter.textContent!.replace(/\D/g, ""), 10) || 0 : null;
}

let toastTimer: number | undefined;
function toast(message: string) {
  let el = document.getElementById("wl-toast");
  if (!el) {
    el = document.createElement("div");
    el.id = "wl-toast";
    el.setAttribute("role", "status");
    el.className =
      "fixed inset-x-4 bottom-20 z-50 mx-auto max-w-sm md:bottom-4 rounded-wl bg-ink px-4 py-3 text-center text-sm font-medium text-bg shadow-lg";
    document.body.append(el);
  }
  el.textContent = message;
  el.hidden = false;
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => (el!.hidden = true), 3500);
}

// Compartir: con sesión, ventana para mandarla por mensaje en WorkLink (y copiar
// o WhatsApp). Sin sesión: menú nativo del celular si existe; si no, copia el enlace.
document.addEventListener("click", async (event) => {
  const button = (event.target as HTMLElement).closest<HTMLButtonElement>("button[data-share-url]");
  if (!button) return;
  const url = button.dataset.shareUrl!;
  const title = button.dataset.shareTitle ?? document.title;
  if (button.dataset.shareAuth && button.dataset.sharePostId) {
    openShareSheet({ url, title, postId: button.dataset.sharePostId });
    return;
  }
  try {
    if (navigator.share && matchMedia("(pointer: coarse)").matches) {
      await navigator.share({ title, url });
      return;
    }
    await navigator.clipboard.writeText(url);
    toast("¡Enlace copiado! Ya lo podés pegar donde quieras.");
  } catch {
    /* el usuario canceló */
  }
});

// "Ver más": muestra el botón solo si el texto quedó cortado.
function checkClamps(root: ParentNode = document) {
  for (const text of root.querySelectorAll<HTMLElement>("[data-clamp]:not([data-clamp-checked])")) {
    text.dataset.clampChecked = "1";
    const more = text.parentElement?.querySelector<HTMLElement>("[data-expand]");
    if (more && text.scrollHeight > text.clientHeight + 2) more.hidden = false;
  }
}
checkClamps();
new MutationObserver(() => checkClamps()).observe(document.body, { childList: true, subtree: true });

document.addEventListener("click", (event) => {
  const more = (event.target as HTMLElement).closest<HTMLElement>("[data-expand]");
  if (!more) return;
  const text = more.parentElement?.querySelector<HTMLElement>("[data-clamp]");
  text?.classList.remove("line-clamp-5");
  more.hidden = true;
});

document.addEventListener("click", async (event) => {
  const button = (event.target as HTMLElement).closest<HTMLButtonElement>("button[data-social]");
  if (!button) return;
  event.preventDefault();
  if (button.dataset.busy) return;

  const kind = button.dataset.social as Kind;
  const id = button.dataset.id!;
  const wasActive = button.getAttribute("aria-pressed") === "true";
  const active = !wasActive;
  const before = currentCount(button, kind);

  render(id, kind, active, before === null ? null : Math.max(before + (active ? 1 : -1), 0));
  for (const b of document.querySelectorAll<HTMLElement>(selectorFor(button))) b.dataset.busy = "1";

  try {
    const result =
      kind === "like"
        ? await actions.social.like({ post_id: id, active })
        : kind === "save"
          ? await actions.social.save({ post_id: id, active })
          : await actions.social.follow({ kind: button.dataset.kind as "profile" | "business", id, active });

    if (result.error) {
      render(id, kind, wasActive, before);
      if (result.error.code === "UNAUTHORIZED") {
        window.location.href = `/ingresar?next=${encodeURIComponent(location.pathname + location.search)}`;
        return;
      }
      toast(result.error.message || "No pudimos guardar el cambio. Probá de nuevo.");
      return;
    }

    render(id, kind, result.data.active, result.data.count);
    if (kind === "save") toast(result.data.active ? "Guardada en tu panel → Guardados" : "Quitada de Guardados");
  } catch {
    render(id, kind, wasActive, before);
    toast("Sin conexión. Probá de nuevo.");
  } finally {
    for (const b of document.querySelectorAll<HTMLElement>(selectorFor(button))) delete b.dataset.busy;
  }
});

// Eliminar una publicación propia: confirma, la elimina y la saca de la página.
document.addEventListener("submit", async (event) => {
  const form = (event.target as HTMLElement).closest<HTMLFormElement>("form[data-delete-post]");
  if (!form) return;
  event.preventDefault();
  if (!window.confirm("¿Eliminar esta publicación? No se puede deshacer.")) return;
  const button = form.querySelector<HTMLButtonElement>("button[type=submit]");
  if (button) button.disabled = true;
  try {
    const { error } = await actions.posts.remove(new FormData(form));
    if (error) {
      toast(error.message || "No pudimos eliminar la publicación.");
      if (button) button.disabled = false;
      return;
    }
    if (form.dataset.redirect) {
      window.location.href = form.dataset.redirect;
      return;
    }
    const card = form.closest<HTMLElement>("[data-post-card]");
    card?.remove();
    toast("Eliminaste la publicación.");
  } catch {
    toast("Sin conexión. Probá de nuevo.");
    if (button) button.disabled = false;
  }
});

// Cerrar el menú "⋯" al tocar fuera de él.
document.addEventListener("click", (event) => {
  for (const menu of document.querySelectorAll<HTMLDetailsElement>("details[data-post-menu][open]")) {
    if (!menu.contains(event.target as Node)) menu.open = false;
  }
});
