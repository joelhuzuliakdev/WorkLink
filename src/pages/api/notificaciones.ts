import type { APIRoute } from "astro";
import { countUnread } from "../../services/notifications";

/**
 * Cantidad de notificaciones sin leer del usuario actual (para la campanita).
 * GET /api/notificaciones -> { unread: number }. Privado: nunca se cachea.
 */
export const GET: APIRoute = async ({ locals }) => {
  const headers = { "Cache-Control": "private, no-store" };
  if (!locals.user) return Response.json({ unread: 0 }, { status: 401, headers });
  const unread = await countUnread(locals.supabase, locals.user.id);
  return Response.json({ unread }, { headers });
};
