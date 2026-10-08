import type { APIRoute } from "astro";
import { countUnread } from "../../services/notifications";
import { countUnreadConversations } from "../../services/messages";

/**
 * Cantidad de notificaciones sin leer del usuario actual (para la campanita).
 * y de conversaciones con mensajes sin leer (para el ícono de mensajes).
 * GET /api/notificaciones -> { unread, messages }. Privado: nunca se cachea.
 */
export const GET: APIRoute = async ({ locals }) => {
  const headers = { "Cache-Control": "private, no-store" };
  if (!locals.user) return Response.json({ unread: 0, messages: 0 }, { status: 401, headers });
  const [unread, messages] = await Promise.all([countUnread(locals.supabase, locals.user.id), countUnreadConversations(locals.supabase)]);
  return Response.json({ unread, messages }, { headers });
};
