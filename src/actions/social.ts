import { ActionError, defineAction } from "astro:actions";
import type { SupabaseClient } from "@supabase/supabase-js";
import { commentRefSchema, commentSchema, followSchema, reactionSchema } from "../schemas/social";
import { dbError, requireUser } from "../lib/auth/guards";

/**
 * Interacción social. Me gusta, guardar y seguir reciben el estado deseado
 * (active: true/false) en vez de "alternar": si el pedido se repite por una
 * red lenta o un doble toque, el resultado es el mismo.
 *
 * Los permisos (publicación visible, bloqueos, cuenta activa) y los
 * contadores los resuelve la base con RLS y triggers.
 */

const isDuplicate = (error: { code?: string }) => error.code === "23505";

async function setRow(
  supabase: SupabaseClient,
  table: string,
  row: Record<string, string>,
  active: boolean,
  messages: { forbidden: string; fallback: string },
) {
  if (active) {
    const { error } = await supabase.from(table).insert(row);
    if (error && !isDuplicate(error)) {
      if (error.code === "42501") throw new ActionError({ code: "FORBIDDEN", message: messages.forbidden });
      throw dbError(error, messages.fallback);
    }
  } else {
    let query = supabase.from(table).delete();
    for (const [column, value] of Object.entries(row)) query = query.eq(column, value);
    const { error } = await query;
    if (error) throw dbError(error, messages.fallback);
  }
}

async function postCounters(supabase: SupabaseClient, postId: string) {
  const { data } = await supabase.from("posts").select("likes_count, saves_count").eq("id", postId).maybeSingle();
  return data ?? { likes_count: 0, saves_count: 0 };
}

export const social = {
  like: defineAction({
    input: reactionSchema,
    handler: async ({ post_id, active }, context) => {
      const user = requireUser(context.locals.user);
      await setRow(context.locals.supabase, "post_likes", { post_id, user_id: user.id }, active, {
        forbidden: "No podés reaccionar a esta publicación.",
        fallback: "No pudimos guardar tu me gusta.",
      });
      const counters = await postCounters(context.locals.supabase, post_id);
      return { active, count: counters.likes_count };
    },
  }),

  save: defineAction({
    input: reactionSchema,
    handler: async ({ post_id, active }, context) => {
      const user = requireUser(context.locals.user);
      await setRow(context.locals.supabase, "post_saves", { post_id, user_id: user.id }, active, {
        forbidden: "No podés guardar esta publicación.",
        fallback: "No pudimos guardar la publicación.",
      });
      const counters = await postCounters(context.locals.supabase, post_id);
      return { active, count: counters.saves_count };
    },
  }),

  follow: defineAction({
    input: followSchema,
    handler: async ({ kind, id, active }, context) => {
      const user = requireUser(context.locals.user);
      const { supabase } = context.locals;
      if (kind === "profile" && id === user.id) {
        throw new ActionError({ code: "BAD_REQUEST", message: "No podés seguirte a vos." });
      }

      const table = kind === "profile" ? "profile_follows" : "business_follows";
      const row: Record<string, string> =
        kind === "profile" ? { follower_id: user.id, followed_id: id } : { follower_id: user.id, business_id: id };
      await setRow(supabase, table, row, active, {
        forbidden: "No podés seguir a esta cuenta.",
        fallback: "No pudimos actualizar a quién seguís.",
      });

      const { data } = await supabase
        .from(kind === "profile" ? "profiles" : "businesses")
        .select("followers_count")
        .eq("id", id)
        .maybeSingle();
      return { active, count: (data?.followers_count as number | undefined) ?? 0 };
    },
  }),

  comment: defineAction({
    accept: "form",
    input: commentSchema,
    handler: async ({ post_id, body }, context) => {
      const user = requireUser(context.locals.user);
      const { data, error } = await context.locals.supabase
        .from("post_comments")
        .insert({ post_id, author_id: user.id, body })
        .select("id")
        .single();
      if (error) {
        if (error.code === "42501") {
          throw new ActionError({ code: "FORBIDDEN", message: "No podés comentar en esta publicación." });
        }
        throw dbError(error, "No pudimos publicar tu comentario.");
      }
      return { id: data.id as string };
    },
  }),

  removeComment: defineAction({
    accept: "form",
    input: commentRefSchema,
    handler: async ({ comment_id }, context) => {
      requireUser(context.locals.user);
      const { data, error } = await context.locals.supabase
        .from("post_comments")
        .delete()
        .eq("id", comment_id)
        .select("id");
      if (error) throw dbError(error, "No pudimos borrar el comentario.");
      if (!data?.length) {
        throw new ActionError({ code: "FORBIDDEN", message: "No podés borrar este comentario." });
      }
      return { ok: true };
    },
  }),
};
