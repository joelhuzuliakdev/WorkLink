import { ActionError, defineAction } from "astro:actions";
import { conversationRefSchema, sendMessageSchema, sharePostSchema } from "../schemas/message";
import { dbError, requireUser } from "../lib/auth/guards";

/**
 * Mensajes privados. La base controla quién puede escribir (participantes,
 * sin bloqueo, cuenta activa) y los límites; acá se traducen los errores.
 */
export const messages = {
  send: defineAction({
    accept: "form",
    input: sendMessageSchema,
    handler: async ({ conversation_id, body, post_id }, { locals }) => {
      const user = requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from("messages")
        .insert({ conversation_id, sender_id: user.id, body, post_id: post_id ?? null })
        .select("id, sender_id, body, created_at, post:posts ( id, title, body )")
        .single();
      if (error) {
        if (error.code === "42501") {
          throw new ActionError({ code: "FORBIDDEN", message: "No podés escribir en esta conversación." });
        }
        throw dbError(error, "No pudimos enviar el mensaje. Probá de nuevo.");
      }
      return data as unknown as { id: string; sender_id: string; body: string; created_at: string; post: { id: string; title: string | null; body: string } | null };
    },
  }),

  /**
   * Compartir una publicación con personas de WorkLink: abre (o retoma) la
   * conversación con cada una y manda un mensaje con la publicación adjunta.
   * La base controla bloqueos, cuentas suspendidas y límites de mensajes.
   */
  share: defineAction({
    accept: "json",
    input: sharePostSchema,
    handler: async ({ post_id, usernames, note }, { locals }) => {
      const user = requireUser(locals.user);
      const supabase = locals.supabase;
      // Solo publicaciones visibles (RLS).
      const { data: post } = await supabase.from("posts").select("id").eq("id", post_id).eq("status", "published").maybeSingle();
      if (!post) throw new ActionError({ code: "NOT_FOUND", message: "La publicación ya no está disponible." });

      const unique = [...new Set(usernames)];
      const { data: people } = await supabase.from("profiles").select("id, username").in("username", unique);
      const sent: string[] = [];
      const failed: string[] = [];
      for (const username of unique) {
        const person = (people ?? []).find((p) => p.username === username);
        if (!person || person.id === user.id) {
          failed.push(username);
          continue;
        }
        const { data: conversationId, error: startError } = await supabase.rpc("start_conversation", { p_other: person.id });
        if (startError || !conversationId) {
          failed.push(username);
          continue;
        }
        const { error } = await supabase.from("messages").insert({
          conversation_id: conversationId,
          sender_id: user.id,
          body: note || "Te comparto esta publicación 👇",
          post_id,
        });
        if (error) {
          if (error.hint === "rate_limited") throw dbError(error, "Mandaste muchos mensajes. Esperá un rato.");
          failed.push(username);
        } else {
          sent.push(username);
        }
      }
      if (!sent.length) throw new ActionError({ code: "FORBIDDEN", message: "No pudimos enviarla. Puede que esas personas no reciban mensajes tuyos." });
      return { sent, failed };
    },
  }),

    hide: defineAction({
    accept: "form",
    input: conversationRefSchema,
    handler: async ({ conversation_id }, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.rpc("hide_conversation", { p_conversation_id: conversation_id });
      if (error) throw dbError(error, "No pudimos ocultar la conversación.");
      return { ok: true };
    },
  }),
};
