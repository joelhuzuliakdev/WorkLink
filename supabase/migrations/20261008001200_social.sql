-- =============================================================================
-- 0012 · Interacción social (Etapa 6)
-- =============================================================================
-- * Me gusta y guardados de publicaciones (una fila por usuario y publicación).
-- * Comentarios en publicaciones (texto plano, hasta 1000 caracteres).
-- * Seguir personas y emprendimientos.
-- * Todos los contadores (likes_count, comments_count, saves_count,
--   followers_count, following_count) los mantiene la base con triggers:
--   nadie puede escribirlos desde la app.
-- * Quién dio me gusta, quién guardó y a quién sigue cada uno es privado: cada
--   usuario ve solo lo suyo. Los números son públicos.
-- * Bloqueos: si una persona bloqueó a otra (en cualquier sentido), no pueden
--   comentarse ni seguirse, y al bloquear se borran los seguimientos mutuos.
-- * Límites anti-abuso configurables en settings.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Contadores sin tocar updated_at
-- -----------------------------------------------------------------------------
-- updated_at indica cambios de contenido (lo usarán el sitemap y la caché).
-- Los triggers de contadores activan esta marca para no modificarlo.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('worklink.counter_update', true), '') = 'on' then
    return new;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Suma (o resta) a un contador de una tabla, sin bajar de cero.
-- Uso interno de los triggers; no se expone a la API.
create or replace function public.bump_counter(p_table text, p_column text, p_id uuid, p_delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_table not in ('posts', 'profiles', 'businesses')
     or p_column not in ('likes_count', 'comments_count', 'saves_count', 'followers_count', 'following_count') then
    raise exception 'Contador inválido';
  end if;
  perform set_config('worklink.counter_update', 'on', true);
  execute format('update public.%I set %I = greatest(%I + $1, 0) where id = $2', p_table, p_column, p_column)
    using p_delta, p_id;
  perform set_config('worklink.counter_update', 'off', true);
end;
$$;

revoke execute on function public.bump_counter(text, text, uuid, integer) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Contadores de seguidores en perfiles
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column followers_count integer not null default 0,
  add column following_count integer not null default 0,
  add constraint profiles_follow_counters_nonneg check (followers_count >= 0 and following_count >= 0);

-- Visibles también para visitantes sin cuenta.
grant select (followers_count, following_count) on public.profiles to anon;

create or replace function public.tg_profiles_protect()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_system_call() then
    return new;
  end if;

  if new.id <> old.id or new.created_at <> old.created_at then
    raise exception 'No se pueden modificar id ni created_at' using errcode = '42501';
  end if;

  if new.followers_count <> old.followers_count or new.following_count <> old.following_count then
    raise exception 'Campo administrado por el sistema' using errcode = '42501';
  end if;

  if new.status is distinct from old.status and not (select public.has_role('moderator')) then
    raise exception 'Solo moderación puede cambiar el estado de una cuenta' using errcode = '42501';
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Funciones de apoyo para las políticas
-- -----------------------------------------------------------------------------

-- ¿El usuario actual puede interactuar con la publicación? Debe estar
-- publicada, con autor activo, y sin bloqueo entre el usuario y el autor.
create or replace function public.can_interact_with_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.posts p
    join public.profiles a on a.id = p.author_id and a.status = 'active'
    where p.id = p_post_id
      and p.status = 'published'
      and p.deleted_at is null
      and not public.is_blocked_between((select auth.uid()), p.author_id)
  );
$$;

revoke execute on function public.can_interact_with_post(uuid) from public, anon;
grant  execute on function public.can_interact_with_post(uuid) to authenticated, service_role;

-- ¿El usuario actual puede seguir a esta persona? (activa, no es él mismo, sin bloqueo)
create or replace function public.can_follow_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_profile_id <> (select auth.uid())
     and exists (select 1 from public.profiles p where p.id = p_profile_id and p.status = 'active')
     and not public.is_blocked_between((select auth.uid()), p_profile_id);
$$;

revoke execute on function public.can_follow_profile(uuid) from public, anon;
grant  execute on function public.can_follow_profile(uuid) to authenticated, service_role;

-- (is_business_public ya existe desde la migración 0005.)

-- Límite genérico: cuántas filas creó el usuario en una tabla en un período.
-- Lanza 'rate_limited' si se pasa. Uso interno de los triggers.
create or replace function public.enforce_rate_limit(
  p_count bigint, p_setting text, p_default integer, p_message text
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_count >= public.setting_int(p_setting, p_default) then
    raise exception '%', p_message using errcode = 'P0001', hint = 'rate_limited';
  end if;
end;
$$;

revoke execute on function public.enforce_rate_limit(bigint, text, integer, text) from public, anon;
grant  execute on function public.enforce_rate_limit(bigint, text, integer, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Me gusta
-- -----------------------------------------------------------------------------
create table public.post_likes (
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index post_likes_user_idx on public.post_likes (user_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Guardados
-- -----------------------------------------------------------------------------
create table public.post_saves (
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index post_saves_user_idx on public.post_saves (user_id, created_at desc);

-- La fecha la pone la base (para ordenar "Guardados" sin que se pueda falsear).
create or replace function public.tg_reaction_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_system_call() then
    new.user_id := (select auth.uid());
    new.created_at := now();
  end if;
  return new;
end;
$$;

create trigger post_likes_before_insert
  before insert on public.post_likes
  for each row execute function public.tg_reaction_before_insert();

create trigger post_saves_before_insert
  before insert on public.post_saves
  for each row execute function public.tg_reaction_before_insert();

create or replace function public.tg_post_likes_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('posts', 'likes_count', new.post_id, 1);
  else
    perform public.bump_counter('posts', 'likes_count', old.post_id, -1);
  end if;
  return null;
end;
$$;

create trigger post_likes_counter
  after insert or delete on public.post_likes
  for each row execute function public.tg_post_likes_counter();

create or replace function public.tg_post_saves_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('posts', 'saves_count', new.post_id, 1);
  else
    perform public.bump_counter('posts', 'saves_count', old.post_id, -1);
  end if;
  return null;
end;
$$;

create trigger post_saves_counter
  after insert or delete on public.post_saves
  for each row execute function public.tg_post_saves_counter();

-- -----------------------------------------------------------------------------
-- Comentarios
-- -----------------------------------------------------------------------------
create table public.post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts (id) on delete cascade,
  author_id  uuid not null references public.profiles (id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now(),
  constraint post_comments_body_len check (char_length(btrim(body)) between 1 and 1000)
);

create index post_comments_post_idx   on public.post_comments (post_id, created_at desc, id desc);
create index post_comments_author_idx on public.post_comments (author_id, created_at desc);

create or replace function public.tg_post_comments_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.body := btrim(new.body);
  if public.is_system_call() then
    return new;
  end if;

  new.author_id := (select auth.uid());
  new.created_at := now();

  perform public.enforce_rate_limit(
    (select count(*) from public.post_comments c
      where c.author_id = new.author_id and c.created_at > now() - interval '1 hour'),
    'limits.comments_per_hour', 60,
    'Escribiste muchos comentarios seguidos. Esperá un rato y probá de nuevo.'
  );
  return new;
end;
$$;

create trigger post_comments_before_insert
  before insert on public.post_comments
  for each row execute function public.tg_post_comments_before_insert();

-- Los comentarios no se editan (se borran y se escriben de nuevo).
create or replace function public.tg_post_comments_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('posts', 'comments_count', new.post_id, 1);
  else
    perform public.bump_counter('posts', 'comments_count', old.post_id, -1);
  end if;
  return null;
end;
$$;

create trigger post_comments_counter
  after insert or delete on public.post_comments
  for each row execute function public.tg_post_comments_counter();

-- -----------------------------------------------------------------------------
-- Seguir personas
-- -----------------------------------------------------------------------------
create table public.profile_follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followed_id uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followed_id),
  constraint profile_follows_not_self check (follower_id <> followed_id)
);

create index profile_follows_followed_idx on public.profile_follows (followed_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Seguir emprendimientos
-- -----------------------------------------------------------------------------
create table public.business_follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  business_id uuid not null references public.businesses (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, business_id)
);

create index business_follows_business_idx on public.business_follows (business_id, created_at desc);

create or replace function public.tg_follows_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_system_call() then
    return new;
  end if;

  new.follower_id := (select auth.uid());
  new.created_at := now();

  perform public.enforce_rate_limit(
    (select count(*) from public.profile_follows f
      where f.follower_id = new.follower_id and f.created_at > now() - interval '24 hours')
    + (select count(*) from public.business_follows f
      where f.follower_id = new.follower_id and f.created_at > now() - interval '24 hours'),
    'limits.follows_per_day', 200,
    'Seguiste a muchas cuentas hoy. Probá de nuevo mañana.'
  );
  return new;
end;
$$;

create trigger profile_follows_before_insert
  before insert on public.profile_follows
  for each row execute function public.tg_follows_before_insert();

create trigger business_follows_before_insert
  before insert on public.business_follows
  for each row execute function public.tg_follows_before_insert();

create or replace function public.tg_profile_follows_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('profiles', 'followers_count', new.followed_id, 1);
    perform public.bump_counter('profiles', 'following_count', new.follower_id, 1);
  else
    perform public.bump_counter('profiles', 'followers_count', old.followed_id, -1);
    perform public.bump_counter('profiles', 'following_count', old.follower_id, -1);
  end if;
  return null;
end;
$$;

create trigger profile_follows_counter
  after insert or delete on public.profile_follows
  for each row execute function public.tg_profile_follows_counter();

create or replace function public.tg_business_follows_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('businesses', 'followers_count', new.business_id, 1);
    perform public.bump_counter('profiles', 'following_count', new.follower_id, 1);
  else
    perform public.bump_counter('businesses', 'followers_count', old.business_id, -1);
    perform public.bump_counter('profiles', 'following_count', old.follower_id, -1);
  end if;
  return null;
end;
$$;

create trigger business_follows_counter
  after insert or delete on public.business_follows
  for each row execute function public.tg_business_follows_counter();

-- Al bloquear a alguien se cortan los seguimientos en ambos sentidos.
create or replace function public.tg_user_blocks_unfollow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.profile_follows
  where (follower_id = new.blocker_id and followed_id = new.blocked_id)
     or (follower_id = new.blocked_id and followed_id = new.blocker_id);
  return null;
end;
$$;

create trigger user_blocks_unfollow
  after insert on public.user_blocks
  for each row execute function public.tg_user_blocks_unfollow();

-- -----------------------------------------------------------------------------
-- Seguridad a nivel de fila
-- -----------------------------------------------------------------------------
alter table public.post_likes       enable row level security;
alter table public.post_saves       enable row level security;
alter table public.post_comments    enable row level security;
alter table public.profile_follows  enable row level security;
alter table public.business_follows enable row level security;

-- Me gusta: cada uno ve y maneja solo los suyos.
create policy "post_likes: veo los míos" on public.post_likes
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "post_likes: doy me gusta" on public.post_likes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.can_interact_with_post(post_id))
  );

create policy "post_likes: quito mi me gusta" on public.post_likes
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Guardados: igual que me gusta.
create policy "post_saves: veo los míos" on public.post_saves
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "post_saves: guardo" on public.post_saves
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.can_interact_with_post(post_id))
  );

create policy "post_saves: quito de guardados" on public.post_saves
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Comentarios: visibles si la publicación lo es (o para quien la edita y
-- moderación). Comenta cualquier usuario activo sin bloqueo con el autor.
-- Borran: quien lo escribió, quien edita la publicación y moderación.
create policy "post_comments: lectura" on public.post_comments
  for select to anon, authenticated
  using (
    (select public.is_post_public(post_id))
    or (select public.can_edit_post(post_id))
    or (select public.has_role('moderator'))
  );

create policy "post_comments: comentar" on public.post_comments
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.can_interact_with_post(post_id))
  );

create policy "post_comments: borrar" on public.post_comments
  for delete to authenticated
  using (
    author_id = (select auth.uid())
    or (select public.can_edit_post(post_id))
    or (select public.has_role('moderator'))
  );

-- Seguir personas: cada uno ve a quién sigue y quién lo sigue.
create policy "profile_follows: veo los míos" on public.profile_follows
  for select to authenticated
  using (follower_id = (select auth.uid()) or followed_id = (select auth.uid()));

create policy "profile_follows: sigo" on public.profile_follows
  for insert to authenticated
  with check (
    follower_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.can_follow_profile(followed_id))
  );

create policy "profile_follows: dejo de seguir" on public.profile_follows
  for delete to authenticated
  using (follower_id = (select auth.uid()));

-- Seguir emprendimientos: cada uno ve a quién sigue; el equipo ve sus seguidores.
create policy "business_follows: veo los míos" on public.business_follows
  for select to authenticated
  using (follower_id = (select auth.uid()) or (select public.is_business_member(business_id)));

create policy "business_follows: sigo" on public.business_follows
  for insert to authenticated
  with check (
    follower_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.is_business_public(business_id))
  );

create policy "business_follows: dejo de seguir" on public.business_follows
  for delete to authenticated
  using (follower_id = (select auth.uid()));

-- Sin UPDATE en ninguna: se crean y se borran.
revoke all on public.post_likes, public.post_saves, public.post_comments,
  public.profile_follows, public.business_follows from anon, authenticated;
grant select, insert, delete on public.post_likes, public.post_saves, public.post_comments,
  public.profile_follows, public.business_follows to authenticated;
grant select on public.post_comments to anon;

-- -----------------------------------------------------------------------------
-- Feed "Siguiendo": ids de publicaciones de personas y emprendimientos que
-- sigue el usuario actual, paginadas por cursor (published_at, id).
-- SECURITY INVOKER: aplica RLS como cualquier consulta. La app trae después
-- el detalle de esas publicaciones (máximo 50 por llamada).
-- -----------------------------------------------------------------------------
create or replace function public.following_feed_ids(
  p_type      public.post_type default null,
  p_before_at timestamptz      default null,
  p_before_id uuid             default null,
  p_limit     integer          default 20
)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id
  from public.posts p
  where p.status = 'published'
    and p.deleted_at is null
    and (p_type is null or p.type = p_type)
    and (p_before_at is null or (p.published_at, p.id) < (p_before_at, coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    and (
      p.author_id in (select f.followed_id from public.profile_follows f where f.follower_id = (select auth.uid()))
      or p.business_id in (select f.business_id from public.business_follows f where f.follower_id = (select auth.uid()))
    )
  order by p.published_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.following_feed_ids(public.post_type, timestamptz, uuid, integer) from public, anon;
grant  execute on function public.following_feed_ids(public.post_type, timestamptz, uuid, integer) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Límites (editables por admin)
-- -----------------------------------------------------------------------------
insert into public.settings (key, value, is_public, description) values
  ('limits.comments_per_hour', '60',  false, 'Comentarios por usuario cada hora'),
  ('limits.follows_per_day',   '200', false, 'Cuentas que un usuario puede empezar a seguir cada 24 h')
on conflict (key) do nothing;

-- Avisa a la API (PostgREST) que recargue el esquema con las tablas nuevas.
notify pgrst, 'reload schema';
