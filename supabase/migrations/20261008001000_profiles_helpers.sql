-- =============================================================================
-- 0010 · Funciones de apoyo para perfiles y emprendimientos (Etapa 4)
-- =============================================================================
-- * search_cities: autocompletado de ciudades sin importar tildes ni errores
--   de tipeo ("villa maria", "rio cuarto", "cordova").
-- * is_business_slug_available: ¿la dirección /e/<slug> está libre? Incluye
--   borradores y emprendimientos eliminados (que RLS no deja ver) y palabras
--   reservadas.
-- =============================================================================

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
  province_name  text
)
language sql
stable
set search_path = ''
as $$
  with term as (select coalesce(public.normalize_text(q), '') as t)
  select c.id, c.name, c.slug, c.province_id, p.name
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

-- Slugs que no pueden usarse como dirección de un emprendimiento.
create or replace function public.is_reserved_slug(p_slug text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_slug = any (array[
    'admin', 'api', 'auth', 'buscar', 'panel', 'cuenta', 'ingresar', 'registrarse', 'recuperar',
    'salir', 'terminos', 'privacidad', 'ayuda', 'soporte', 'contacto', 'necesidades', 'categorias',
    'emprendedores', 'emprendimientos', 'nuevo', 'editar', 'worklink', 'www', 'static', 'assets'
  ]);
$$;

create or replace function public.is_business_slug_available(p_slug text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     and char_length(p_slug) between 3 and 80
     and not public.is_reserved_slug(p_slug)
     and not exists (select 1 from public.businesses b where b.slug = p_slug::extensions.citext);
$$;

revoke execute on function public.is_business_slug_available(text) from public, anon;
grant  execute on function public.is_business_slug_available(text) to authenticated;

-- Los slugs reservados también se bloquean en la tabla.
alter table public.businesses
  add constraint businesses_slug_not_reserved check (not public.is_reserved_slug(slug::text));

-- Avisa a la API (PostgREST) que recargue el esquema con las funciones nuevas.
notify pgrst, 'reload schema';
