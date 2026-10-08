import type { APIRoute } from "astro";
import { getConversation, getMessages, getMessagesAfter, markConversationRead } from "../../../services/messages";
import { displayName } from "../../../services/profiles";
import { mediaUrl } from "../../../lib/media";

/**
 * Mensajes nuevos de una conversación (la pide la pantalla del chat cada
 * pocos segundos): GET /api/mensajes/<id>?despues=<fecha ISO>
 * Responde los mensajes nuevos y hasta dónde leyó la otra persona ("Visto").
 * Si llegaron mensajes de la otra persona, marca la conversación como leída.
 *
 * GET /api/mensajes/<id>?ultimos=1 -> la conversación (persona y últimos
 * mensajes) para abrir la ventanita flotante de la computadora.
 */
export const GET: APIRoute = async ({ params, url, locals }) => {
  const headers = { "Cache-Control": "private, no-store" };
  const user = locals.user;
  if (!user) return Response.json({ error: "unauthorized" }, { status: 401, headers });

  const id = params.id ?? "";
  if (/^[0-9a-f-]{36}$/.test(id) && url.searchParams.get("ultimos") === "1") {
    const conversation = await getConversation(locals.supabase, id, user.id);
    if (!conversation) return Response.json({ error: "not_found" }, { status: 404, headers });
    const { messages } = await getMessages(locals.supabase, id);
    if (conversation.unread) await markConversationRead(locals.supabase, id);
    const other = conversation.other;
    return Response.json(
      {
        me: user.id,
        other: other
          ? {
              name: displayName(other),
              username: other.username,
              avatar: mediaUrl("avatar", other.avatar_path, 96),
              verified: Boolean(other.verified_at),
              headline: other.headline,
            }
          : null,
        messages,
        otherLastReadAt: conversation.otherLastReadAt,
      },
      { headers },
    );
  }
  const after = url.searchParams.get("despues") ?? "";
  if (!/^[0-9a-f-]{36}$/.test(id) || Number.isNaN(Date.parse(after))) {
    return Response.json({ error: "bad_request" }, { status: 400, headers });
  }

  const conversation = await getConversation(locals.supabase, id, user.id);
  if (!conversation) return Response.json({ error: "not_found" }, { status: 404, headers });

  const messages = await getMessagesAfter(locals.supabase, id, after);
  if (messages.some((m) => m.sender_id !== user.id)) await markConversationRead(locals.supabase, id);

  return Response.json({ messages, otherLastReadAt: conversation.otherLastReadAt }, { headers });
};
