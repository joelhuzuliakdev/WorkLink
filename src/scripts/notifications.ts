/**
 * Campanita: actualiza la cantidad de notificaciones sin leer cada minuto
 * mientras la pestaña está a la vista, y al volver a ella. Una consulta
 * liviana (solo un número); sin conexión, no hace nada.
 */
const INTERVAL = 60_000;
let timer: number | undefined;

const enabled = () => Boolean(document.querySelector("[data-notifications-badge]"));

async function refresh() {
  if (document.visibilityState !== "visible" || !enabled()) return;
  try {
    const res = await fetch("/api/notificaciones", { headers: { Accept: "application/json" } });
    if (!res.ok) return;
    const { unread, messages } = (await res.json()) as { unread: number; messages: number };
    for (const badge of document.querySelectorAll<HTMLElement>("[data-messages-badge]")) {
      badge.textContent = messages > 99 ? "99+" : String(messages);
      badge.hidden = messages === 0;
    }
    for (const badge of document.querySelectorAll<HTMLElement>("[data-notifications-badge]")) {
      badge.textContent = unread > 99 ? "99+" : String(unread);
      badge.hidden = unread === 0;
    }
    for (const link of document.querySelectorAll<HTMLElement>("[data-notifications-link]")) {
      link.setAttribute("aria-label", unread ? `Notificaciones (${unread} sin leer)` : "Notificaciones");
    }
  } catch {
    /* sin conexión: se reintenta en el próximo ciclo */
  }
}

function start() {
  window.clearInterval(timer);
  timer = window.setInterval(refresh, INTERVAL);
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") {
    void refresh();
    start();
  } else {
    window.clearInterval(timer);
  }
});
start();
