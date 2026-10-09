-- =============================================================================
-- 0022 · Reseñas, calificaciones y denuncias (Etapa 11)
-- =============================================================================
-- * Se califica a un emprendimiento o a una persona con 1 a 5 estrellas y un
--   comentario opcional. Una reseña por persona y por emprendimiento/persona
--   (se puede editar o borrar).
-- * Solo opina quien tuvo un trato real (para evitar reseñas falsas):
--     - "Contrató por WorkLink": aceptó una propuesta de ese emprendimiento o
--       de esa persona (Etapa 10). La reseña se marca como verificada.
--     - "Habló por WorkLink": tienen una conversación privada en la que los
--       DOS escribieron.
--   Nadie se califica a sí mismo ni a su propio emprendimiento, y no se puede
--   opinar si hay un bloqueo entre las partes.
-- * El emprendimiento (dueño o editores) o la persona calificada puede
--   responder una vez (y editar la respuesta).
-- * Promedio y cantidad se guardan en businesses / profiles y los recalcula
--   la base: nadie los puede tocar desde la app.
-- * Denuncias: cualquiera con cuenta puede denunciar una reseña. Con 3
--   denuncias de personas distintas (sin contar al emprendimiento calificado)
--   la reseña se oculta hasta que moderación la revise (Etapa 12).
-- * Avisos: reseña nueva → al emprendimiento/persona; respuesta → a quien
--   escribió la reseña.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Calificación de personas (los emprendimientos ya tienen sus columnas)
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists rating_sum   integer not null default 0,
  add column if not exists rating_count integer not null default 0,
  add constraint profiles_rating_nonneg check (rating_sum >= 0 and rating_count >= 0);

grant select (rating_sum, rating_count) on public.profiles to anon;

-- Protección del perfil: se suman los campos de calificación.
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
     or new.plan_tier <> old.plan_tier
     or new.rating_sum <> old.rating_sum
     or new.rating_count <> old.rating_count then
    raise exception 'Campo administrado por el sistema' using errcode = '42501';
  end if;

  if new.verified_at is distinct from old.verified_at and not (select public.has_role('admin')) then
    raise exception 'Solo la administración puede verificar cuentas' using errcode = '42501';
  end if;

  if new.status is distinct from old.status and not (select public.has_role('moderator')) then
    raise exception 'Solo moderación puede cambiar el estado de una cuenta' using errcode = '42501';
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Reseñas
-- -----------------------------------------------------------------------------
create table public.reviews (
  id             uuid primary key default gen_random_uuid(),
  author_id      uuid not null references public.profiles (id) on delete cascade,
  business_id    uuid references public.businesses (id) on delete cascade,
  profile_id     uuid references public.profiles (id) on delete cascade,
  proposal_id    uuid references public.proposals (id) on delete set null,
  rating         smallint not null,
  body           text,
  verified       boolean not null default false,
  reply          text,
  reply_at       timestamptz,
  status         public.content_status not null default 'published',
  reports_count  integer not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  edited_at      timestamptz,
  constraint reviews_one_subject check (num_nonnulls(business_id, profile_id) = 1),
  constraint reviews_not_self check (profile_id is null or profile_id <> author_id),
  constraint reviews_rating check (rating between 1 and 5),
  constraint reviews_body_len check (body is null or char_length(body) between 1 and 1000),
  constraint reviews_reply_len check (reply is null or char_length(reply) between 1 and 1000),
  constraint reviews_reports_nonneg check (reports_count >= 0)
);

create unique index reviews_one_per_business on public.reviews (author_id, business_id) where business_id is not null;
create unique index reviews_one_per_profile on public.reviews (author_id, profile_id) where profile_id is not null;
create index reviews_business_idx on public.reviews (business_id, created_at desc) where business_id is not null;
create index reviews_profile_idx on public.reviews (profile_id, created_at desc) where profile_id is not null;
create index reviews_author_idx on public.reviews (author_id, created_at desc);

create trigger reviews_set_updated_at
  before update on public.reviews
  for each row execute function public.set_updated_at();

alter table public.notifications
  add column if not exists review_id uuid references public.reviews (id) on delete cascade;

create unique index if not exists notifications_review_once
  on public.notifications (recipient_id, review_id, type) where review_id is not null;

-- -----------------------------------------------------------------------------
-- ¿El usuario actual puede calificar a este emprendimiento o persona?
-- Devuelve: 'hired' (contrató por WorkLink), 'contacted' (hablaron por
-- mensajes), o el motivo por el que no: 'login', 'invalid', 'self',
-- 'unavailable', 'blocked', 'none'.
-- -----------------------------------------------------------------------------
create or replace function public.review_eligibility(p_business_id uuid, p_profile_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me     uuid := (select auth.uid());
  target uuid;   -- la persona del otro lado (dueño del emprendimiento o la persona)
begin
  if me is null then
    return 'login';
  end if;
  if num_nonnulls(p_business_id, p_profile_id) <> 1 then
    return 'invalid';
  end if;

  if p_business_id is not null then
    select b.owner_id into target
    from public.businesses b
    where b.id = p_business_id and b.status = 'active' and b.deleted_at is null;
    if target is null then
      return 'unavailable';
    end if;
    if exists (select 1 from public.business_members bm where bm.business_id = p_business_id and bm.user_id = me) then
      return 'self';
    end if;
  else
    select p.id into target from public.profiles p where p.id = p_profile_id and p.status = 'active';
    if target is null then
      return 'unavailable';
    end if;
    if target = me then
      return 'self';
    end if;
  end if;

  if public.is_blocked_between(me, target) then
    return 'blocked';
  end if;

  -- Contrató: aceptó una propuesta de ese emprendimiento o de esa persona.
  if exists (
    select 1
    from public.proposals pr
    join public.needs n on n.id = pr.need_id
    where pr.status = 'accepted'
      and n.author_id = me
      and (
        (p_business_id is not null and pr.business_id = p_business_id)
        or (p_profile_id is not null and pr.author_id = p_profile_id)
      )
  ) then
    return 'hired';
  end if;

  -- Hablaron: conversación en la que escribieron los dos.
  if exists (
    select 1
    from public.conversations c
    where c.user_low = least(me, target) and c.user_high = greatest(me, target)
      and exists (select 1 from public.messages m where m.conversation_id = c.id and m.sender_id = me)
      and exists (select 1 from public.messages m where m.conversation_id = c.id and m.sender_id = target)
  ) then
    return 'contacted';
  end if;

  return 'none';
end;
$$;

revoke execute on function public.review_eligibility(uuid, uuid) from public, anon;
grant  execute on function public.review_eligibility(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Promedios (los recalcula la base; nunca la app)
-- -----------------------------------------------------------------------------
create or replace function public.recompute_rating(p_business_id uuid, p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('worklink.counter_update', 'on', true);
  if p_business_id is not null then
    update public.businesses b
    set rating_sum   = coalesce(s.total, 0),
        rating_count = coalesce(s.cnt, 0),
        rating_dist  = array[coalesce(s.d1, 0), coalesce(s.d2, 0), coalesce(s.d3, 0), coalesce(s.d4, 0), coalesce(s.d5, 0)]
    from (
      select sum(r.rating)::integer as total, count(*)::integer as cnt,
             (count(*) filter (where r.rating = 1))::integer as d1,
             (count(*) filter (where r.rating = 2))::integer as d2,
             (count(*) filter (where r.rating = 3))::integer as d3,
             (count(*) filter (where r.rating = 4))::integer as d4,
             (count(*) filter (where r.rating = 5))::integer as d5
      from public.reviews r
      where r.business_id = p_business_id and r.status = 'published'
    ) s
    where b.id = p_business_id;
  end if;
  if p_profile_id is not null then
    update public.profiles p
    set rating_sum   = coalesce(s.total, 0),
        rating_count = coalesce(s.cnt, 0)
    from (
      select sum(r.rating)::integer as total, count(*)::integer as cnt
      from public.reviews r
      where r.profile_id = p_profile_id and r.status = 'published'
    ) s
    where p.id = p_profile_id;
  end if;
  perform set_config('worklink.counter_update', 'off', true);
end;
$$;

revoke execute on function public.recompute_rating(uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Reglas al escribir o editar una reseña
-- -----------------------------------------------------------------------------
-- (Sin SECURITY DEFINER: así is_system_call() distingue la app de la base.)
create or replace function public.tg_reviews_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  eligibility text;
begin
  if new.body is not null then
    new.body := nullif(btrim(new.body), '');
  end if;

  if public.is_system_call() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.author_id     := (select auth.uid());
    new.status        := 'published';
    new.reply         := null;
    new.reply_at      := null;
    new.reports_count := 0;
    new.edited_at     := null;
    new.created_at    := now();

    eligibility := public.review_eligibility(new.business_id, new.profile_id);
    if eligibility = 'self' then
      raise exception 'No podés calificarte a vos mismo' using errcode = '42501';
    elsif eligibility = 'blocked' then
      raise exception 'No podés calificar a esta persona' using errcode = '42501';
    elsif eligibility in ('unavailable', 'invalid', 'login') then
      raise exception 'No se puede calificar a esta cuenta' using errcode = '42501';
    elsif eligibility = 'none' then
      raise exception 'Solo pueden opinar quienes contrataron o hablaron por mensajes con esta cuenta en WorkLink'
        using errcode = '42501';
    end if;

    new.verified := eligibility = 'hired';
    if new.verified then
      select pr.id into new.proposal_id
      from public.proposals pr
      join public.needs n on n.id = pr.need_id
      where pr.status = 'accepted' and n.author_id = new.author_id
        and ((new.business_id is not null and pr.business_id = new.business_id)
          or (new.profile_id is not null and pr.author_id = new.profile_id))
      order by pr.decided_at desc nulls last
      limit 1;
    else
      new.proposal_id := null;
    end if;

    perform public.enforce_rate_limit(
      (select count(*) from public.reviews r where r.author_id = new.author_id and r.created_at > now() - interval '24 hours'),
      'limits.reviews_per_day', 10, 'Alcanzaste el límite de reseñas por día'
    );
    return new;
  end if;

  -- UPDATE: quien la escribió cambia estrellas y comentario; moderación, el estado.
  if new.author_id <> old.author_id
     or new.business_id is distinct from old.business_id
     or new.profile_id is distinct from old.profile_id
     or new.proposal_id is distinct from old.proposal_id
     or new.verified <> old.verified
     or new.reply is distinct from old.reply
     or new.reply_at is distinct from old.reply_at
     or new.reports_count <> old.reports_count
     or new.created_at <> old.created_at then
    raise exception 'Campo administrado por el sistema' using errcode = '42501';
  end if;

  if new.status is distinct from old.status and not (select public.has_role('moderator')) then
    raise exception 'Solo moderación puede ocultar reseñas' using errcode = '42501';
  end if;

  if new.rating <> old.rating or new.body is distinct from old.body then
    if old.author_id <> (select auth.uid()) then
      raise exception 'Solo quien la escribió puede editar la reseña' using errcode = '42501';
    end if;
    new.edited_at := now();
  end if;
  return new;
end;
$$;

create trigger reviews_before_write
  before insert or update on public.reviews
  for each row execute function public.tg_reviews_before_write();

create or replace function public.tg_reviews_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.recompute_rating(old.business_id, old.profile_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    if tg_op = 'INSERT' or new.rating <> old.rating or new.status <> old.status then
      perform public.recompute_rating(new.business_id, new.profile_id);
    end if;
  end if;

  if tg_op = 'INSERT' then
    recipient := coalesce(
      new.profile_id,
      (select b.owner_id from public.businesses b where b.id = new.business_id)
    );
    if recipient is not null and recipient <> new.author_id then
      insert into public.notifications (recipient_id, actor_id, type, business_id, review_id)
      values (recipient, new.author_id, 'review_received', new.business_id, new.id)
      on conflict do nothing;
    end if;
  end if;

  return null;
end;
$$;

create trigger reviews_after_write
  after insert or update or delete on public.reviews
  for each row execute function public.tg_reviews_after_write();

-- -----------------------------------------------------------------------------
-- Responder una reseña (emprendimiento o persona calificada)
-- -----------------------------------------------------------------------------
create or replace function public.reply_review(p_review_id uuid, p_reply text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me    uuid := (select auth.uid());
  rv      public.reviews%rowtype;
  v_reply text := nullif(btrim(coalesce(p_reply, '')), '');
begin
  if me is null then
    raise exception 'Ingresá para responder' using errcode = '42501';
  end if;

  select * into rv from public.reviews r where r.id = p_review_id;
  if rv.id is null or rv.status <> 'published' then
    raise exception 'La reseña no existe' using errcode = '42501';
  end if;

  if not (
    (rv.profile_id is not null and rv.profile_id = me)
    or (rv.business_id is not null and exists (
      select 1 from public.business_members bm where bm.business_id = rv.business_id and bm.user_id = me
    ))
  ) then
    raise exception 'Solo el emprendimiento o la persona calificada puede responder' using errcode = '42501';
  end if;

  if v_reply is not null and char_length(v_reply) > 1000 then
    raise exception 'La respuesta puede tener hasta 1000 caracteres' using errcode = '23514';
  end if;

  update public.reviews
  set reply = v_reply,
      reply_at = case when v_reply is null then null else now() end
  where id = rv.id;

  if v_reply is null then
    delete from public.notifications where review_id = rv.id and type = 'review_reply';
  elsif rv.author_id <> me and not public.is_blocked_between(rv.author_id, me) then
    insert into public.notifications (recipient_id, actor_id, type, business_id, review_id)
    values (rv.author_id, me, 'review_reply', rv.business_id, rv.id)
    on conflict do nothing;
  end if;
end;
$$;

revoke execute on function public.reply_review(uuid, text) from public, anon;
grant  execute on function public.reply_review(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Denuncias (genéricas; la revisión llega con el panel de la Etapa 12)
-- -----------------------------------------------------------------------------
create table public.reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid not null references public.profiles (id) on delete cascade,
  target_type     public.report_target not null,
  target_id       uuid not null,
  reason          public.report_reason not null,
  details         text,
  status          public.report_status not null default 'open',
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz,
  resolved_by     uuid references public.profiles (id) on delete set null,
  resolution_note text,
  constraint reports_details_len check (details is null or char_length(details) <= 500),
  constraint reports_note_len check (resolution_note is null or char_length(resolution_note) <= 500),
  constraint reports_once unique (reporter_id, target_type, target_id)
);

create index reports_open_idx on public.reports (created_at) where status = 'open';
create index reports_target_idx on public.reports (target_type, target_id);

create or replace function public.tg_reports_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ok boolean;
begin
  if public.is_system_call() then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if not (select public.has_role('moderator')) then
      raise exception 'Solo moderación revisa denuncias' using errcode = '42501';
    end if;
    if new.reporter_id <> old.reporter_id or new.target_type <> old.target_type
       or new.target_id <> old.target_id or new.created_at <> old.created_at then
      raise exception 'Campo administrado por el sistema' using errcode = '42501';
    end if;
    if new.status <> old.status and new.status <> 'open' then
      new.resolved_at := now();
      new.resolved_by := (select auth.uid());
    end if;
    return new;
  end if;

  new.reporter_id := (select auth.uid());
  new.status      := 'open';
  new.created_at  := now();
  new.resolved_at := null;
  new.resolved_by := null;
  new.resolution_note := null;
  new.details     := nullif(btrim(coalesce(new.details, '')), '');

  ok := case new.target_type
    when 'review'   then exists (select 1 from public.reviews r where r.id = new.target_id and r.status = 'published' and r.author_id <> new.reporter_id)
    when 'post'     then exists (select 1 from public.posts p where p.id = new.target_id and p.deleted_at is null and p.author_id <> new.reporter_id)
    when 'comment'  then exists (select 1 from public.post_comments c where c.id = new.target_id and c.author_id <> new.reporter_id)
    when 'profile'  then exists (select 1 from public.profiles p where p.id = new.target_id and p.id <> new.reporter_id)
    when 'business' then exists (select 1 from public.businesses b where b.id = new.target_id and b.deleted_at is null and b.owner_id <> new.reporter_id)
    when 'need'     then exists (select 1 from public.needs n where n.id = new.target_id and n.deleted_at is null and n.author_id <> new.reporter_id)
    else false
  end;
  if not ok then
    raise exception 'No se puede denunciar este contenido' using errcode = '42501';
  end if;

  perform public.enforce_rate_limit(
    (select count(*) from public.reports r where r.reporter_id = new.reporter_id and r.created_at > now() - interval '24 hours'),
    'limits.reports_per_day', 20, 'Alcanzaste el límite de denuncias por día'
  );
  return new;
end;
$$;

create trigger reports_before_write
  before insert or update on public.reports
  for each row execute function public.tg_reports_before_write();

-- Reseña denunciada por varias personas: se oculta hasta que moderación la vea.
-- No cuentan las denuncias del propio emprendimiento/persona calificada (para
-- que no puedan ocultar las reseñas negativas).
create or replace function public.tg_reports_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  rv     public.reviews%rowtype;
  total  integer;
begin
  if new.target_type <> 'review' then
    return null;
  end if;
  select * into rv from public.reviews r where r.id = new.target_id;
  if rv.id is null then
    return null;
  end if;

  select count(*)::integer into total
  from public.reports rp
  where rp.target_type = 'review' and rp.target_id = rv.id and rp.status = 'open'
    and rp.reporter_id is distinct from rv.profile_id
    and not exists (
      select 1 from public.business_members bm
      where rv.business_id is not null and bm.business_id = rv.business_id and bm.user_id = rp.reporter_id
    );

  update public.reviews
  set reports_count = total,
      status = case
        when status = 'published' and total >= public.setting_int('reviews.auto_hide_reports', 3) then 'hidden'::public.content_status
        else status
      end
  where id = rv.id;
  return null;
end;
$$;

create trigger reports_after_insert
  after insert on public.reports
  for each row execute function public.tg_reports_after_insert();

-- -----------------------------------------------------------------------------
-- Seguridad (RLS)
-- -----------------------------------------------------------------------------
alter table public.reviews enable row level security;
alter table public.reports enable row level security;

create policy "reviews: públicas las publicadas" on public.reviews
  for select to anon, authenticated
  using (
    status = 'published'
    or author_id = (select auth.uid())
    or (select public.has_role('moderator'))
  );

create policy "reviews: usuarios activos escriben" on public.reviews
  for insert to authenticated
  with check (author_id = (select auth.uid()) and (select public.is_active_user()));

create policy "reviews: el autor edita" on public.reviews
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

create policy "reviews: moderación edita" on public.reviews
  for update to authenticated
  using ((select public.has_role('moderator')))
  with check ((select public.has_role('moderator')));

create policy "reviews: el autor o moderación borra" on public.reviews
  for delete to authenticated
  using (author_id = (select auth.uid()) or (select public.has_role('moderator')));

revoke all on public.reviews from anon, authenticated;
grant select on public.reviews to anon, authenticated;
grant insert (business_id, profile_id, rating, body) on public.reviews to authenticated;
grant update (rating, body, status) on public.reviews to authenticated;
grant delete on public.reviews to authenticated;

create policy "reports: cada uno ve las suyas, moderación todas" on public.reports
  for select to authenticated
  using (reporter_id = (select auth.uid()) or (select public.has_role('moderator')));

create policy "reports: usuarios activos denuncian" on public.reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()) and (select public.is_active_user()));

create policy "reports: moderación revisa" on public.reports
  for update to authenticated
  using ((select public.has_role('moderator')))
  with check ((select public.has_role('moderator')));

revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;
grant insert (target_type, target_id, reason, details) on public.reports to authenticated;
grant update (status, resolution_note) on public.reports to authenticated;

insert into public.settings (key, value, description) values
  ('limits.reviews_per_day', '10', 'Reseñas por persona cada 24 h'),
  ('limits.reports_per_day', '20', 'Denuncias por persona cada 24 h'),
  ('reviews.auto_hide_reports', '3', 'Denuncias de personas distintas para ocultar una reseña hasta revisarla')
on conflict (key) do nothing;

notify pgrst, 'reload schema';
