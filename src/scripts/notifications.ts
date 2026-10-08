/**
 * Íconos de mensajes y notificaciones del encabezado: consulta cada 10
 * segundos mientras la pestaña está a la vista (y al volver a ella) cuántos
 * hay sin leer. Si llega un mensaje nuevo y no estás en Mensajes, muestra un
 * aviso abajo con un enlace para leerlo.
 * Es una consulta liviana (solo dos números); sin conexión, no hace nada.
 */
const INTERVAL = 10_000;
let timer: number | undefined;
let lastMessages: number | null = null;

const enabled = () => Boolean(document.querySelector("[data-notifications-badge]"));

function setBadges(selector: string, count: number) {
  for (const badge of document.querySelectorAll<HTMLElement>(selector)) {
    badge.textContent = count > 99 ? "99+" : String(count);
    badge.hidden = count === 0;
  }
}

function initialMessages(): number {
  const badge = document.querySelector<HTMLElement>("[data-messages-badge]");
  return badge && !badge.hidden ? Number.parseInt(badge.textContent ?? "0", 10) || 0 : 0;
}

function announce(text: string, href: string) {
  let box = document.getElementById("wl-message-toast") as HTMLAnchorElement | null;
  if (!box) {
    box = document.createElement("a");
    box.id = "wl-message-toast";
    box.setAttribute("role", "status");
    box.className =
      "fixed bottom-4 right-4 z-50 flex max-w-xs items-center gap-3 rounded-wl-lg bg-ink px-4 py-3 text-sm font-semibold text-white shadow-xl";
    document.body.append(box);
  }
  box.href = href;
  box.textContent = text;
  box.hidden = false;
  window.setTimeout(() => box && (box.hidden = true), 6000);
}

async function refresh() {
  if (document.visibilityState !== "visible" || !enabled()) return;
  try {
    const res = await fetch("/api/notificaciones", { headers: { Accept: "application/json" } });
    if (!res.ok) return;
    const { unread, messages } = (await res.json()) as { unread: number; messages: number };
    setBadges("[data-notifications-badge]", unread);
    setBadges("[data-messages-badge]", messages);
    for (const link of document.querySelectorAll<HTMLElement>("[data-notifications-link]")) {
      link.setAttribute("aria-label", unread ? `Notificaciones (${unread} sin leer)` : "Notificaciones");
    }
    if (lastMessages !== null && messages > lastMessages && !location.pathname.startsWith("/mensajes")) {
      announce("💬 Tenés un mensaje nuevo. Tocá para leerlo.", "/mensajes");
    }
    lastMessages = messages;
  } catch {
    /* sin conexión: se reintenta en el próximo ciclo */
  }
}

function start() {
  window.clearInterval(timer);
  timer = window.setInterval(refresh, INTERVAL);
}

if (enabled()) {
  lastMessages = initialMessages();
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      void refresh();
      start();
    } else {
      window.clearInterval(timer);
    }
  });
  window.addEventListener("focus", () => void refresh());
  start();
}
