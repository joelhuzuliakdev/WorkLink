-- =============================================================================
-- 0018 · Cantidad de mensajes sin leer por conversación
-- =============================================================================
-- Para mostrar "3 mensajes nuevos" en la bandeja y en el panel de Chats, y el
-- aviso "Nombre: mensaje" cuando llega uno nuevo. Solo cuenta mensajes de la
-- otra persona posteriores a lo que leyó el usuario actual.
-- =============================================================================

create or replace function public.conversation_unread_counts()
returns table (conversation_id uuid, unread integer)
language sql
stable
security definer
set search_path = ''
as $$
  select m.conversation_id, count(msg.id)::integer
  from public.conversation_members m
  join public.messages msg
    on msg.conversation_id = m.conversation_id
   and msg.sender_id <> m.user_id
   and msg.created_at > m.last_read_at
  where m.user_id = (select auth.uid())
  group by m.conversation_id;
$$;

revoke execute on function public.conversation_unread_counts() from public, anon;
grant  execute on function public.conversation_unread_counts() to authenticated;

-- Último mensaje sin leer que recibió el usuario actual (para el aviso emergente).
create or replace function public.latest_unread_message()
returns table (conversation_id uuid, sender_name text, sender_username text, body text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select msg.conversation_id,
         coalesce(nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''), '@' || p.username::text),
         p.username::text,
         left(msg.body, 120),
         msg.created_at
  from public.conversation_members m
  join public.messages msg
    on msg.conversation_id = m.conversation_id
   and msg.sender_id <> m.user_id
   and msg.created_at > m.last_read_at
  join public.profiles p on p.id = msg.sender_id
  where m.user_id = (select auth.uid())
  order by msg.created_at desc
  limit 1;
$$;

revoke execute on function public.latest_unread_message() from public, anon;
grant  execute on function public.latest_unread_message() to authenticated;

notify pgrst, 'reload schema';
