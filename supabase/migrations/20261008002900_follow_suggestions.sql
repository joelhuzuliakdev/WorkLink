-- =============================================================================
-- 0029 · "A quién seguir": sugerencias de personas y emprendimientos
-- =============================================================================
-- Para que el inicio de quien recién llega no esté vacío. Primero lo de su
-- ciudad, después su provincia; suman los verificados, los que tienen foto,
-- los que publicaron hace poco y los más seguidos. Nunca: la propia cuenta,
-- lo que ya sigue, cuentas suspendidas ni personas con bloqueo.
-- Devuelven solo ids (la app trae los datos con RLS).
-- =============================================================================

create or replace function public.suggested_profile_ids(p_limit integer default 6)
returns table (id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select p.id, p.city_id, c.province_id
    from public.profiles p
    left join public.cities c on c.id = p.city_id
    where p.id = (select auth.uid())
  )
  select p.id
  from public.profiles p
  cross join me
  left join public.cities c on c.id = p.city_id
  where p.id <> me.id
    and p.status = 'active'
    and not exists (select 1 from public.profile_follows f where f.follower_id = me.id and f.followed_id = p.id)
    and not public.is_blocked_between(me.id, p.id)
  order by
    (case when p.city_id = me.city_id then 4 when c.province_id = me.province_id then 2 else 0 end)
    + (case when p.verified_at is not null then 2 else 0 end)
    + (case when p.avatar_path is not null then 1 else 0 end)
    + (case when exists (
        select 1 from public.posts po
        where po.author_id = p.id and po.status = 'published' and po.deleted_at is null and po.published_at > now() - interval '30 days'
      ) then 2 else 0 end)
    + (case when p.plan_tier <> 'free' then 1 else 0 end) desc,
    p.followers_count desc,
    p.created_at desc
  limit least(greatest(coalesce(p_limit, 6), 1), 20);
$$;

create or replace function public.suggested_business_ids(p_limit integer default 6)
returns table (id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select p.id, p.city_id, c.province_id
    from public.profiles p
    left join public.cities c on c.id = p.city_id
    where p.id = (select auth.uid())
  )
  select b.id
  from public.businesses b
  cross join me
  left join public.cities c on c.id = b.city_id
  where b.status = 'active'
    and b.deleted_at is null
    and b.owner_id <> me.id
    and not exists (select 1 from public.business_members bm where bm.business_id = b.id and bm.user_id = me.id)
    and not exists (select 1 from public.business_follows f where f.follower_id = me.id and f.business_id = b.id)
    and not public.is_blocked_between(me.id, b.owner_id)
  order by
    (case when b.city_id = me.city_id then 4 when c.province_id = me.province_id then 2 else 0 end)
    + (case when b.verification = 'verified' then 2 else 0 end)
    + (case when b.logo_path is not null then 1 else 0 end)
    + (case when b.rating_count > 0 then 1 else 0 end)
    + (case when b.plan_tier <> 'free' then 1 else 0 end) desc,
    b.followers_count desc,
    b.created_at desc
  limit least(greatest(coalesce(p_limit, 6), 1), 20);
$$;

revoke execute on function public.suggested_profile_ids(integer) from public, anon;
revoke execute on function public.suggested_business_ids(integer) from public, anon;
grant execute on function public.suggested_profile_ids(integer) to authenticated;
grant execute on function public.suggested_business_ids(integer) to authenticated;

notify pgrst, 'reload schema';
