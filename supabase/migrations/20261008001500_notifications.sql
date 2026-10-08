-- =============================================================================
-- 0015 · Notificaciones (Etapa 8)
-- =============================================================================
-- * Avisos dentro de WorkLink: me gusta en tu publicación, comentario en tu
--   publicación, alguien empezó a seguirte o a seguir tu emprendimiento.
-- * Las crea la base con triggers (nadie puede crear avisos falsos desde la
--   app). Cada usuario solo ve y marca como leídos los suyos.
-- * Sin avisos duplicados: dar y quitar me gusta varias veces deja un solo
--   aviso; al quitar el me gusta o dejar de seguir, el aviso se borra.
-- * Los leídos de más de 90 días los borra la limpieza diaria.
-- * Pensado para sumar después: mensajes (Etapa 9) y propuestas (Etapa 10).
-- =============================================================================

create type public.notification_type as enum ('post_like', 'post_comment', 'profile_follow', 'business_follow');

create table public.notifications (
  id            uuid primary key default gen_random_uuid(),
  recipient_id  uuid not null references public.profiles (id) on delete cascade,
  actor_id      uuid not null references public.profiles (id) on delete cascade,
  type          public.notification_type not null,
  post_id       uuid references public.posts (id) on delete cascade,
  comment_id    uuid references public.post_comments (id) on delete cascade,
  business_id   uuid references public.businesses (id) on delete cascade,
  created_at    timestamptz not null default now(),
  read_at       timestamptz,
  constraint notifications_not_self check (recipient_id <> actor_id)
);

-- Lista del usuario (más nuevas primero) y contador de no leídas.
create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc, id desc);
create index notifications_unread_idx on public.notifications (recipient_id) where read_at is null;
create index notifications_cleanup_idx on public.notifications (read_at) where read_at is not null;

-- Un solo aviso por persona y publicación (me gusta) o por seguimiento.
create unique index notifications_like_once on public.notifications (recipient_id, actor_id, post_id) where type = 'post_like';
create unique index notifications_follow_once on public.notifications (recipient_id, actor_id) where type = 'profile_follow';
create unique index notifications_business_follow_once on public.notifications (recipient_id, actor_id, business_id) where type = 'business_follow';

-- -----------------------------------------------------------------------------
-- Creación de avisos (solo desde triggers; SECURITY DEFINER)
-- -----------------------------------------------------------------------------
create or replace function public.notify(
  p_recipient uuid,
  p_actor     uuid,
  p_type      public.notification_type,
  p_post      uuid default null,
  p_comment   uuid default null,
  p_business  uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient is null or p_actor is null or p_recipient = p_actor then
    return;
  end if;
  -- Sin avisos entre personas con bloqueo.
  if public.is_blocked_between(p_recipient, p_actor) then
    return;
  end if;
  insert into public.notifications (recipient_id, actor_id, type, post_id, comment_id, business_id)
  values (p_recipient, p_actor, p_type, p_post, p_comment, p_business)
  on conflict do nothing;
end;
$$;

revoke execute on function public.notify(uuid, uuid, public.notification_type, uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.tg_notify_post_like()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.notify((select p.author_id from public.posts p where p.id = new.post_id), new.user_id, 'post_like', new.post_id);
  else
    delete from public.notifications n
    where n.type = 'post_like' and n.actor_id = old.user_id and n.post_id = old.post_id;
  end if;
  return null;
end;
$$;

create trigger post_likes_notify
  after insert or delete on public.post_likes
  for each row execute function public.tg_notify_post_like();

create or replace function public.tg_notify_post_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.notify((select p.author_id from public.posts p where p.id = new.post_id), new.author_id, 'post_comment', new.post_id, new.id);
  return null;
end;
$$;

-- Al borrar el comentario, el aviso se borra solo (comment_id on delete cascade).
create trigger post_comments_notify
  after insert on public.post_comments
  for each row execute function public.tg_notify_post_comment();

create or replace function public.tg_notify_profile_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.notify(new.followed_id, new.follower_id, 'profile_follow');
  else
    delete from public.notifications n
    where n.type = 'profile_follow' and n.actor_id = old.follower_id and n.recipient_id = old.followed_id;
  end if;
  return null;
end;
$$;

create trigger profile_follows_notify
  after insert or delete on public.profile_follows
  for each row execute function public.tg_notify_profile_follow();

-- Seguir un emprendimiento avisa a su dueño.
create or replace function public.tg_notify_business_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.notify((select b.owner_id from public.businesses b where b.id = new.business_id), new.follower_id, 'business_follow', null, null, new.business_id);
  else
    delete from public.notifications n
    where n.type = 'business_follow' and n.actor_id = old.follower_id and n.business_id = old.business_id;
  end if;
  return null;
end;
$$;

create trigger business_follows_notify
  after insert or delete on public.business_follows
  for each row execute function public.tg_notify_business_follow();

-- -----------------------------------------------------------------------------
-- Seguridad: cada uno ve sus avisos y solo puede marcarlos como leídos.
-- -----------------------------------------------------------------------------
alter table public.notifications enable row level security;

create policy "notifications: veo las mías" on public.notifications
  for select to authenticated
  using (recipient_id = (select auth.uid()));

create policy "notifications: marco las mías como leídas" on public.notifications
  for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

create policy "notifications: borro las mías" on public.notifications
  for delete to authenticated
  using (recipient_id = (select auth.uid()));

revoke all on public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
-- Solo la columna read_at se puede modificar.
grant update (read_at) on public.notifications to authenticated;

-- Marcar todas como leídas (una sola consulta, sin pasar ids).
create or replace function public.mark_notifications_read()
returns integer
language sql
security invoker
set search_path = ''
as $$
  with updated as (
    update public.notifications
    set read_at = now()
    where recipient_id = (select auth.uid()) and read_at is null
    returning 1
  )
  select count(*)::integer from updated;
$$;

revoke execute on function public.mark_notifications_read() from public, anon;
grant execute on function public.mark_notifications_read() to authenticated;

notify pgrst, 'reload schema';
