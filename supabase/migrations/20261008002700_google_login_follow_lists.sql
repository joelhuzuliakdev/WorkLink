-- =============================================================================
-- 0027 · Ingresar con Google y listas de seguidores
-- =============================================================================
-- * handle_new_user: con Google, el nombre llega como given_name / family_name
--   (o full_name / name). Se toma de ahí; el usuario se arma con el email.
-- * profile_follow_ids: quiénes siguen a una persona y a quiénes sigue.
--   La tabla profile_follows solo deja ver los seguimientos propios (RLS);
--   esta función muestra las listas públicas (como en Instagram), solo a
--   usuarios con sesión, sin cuentas suspendidas ni personas bloqueadas.
-- =============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta       jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  full_name  text := nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name', '')), '');
  v_first    text;
  v_last     text;
  base_name  text;
  candidate  text;
  v_intent   public.user_intent;
  attempt    integer := 0;
begin
  -- Registro con email: first_name / last_name. Con Google: given_name / family_name o el nombre completo.
  v_first := coalesce(nullif(btrim(meta ->> 'first_name'), ''), nullif(btrim(meta ->> 'given_name'), ''));
  v_last  := coalesce(nullif(btrim(meta ->> 'last_name'), ''), nullif(btrim(meta ->> 'family_name'), ''));
  if v_first is null and full_name is not null then
    v_first := split_part(full_name, ' ', 1);
    v_last  := coalesce(v_last, nullif(btrim(substr(full_name, char_length(v_first) + 1)), ''));
  end if;

  base_name := regexp_replace(
    coalesce(public.normalize_text(meta ->> 'username'), split_part(coalesce(new.email, ''), '@', 1)),
    '[^a-z0-9_.]', '', 'g'
  );
  base_name := left(coalesce(nullif(base_name, ''), 'usuario'), 24);
  if char_length(base_name) < 3 then
    base_name := base_name || 'usr';
  end if;

  candidate := base_name;
  while exists (select 1 from public.profiles p where p.username = candidate::extensions.citext) loop
    attempt   := attempt + 1;
    candidate := base_name || lpad((floor(random() * 10000))::int::text, 4, '0');
    if attempt > 20 then
      candidate := base_name || replace(left(gen_random_uuid()::text, 6), '-', '');
    end if;
  end loop;

  v_intent := case when meta ->> 'intent' = 'provider' then 'provider'::public.user_intent
                   else 'seeker'::public.user_intent end;

  insert into public.profiles (id, username, first_name, last_name, intent)
  values (new.id, candidate, left(v_first, 60), left(v_last, 60), v_intent);

  return new;
end;
$$;

create or replace function public.profile_follow_ids(
  p_profile_id uuid,
  p_kind       text,
  p_limit      integer default 30,
  p_offset     integer default 0
)
returns table (id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
  from public.profile_follows f
  join public.profiles p on p.id = case when p_kind = 'followers' then f.follower_id else f.followed_id end
  where (select auth.uid()) is not null
    and p_kind in ('followers', 'following')
    and (case when p_kind = 'followers' then f.followed_id else f.follower_id end) = p_profile_id
    and p.status = 'active'
    and not public.is_blocked_between((select auth.uid()), p.id)
  order by f.created_at desc, p.id
  limit least(greatest(coalesce(p_limit, 30), 1), 100)
  offset least(greatest(coalesce(p_offset, 0), 0), 5000);
$$;

revoke execute on function public.profile_follow_ids(uuid, text, integer, integer) from public, anon;
grant  execute on function public.profile_follow_ids(uuid, text, integer, integer) to authenticated;

notify pgrst, 'reload schema';
