-- =============================================================================
-- 0017 · Mensajes privados (Etapa 9)
-- =============================================================================
-- * Conversaciones de a dos. Una sola conversación por par de personas.
-- * Solo los dos participantes ven la conversación y sus mensajes (RLS).
-- * Con bloqueo (en cualquier sentido) no se puede empezar ni escribir.
-- * Cada participante tiene su estado: hasta dónde leyó (para "no leídos" y
--   "Visto") y si la ocultó de su bandeja (vuelve a aparecer con un mensaje nuevo).
-- * Un mensaje puede citar la publicación por la que se consulta.
-- * Límites anti-spam: conversaciones nuevas por día y mensajes por hora.
-- =============================================================================

create table public.conversations (
  id                    uuid primary key default gen_random_uuid(),
  -- Par ordenado (user_low < user_high): garantiza una conversación por par.
  user_low              uuid not null references public.profiles (id) on delete cascade,
  user_high             uuid not null references public.profiles (id) on delete cascade,
  created_by            uuid not null references public.profiles (id) on delete cascade,
  created_at            timestamptz not null default now(),
  last_message_at       timestamptz,
  last_message_preview  text,
  last_sender_id        uuid references public.profiles (id) on delete set null,
  constraint conversations_pair_order check (user_low < user_high),
  constraint conversations_pair_key unique (user_low, user_high)
);

create table public.conversation_members (
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  last_read_at     timestamptz not null default now(),
  hidden_at        timestamptz,
  primary key (conversation_id, user_id)
);

create index conversation_members_user_idx on public.conversation_members (user_id);

create table public.messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  sender_id        uuid not null references public.profiles (id) on delete cascade,
  body             text not null,
  post_id          uuid references public.posts (id) on delete set null,
  created_at       timestamptz not null default now(),
  constraint messages_body_len check (char_length(btrim(body)) between 1 and 2000)
);

create index messages_conversation_idx on public.messages (conversation_id, created_at desc, id desc);
create index messages_sender_recent_idx on public.messages (sender_id, created_at desc);

-- ¿El usuario actual participa de la conversación?
create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = (select auth.uid())
  );
$$;

revoke execute on function public.is_conversation_member(uuid) from public, anon;
grant  execute on function public.is_conversation_member(uuid) to authenticated, service_role;

-- La otra persona de la conversación (para el usuario actual).
create or replace function public.conversation_other(p_conversation_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when c.user_low = (select auth.uid()) then c.user_high else c.user_low end
  from public.conversations c
  where c.id = p_conversation_id
    and (select auth.uid()) in (c.user_low, c.user_high);
$$;

revoke execute on function public.conversation_other(uuid) from public, anon;
grant  execute on function public.conversation_other(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Empezar (o retomar) una conversación con otra persona. Devuelve su id.
-- -----------------------------------------------------------------------------
create or replace function public.start_conversation(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me     uuid := (select auth.uid());
  low    uuid;
  high   uuid;
  conv   uuid;
begin
  if me is null then
    raise exception 'Tenés que ingresar' using errcode = '42501';
  end if;
  if p_other is null or p_other = me then
    raise exception 'No podés escribirte a vos' using errcode = '22023';
  end if;
  if not public.is_active_user() then
    raise exception 'Tu cuenta no puede enviar mensajes' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other and p.status = 'active') then
    raise exception 'Esa cuenta no está disponible' using errcode = '42501';
  end if;
  if public.is_blocked_between(me, p_other) then
    raise exception 'No podés escribirle a esta persona' using errcode = '42501';
  end if;

  low  := least(me, p_other);
  high := greatest(me, p_other);

  select c.id into conv from public.conversations c where c.user_low = low and c.user_high = high;
  if conv is not null then
    return conv;
  end if;

  if (
    select count(*) from public.conversations c
    where c.created_by = me and c.created_at > now() - interval '24 hours'
  ) >= public.setting_int('limits.conversations_per_day', 30) then
    raise exception 'Empezaste muchas conversaciones hoy. Probá de nuevo mañana.'
      using errcode = 'P0001', hint = 'rate_limited';
  end if;

  insert into public.conversations (user_low, user_high, created_by)
  values (low, high, me)
  on conflict (user_low, user_high) do nothing
  returning id into conv;

  if conv is null then
    select c.id into conv from public.conversations c where c.user_low = low and c.user_high = high;
    return conv;
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  values (conv, me), (conv, p_other);
  return conv;
end;
$$;

revoke execute on function public.start_conversation(uuid) from public, anon;
grant  execute on function public.start_conversation(uuid) to authenticated;

-- Marcar como leída (hasta ahora) para el usuario actual.
create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.conversation_members
  set last_read_at = now()
  where conversation_id = p_conversation_id and user_id = (select auth.uid());
$$;

revoke execute on function public.mark_conversation_read(uuid) from public, anon;
grant  execute on function public.mark_conversation_read(uuid) to authenticated;

-- Ocultar de mi bandeja (vuelve a aparecer si llega un mensaje nuevo).
create or replace function public.hide_conversation(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.conversation_members
  set hidden_at = now(), last_read_at = now()
  where conversation_id = p_conversation_id and user_id = (select auth.uid());
$$;

revoke execute on function public.hide_conversation(uuid) from public, anon;
grant  execute on function public.hide_conversation(uuid) to authenticated;

-- Conversaciones con mensajes sin leer del usuario actual (para el ícono).
create or replace function public.unread_conversations_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.conversation_members m
  join public.conversations c on c.id = m.conversation_id
  where m.user_id = (select auth.uid())
    and c.last_message_at is not null
    and c.last_sender_id is distinct from m.user_id
    and c.last_message_at > m.last_read_at;
$$;

revoke execute on function public.unread_conversations_count() from public, anon;
grant  execute on function public.unread_conversations_count() to authenticated;

-- -----------------------------------------------------------------------------
-- Envío de mensajes: autor = usuario actual, límite por hora, y al guardarse
-- actualiza la conversación (último mensaje) y la vuelve a mostrar a ambos.
-- -----------------------------------------------------------------------------
create or replace function public.tg_messages_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.body := btrim(new.body);
  if public.is_system_call() then
    return new;
  end if;
  new.sender_id := (select auth.uid());
  new.created_at := now();

  perform public.enforce_rate_limit(
    (select count(*) from public.messages m
      where m.sender_id = new.sender_id and m.created_at > now() - interval '1 hour'),
    'limits.messages_per_hour', 200,
    'Mandaste muchos mensajes seguidos. Esperá un rato y probá de nuevo.'
  );
  return new;
end;
$$;

create trigger messages_before_insert
  before insert on public.messages
  for each row execute function public.tg_messages_before_insert();

create or replace function public.tg_messages_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations
  set last_message_at = new.created_at,
      last_message_preview = left(regexp_replace(new.body, '\s+', ' ', 'g'), 140),
      last_sender_id = new.sender_id
  where id = new.conversation_id;

  update public.conversation_members
  set hidden_at = null,
      last_read_at = case when user_id = new.sender_id then new.created_at else last_read_at end
  where conversation_id = new.conversation_id;
  return null;
end;
$$;

create trigger messages_after_insert
  after insert on public.messages
  for each row execute function public.tg_messages_after_insert();

-- -----------------------------------------------------------------------------
-- Seguridad
-- -----------------------------------------------------------------------------
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;

create policy "conversations: participantes" on public.conversations
  for select to authenticated
  using ((select auth.uid()) in (user_low, user_high));

create policy "conversation_members: participantes" on public.conversation_members
  for select to authenticated
  using ((select public.is_conversation_member(conversation_id)));

create policy "messages: participantes leen" on public.messages
  for select to authenticated
  using ((select public.is_conversation_member(conversation_id)));

create policy "messages: participantes escriben" on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.is_conversation_member(conversation_id))
    and not public.is_blocked_between((select auth.uid()), public.conversation_other(conversation_id))
  );

-- Todo lo demás pasa por las funciones de arriba: sin UPDATE/DELETE directos.
revoke all on public.conversations, public.conversation_members, public.messages from anon, authenticated;
grant select on public.conversations, public.conversation_members to authenticated;
grant select, insert on public.messages to authenticated;

insert into public.settings (key, value, is_public, description) values
  ('limits.conversations_per_day', '30',  false, 'Conversaciones nuevas que una persona puede empezar cada 24 h'),
  ('limits.messages_per_hour',     '200', false, 'Mensajes por persona cada hora')
on conflict (key) do nothing;

notify pgrst, 'reload schema';
