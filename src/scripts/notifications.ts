/**
 * Íconos de mensajes y notificaciones del encabezado: consulta cada 10
 * segundos mientras la pestaña está a la vista (y al volver a ella) cuántos
 * hay sin leer. Si llega un mensaje nuevo, muestra un aviso abajo a la derecha
 * con quién lo mandó y el texto; al tocarlo se abre la conversación.
 * Es una consulta liviana; sin conexión, no hace nada.
 *
 * Con la pestaña en segundo plano sigue consultando (más espaciado) para
 * sonar y mostrar "(2) WorkLink" en el título cuando llega algo nuevo.
 */
import { playChime } from "./sound";

const INTERVAL = 10_000;
const BACKGROUND_INTERVAL = 30_000;
let lastUnread: number | null = null;
let lastMessages: number | null = null;
const baseTitle = document.title.replace(/^\(\d+\+?\) /, "");
let timer: number | undefined;
let lastSeenAt: string | null = null;
let primed = false;

interface Latest {
  conversationId: string;
  name: string;
  body: string;
  at: string;
}

const enabled = () => Boolean(document.querySelector("[data-notifications-badge]"));

function setBadges(selector: string, count: number) {
  for (const badge of document.querySelectorAll<HTMLElement>(selector)) {
    badge.textContent = count > 99 ? "99+" : String(count);
    badge.hidden = count === 0;
  }
}

/** ¿Ya está mirando esa conversación (página o ventanita)? */
const isViewing = (id: string) =>
  location.pathname === `/mensajes/${id}` || Boolean(document.querySelector(`section[data-conversation="${id}"]:not([data-minimized])`));

let hideTimer: number | undefined;
function announce(latest: Latest) {
  let box = document.getElementById("wl-message-toast") as HTMLAnchorElement | null;
  if (!box) {
    box = document.createElement("a");
    box.id = "wl-message-toast";
    box.setAttribute("role", "status");
    box.className =
      "fixed bottom-20 left-4 right-4 z-50 flex items-start gap-3 md:bottom-4 rounded-wl-lg border border-line bg-surface p-3 text-ink shadow-2xl sm:left-auto sm:w-80";
    document.body.append(box);
  }
  box.href = `/mensajes/${latest.conversationId}`;
  box.dataset.conversation = latest.conversationId;
  const icon = document.createElement("span");
  icon.className = "grid h-9 w-9 shrink-0 place-items-center rounded-full bg-brand text-brand-contrast";
  icon.setAttribute("aria-hidden", "true");
  icon.textContent = "💬";
  const text = document.createElement("span");
  text.className = "min-w-0 flex-1";
  const title = document.createElement("strong");
  title.className = "block truncate text-sm";
  title.textContent = latest.name;
  const body = document.createElement("span");
  body.className = "line-clamp-2 block text-sm text-ink-muted";
  body.textContent = latest.body;
  text.append(title, body);
  box.replaceChildren(icon, text);
  box.hidden = false;
  window.clearTimeout(hideTimer);
  hideTimer = window.setTimeout(() => box && (box.hidden = true), 7000);
}

// En la computadora, tocar el aviso abre la ventanita en vez de cambiar de página.
document.addEventListener("click", (event) => {
  const box = (event.target as HTMLElement).closest<HTMLAnchorElement>("#wl-message-toast");
  if (!box) return;
  box.hidden = true;
  if (matchMedia("(min-width: 768px)").matches && !location.pathname.startsWith("/mensajes")) {
    event.preventDefault();
    window.dispatchEvent(new CustomEvent("wl:open-chat", { detail: { id: box.dataset.conversation } }));
  }
});

function setTitle(total: number) {
  document.title = total > 0 ? `(${total > 99 ? "99+" : total}) ${baseTitle}` : baseTitle;
}

async function refresh() {
  if (!enabled()) return;
  try {
    const res = await fetch("/api/notificaciones", { headers: { Accept: "application/json" } });
    if (!res.ok) return;
    const { unread, messages, latest } = (await res.json()) as { unread: number; messages: number; latest: Latest | null };
    setBadges("[data-notifications-badge]", unread);
    setBadges("[data-messages-badge]", messages);
    for (const link of document.querySelectorAll<HTMLElement>("[data-notifications-link]")) {
      link.setAttribute("aria-label", unread ? `Notificaciones (${unread} sin leer)` : "Notificaciones");
    }
    setTitle(unread + messages);
    // Aviso (y sonido) solo para lo que llegó después de abrir la página.
    const newMessage = Boolean(latest && primed && (!lastSeenAt || latest.at > lastSeenAt) && !isViewing(latest.conversationId));
    if (newMessage && latest) {
      if (document.visibilityState === "visible") announce(latest);
      playChime("message");
    } else if (primed && lastUnread !== null && unread > lastUnread) {
      playChime("notification");
    } else if (primed && lastMessages !== null && messages > lastMessages && !newMessage) {
      playChime("message");
    }
    lastUnread = unread;
    lastMessages = messages;
    if (latest && (!lastSeenAt || latest.at > lastSeenAt)) lastSeenAt = latest.at;
    if (!lastSeenAt) lastSeenAt = new Date().toISOString();
    primed = true;
  } catch {
    /* sin conexión: se reintenta en el próximo ciclo */
  }
}

function start() {
  window.clearInterval(timer);
  timer = window.setInterval(refresh, document.visibilityState === "visible" ? INTERVAL : BACKGROUND_INTERVAL);
}

if (enabled()) {
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") void refresh();
    start();
  });
  window.addEventListener("focus", () => void refresh());
  window.addEventListener("wl:refresh-badges", () => void refresh());
  void refresh();
  start();
}
