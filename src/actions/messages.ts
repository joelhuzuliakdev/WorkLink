import { ActionError, defineAction } from "astro:actions";
import { conversationRefSchema, sendMessageSchema } from "../schemas/message";
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
