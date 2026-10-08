import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Mensajes privados. RLS garantiza que solo los dos participantes ven la
 * conversación; las altas pasan por funciones de la base (start_conversation)
 * y por insert en messages (con bloqueos y límites controlados por la base).
 */

export interface ChatPerson {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  verified_at: string | null;
  situation: "job_seeking" | "entrepreneur" | "freelancer" | "hiring" | null;
  headline: string | null;
}

export interface ConversationView {
  id: string;
  other: ChatPerson | null;
  last_message_at: string | null;
  last_message_preview: string | null;
  last_sender_id: string | null;
  myLastReadAt: string;
  otherLastReadAt: string | null;
  hidden: boolean;
  unread: boolean;
}

export interface MessageView {
  id: string;
  sender_id: string;
  body: string;
  created_at: string;
  post: { id: string; title: string | null; body: string } | null;
}

const PERSON = "id, username, first_name, last_name, avatar_path, verified_at, situation, headline";
const CONVERSATION_COLUMNS = `id, user_low, user_high, last_message_at, last_message_preview, last_sender_id,
  low:profiles!conversations_user_low_fkey ( ${PERSON} ),
  high:profiles!conversations_user_high_fkey ( ${PERSON} ),
  conversation_members ( user_id, last_read_at, hidden_at )`;

type ConversationRow = {
  id: string;
  user_low: string;
  user_high: string;
  last_message_at: string | null;
  last_message_preview: string | null;
  last_sender_id: string | null;
  low: ChatPerson | null;
  high: ChatPerson | null;
  conversation_members: { user_id: string; last_read_at: string; hidden_at: string | null }[];
};

function toConversation(row: ConversationRow, me: string): ConversationView {
  const mine = row.conversation_members.find((m) => m.user_id === me);
  const theirs = row.conversation_members.find((m) => m.user_id !== me);
  const myLastReadAt = mine?.last_read_at ?? new Date(0).toISOString();
  return {
    id: row.id,
    other: row.user_low === me ? row.high : row.low,
    last_message_at: row.last_message_at,
    last_message_preview: row.last_message_preview,
    last_sender_id: row.last_sender_id,
    myLastReadAt,
    otherLastReadAt: theirs?.last_read_at ?? null,
    hidden: Boolean(mine?.hidden_at),
    unread: Boolean(row.last_message_at && row.last_sender_id !== me && row.last_message_at > myLastReadAt),
  };
}

/** Bandeja: conversaciones con mensajes, de la más reciente a la más vieja. */
export async function getConversations(supabase: SupabaseClient, me: string, limit = 50): Promise<ConversationView[]> {
  const { data, error } = await supabase
    .from("conversations")
    .select(CONVERSATION_COLUMNS)
    .or(`user_low.eq.${me},user_high.eq.${me}`)
    .not("last_message_at", "is", null)
    .order("last_message_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return ((data ?? []) as unknown as ConversationRow[])
    .map((row) => toConversation(row, me))
    .filter((c) => !c.hidden && c.other);
}

export async function getConversation(supabase: SupabaseClient, id: string, me: string): Promise<ConversationView | null> {
  const { data, error } = await supabase.from("conversations").select(CONVERSATION_COLUMNS).eq("id", id).maybeSingle();
  if (error) throw error;
  return data ? toConversation(data as unknown as ConversationRow, me) : null;
}

export const MESSAGES_PAGE = 50;

const MESSAGE_COLUMNS = "id, sender_id, body, created_at, post:posts ( id, title, body )";

/** Últimos mensajes (o los anteriores a `before`), en orden cronológico. */
export async function getMessages(
  supabase: SupabaseClient,
  conversationId: string,
  { before }: { before?: string | null } = {},
): Promise<{ messages: MessageView[]; hasOlder: boolean }> {
  let query = supabase
    .from("messages")
    .select(MESSAGE_COLUMNS)
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(MESSAGES_PAGE + 1);
  if (before && !Number.isNaN(Date.parse(before))) query = query.lt("created_at", before);
  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as MessageView[];
  return { messages: rows.slice(0, MESSAGES_PAGE).reverse(), hasOlder: rows.length > MESSAGES_PAGE };
}

/** Mensajes nuevos después de una fecha (para la actualización periódica). */
export async function getMessagesAfter(supabase: SupabaseClient, conversationId: string, after: string): Promise<MessageView[]> {
  const { data, error } = await supabase
    .from("messages")
    .select(MESSAGE_COLUMNS)
    .eq("conversation_id", conversationId)
    .gt("created_at", after)
    .order("created_at", { ascending: true })
    .limit(100);
  if (error) throw error;
  return (data ?? []) as unknown as MessageView[];
}

export async function markConversationRead(supabase: SupabaseClient, conversationId: string): Promise<void> {
  const { error } = await supabase.rpc("mark_conversation_read", { p_conversation_id: conversationId });
  if (error) console.error("[mensajes]", error.message);
}

export async function countUnreadConversations(supabase: SupabaseClient): Promise<number> {
  const { data, error } = await supabase.rpc("unread_conversations_count");
  if (error) {
    console.error("[mensajes]", error.message);
    return 0;
  }
  return Number(data ?? 0);
}

/** Enlace para escribirle a alguien (opcionalmente citando una publicación). */
export function newMessagePath(username: string, postId?: string | null): string {
  const params = new URLSearchParams({ con: username });
  if (postId) params.set("publicacion", postId);
  return `/mensajes/nuevo?${params}`;
}
