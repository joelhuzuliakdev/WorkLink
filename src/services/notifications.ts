import type { SupabaseClient } from "@supabase/supabase-js";
import { decodeCursor, encodeCursor, type Cursor } from "./posts";

/**
 * Notificaciones del usuario actual (RLS: cada uno ve solo las suyas).
 * Las crea la base con triggers; acá solo se leen y se marcan como leídas.
 */

export type NotificationType = "post_like" | "post_comment" | "profile_follow" | "business_follow";

export interface NotificationView {
  id: string;
  type: NotificationType;
  created_at: string;
  read_at: string | null;
  actor: { username: string; first_name: string | null; last_name: string | null; avatar_path: string | null } | null;
  post: { id: string; title: string | null; body: string } | null;
  comment: { id: string; body: string } | null;
  business: { slug: string; name: string } | null;
}

export const NOTIFICATIONS_PAGE = 30;

const COLUMNS = `id, type, created_at, read_at,
  actor:profiles!notifications_actor_id_fkey ( username, first_name, last_name, avatar_path ),
  post:posts ( id, title, body ),
  comment:post_comments ( id, body ),
  business:businesses ( slug, name )`;

export async function getNotifications(
  supabase: SupabaseClient,
  userId: string,
  cursor?: Cursor | null,
): Promise<{ items: NotificationView[]; nextCursor: string | null }> {
  let query = supabase
    .from("notifications")
    .select(COLUMNS)
    .eq("recipient_id", userId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(NOTIFICATIONS_PAGE + 1);
  if (cursor) {
    query = query.or(`created_at.lt."${cursor.publishedAt}",and(created_at.eq."${cursor.publishedAt}",id.lt.${cursor.id})`);
  }
  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as NotificationView[];
  const page = rows.slice(0, NOTIFICATIONS_PAGE);
  const last = page[page.length - 1];
  return {
    // Si la cuenta de quien la generó fue suspendida, RLS devuelve actor null: se omite.
    items: page.filter((n) => n.actor),
    nextCursor: rows.length > NOTIFICATIONS_PAGE && last ? encodeCursor({ published_at: last.created_at, id: last.id }) : null,
  };
}

export { decodeCursor };

export async function countUnread(supabase: SupabaseClient, userId: string): Promise<number> {
  const { count, error } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("recipient_id", userId)
    .is("read_at", null);
  if (error) {
    console.error("[notificaciones]", error.message);
    return 0;
  }
  return count ?? 0;
}

export async function markAllRead(supabase: SupabaseClient): Promise<void> {
  const { error } = await supabase.rpc("mark_notifications_read");
  if (error) console.error("[notificaciones]", error.message);
}
