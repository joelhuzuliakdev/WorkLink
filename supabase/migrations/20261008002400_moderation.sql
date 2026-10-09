-- =============================================================================
-- 0024 · Panel de administración y moderación (Etapa 12)
-- =============================================================================
-- * moderate(): ÚNICA puerta para las decisiones de moderación (ocultar o
--   restaurar reseñas, publicaciones y necesidades; borrar comentarios;
--   suspender o reactivar cuentas y emprendimientos; verificar). Revisa el rol
--   en la base, aplica el cambio, cierra las denuncias de ese contenido y deja
--   registro en moderation_actions.
-- * set_staff_role(): solo super_admin da o quita roles de staff.
-- * admin_stats() y admin_report_groups(): números del resumen y denuncias
--   agrupadas por contenido, solo para staff.
-- * Un moderador no puede actuar sobre otra cuenta de staff de su mismo
--   nivel o superior, ni sobre su propia cuenta.
-- =============================================================================

create table public.moderation_actions (
  id            uuid primary key default gen_random_uuid(),
  moderator_id  uuid references public.profiles (id) on delete set null,
  target_type   public.report_target not null,
  target_id     uuid not null,
  action        text not null,
  note          text,
  created_at    timestamptz not null default now(),
  constraint moderation_actions_note_len check (note is null or char_length(note) <= 500)
);

create index moderation_actions_recent_idx on public.moderation_actions (created_at desc);
create index moderation_actions_target_idx on public.moderation_actions (target_type, target_id);

alter table public.moderation_actions enable row level security;

create policy "moderation_actions: solo staff" on public.moderation_actions
  for select to authenticated
  using ((select public.has_role('moderator')));

revoke all on public.moderation_actions from anon, authenticated;
grant select on public.moderation_actions to authenticated;

-- Todo el equipo ve quién más es del equipo (para no moderarse entre sí por
-- error); el resto de las personas solo ve su propio rol.
drop policy if exists "user_roles: cada uno ve su rol, admin ve todos" on public.user_roles;
create policy "user_roles: cada uno ve su rol, el equipo ve todos" on public.user_roles
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.has_role('moderator')));

-- Rol de staff de una cuenta (null si no tiene). Solo se responde sobre la
-- propia cuenta o si quien pregunta es del equipo (no se expone quién es staff).
create or replace function public.staff_role_of(p_user_id uuid)
returns public.staff_role
language sql
stable
security definer
set search_path = ''
as $$
  select ur.role
  from public.user_roles ur
  where ur.user_id = p_user_id
    and (
      p_user_id = (select auth.uid())
      or exists (select 1 from public.user_roles me where me.user_id = (select auth.uid()))
    );
$$;

revoke execute on function public.staff_role_of(uuid) from public, anon;
grant  execute on function public.staff_role_of(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Decisiones de moderación
-- -----------------------------------------------------------------------------
create or replace function public.moderate(
  p_target_type public.report_target,
  p_target_id   uuid,
  p_action      text,
  p_note        text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me        uuid := (select auth.uid());
  my_role   public.staff_role := public.staff_role_of((select auth.uid()));
  owner     uuid;   -- dueño del contenido (para no actuar sobre staff superior)
  done      integer := 0;
  v_note    text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if me is null or my_role is null then
    raise exception 'Solo el equipo de moderación puede hacer esto' using errcode = '42501';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'La nota puede tener hasta 500 caracteres' using errcode = '23514';
  end if;
  if p_action not in ('hide', 'restore', 'delete', 'suspend', 'reactivate', 'verify', 'unverify', 'dismiss') then
    raise exception 'Acción desconocida' using errcode = '22023';
  end if;

  -- Quién es el dueño del contenido.
  owner := case p_target_type
    when 'review'   then (select r.author_id from public.reviews r where r.id = p_target_id)
    when 'post'     then (select p.author_id from public.posts p where p.id = p_target_id)
    when 'comment'  then (select c.author_id from public.post_comments c where c.id = p_target_id)
    when 'profile'  then (select p.id from public.profiles p where p.id = p_target_id)
    when 'business' then (select b.owner_id from public.businesses b where b.id = p_target_id)
    when 'need'     then (select n.author_id from public.needs n where n.id = p_target_id)
  end;
  if owner is null and p_action <> 'dismiss' then
    raise exception 'El contenido ya no existe' using errcode = '42501';
  end if;

  if p_action <> 'dismiss' and owner is not null then
    if owner = me and p_target_type = 'profile' then
      raise exception 'No podés moderar tu propia cuenta' using errcode = '42501';
    end if;
    if owner <> me and public.staff_role_of(owner) is not null and public.staff_role_of(owner) >= my_role then
      raise exception 'No podés moderar a alguien del equipo con tu mismo rol o superior' using errcode = '42501';
    end if;
  end if;

  if p_action in ('verify', 'unverify') and my_role < 'admin' then
    raise exception 'Solo la administración puede verificar cuentas' using errcode = '42501';
  end if;

  if p_action = 'dismiss' then
    done := 1;
  elsif p_target_type = 'review' then
    if p_action = 'hide' then
      update public.reviews set status = 'removed' where id = p_target_id;
    elsif p_action = 'restore' then
      update public.reviews set status = 'published', reports_count = 0 where id = p_target_id;
    elsif p_action = 'delete' then
      delete from public.reviews where id = p_target_id;
    end if;
    get diagnostics done = row_count;
  elsif p_target_type = 'post' then
    if p_action = 'hide' then
      update public.posts set status = 'removed' where id = p_target_id;
    elsif p_action = 'restore' then
      update public.posts set status = 'published' where id = p_target_id and status = 'removed';
    end if;
    get diagnostics done = row_count;
  elsif p_target_type = 'comment' then
    if p_action in ('hide', 'delete') then
      delete from public.post_comments where id = p_target_id;
    end if;
    get diagnostics done = row_count;
  elsif p_target_type = 'need' then
    if p_action in ('hide', 'delete') then
      update public.needs set deleted_at = now(), status = 'closed', closed_at = coalesce(closed_at, now()) where id = p_target_id;
    elsif p_action = 'restore' then
      update public.needs set deleted_at = null where id = p_target_id;
    end if;
    get diagnostics done = row_count;
  elsif p_target_type = 'business' then
    if p_action in ('hide', 'suspend') then
      update public.businesses set status = 'suspended' where id = p_target_id;
    elsif p_action in ('restore', 'reactivate') then
      update public.businesses set status = 'active' where id = p_target_id and status = 'suspended';
    elsif p_action = 'verify' then
      update public.businesses set verification = 'verified', verified_at = now() where id = p_target_id;
    elsif p_action = 'unverify' then
      update public.businesses set verification = 'none', verified_at = null where id = p_target_id;
    end if;
    get diagnostics done = row_count;
  elsif p_target_type = 'profile' then
    if p_action in ('hide', 'suspend') then
      update public.profiles set status = 'suspended' where id = p_target_id;
    elsif p_action in ('restore', 'reactivate') then
      update public.profiles set status = 'active' where id = p_target_id;
    elsif p_action = 'verify' then
      update public.profiles set verified_at = now() where id = p_target_id;
    elsif p_action = 'unverify' then
      update public.profiles set verified_at = null where id = p_target_id;
    end if;
    get diagnostics done = row_count;
  end if;

  if done = 0 then
    raise exception 'Esa acción no aplica a este contenido' using errcode = '22023';
  end if;

  -- Cierra las denuncias abiertas de ese contenido.
  if p_action not in ('verify', 'unverify') then
    update public.reports
    set status = case when p_action in ('dismiss', 'restore', 'reactivate') then 'dismissed'::public.report_status else 'resolved'::public.report_status end,
        resolved_at = now(),
        resolved_by = me,
        resolution_note = v_note
    where target_type = p_target_type and target_id = p_target_id and status = 'open';
  end if;

  insert into public.moderation_actions (moderator_id, target_type, target_id, action, note)
  values (me, p_target_type, p_target_id, p_action, v_note);
end;
$$;

revoke execute on function public.moderate(public.report_target, uuid, text, text) from public, anon;
grant  execute on function public.moderate(public.report_target, uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Roles del equipo (solo super_admin)
-- -----------------------------------------------------------------------------
create or replace function public.set_staff_role(p_user_id uuid, p_role public.staff_role)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null or public.staff_role_of(me) is distinct from 'super_admin' then
    raise exception 'Solo super administración asigna roles' using errcode = '42501';
  end if;
  if p_user_id = me then
    raise exception 'No podés cambiar tu propio rol' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'La cuenta no existe' using errcode = '42501';
  end if;

  if p_role is null then
    delete from public.user_roles where user_id = p_user_id;
  else
    insert into public.user_roles (user_id, role, granted_by)
    values (p_user_id, p_role, me)
    on conflict (user_id) do update set role = excluded.role, granted_by = excluded.granted_by;
  end if;

  insert into public.moderation_actions (moderator_id, target_type, target_id, action, note)
  values (me, 'profile', p_user_id, 'role', coalesce(p_role::text, 'sin rol'));
end;
$$;

revoke execute on function public.set_staff_role(uuid, public.staff_role) from public, anon;
grant  execute on function public.set_staff_role(uuid, public.staff_role) to authenticated;

-- -----------------------------------------------------------------------------
-- Números del resumen
-- -----------------------------------------------------------------------------
create or replace function public.admin_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select public.has_role('moderator')) then
    raise exception 'Solo staff' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'users',            (select count(*) from public.profiles),
    'users_week',       (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'users_suspended',  (select count(*) from public.profiles where status <> 'active'),
    'businesses',       (select count(*) from public.businesses where status = 'active' and deleted_at is null),
    'businesses_week',  (select count(*) from public.businesses where created_at > now() - interval '7 days' and deleted_at is null),
    'posts',            (select count(*) from public.posts where status = 'published' and deleted_at is null),
    'posts_week',       (select count(*) from public.posts where created_at > now() - interval '7 days' and deleted_at is null),
    'needs_open',       (select count(*) from public.needs where status in ('open', 'in_review') and deleted_at is null and expires_at > now()),
    'needs_awarded',    (select count(*) from public.needs where status = 'awarded'),
    'proposals_week',   (select count(*) from public.proposals where created_at > now() - interval '7 days'),
    'messages_week',    (select count(*) from public.messages where created_at > now() - interval '7 days'),
    'reviews',          (select count(*) from public.reviews where status = 'published'),
    'reports_open',     (select count(*) from public.reports where status = 'open'),
    'reviews_hidden',   (select count(*) from public.reviews where status = 'hidden')
  );
end;
$$;

revoke execute on function public.admin_stats() from public, anon;
grant  execute on function public.admin_stats() to authenticated;

-- Denuncias agrupadas por contenido (lo más denunciado y reciente primero).
create or replace function public.admin_report_groups(p_status public.report_status default 'open', p_limit integer default 50)
returns table (
  target_type  public.report_target,
  target_id    uuid,
  reports      integer,
  reasons      text[],
  details      text[],
  last_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select public.has_role('moderator')) then
    raise exception 'Solo staff' using errcode = '42501';
  end if;
  return query
    select r.target_type, r.target_id, count(*)::integer,
           array_agg(distinct r.reason::text),
           (array_agg(r.details order by r.created_at desc) filter (where r.details is not null))[1:5],
           max(r.created_at)
    from public.reports r
    where r.status = p_status
    group by r.target_type, r.target_id
    order by count(*) desc, max(r.created_at) desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

revoke execute on function public.admin_report_groups(public.report_status, integer) from public, anon;
grant  execute on function public.admin_report_groups(public.report_status, integer) to authenticated;

notify pgrst, 'reload schema';
