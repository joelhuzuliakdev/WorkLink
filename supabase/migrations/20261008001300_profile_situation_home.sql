-- =============================================================================
-- 0013 · Situación en el perfil e inicio personalizado
-- =============================================================================
-- * Cada persona puede indicar su situación (busca empleo, tiene un
--   emprendimiento, ofrece servicios, busca contratar) y su rubro ("headline",
--   por ejemplo "Electricista matriculado"). Se muestran en el perfil y en sus
--   publicaciones.
-- * plan_tier en perfiles: lo administra el sistema (suscripciones, más
--   adelante). Las publicaciones de cuentas pagas son las "destacadas" del
--   inicio para quien todavía no sigue a nadie.
-- * El feed "Siguiendo" incluye también las publicaciones propias.
-- * Índices de trigramas para el buscador básico por palabra.
-- =============================================================================

create type public.profile_situation as enum ('job_seeking', 'entrepreneur', 'freelancer', 'hiring');

alter table public.profiles
  add column situation public.profile_situation,
  add column headline  text,
  add column plan_tier text not null default 'free',
  add constraint profiles_headline_len check (char_length(headline) <= 80),
  add constraint profiles_plan_tier check (plan_tier in ('free', 'pro', 'premium'));

grant select (situation, headline, plan_tier) on public.profiles to anon;

-- El plan solo lo cambia el sistema (pagos), nunca el usuario.
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

  if new.followers_count <> old.followers_count
     or new.following_count <> old.following_count
     or new.plan_tier <> old.plan_tier then
    raise exception 'Campo administrado por el sistema' using errcode = '42501';
  end if;

  if new.status is distinct from old.status and not (select public.has_role('moderator')) then
    raise exception 'Solo moderación puede cambiar el estado de una cuenta' using errcode = '42501';
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Feed "Siguiendo": ahora incluye las publicaciones propias.
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
      p.author_id = (select auth.uid())
      or p.author_id in (select f.followed_id from public.profile_follows f where f.follower_id = (select auth.uid()))
      or p.business_id in (select f.business_id from public.business_follows f where f.follower_id = (select auth.uid()))
    )
  order by p.published_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

-- -----------------------------------------------------------------------------
-- Destacadas: publicaciones de cuentas o emprendimientos con plan pago.
-- -----------------------------------------------------------------------------
create or replace function public.featured_feed_ids(
  p_before_at timestamptz default null,
  p_before_id uuid        default null,
  p_limit     integer     default 20
)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id
  from public.posts p
  left join public.profiles a on a.id = p.author_id
  left join public.businesses b on b.id = p.business_id
  where p.status = 'published'
    and p.deleted_at is null
    and (p_before_at is null or (p.published_at, p.id) < (p_before_at, coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    and (coalesce(a.plan_tier, 'free') <> 'free' or coalesce(b.plan_tier, 'free') <> 'free')
  order by p.published_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.featured_feed_ids(timestamptz, uuid, integer) from public;
grant  execute on function public.featured_feed_ids(timestamptz, uuid, integer) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Buscador básico por palabra (ILIKE acelerado con índices de trigramas).
-- La Etapa 7 suma búsqueda por relevancia, rubros y ciudades.
-- -----------------------------------------------------------------------------
create extension if not exists pg_trgm with schema extensions;

create index if not exists profiles_search_trgm_idx on public.profiles
  using gin ((coalesce(first_name, '') || ' ' || coalesce(last_name, '') || ' ' || username::text || ' ' || coalesce(headline, '')) extensions.gin_trgm_ops);

create index if not exists businesses_name_trgm_idx on public.businesses
  using gin (name extensions.gin_trgm_ops);

create index if not exists posts_body_trgm_idx on public.posts
  using gin ((coalesce(title, '') || ' ' || body) extensions.gin_trgm_ops);

-- Personas que coinciden con el texto (nombre, apellido, usuario o rubro).
-- Devuelve solo ids: la app trae después las columnas públicas (así no se
-- exponen datos de contacto a quien no tiene permiso de verlos).
create or replace function public.search_profile_ids(p_query text, p_limit integer default 12)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id
  from public.profiles p
  where p.status = 'active'
    and char_length(btrim(p_query)) >= 2
    and (coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || p.username::text || ' ' || coalesce(p.headline, ''))
        ilike '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  order by p.plan_tier <> 'free' desc, p.followers_count desc, p.created_at desc
  limit least(greatest(coalesce(p_limit, 12), 1), 30);
$$;

-- Publicaciones que contienen el texto (título o cuerpo), de la más nueva a la más vieja.
create or replace function public.search_post_ids(p_query text, p_limit integer default 20)
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
    and char_length(btrim(p_query)) >= 2
    and (coalesce(p.title, '') || ' ' || p.body)
        ilike '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  order by p.published_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.search_profile_ids(text, integer) from public;
revoke execute on function public.search_post_ids(text, integer) from public;
grant  execute on function public.search_profile_ids(text, integer) to anon, authenticated, service_role;
grant  execute on function public.search_post_ids(text, integer) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
