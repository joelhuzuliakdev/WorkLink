-- =============================================================================
-- 0014 · Buscador con filtros y directorio por rubro y ciudad (Etapa 7)
-- =============================================================================
-- * Búsquedas con filtros opcionales (texto, rubro, especialidad, ciudad,
--   provincia, tipo, situación). Sin texto, funcionan como directorio.
--   Devuelven solo ids; la app trae después las columnas públicas.
-- * Conteos por rubro y ciudad para las páginas del directorio y el sitemap.
-- * Los umbrales SEO pasan a ser públicos (la app decide si una página de
--   directorio se indexa según cuántos emprendimientos tiene).
-- Todas las funciones son SECURITY INVOKER: respetan RLS como cualquier consulta.
-- =============================================================================

-- "%texto%" con los comodines de LIKE escapados (busca el texto tal cual).
create or replace function public.like_contains(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '%' || replace(replace(replace(btrim(p_text), '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

-- Texto de búsqueda válido (2+ caracteres) o null.
create or replace function public.search_text(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when char_length(btrim(coalesce(p_text, ''))) >= 2 then btrim(p_text) end;
$$;

grant execute on function public.like_contains(text) to anon, authenticated, service_role;
grant execute on function public.search_text(text) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Ciudades: departamento (para distinguir localidades con el mismo nombre en
-- una provincia, por ejemplo "San José" de Tulumba y de San Javier). Lo
-- completa el importador de localidades (scripts/importar-localidades.mjs).
-- -----------------------------------------------------------------------------
alter table public.cities add column if not exists department text;

drop function if exists public.search_cities(text, smallint, integer);
create or replace function public.search_cities(
  q              text,
  p_province_id  smallint default null,
  max_results    integer  default 10
)
returns table (
  id             integer,
  name           text,
  slug           text,
  province_id    smallint,
  province_name  text,
  department     text
)
language sql
stable
set search_path = ''
as $$
  with term as (select coalesce(public.normalize_text(q), '') as t)
  select c.id, c.name, c.slug, c.province_id, p.name, c.department
  from public.cities c
  join public.provinces p on p.id = c.province_id
  where c.active
    and (p_province_id is null or c.province_id = p_province_id)
    and (
      (select t from term) = ''
      or public.normalize_text(c.name) like (select t from term) || '%'
      or public.normalize_text(c.name) like '% ' || (select t from term) || '%'
      or extensions.word_similarity((select t from term), public.normalize_text(c.name)) >= 0.45
    )
  order by
    (public.normalize_text(c.name) like (select t from term) || '%') desc,
    extensions.word_similarity((select t from term), public.normalize_text(c.name)) desc,
    c.population desc nulls last,
    c.name
  limit least(greatest(coalesce(max_results, 10), 1), 25);
$$;

grant execute on function public.search_cities(text, smallint, integer) to anon, authenticated;

-- Índice para buscar emprendimientos por nombre o frase corta.
drop index if exists public.businesses_name_trgm_idx;
create index if not exists businesses_search_trgm_idx on public.businesses
  using gin ((name || ' ' || coalesce(tagline, '')) extensions.gin_trgm_ops);

create index if not exists businesses_province_idx on public.businesses (province_id)
  where status = 'active' and deleted_at is null;

-- Reemplazan a las versiones de la migración 0013 (con menos parámetros).
drop function if exists public.search_profile_ids(text, integer);
drop function if exists public.search_post_ids(text, integer);

-- -----------------------------------------------------------------------------
-- Emprendimientos
-- -----------------------------------------------------------------------------
create or replace function public.search_business_ids(
  p_query          text     default null,
  p_category_id    integer  default null,
  p_subcategory_id integer  default null,
  p_city_id        integer  default null,
  p_province_id    smallint default null,
  p_limit          integer  default 20,
  p_offset         integer  default 0
)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select b.id
  from public.businesses b
  where b.status = 'active'
    and b.deleted_at is null
    and (p_category_id is null or b.category_id = p_category_id)
    and (p_subcategory_id is null or exists (
      select 1 from public.business_subcategories bs
      where bs.business_id = b.id and bs.subcategory_id = p_subcategory_id
    ))
    and (p_city_id is null or b.city_id = p_city_id)
    and (p_province_id is null or b.province_id = p_province_id)
    and (
      public.search_text(p_query) is null
      or (b.name || ' ' || coalesce(b.tagline, '')) ilike public.like_contains(p_query)
    )
  order by (b.plan_tier <> 'free') desc,
           (b.verification = 'verified') desc,
           b.search_boost desc,
           b.followers_count desc,
           b.created_at desc,
           b.id
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 1000);
$$;

-- -----------------------------------------------------------------------------
-- Personas
-- -----------------------------------------------------------------------------
create or replace function public.search_profile_ids(
  p_query     text                     default null,
  p_city_id   integer                  default null,
  p_situation public.profile_situation default null,
  p_limit     integer                  default 20,
  p_offset    integer                  default 0
)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id
  from public.profiles p
  where p.status = 'active'
    and (p_city_id is null or p.city_id = p_city_id)
    and (p_situation is null or p.situation = p_situation)
    and (
      public.search_text(p_query) is null
      or (coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || p.username::text || ' ' || coalesce(p.headline, ''))
         ilike public.like_contains(p_query)
    )
    -- Sin ningún filtro no se listan personas (privacidad: no es un padrón).
    and (public.search_text(p_query) is not null or p_city_id is not null or p_situation is not null)
  order by (p.plan_tier <> 'free') desc, p.followers_count desc, p.created_at desc, p.id
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 1000);
$$;

-- -----------------------------------------------------------------------------
-- Publicaciones
-- -----------------------------------------------------------------------------
create or replace function public.search_post_ids(
  p_query       text             default null,
  p_type        public.post_type default null,
  p_category_id integer          default null,
  p_city_id     integer          default null,
  p_limit       integer          default 20,
  p_offset      integer          default 0
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
    and (p_category_id is null or p.category_id = p_category_id)
    and (p_city_id is null or p.city_id = p_city_id)
    and (
      public.search_text(p_query) is null
      or (coalesce(p.title, '') || ' ' || p.body) ilike public.like_contains(p_query)
    )
  order by p.published_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 1000);
$$;

revoke execute on function public.search_business_ids(text, integer, integer, integer, smallint, integer, integer) from public;
revoke execute on function public.search_profile_ids(text, integer, public.profile_situation, integer, integer) from public;
revoke execute on function public.search_post_ids(text, public.post_type, integer, integer, integer, integer) from public;
grant execute on function public.search_business_ids(text, integer, integer, integer, smallint, integer, integer) to anon, authenticated, service_role;
grant execute on function public.search_profile_ids(text, integer, public.profile_situation, integer, integer) to anon, authenticated, service_role;
grant execute on function public.search_post_ids(text, public.post_type, integer, integer, integer, integer) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Directorio: rubros con cantidad de emprendimientos activos
-- -----------------------------------------------------------------------------
create or replace function public.directory_categories()
returns table (id integer, name text, slug text, seo_noun text, description text, businesses bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.name, c.slug, c.seo_noun, c.description,
         count(b.id) filter (where b.status = 'active' and b.deleted_at is null) as businesses
  from public.categories c
  left join public.businesses b on b.category_id = c.id
  where c.active
  group by c.id
  order by c.sort_order, c.name;
$$;

-- Ciudades con emprendimientos de un rubro (para su página y sus enlaces).
create or replace function public.directory_category_cities(p_category_id integer, p_limit integer default 40)
returns table (
  city_id integer, city_name text, city_slug text,
  province_id smallint, province_name text, province_slug text,
  businesses bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select ci.id, ci.name, ci.slug, pr.id, pr.name, pr.slug, count(*) as businesses
  from public.businesses b
  join public.cities ci on ci.id = b.city_id
  join public.provinces pr on pr.id = ci.province_id
  where b.category_id = p_category_id
    and b.status = 'active'
    and b.deleted_at is null
  group by ci.id, pr.id
  order by count(*) desc, ci.name
  limit least(greatest(coalesce(p_limit, 40), 1), 200);
$$;

-- Pares rubro + ciudad con al menos p_min emprendimientos (sitemap).
create or replace function public.directory_landing_pairs(p_min integer default 3)
returns table (category_slug text, province_slug text, city_slug text, businesses bigint, last_updated timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.slug, pr.slug, ci.slug, count(*), max(b.updated_at)
  from public.businesses b
  join public.categories c on c.id = b.category_id and c.active
  join public.cities ci on ci.id = b.city_id
  join public.provinces pr on pr.id = ci.province_id
  where b.status = 'active' and b.deleted_at is null
  group by c.slug, pr.slug, ci.slug
  having count(*) >= greatest(coalesce(p_min, 3), 1)
  order by count(*) desc
  limit 45000;
$$;

grant execute on function public.directory_categories() to anon, authenticated, service_role;
grant execute on function public.directory_category_cities(integer, integer) to anon, authenticated, service_role;
grant execute on function public.directory_landing_pairs(integer) to anon, authenticated, service_role;

-- Rubros con emprendimientos en una ciudad (enlaces "Otros rubros en ...").
create or replace function public.directory_city_categories(p_city_id integer)
returns table (id integer, name text, slug text, businesses bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.name, c.slug, count(*)
  from public.businesses b
  join public.categories c on c.id = b.category_id and c.active
  where b.city_id = p_city_id and b.status = 'active' and b.deleted_at is null
  group by c.id
  order by count(*) desc, c.name;
$$;

grant execute on function public.directory_city_categories(integer) to anon, authenticated, service_role;

-- El orden de resultados usa search_boost: visible también sin sesión (no es sensible).
grant select (search_boost) on public.businesses to anon;

-- Umbrales SEO legibles por la app sin sesión.
update public.settings set is_public = true where key like 'seo.%';

notify pgrst, 'reload schema';
