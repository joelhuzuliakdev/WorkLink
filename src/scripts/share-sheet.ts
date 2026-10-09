/**
 * Ventana "Compartir" de una publicación:
 *  - Enviar por WorkLink: elegís personas (con quienes hablaste, a quienes
 *    seguís, o buscando por nombre) y les llega por mensaje privado con la
 *    publicación adjunta.
 *  - Copiar enlace, WhatsApp y el menú del celular.
 * Todo el contenido de otras personas se inserta como texto (nunca HTML).
 */
import { actions } from "astro:actions";

interface Person {
  username: string;
  name: string;
  avatar: string | null;
  initials: string;
  verified: boolean;
}

interface ShareTarget {
  url: string;
  title: string;
  postId: string;
}

let dialog: HTMLDialogElement | null = null;
let current: ShareTarget | null = null;
const selected = new Map<string, Person>();
let searchTimer: number | undefined;

function el<K extends keyof HTMLElementTagNameMap>(tag: K, className = "", text?: string): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function build(): HTMLDialogElement {
  const d = el(
    "dialog",
    "m-0 mt-auto w-full max-w-none rounded-t-wl-lg border border-line bg-surface p-0 text-ink shadow-2xl backdrop:bg-black/50 sm:m-auto sm:max-w-md sm:rounded-wl-lg",
  );
  d.setAttribute("aria-labelledby", "share-title");
  d.innerHTML = `
    <div class="flex items-center justify-between border-b border-line px-4 py-3">
      <h2 id="share-title" class="text-lg font-bold">Compartir</h2>
      <button type="button" class="grid h-9 w-9 place-items-center rounded-full text-ink-muted hover:bg-surface-muted hover:text-ink" data-share-close aria-label="Cerrar">✕</button>
    </div>
    <div class="flex max-h-[75vh] flex-col overflow-y-auto">
      <section class="px-4 pt-4" aria-labelledby="share-wl">
        <h3 id="share-wl" class="text-sm font-semibold">Enviar por mensaje en WorkLink</h3>
        <label class="sr-only" for="share-search">Buscar personas</label>
        <input id="share-search" type="search" autocomplete="off" placeholder="Buscar por nombre o usuario"
          class="mt-2 h-10 w-full rounded-full border border-line bg-surface-muted px-4 text-base focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25" data-share-search />
        <ul class="mt-2 flex flex-col" data-share-people aria-label="Personas"></ul>
        <p class="py-3 text-center text-sm text-ink-muted" data-share-empty hidden></p>
      </section>
      <section class="sticky bottom-0 border-t border-line bg-surface px-4 py-3" data-share-send-box hidden>
        <label class="sr-only" for="share-note">Mensaje (opcional)</label>
        <textarea id="share-note" rows="2" maxlength="500" placeholder="Escribí algo (opcional)"
          class="w-full resize-none rounded-wl border border-line bg-surface px-3 py-2 text-base focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25" data-share-note></textarea>
        <button type="button" class="mt-2 h-11 w-full rounded-wl bg-brand font-semibold text-brand-contrast hover:bg-brand-hover disabled:opacity-60" data-share-send></button>
      </section>
      <p class="mx-4 mt-3 rounded-wl px-3 py-2 text-sm" data-share-status role="status" hidden></p>
      <section class="px-4 py-4" aria-labelledby="share-other">
        <h3 id="share-other" class="text-sm font-semibold">Otras formas</h3>
        <div class="mt-2 grid grid-cols-3 gap-2 text-sm">
          <button type="button" class="flex flex-col items-center gap-1 rounded-wl border border-line p-3 hover:bg-surface-muted" data-share-copy><span aria-hidden="true" class="text-xl">🔗</span><span>Copiar enlace</span></button>
          <a target="_blank" rel="noopener" class="flex flex-col items-center gap-1 rounded-wl border border-line p-3 hover:bg-surface-muted" data-share-whatsapp><span aria-hidden="true" class="text-xl">🟢</span><span>WhatsApp</span></a>
          <button type="button" class="flex flex-col items-center gap-1 rounded-wl border border-line p-3 hover:bg-surface-muted" data-share-native><span aria-hidden="true" class="text-xl">⋯</span><span>Más</span></button>
        </div>
      </section>
    </div>`;
  document.body.append(d);

  d.querySelector("[data-share-close]")!.addEventListener("click", () => d.close());
  // Tocar el fondo oscuro cierra.
  d.addEventListener("click", (event) => {
    if (event.target === d) d.close();
  });
  d.querySelector<HTMLInputElement>("[data-share-search]")!.addEventListener("input", (event) => {
    window.clearTimeout(searchTimer);
    const q = (event.target as HTMLInputElement).value;
    searchTimer = window.setTimeout(() => void load(q), 250);
  });
  d.querySelector("[data-share-send]")!.addEventListener("click", () => void send());
  d.querySelector("[data-share-copy]")!.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(current!.url);
      status("¡Enlace copiado!", "ok");
    } catch {
      status("No pudimos copiar el enlace.", "error");
    }
  });
  d.querySelector("[data-share-native]")!.addEventListener("click", async () => {
    try {
      await navigator.share({ title: current!.title, url: current!.url });
    } catch {
      /* canceló */
    }
  });
  return d;
}

function status(text: string, tone: "ok" | "error") {
  const box = dialog!.querySelector<HTMLElement>("[data-share-status]")!;
  box.textContent = text;
  box.className = `mx-4 mt-3 rounded-wl px-3 py-2 text-sm ${tone === "ok" ? "bg-success-soft text-success" : "bg-danger-soft text-danger"}`;
  box.hidden = false;
}

function avatar(person: Person) {
  if (person.avatar) {
    const img = el("img", "h-10 w-10 shrink-0 rounded-full object-cover");
    img.src = person.avatar;
    img.alt = "";
    img.loading = "lazy";
    return img;
  }
  return el("span", "grid h-10 w-10 shrink-0 place-items-center rounded-full bg-seek-soft text-sm font-bold text-seek", person.initials);
}

function render(people: Person[], emptyText: string) {
  const list = dialog!.querySelector<HTMLUListElement>("[data-share-people]")!;
  const empty = dialog!.querySelector<HTMLElement>("[data-share-empty]")!;
  // Las elegidas quedan arriba aunque no estén en la búsqueda actual.
  const all = [...selected.values(), ...people.filter((p) => !selected.has(p.username))];
  list.replaceChildren(
    ...all.map((person) => {
      const li = el("li");
      const button = el("button", "flex w-full items-center gap-3 rounded-wl px-2 py-2 text-left hover:bg-surface-muted");
      button.type = "button";
      button.dataset.shareUser = person.username;
      button.setAttribute("aria-pressed", String(selected.has(person.username)));
      const text = el("span", "min-w-0 flex-1");
      const name = el("span", "block truncate font-medium", person.name + (person.verified ? " ✓" : ""));
      const user = el("span", "block truncate text-xs text-ink-muted", `@${person.username}`);
      text.append(name, user);
      const check = el(
        "span",
        `grid h-6 w-6 shrink-0 place-items-center rounded-full border text-xs font-bold ${selected.has(person.username) ? "border-brand bg-brand text-brand-contrast" : "border-line"}`,
        selected.has(person.username) ? "✓" : "",
      );
      check.setAttribute("aria-hidden", "true");
      button.append(avatar(person), text, check);
      button.addEventListener("click", () => {
        if (selected.has(person.username)) selected.delete(person.username);
        else if (selected.size < 10) selected.set(person.username, person);
        render(people, emptyText);
        updateSend();
      });
      li.append(button);
      return li;
    }),
  );
  empty.hidden = all.length > 0;
  empty.textContent = emptyText;
}

function updateSend() {
  const box = dialog!.querySelector<HTMLElement>("[data-share-send-box]")!;
  const button = dialog!.querySelector<HTMLButtonElement>("[data-share-send]")!;
  box.hidden = selected.size === 0;
  const names = [...selected.values()].map((p) => p.name.split(" ")[0]);
  button.textContent = names.length <= 2 ? `Enviar a ${names.join(" y ")}` : `Enviar a ${names[0]} y ${names.length - 1} más`;
}

async function load(q = "") {
  try {
    const res = await fetch(`/api/compartir/contactos?q=${encodeURIComponent(q.trim())}`, { headers: { Accept: "application/json" } });
    if (res.status === 401) {
      window.location.href = `/ingresar?next=${encodeURIComponent(location.pathname)}`;
      return;
    }
    const { people } = (await res.json()) as { people: Person[] };
    render(
      people,
      q.trim().length >= 2 ? "No encontramos a nadie con ese nombre." : "Buscá a alguien por su nombre. Acá también aparecen las personas que seguís y con quienes hablaste.",
    );
  } catch {
    render([], "Sin conexión. Probá de nuevo.");
  }
}

async function send() {
  const button = dialog!.querySelector<HTMLButtonElement>("[data-share-send]")!;
  const note = dialog!.querySelector<HTMLTextAreaElement>("[data-share-note]")!.value;
  button.disabled = true;
  try {
    const { data, error } = await actions.messages.share({ post_id: current!.postId, usernames: [...selected.keys()], note });
    if (error) {
      status(error.message || "No pudimos enviarla.", "error");
      return;
    }
    const names = data.sent.map((u) => selected.get(u)?.name.split(" ")[0] ?? u);
    status(`¡Listo! Se la mandaste a ${names.length <= 2 ? names.join(" y ") : `${names[0]} y ${names.length - 1} más`}.`, "ok");
    selected.clear();
    dialog!.querySelector<HTMLTextAreaElement>("[data-share-note]")!.value = "";
    updateSend();
    void load(dialog!.querySelector<HTMLInputElement>("[data-share-search]")!.value);
    window.dispatchEvent(new Event("wl:refresh-badges"));
  } catch {
    status("Sin conexión. Probá de nuevo.", "error");
  } finally {
    button.disabled = false;
  }
}

export function openShareSheet(target: ShareTarget) {
  dialog ??= build();
  current = target;
  selected.clear();
  dialog.querySelector<HTMLElement>("[data-share-status]")!.hidden = true;
  dialog.querySelector<HTMLInputElement>("[data-share-search]")!.value = "";
  dialog.querySelector<HTMLTextAreaElement>("[data-share-note]")!.value = "";
  dialog.querySelector<HTMLAnchorElement>("[data-share-whatsapp]")!.href = `https://wa.me/?text=${encodeURIComponent(`${target.title} ${target.url}`)}`;
  dialog.querySelector<HTMLElement>("[data-share-native]")!.hidden = !("share" in navigator);
  updateSend();
  render([], "Cargando…");
  dialog.showModal();
  void load();
}
