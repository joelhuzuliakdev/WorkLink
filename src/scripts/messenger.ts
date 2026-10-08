/**
 * Mensajes estilo Facebook en la computadora (pantallas de 768 px o más):
 *  - el ícono de mensajes abre un panel "Chats" con buscador y la bandeja
 *  - cada conversación se abre en una ventanita abajo a la derecha, encima de
 *    la página, con botones para minimizar (−) y cerrar (✕)
 *  - la ventanita sigue abierta al pasar a otra página (se recuerda en la pestaña)
 *  - "Mensaje" / "Enviar mensaje" en perfiles y publicaciones la abren directo
 * En el celular no se usa: el ícono lleva a /mensajes (pantalla completa).
 * Los textos se insertan siempre con textContent: nunca como HTML.
 */
import { ChatThread, type ChatMessage } from "./chat-core";

const desktop = matchMedia("(min-width: 768px)");
const STORE = "wl-chat";
const MAX_LEN = 2000;

interface ConversationItem {
  id: string;
  name: string;
  username: string | null;
  avatar: string | null;
  verified: boolean;
  preview: string;
  mine: boolean;
  when: string;
  unread: boolean;
  unreadCount: number;
}

interface OpenData {
  me: string;
  other: { name: string; username: string; avatar: string | null; verified: boolean; headline: string | null } | null;
  messages: ChatMessage[];
  otherLastReadAt: string | null;
}

const el = <K extends keyof HTMLElementTagNameMap>(tag: K, className = "", text?: string) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

function avatar(name: string, url: string | null, size: number) {
  if (url) {
    const img = el("img", "shrink-0 rounded-full object-cover");
    img.src = url;
    img.alt = "";
    img.width = size;
    img.height = size;
    img.style.width = img.style.height = `${size}px`;
    return img;
  }
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() ?? "")
    .join("");
  const span = el("span", "grid shrink-0 place-items-center rounded-full bg-seek-soft font-bold text-seek", initials || "?");
  span.style.width = span.style.height = `${size}px`;
  span.style.fontSize = `${Math.round(size * 0.38)}px`;
  return span;
}

const verifiedIcon = () => {
  const span = el("span", "inline-flex shrink-0 text-seek");
  span.title = "Cuenta verificada por WorkLink";
  span.innerHTML =
    '<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path fill="currentColor" d="M12 1.5l2.6 1.9 3.2-.1 1 3.1 2.6 1.9-1 3.1 1 3.1-2.6 1.9-1 3.1-3.2-.1L12 22.5l-2.6-1.9-3.2.1-1-3.1-2.6-1.9 1-3.1-1-3.1 2.6-1.9 1-3.1 3.2.1L12 1.5Z"/><path fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="m8 12.2 2.7 2.7L16.2 9.4"/></svg>';
  return span;
};

const iconButton = (label: string, svg: string) => {
  const b = el("button", "grid h-8 w-8 place-items-center rounded-full text-ink-muted hover:bg-surface-muted hover:text-ink");
  b.type = "button";
  b.setAttribute("aria-label", label);
  b.title = label;
  b.innerHTML = svg;
  return b;
};

const ICON_CLOSE = '<svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-current stroke-2" aria-hidden="true"><path stroke-linecap="round" d="M6 6l12 12M18 6 6 18"/></svg>';
const ICON_MIN = '<svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-current stroke-2" aria-hidden="true"><path stroke-linecap="round" d="M6 12h12"/></svg>';
const ICON_EXPAND = '<svg viewBox="0 0 24 24" class="h-[18px] w-[18px] fill-none stroke-current stroke-2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M14 4h6v6M20 4l-7 7M10 20H4v-6M4 20l7-7"/></svg>';
const ICON_SEND = '<svg viewBox="0 0 24 24" class="h-5 w-5 fill-current" aria-hidden="true"><path d="M3.4 20.4 21 12 3.4 3.6 3.4 10l12.6 2-12.6 2z"/></svg>';

// ---------------------------------------------------------------------------
// Panel "Chats"
// ---------------------------------------------------------------------------
let panel: HTMLElement | null = null;

function closePanel() {
  panel?.remove();
  panel = null;
}

async function openPanel() {
  closePanel();
  panel = el("section", "fixed right-4 top-[4.25rem] z-40 flex max-h-[calc(100dvh-5.5rem)] w-[360px] flex-col overflow-hidden rounded-wl-lg border border-line bg-surface shadow-2xl");
  panel.setAttribute("role", "dialog");
  panel.setAttribute("aria-label", "Chats");

  const head = el("div", "flex items-center justify-between px-4 pb-2 pt-3");
  head.append(el("h2", "text-xl font-bold", "Chats"));
  const expand = el("a", "grid h-8 w-8 place-items-center rounded-full text-ink-muted hover:bg-surface-muted hover:text-ink");
  expand.href = "/mensajes";
  expand.title = "Abrir Mensajes";
  expand.setAttribute("aria-label", "Abrir Mensajes en pantalla completa");
  expand.innerHTML = ICON_EXPAND;
  head.append(expand);

  const searchWrap = el("div", "px-4 pb-2");
  const search = el("input", "h-9 w-full rounded-full border border-line bg-surface-muted px-4 text-sm focus:border-brand focus:outline-none");
  search.type = "search";
  search.placeholder = "Buscar en Mensajes";
  search.setAttribute("aria-label", "Buscar conversación");
  searchWrap.append(search);

  const list = el("ul", "flex-1 overflow-y-auto px-2 pb-2");
  list.append(el("li", "px-3 py-6 text-center text-sm text-ink-muted", "Cargando…"));

  const foot = el("a", "block border-t border-line py-2.5 text-center text-sm font-semibold text-brand hover:bg-surface-muted", "Ver todo en Mensajes");
  foot.href = "/mensajes";

  panel.append(head, searchWrap, list, foot);
  document.body.append(panel);
  search.focus();

  try {
    const res = await fetch("/api/conversaciones", { headers: { Accept: "application/json" } });
    if (!res.ok) throw new Error();
    const { conversations } = (await res.json()) as { conversations: ConversationItem[] };
    list.replaceChildren();
    if (!conversations.length) {
      list.append(el("li", "px-3 py-6 text-center text-sm text-ink-muted", "Todavía no tenés mensajes. Escribile a alguien desde su perfil."));
      return;
    }
    for (const c of conversations) {
      const li = el("li");
      li.dataset.name = c.name.toLowerCase();
      const button = el("button", `flex w-full items-center gap-3 rounded-wl p-2 text-left hover:bg-surface-muted ${c.unread ? "" : ""}`);
      button.type = "button";
      const textBox = el("span", "min-w-0 flex-1");
      const nameRow = el("span", `flex items-center gap-1 ${c.unread ? "font-bold" : "font-semibold"}`);
      nameRow.append(el("span", "truncate", c.name));
      if (c.verified) nameRow.append(verifiedIcon());
      const preview = el("span", `flex gap-1 text-sm ${c.unread ? "font-semibold text-ink" : "text-ink-muted"}`);
      const summary = c.unreadCount > 1 ? `${c.unreadCount > 99 ? "+99" : c.unreadCount} mensajes nuevos` : `${c.mine ? "Vos: " : ""}${c.preview}`;
      preview.append(el("span", "truncate", summary), el("span", "shrink-0", `· ${c.when}`));
      textBox.append(nameRow, preview);
      button.append(avatar(c.name, c.avatar, 52), textBox);
      if (c.unreadCount > 0) {
        const count = el("span", "grid h-5 min-w-5 shrink-0 place-items-center rounded-full bg-brand px-1.5 text-[11px] font-bold text-brand-contrast", c.unreadCount > 99 ? "99+" : String(c.unreadCount));
        count.setAttribute("aria-label", `${c.unreadCount} sin leer`);
        button.append(count);
      }
      button.addEventListener("click", () => {
        closePanel();
        void openChat(c.id);
      });
      li.append(button);
      list.append(li);
    }
    search.addEventListener("input", () => {
      const term = search.value.trim().toLowerCase();
      for (const li of list.querySelectorAll<HTMLElement>("li[data-name]")) li.hidden = Boolean(term) && !li.dataset.name!.includes(term);
    });
  } catch {
    list.replaceChildren(el("li", "px-3 py-6 text-center text-sm text-ink-muted", "No pudimos cargar tus mensajes. Probá de nuevo."));
  }
}

// ---------------------------------------------------------------------------
// Ventanita de conversación
// ---------------------------------------------------------------------------
let win: HTMLElement | null = null;
let thread: ChatThread | null = null;

function remember(id: string | null, minimized = false) {
  try {
    if (id) sessionStorage.setItem(STORE, JSON.stringify({ id, minimized }));
    else sessionStorage.removeItem(STORE);
  } catch {
    /* almacenamiento no disponible: no se recuerda */
  }
}

function closeChat() {
  thread?.stop();
  thread = null;
  win?.remove();
  win = null;
  remember(null);
}

async function openChat(id: string, opts: { minimized?: boolean; post?: { id: string; title: string } | null } = {}) {
  closeChat();
  let data: OpenData;
  try {
    const res = await fetch(`/api/mensajes/${id}?ultimos=1`, { headers: { Accept: "application/json" } });
    if (!res.ok) throw new Error();
    data = (await res.json()) as OpenData;
  } catch {
    remember(null);
    window.location.href = `/mensajes/${id}`;
    return;
  }

  const name = data.other?.name ?? "Usuario";
  win = el("section", "fixed bottom-0 right-6 z-40 flex w-[330px] flex-col overflow-hidden rounded-t-xl border border-b-0 border-line bg-surface shadow-2xl");
  win.setAttribute("role", "dialog");
  win.setAttribute("aria-label", `Conversación con ${name}`);
  win.dataset.conversation = id;

  // Encabezado
  const head = el("div", "flex items-center gap-1 border-b border-line px-2 py-1.5");
  const who = el("a", "flex min-w-0 flex-1 items-center gap-2 rounded-wl p-1 hover:bg-surface-muted");
  who.href = data.other ? `/u/${data.other.username}` : "#";
  const nameBox = el("span", "min-w-0");
  const nameRow = el("span", "flex items-center gap-1 text-sm font-semibold");
  nameRow.append(el("span", "truncate", name));
  if (data.other?.verified) nameRow.append(verifiedIcon());
  nameBox.append(nameRow);
  if (data.other?.headline) nameBox.append(el("span", "block truncate text-xs text-ink-muted", data.other.headline));
  who.append(avatar(name, data.other?.avatar ?? null, 32), nameBox);
  const minimize = iconButton("Minimizar", ICON_MIN);
  const close = iconButton("Cerrar", ICON_CLOSE);
  head.append(who, minimize, close);

  // Cuerpo
  const body = el("div", "flex h-[400px] flex-col");
  const scroller = el("div", "flex-1 overflow-y-auto px-3 py-2 text-[15px]");
  const list = el("ol", "flex flex-col gap-1.5");
  const empty = data.messages.length ? null : el("p", "mt-8 text-center text-sm text-ink-muted", `Escribile a ${name}. Los mensajes son privados.`);
  const seen = el("p", "mt-1 text-right text-xs text-ink-muted", "Visto");
  seen.hidden = true;
  if (empty) scroller.append(empty);
  scroller.append(list, seen);

  const form = el("form", "border-t border-line p-2");
  const hidden = el("input");
  hidden.type = "hidden";
  hidden.name = "conversation_id";
  hidden.value = id;
  form.append(hidden);
  if (opts.post) {
    const context = el("div", "mb-1.5 truncate rounded-wl bg-surface-muted px-2.5 py-1.5 text-xs");
    context.dataset.chatContext = "";
    context.append("Consulta sobre: ", el("strong", "", opts.post.title));
    const postInput = el("input");
    postInput.type = "hidden";
    postInput.name = "post_id";
    postInput.value = opts.post.id;
    context.append(postInput);
    form.append(context);
  }
  const errorBox = el("p", "mb-1.5 text-xs text-danger");
  errorBox.setAttribute("role", "alert");
  errorBox.hidden = true;
  const row = el("div", "flex items-end gap-2");
  const textarea = el("textarea", "max-h-32 min-h-9 flex-1 resize-none rounded-2xl border border-line bg-surface-muted px-3 py-1.5 text-sm focus:border-brand focus:outline-none");
  textarea.name = "body";
  textarea.rows = 1;
  textarea.maxLength = MAX_LEN;
  textarea.placeholder = "Aa";
  textarea.setAttribute("aria-label", "Mensaje");
  const send = el("button", "grid h-9 w-9 shrink-0 place-items-center rounded-full bg-brand text-brand-contrast hover:bg-brand-hover disabled:opacity-50");
  send.type = "submit";
  send.setAttribute("aria-label", "Enviar");
  send.innerHTML = ICON_SEND;
  row.append(textarea, send);
  form.append(errorBox, row);
  body.append(scroller, form);

  win.append(head, body);
  document.body.append(win);

  thread = new ChatThread(id, data.me, { list, scroller, seen, form, textarea, sendButton: send, errorBox, empty }, { otherRead: data.otherLastReadAt });
  for (const m of data.messages) thread.render(m);
  thread.updateSeen();
  thread.toBottom();
  thread.start();
  // Al abrirla queda leída: actualizar los íconos del encabezado ya.
  window.dispatchEvent(new Event("wl:refresh-badges"));

  const setMinimized = (value: boolean) => {
    body.hidden = value;
    if (value) win!.dataset.minimized = "";
    else delete win!.dataset.minimized;
    minimize.setAttribute("aria-label", value ? "Abrir" : "Minimizar");
    minimize.title = value ? "Abrir" : "Minimizar";
    remember(id, value);
    if (value) thread?.stop();
    else {
      thread?.start();
      void thread?.poll();
      thread?.toBottom();
      textarea.focus();
    }
  };
  minimize.addEventListener("click", () => setMinimized(!body.hidden));
  close.addEventListener("click", closeChat);
  setMinimized(Boolean(opts.minimized));
}

// ---------------------------------------------------------------------------
// Conexión con la página
// ---------------------------------------------------------------------------
const onMessagesPage = () => location.pathname.startsWith("/mensajes");

document.addEventListener("click", async (event) => {
  if (!desktop.matches || event.metaKey || event.ctrlKey || event.shiftKey) return;
  const target = event.target as HTMLElement;

  const toggle = target.closest<HTMLAnchorElement>("[data-messages-toggle]");
  if (toggle && !onMessagesPage()) {
    event.preventDefault();
    if (panel) closePanel();
    else void openPanel();
    return;
  }

  const starter = target.closest<HTMLAnchorElement>("[data-open-chat]");
  if (starter && !onMessagesPage()) {
    event.preventDefault();
    try {
      const res = await fetch("/api/conversaciones", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ username: starter.dataset.openChat }),
      });
      if (res.status === 401) {
        window.location.href = starter.href;
        return;
      }
      const json = (await res.json()) as { id?: string; error?: string };
      if (!json.id) throw new Error(json.error);
      const post = starter.dataset.postId ? { id: starter.dataset.postId, title: starter.dataset.postTitle ?? "esta publicación" } : null;
      await openChat(json.id, { post });
    } catch {
      window.location.href = starter.href;
    }
    return;
  }

  if (panel && !panel.contains(target)) closePanel();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closePanel();
});

// El aviso de mensaje nuevo abre la conversación en la ventanita.
window.addEventListener("wl:open-chat", (event) => {
  const id = (event as CustomEvent<{ id?: string }>).detail?.id;
  if (id && desktop.matches) void openChat(id);
});

// Al cambiar de página, la ventanita se vuelve a abrir como estaba.
if (desktop.matches && !onMessagesPage()) {
  try {
    const saved = JSON.parse(sessionStorage.getItem(STORE) ?? "null") as { id: string; minimized: boolean } | null;
    if (saved?.id) void openChat(saved.id, { minimized: saved.minimized });
  } catch {
    /* nada guardado */
  }
}
