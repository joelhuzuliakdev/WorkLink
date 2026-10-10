/**
 * Detalles de terminación para todo el sitio:
 *
 * 1. Botones con "cargando": al enviar un formulario, el botón que se tocó
 *    muestra una ruedita y el formulario no se puede mandar dos veces
 *    (evita publicaciones o pagos duplicados por tocar dos veces).
 *    Los formularios que maneja JavaScript (me gusta, chat, etc.) cancelan el
 *    envío normal y por eso no se tocan. Para excluir uno: data-no-loading.
 *
 * 2. Barra de progreso arriba al cambiar de página, si tarda más de un
 *    instante (así se nota que el toque funcionó aunque la conexión sea lenta).
 *
 * Al volver con "atrás" (la página sale del caché del navegador) se limpia todo.
 */

const BUSY = "data-loading";

function reset() {
  for (const button of document.querySelectorAll<HTMLElement>(`[${BUSY}]`)) {
    button.removeAttribute(BUSY);
    button.removeAttribute("aria-busy");
  }
  for (const form of document.querySelectorAll<HTMLFormElement>("form[data-submitting]")) {
    delete form.dataset.submitting;
  }
  progress(false);
}

document.addEventListener("submit", (event) => {
  const form = event.target as HTMLFormElement;
  if (!(form instanceof HTMLFormElement) || form.hasAttribute("data-no-loading") || form.method === "dialog") return;

  // Segundo toque mientras se envía: se ignora.
  if (form.dataset.submitting) {
    event.preventDefault();
    return;
  }

  const submitter = (event.submitter as HTMLElement | null) ?? form.querySelector<HTMLElement>("button[type=submit], button:not([type])");
  // Se decide después de que corran los demás manejadores (por si alguno
  // envía con JavaScript y cancela el envío normal).
  setTimeout(() => {
    if (event.defaultPrevented) return;
    form.dataset.submitting = "1";
    if (submitter && !(submitter as HTMLButtonElement).formTarget && form.target !== "_blank") {
      submitter.setAttribute(BUSY, "");
      submitter.setAttribute("aria-busy", "true");
    }
    if (form.target !== "_blank") progress(true);
    // Si por algo la página no cambia (descarga, error de red), se libera.
    setTimeout(reset, 15000);
  }, 0);
});

// --- Barra de progreso -------------------------------------------------------
let bar: HTMLDivElement | null = null;
let timer: number | undefined;

function progress(on: boolean) {
  window.clearTimeout(timer);
  if (!on) {
    bar?.remove();
    bar = null;
    return;
  }
  timer = window.setTimeout(() => {
    if (bar) return;
    bar = document.createElement("div");
    bar.className = "wl-progress";
    bar.setAttribute("aria-hidden", "true");
    document.body.append(bar);
  }, 150);
}

document.addEventListener("click", (event) => {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  const link = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
  if (!link || link.target === "_blank" || link.hasAttribute("download") || link.origin !== location.origin) return;
  // Mismo documento (#ancla) o descarga de archivos de la API: no hay cambio de página.
  if (link.pathname === location.pathname && link.search === location.search) return;
  if (link.pathname.startsWith("/api/")) return;
  setTimeout(() => {
    if (!event.defaultPrevented) progress(true);
  }, 0);
});

window.addEventListener("pageshow", reset);
