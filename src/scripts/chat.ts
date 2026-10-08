/**
 * Pantalla de conversación:
 *  - envía sin recargar (y si algo falla, deja el texto para reintentar)
 *  - trae los mensajes nuevos cada 4 segundos mientras la pestaña está a la vista
 *  - muestra "Visto" cuando la otra persona leyó el último mensaje propio
 *  - Enter envía en computadora (Shift+Enter hace un salto de línea)
 * Los textos se insertan con textContent: nunca como HTML.
 */
import { actions } from "astro:actions";

interface ChatMessage {
  id: string;
  sender_id: string;
  body: string;
  created_at: string;
  post: { id: string; title: string | null; body: string } | null;
}

const TZ = "America/Argentina/Cordoba";
const POLL_MS = 4000;
const dayKey = (iso: string) =>
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(iso));
const timeLabel = (iso: string) => new Intl.DateTimeFormat("es-AR", { timeZone: TZ, hour: "2-digit", minute: "2-digit" }).format(new Date(iso));

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

const root = document.querySelector<HTMLElement>("[data-chat]");
if (root) {
  const conversationId = root.dataset.conversation!;
  const me = root.dataset.me!;
  const list = root.querySelector<HTMLOListElement>("[data-chat-list]")!;
  const scroller = root.querySelector<HTMLElement>("[data-chat-scroll]")!;
  const form = root.querySelector<HTMLFormElement>("[data-chat-form]")!;
  const textarea = form.querySelector<HTMLTextAreaElement>("textarea")!;
  const sendButton = form.querySelector<HTMLButtonElement>("button[type=submit]")!;
  const seen = root.querySelector<HTMLElement>("[data-chat-seen]")!;
  const errorBox = root.querySelector<HTMLElement>("[data-chat-error-js]")!;
  let last = root.dataset.last!;
  let otherRead = root.dataset.otherRead || "";
  let lastMineAt = [...list.querySelectorAll<HTMLElement>("li[data-message]")]
    .filter((li) => li.classList.contains("justify-end"))
    .map((li) => li.querySelector("time")?.getAttribute("datetime") ?? "")
    .pop() ?? "";

  const nearBottom = () => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 120;
  const toBottom = () => (scroller.scrollTop = scroller.scrollHeight);
  toBottom();

  const updateSeen = () => {
    seen.hidden = !(lastMineAt && otherRead && otherRead >= lastMineAt);
  };

  function render(message: ChatMessage) {
    if (list.querySelector(`[data-message="${message.id}"]`)) return;
    root!.querySelector("[data-chat-empty]")?.remove();

    const days = list.querySelectorAll<HTMLElement>("li[data-day]");
    const lastDay = days[days.length - 1]?.dataset.day;
    const key = dayKey(message.created_at);
    if (lastDay !== key) {
      const sep = document.createElement("li");
      sep.className = "my-3 text-center text-xs font-semibold text-ink-muted";
      sep.dataset.day = key;
      sep.textContent = "Hoy";
      list.append(sep);
    }

    const mine = message.sender_id === me;
    const li = document.createElement("li");
    li.className = `flex ${mine ? "justify-end" : "justify-start"}`;
    li.dataset.message = message.id;
    const bubble = document.createElement("div");
    bubble.className = `max-w-[80%] rounded-2xl px-3.5 py-2 ${mine ? "rounded-br-md bg-brand text-brand-contrast" : "rounded-bl-md bg-surface-muted text-ink"}`;
    if (message.post) {
      const link = document.createElement("a");
      const words = slug(message.post.title || message.post.body);
      link.href = `/p/${words ? `${words}-` : ""}${message.post.id}`;
      link.className = `mb-1.5 block rounded-wl border px-2.5 py-1.5 text-xs ${mine ? "border-white/30" : "border-line"}`;
      link.append("Consulta sobre: ");
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

    if (message.created_at > last) last = message.created_at;
    if (mine && message.created_at > lastMineAt) lastMineAt = message.created_at;
  }

  // Altura automática del cuadro de texto.
  const resize = () => {
    textarea.style.height = "auto";
    textarea.style.height = `${Math.min(textarea.scrollHeight, 160)}px`;
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
    const body = textarea.value.trim();
    if (!body || sendButton.disabled) return;
    sendButton.disabled = true;
    errorBox.classList.add("hidden");
    try {
      const { data, error } = await actions.messages.send(new FormData(form));
      if (error) {
        errorBox.textContent = error.message || "No pudimos enviar el mensaje.";
        errorBox.classList.remove("hidden");
        return;
      }
      render(data as ChatMessage);
      textarea.value = "";
      resize();
      // La publicación consultada se cita solo en el primer mensaje.
      form.querySelector("[data-chat-context]")?.remove();
      form.querySelector("[data-chat-error]")?.remove();
      updateSeen();
      toBottom();
    } catch {
      errorBox.textContent = "Sin conexión. Tu mensaje no se envió: probá de nuevo.";
      errorBox.classList.remove("hidden");
    } finally {
      sendButton.disabled = false;
      textarea.focus();
    }
  });

  let polling = false;
  async function poll() {
    if (polling || document.visibilityState !== "visible") return;
    polling = true;
    try {
      const res = await fetch(`/api/mensajes/${conversationId}?despues=${encodeURIComponent(last)}`, { headers: { Accept: "application/json" } });
      if (res.ok) {
        const json = (await res.json()) as { messages: ChatMessage[]; otherLastReadAt: string | null };
        const stick = nearBottom();
        for (const message of json.messages) render(message);
        otherRead = json.otherLastReadAt ?? otherRead;
        updateSeen();
        if (json.messages.length && stick) toBottom();
      }
    } catch {
      /* sin conexión: se reintenta */
    } finally {
      polling = false;
    }
  }
  setInterval(poll, POLL_MS);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") void poll();
  });

  // Confirmación para "Ocultar".
  for (const confirmForm of root.querySelectorAll<HTMLFormElement>("form[data-confirm]")) {
    confirmForm.addEventListener("submit", (event) => {
      if (!window.confirm(confirmForm.dataset.confirm ?? "¿Confirmás?")) event.preventDefault();
    });
  }
}
