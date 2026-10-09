/**
 * Lógica compartida de una conversación (la usan la página /mensajes/[id] y
 * la ventanita flotante de la computadora):
 *  - dibuja mensajes (siempre con textContent: nunca como HTML)
 *  - envía sin recargar y trae los nuevos cada pocos segundos
 *  - muestra "Visto" cuando la otra persona leyó el último mensaje propio
 */
import { actions } from "astro:actions";

export interface ChatMessage {
  id: string;
  sender_id: string;
  body: string;
  created_at: string;
  post: { id: string; title: string | null; body: string } | null;
}

const TZ = "America/Argentina/Cordoba";
export const dayKey = (iso: string) =>
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(iso));
export const timeLabel = (iso: string) =>
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, hour: "2-digit", minute: "2-digit" }).format(new Date(iso));

const todayKey = () => dayKey(new Date().toISOString());
const yesterdayKey = () => dayKey(new Date(Date.now() - 86400000).toISOString());
export function dayLabel(iso: string) {
  const key = dayKey(iso);
  if (key === todayKey()) return "Hoy";
  if (key === yesterdayKey()) return "Ayer";
  return new Intl.DateTimeFormat("es-AR", { timeZone: TZ, weekday: "long", day: "numeric", month: "long" }).format(new Date(iso));
}

function slug(text: string) {
  return text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60)
    .replace(/-+$/g, "");
}

export interface ThreadElements {
  list: HTMLOListElement;
  scroller: HTMLElement;
  seen: HTMLElement;
  form: HTMLFormElement;
  textarea: HTMLTextAreaElement;
  sendButton: HTMLButtonElement;
  errorBox: HTMLElement;
  empty?: HTMLElement | null;
}

export class ChatThread {
  private last: string;
  private otherRead: string;
  private lastMineAt = "";
  private timer: number | undefined;
  private polling = false;

  constructor(
    private readonly conversationId: string,
    private readonly me: string,
    private readonly el: ThreadElements,
    opts: { last?: string; otherRead?: string | null; pollMs?: number } = {},
  ) {
    this.last = opts.last || new Date(0).toISOString();
    this.otherRead = opts.otherRead ?? "";
    this.pollMs = opts.pollMs ?? 4000;
    // Mensajes ya dibujados por el servidor.
    for (const li of el.list.querySelectorAll<HTMLElement>("li[data-message][data-mine]")) {
      const at = li.querySelector("time")?.getAttribute("datetime") ?? "";
      if (at > this.lastMineAt) this.lastMineAt = at;
    }
    this.bindForm();
  }

  private readonly pollMs: number;

  get isNearBottom() {
    const s = this.el.scroller;
    return s.scrollHeight - s.scrollTop - s.clientHeight < 120;
  }

  toBottom() {
    this.el.scroller.scrollTop = this.el.scroller.scrollHeight;
  }

  updateSeen() {
    this.el.seen.hidden = !(this.lastMineAt && this.otherRead && this.otherRead >= this.lastMineAt);
  }

  render(message: ChatMessage) {
    const { list } = this.el;
    if (list.querySelector(`[data-message="${message.id}"]`)) return;
    this.el.empty?.remove();

    const days = list.querySelectorAll<HTMLElement>("li[data-day]");
    const key = dayKey(message.created_at);
    if (days[days.length - 1]?.dataset.day !== key) {
      const sep = document.createElement("li");
      sep.className = "my-3 text-center text-xs font-semibold first-letter:uppercase text-ink-muted";
      sep.dataset.day = key;
      sep.textContent = dayLabel(message.created_at);
      list.append(sep);
    }

    const mine = message.sender_id === this.me;
    const li = document.createElement("li");
    li.className = `flex ${mine ? "justify-end" : "justify-start"}`;
    li.dataset.message = message.id;
    if (mine) li.dataset.mine = "";
    const bubble = document.createElement("div");
    bubble.className = `max-w-[78%] rounded-2xl px-3 py-1.5 ${mine ? "rounded-br-md bg-brand text-brand-contrast" : "rounded-bl-md bg-surface-muted text-ink"}`;
    if (message.post) {
      const link = document.createElement("a");
      const words = slug(message.post.title || message.post.body);
      link.href = `/p/${words ? `${words}-` : ""}${message.post.id}`;
      link.className = `mb-1.5 block rounded-wl border px-2.5 py-1.5 text-xs ${mine ? "border-white/30" : "border-line"}`;
      link.append("📎 Publicación: ");
      const strong = document.createElement("strong");
      strong.textContent = (message.post.title || message.post.body).slice(0, 60);
      link.append(strong);
      bubble.append(link);
    }
    const text = document.createElement("p");
    text.className = "whitespace-pre-line break-words";
    text.textContent = message.body;
    const time = document.createElement("time");
    time.dateTime = message.created_at;
    time.className = `mt-0.5 block text-right text-[11px] ${mine ? "opacity-75" : "text-ink-muted"}`;
    time.textContent = timeLabel(message.created_at);
    bubble.append(text, time);
    li.append(bubble);
    list.append(li);

    if (message.created_at > this.last) this.last = message.created_at;
    if (mine && message.created_at > this.lastMineAt) this.lastMineAt = message.created_at;
  }

  private bindForm() {
    const { form, textarea, sendButton, errorBox } = this.el;
    const resize = () => {
      textarea.style.height = "auto";
      textarea.style.height = `${Math.min(textarea.scrollHeight, 128)}px`;
    };
    textarea.addEventListener("input", resize);
    textarea.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && !event.shiftKey && !matchMedia("(pointer: coarse)").matches) {
        event.preventDefault();
        form.requestSubmit();
      }
    });
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (!textarea.value.trim() || sendButton.disabled) return;
      sendButton.disabled = true;
      errorBox.hidden = true;
      try {
        const { data, error } = await actions.messages.send(new FormData(form));
        if (error) {
          errorBox.textContent = error.message || "No pudimos enviar el mensaje.";
          errorBox.hidden = false;
          return;
        }
        this.render(data as ChatMessage);
        textarea.value = "";
        resize();
        // La publicación consultada se cita solo en el primer mensaje.
        form.querySelector("[data-chat-context]")?.remove();
        form.querySelector("[data-chat-error]")?.remove();
        this.updateSeen();
        this.toBottom();
      } catch {
        errorBox.textContent = "Sin conexión. Tu mensaje no se envió: probá de nuevo.";
        errorBox.hidden = false;
      } finally {
        sendButton.disabled = false;
        textarea.focus();
      }
    });
  }

  async poll() {
    if (this.polling || document.visibilityState !== "visible") return;
    this.polling = true;
    try {
      const res = await fetch(`/api/mensajes/${this.conversationId}?despues=${encodeURIComponent(this.last)}`, {
        headers: { Accept: "application/json" },
      });
      if (res.ok) {
        const json = (await res.json()) as { messages: ChatMessage[]; otherLastReadAt: string | null };
        const stick = this.isNearBottom;
        for (const message of json.messages) this.render(message);
        this.otherRead = json.otherLastReadAt ?? this.otherRead;
        this.updateSeen();
        if (json.messages.length && stick) this.toBottom();
      }
    } catch {
      /* sin conexión: se reintenta */
    } finally {
      this.polling = false;
    }
  }

  start() {
    this.stop();
    this.timer = window.setInterval(() => void this.poll(), this.pollMs);
  }

  stop() {
    window.clearInterval(this.timer);
  }
}
