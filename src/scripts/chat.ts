/**
 * Página de conversación (/mensajes/[id]). La lógica de mensajes está en
 * chat-core.ts (compartida con la ventanita flotante de la computadora).
 */
import { ChatThread } from "./chat-core";

const root = document.querySelector<HTMLElement>("[data-chat]");
if (root) {
  const conversationId = root.dataset.conversation!;
  const form = root.querySelector<HTMLFormElement>("[data-chat-form]")!;
  const thread = new ChatThread(
    conversationId,
    root.dataset.me!,
    {
      list: root.querySelector<HTMLOListElement>("[data-chat-list]")!,
      scroller: root.querySelector<HTMLElement>("[data-chat-scroll]")!,
      seen: root.querySelector<HTMLElement>("[data-chat-seen]")!,
      form,
      textarea: form.querySelector<HTMLTextAreaElement>("textarea")!,
      sendButton: form.querySelector<HTMLButtonElement>("button[type=submit]")!,
      errorBox: root.querySelector<HTMLElement>("[data-chat-error-js]")!,
      empty: root.querySelector<HTMLElement>("[data-chat-empty]"),
    },
    { last: root.dataset.last, otherRead: root.dataset.otherRead },
  );
  thread.toBottom();
  thread.start();
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") void thread.poll();
  });

  // Cerrar (✕): volver a la página anterior si vino de WorkLink; si no, a la bandeja.
  const close = root.querySelector<HTMLAnchorElement>("[data-chat-close]");
  close?.addEventListener("click", (event) => {
    const cameFromSite = document.referrer.startsWith(location.origin) && !document.referrer.includes(`/mensajes/${conversationId}`);
    if (cameFromSite && history.length > 1) {
      event.preventDefault();
      history.back();
    }
  });
  const textarea = form.querySelector<HTMLTextAreaElement>("textarea")!;
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !textarea.value.trim()) close?.click();
  });

  // Confirmación para "Ocultar".
  for (const confirmForm of root.querySelectorAll<HTMLFormElement>("form[data-confirm]")) {
    confirmForm.addEventListener("submit", (event) => {
      if (!window.confirm(confirmForm.dataset.confirm ?? "¿Confirmás?")) event.preventDefault();
    });
  }
}
