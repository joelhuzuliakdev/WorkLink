import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Consultas de interacción social: me gusta, guardados, comentarios y
 * seguimientos. Las tablas son privadas por RLS (cada uno ve lo suyo); los
 * contadores públicos están en posts, profiles y businesses.
 */

export interface ViewerReactions {
  liked: Set<string>;
  saved: Set<string>;
}

const EMPTY: ViewerReactions = { liked: new Set(), saved: new Set() };

/** ¿Cuáles de estas publicaciones le gustan / tiene guardadas el usuario? */
export async function getViewerReactions(
  supabase: SupabaseClient,
  userId: string | null | undefined,
  postIds: string[],
): Promise<ViewerReactions> {
  if (!userId || !postIds.length) return EMPTY;
  const ids = [...new Set(postIds)];
  const [likes, saves] = await Promise.all([
    supabase.from("post_likes").select("post_id").eq("user_id", userId).in("post_id", ids),
    supabase.from("post_saves").select("post_id").eq("user_id", userId).in("post_id", ids),
  ]);
  if (likes.error) throw likes.error;
  if (saves.error) throw saves.error;
  return {
    liked: new Set((likes.data ?? []).map((row) => row.post_id as string)),
    saved: new Set((saves.data ?? []).map((row) => row.post_id as string)),
  };
}

/** ¿El usuario sigue a esta persona o emprendimiento? */
export async function isFollowing(
  supabase: SupabaseClient,
  userId: string | null | undefined,
  kind: "profile" | "business",
  id: string,
): Promise<boolean> {
  if (!userId) return false;
  const query =
    kind === "profile"
      ? supabase.from("profile_follows").select("followed_id").eq("follower_id", userId).eq("followed_id", id)
      : supabase.from("business_follows").select("business_id").eq("follower_id", userId).eq("business_id", id);
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  return Boolean(data);
}

/** ¿Sigue a alguien? (para mostrar u ocultar la pestaña "Siguiendo" vacía). */
export async function followsAnyone(supabase: SupabaseClient, userId: string): Promise<boolean> {
  const { data, error } = await supabase.from("profiles").select("following_count").eq("id", userId).maybeSingle();
  if (error) throw error;
  return (data?.following_count ?? 0) > 0;
}

export interface CommentView {
  id: string;
  post_id: string;
  author_id: string;
  body: string;
  created_at: string;
  author: { username: string; first_name: string | null; last_name: string | null; avatar_path: string | null } | null;
}

export const COMMENTS_PAGE_SIZE = 50;

/**
 * Comentarios de una publicación, del más viejo al más nuevo (como una
 * conversación). Trae los últimos `limit`; `before` pagina hacia atrás.
 */
export async function getComments(
  supabase: SupabaseClient,
  postId: string,
  { limit = COMMENTS_PAGE_SIZE, before }: { limit?: number; before?: string | null } = {},
): Promise<{ comments: CommentView[]; hasOlder: boolean }> {
  let query = supabase
    .from("post_comments")
    .select("id, post_id, author_id, body, created_at, author:profiles!post_comments_author_id_fkey ( username, first_name, last_name, avatar_path )")
    .eq("post_id", postId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(limit + 1);
  if (before && !Number.isNaN(Date.parse(before))) query = query.lt("created_at", before);

  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as CommentView[];
  return {
    // Se omiten comentarios de cuentas suspendidas (RLS devuelve author null).
    comments: rows.slice(0, limit).filter((c) => c.author).reverse(),
    hasOlder: rows.length > limit,
  };
}

export const SAVED_PAGE_SIZE = 20;

/** Ids de publicaciones guardadas por el usuario, de la más reciente a la más vieja. */
export async function getSavedPostIds(
  supabase: SupabaseClient,
  userId: string,
  page: number,
): Promise<{ ids: string[]; hasMore: boolean }> {
  const from = (page - 1) * SAVED_PAGE_SIZE;
  const { data, error } = await supabase
    .from("post_saves")
    .select("post_id")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .range(from, from + SAVED_PAGE_SIZE);
  if (error) throw error;
  const ids = (data ?? []).map((row) => row.post_id as string);
  return { ids: ids.slice(0, SAVED_PAGE_SIZE), hasMore: ids.length > SAVED_PAGE_SIZE };
}

/** "1 seguidor" / "1.234 seguidores". */
export function followersLabel(count: number): string {
  return `${count.toLocaleString("es-AR")} ${count === 1 ? "seguidor" : "seguidores"}`;
}
