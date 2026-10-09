-- =============================================================================
-- 0023 · Que las necesidades se vean (inicio y buscador)
-- =============================================================================
-- * home_need_ids: necesidades abiertas para el inicio de cada usuario.
--   Primero las de su ciudad, las de personas que sigue y las del rubro de
--   sus emprendimientos; después el resto, de la más nueva a la más vieja.
-- * search_need_ids: buscador (texto en título y detalle, rubro y ciudad).
-- Las dos devuelven solo ids (la app trae los datos con RLS).
-- =============================================================================

create or replace function public.home_need_ids(p_limit integer default 3)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  with me as (
    select p.id, p.city_id, c.province_id
    from public.profiles p
    left join public.cities c on c.id = p.city_id
    where p.id = (select auth.uid())
  )
  select n.id
  from public.needs n
  cross join me
  where n.status in ('open', 'in_review')
    and n.deleted_at is null
    and n.expires_at > now()
  order by
    -- Cuánto le interesa: su ciudad, gente que sigue, rubro de sus emprendimientos, su provincia.
    (case when n.city_id = me.city_id then 4 else 0 end)
    + (case when exists (
        select 1 from public.profile_follows f where f.follower_id = me.id and f.followed_id = n.author_id
      ) then 3 else 0 end)
    + (case when exists (
        select 1
        from public.business_members bm
        join public.businesses b on b.id = bm.business_id
        where bm.user_id = me.id and b.category_id = n.category_id and b.deleted_at is null
      ) then 3 else 0 end)
    + (case when n.province_id = me.province_id then 1 else 0 end) desc,
    n.created_at desc,
    n.id desc
  limit least(greatest(coalesce(p_limit, 3), 1), 20);
$$;

create or replace function public.search_need_ids(
  p_query       text    default null,
  p_category_id integer default null,
  p_city_id     integer default null,
  p_limit       integer default 20,
  p_offset      integer default 0
)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select n.id
  from public.needs n
  where n.status in ('open', 'in_review')
    and n.deleted_at is null
    and n.expires_at > now()
    and (p_category_id is null or n.category_id = p_category_id)
    and (p_city_id is null or n.city_id = p_city_id)
    and (
      public.search_text(p_query) is null
      or (n.title || ' ' || n.description) ilike public.like_contains(p_query)
    )
  order by n.created_at desc, n.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 1000);
$$;

revoke execute on function public.home_need_ids(integer) from public, anon;
grant  execute on function public.home_need_ids(integer) to authenticated, service_role;
revoke execute on function public.search_need_ids(text, integer, integer, integer, integer) from public;
grant  execute on function public.search_need_ids(text, integer, integer, integer, integer) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
