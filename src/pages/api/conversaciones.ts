import type { APIRoute } from "astro";
import { getConversations } from "../../services/messages";
import { displayName } from "../../services/profiles";
import { mediaUrl } from "../../lib/media";
import { formatRelative } from "../../lib/format";

/**
 * Bandeja para el panel de mensajes de la computadora.
 *  GET  /api/conversaciones           -> { conversations: [...] }
 *  POST /api/conversaciones {username} -> { id }  (empieza o retoma una conversación)
 * Privado: nunca se cachea. La base controla bloqueos y límites.
 */
const headers = { "Cache-Control": "private, no-store" };

export const GET: APIRoute = async ({ locals }) => {
  const user = locals.user;
  if (!user) return Response.json({ error: "unauthorized" }, { status: 401, headers });
  const list = await getConversations(locals.supabase, user.id, 30);
  return Response.json(
    {
      conversations: list.map((c) => ({
        id: c.id,
        name: c.other ? displayName(c.other) : "Usuario",
        username: c.other?.username ?? null,
        avatar: mediaUrl("avatar", c.other?.avatar_path, 96),
        verified: Boolean(c.other?.verified_at),
        preview: c.last_message_preview ?? "",
        mine: c.last_sender_id === user.id,
        when: c.last_message_at ? formatRelative(c.last_message_at) : "",
        unread: c.unread,
        unreadCount: c.unreadCount,
      })),
    },
    { headers },
  );
};

export const POST: APIRoute = async ({ locals, request }) => {
  const user = locals.user;
  if (!user) return Response.json({ error: "Tenés que ingresar." }, { status: 401, headers });
  let username = "";
  try {
    username = String(((await request.json()) as { username?: string }).username ?? "").toLowerCase();
  } catch {
    /* cuerpo inválido */
  }
  if (!/^[a-z0-9_.]{3,30}$/.test(username)) return Response.json({ error: "Usuario inválido." }, { status: 400, headers });

  const { data: other } = await locals.supabase.from("profiles").select("id").eq("username", username).eq("status", "active").maybeSingle();
  if (!other) return Response.json({ error: "Esa cuenta no está disponible." }, { status: 404, headers });
  const { data, error } = await locals.supabase.rpc("start_conversation", { p_other: other.id });
  if (error || !data) return Response.json({ error: error?.message ?? "No pudimos abrir la conversación." }, { status: 403, headers });
  return Response.json({ id: data }, { headers });
};
