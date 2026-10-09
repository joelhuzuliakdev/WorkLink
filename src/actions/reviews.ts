import { ActionError, defineAction } from "astro:actions";
import { replySchema, reportSchema, reviewRefSchema, reviewSchema } from "../schemas/review";
import { dbError, requireUser } from "../lib/auth/guards";

/**
 * Reseñas: escribir/editar, borrar, responder y denunciar. Quién puede hacer
 * cada cosa lo decide la base; acá se traducen sus mensajes.
 */
const fromDb = (error: { code?: string; message?: string; hint?: string | null }, fallback: string) =>
  error.code === "42501" && error.message && !error.message.startsWith("new row") && !error.message.startsWith("permission")
    ? new ActionError({ code: "FORBIDDEN", message: error.message })
    : dbError(error, fallback);

export const reviews = {
  save: defineAction({
    accept: "form",
    input: reviewSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const body = input.body ?? null;
      if (input.review_id) {
        const { data, error } = await locals.supabase
          .from("reviews")
          .update({ rating: input.rating, body })
          .eq("id", input.review_id)
          .select("id");
        if (error) throw fromDb(error, "No pudimos guardar los cambios.");
        if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No podés editar esta reseña." });
        return { id: input.review_id, created: false };
      }
      const { data, error } = await locals.supabase
        .from("reviews")
        .insert({
          business_id: input.subject_type === "business" ? input.subject_id : null,
          profile_id: input.subject_type === "profile" ? input.subject_id : null,
          rating: input.rating,
          body,
        })
        .select("id")
        .single();
      if (error) {
        if (error.code === "23505") throw new ActionError({ code: "CONFLICT", message: "Ya escribiste una reseña. Podés editarla." });
        throw fromDb(error, "No pudimos publicar tu reseña. Probá de nuevo.");
      }
      return { id: (data as { id: string }).id, created: true };
    },
  }),

  remove: defineAction({
    accept: "form",
    input: reviewRefSchema,
    handler: async ({ review_id }, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase.from("reviews").delete().eq("id", review_id).select("id");
      if (error) throw fromDb(error, "No pudimos borrar la reseña.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No podés borrar esta reseña." });
      return { ok: true };
    },
  }),

  reply: defineAction({
    accept: "form",
    input: replySchema,
    handler: async ({ review_id, reply }, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.rpc("reply_review", { p_review_id: review_id, p_reply: reply ?? null });
      if (error) throw fromDb(error, "No pudimos guardar la respuesta.");
      return { id: review_id, removed: !reply };
    },
  }),

  report: defineAction({
    accept: "form",
    input: reportSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.from("reports").insert({
        target_type: input.target_type,
        target_id: input.target_id,
        reason: input.reason,
        details: input.details ?? null,
      });
      if (error) {
        if (error.code === "23505") return { ok: true, already: true };
        throw fromDb(error, "No pudimos enviar la denuncia.");
      }
      return { ok: true, already: false };
    },
  }),
};
