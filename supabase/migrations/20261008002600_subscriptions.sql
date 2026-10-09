-- =============================================================================
-- 0026 · Suscripciones con Mercado Pago y verificación paga (Etapa 13)
-- =============================================================================
-- Planes (precios editables por administración):
--   * destacado     $10.000/mes: publicaciones en "Destacados" del inicio,
--                   primero en el buscador, propuestas sin límite.
--   * pro           $20.000/mes: lo mismo para la persona y para UNO de sus
--                   emprendimientos (primero en su rubro y ciudad, insignia
--                   PRO) + verificación incluida.
--   * verificacion  $12.000/mes: tilde azul (con revisión de DNI y selfie).
--
-- Cómo se cobra: cada suscripción es un "preapproval" de Mercado Pago. Los
-- datos de pago SOLO los escribe el servidor (service_role) después de
-- consultarlos a la API de Mercado Pago: la app no puede marcarse como paga.
--
-- Qué da derecho a los beneficios: un pago acreditado. Cada pago extiende
-- "paid_through" un mes (+3 días de gracia por reintentos de cobro). Al
-- cancelar, los beneficios siguen hasta esa fecha.
--
-- Verificación paga: con la suscripción al día, la persona sube foto del DNI
-- y una selfie (bucket privado "verification"); administración las revisa.
-- Si la suscripción se termina, la tilde paga se quita sola (la tilde que
-- puso administración a mano no se toca).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Perfil: nuevo nivel "destacado" y origen de la verificación
-- -----------------------------------------------------------------------------
alter table public.profiles drop constraint if exists profiles_plan_tier;
alter table public.profiles
  add constraint profiles_plan_tier check (plan_tier in ('free', 'destacado', 'pro', 'premium'));

alter table public.profiles
  add column if not exists verified_source text,
  add constraint profiles_verified_source check (verified_source is null or verified_source in ('manual', 'paid'));

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
     or new.rating_count <> old.rating_count
     or new.verified_source is distinct from old.verified_source then
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

-- Avisos del sistema (pagos, verificación): no tienen una persona que los envíe.
alter table public.notifications alter column actor_id drop not null;
alter table public.notifications drop constraint if exists notifications_not_self;
alter table public.notifications
  add constraint notifications_not_self check (actor_id is null or recipient_id <> actor_id);

-- -----------------------------------------------------------------------------
-- Planes
-- -----------------------------------------------------------------------------
create table public.plans (
  id                     text primary key,
  name                   text not null,
  description            text not null,
  features               text[] not null default '{}',
  price                  numeric(12, 2) not null,
  currency               char(3) not null default 'ARS',
  includes_verification  boolean not null default false,
  requires_business      boolean not null default false,
  active                 boolean not null default true,
  sort                   smallint not null default 0,
  updated_at             timestamptz not null default now(),
  constraint plans_id check (id in ('destacado', 'pro', 'verificacion')),
  constraint plans_price check (price >= 100 and price <= 10000000),
  constraint plans_name_len check (char_length(name) between 2 and 40),
  constraint plans_description_len check (char_length(description) between 5 and 300)
);

create trigger plans_set_updated_at
  before update on public.plans
  for each row execute function public.set_updated_at();

insert into public.plans (id, name, description, features, price, includes_verification, requires_business, sort) values
  ('destacado', 'Destacado',
   'Para personas y freelancers que quieren que los vean más.',
   array['Tus publicaciones aparecen en "Destacados" del inicio',
         'Salís primero en el buscador de personas',
         'Propuestas sin límite en Necesidades'],
   10000, false, false, 1),
  ('pro', 'Emprendimiento Pro',
   'Para emprendimientos que quieren más clientes.',
   array['Todo lo del plan Destacado',
         'Tu emprendimiento sale primero en su rubro y ciudad',
         'Insignia PRO en tu página y en el buscador',
         'Verificación con tilde azul incluida'],
   20000, true, true, 2),
  ('verificacion', 'Verificación',
   'Tilde azul: le mostrás a todos que tu identidad está verificada.',
   array['Tilde azul al lado de tu nombre',
         'Revisamos tu DNI y una selfie (privados, solo los ve administración)'],
   12000, true, false, 3)
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- Suscripciones y pagos
-- -----------------------------------------------------------------------------
create table public.subscriptions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles (id) on delete cascade,
  plan_id            text not null references public.plans (id),
  business_id        uuid references public.businesses (id) on delete set null,
  status             public.subscription_status not null default 'pending',
  price              numeric(12, 2) not null,
  currency           char(3) not null default 'ARS',
  payer_email        text not null,
  mp_preapproval_id  text unique,
  init_point         text,
  paid_through       timestamptz,
  next_payment_at    timestamptz,
  started_at         timestamptz,
  cancelled_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint subscriptions_email check (payer_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(payer_email) <= 200)
);

-- Una suscripción viva por plan (y por emprendimiento en el Pro).
create unique index subscriptions_one_live
  on public.subscriptions (user_id, plan_id, coalesce(business_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where status in ('pending', 'authorized', 'paused');
create index subscriptions_user_idx on public.subscriptions (user_id, created_at desc);
create index subscriptions_live_idx on public.subscriptions (status) where status in ('pending', 'authorized', 'paused');

create trigger subscriptions_set_updated_at
  before update on public.subscriptions
  for each row execute function public.set_updated_at();

create table public.subscription_payments (
  id                        uuid primary key default gen_random_uuid(),
  subscription_id           uuid not null references public.subscriptions (id) on delete cascade,
  user_id                   uuid not null references public.profiles (id) on delete cascade,
  plan_id                   text not null references public.plans (id),
  mp_payment_id             text not null unique,
  mp_authorized_payment_id  text,
  status                    text not null,
  amount                    numeric(12, 2) not null,
  fee                       numeric(12, 2) not null default 0,
  net                       numeric(12, 2) not null default 0,
  currency                  char(3) not null default 'ARS',
  paid_at                   timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index subscription_payments_paid_idx on public.subscription_payments (paid_at desc) where status = 'approved';
create index subscription_payments_sub_idx on public.subscription_payments (subscription_id, created_at desc);

create trigger subscription_payments_set_updated_at
  before update on public.subscription_payments
  for each row execute function public.set_updated_at();

alter table public.notifications
  add column if not exists subscription_id uuid references public.subscriptions (id) on delete cascade;

-- -----------------------------------------------------------------------------
-- Pedidos de verificación (DNI + selfie)
-- -----------------------------------------------------------------------------
create table public.verification_requests (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  document_path   text not null,
  selfie_path     text not null,
  status          public.verification_request_status not null default 'pending',
  reject_reason   text,
  reviewed_by     uuid references public.profiles (id) on delete set null,
  reviewed_at     timestamptz,
  created_at      timestamptz not null default now(),
  constraint verification_requests_reason_len check (reject_reason is null or char_length(reject_reason) <= 300)
);

create unique index verification_requests_one_pending on public.verification_requests (user_id) where status = 'pending';
create index verification_requests_pending_idx on public.verification_requests (created_at) where status = 'pending';

-- -----------------------------------------------------------------------------
-- Beneficios: los recalcula la base a partir de los pagos
-- -----------------------------------------------------------------------------
create or replace function public.refresh_entitlements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  has_pro        boolean;
  has_destacado  boolean;
  has_verif      boolean;
  approved_doc   boolean;
begin
  select
    bool_or(s.plan_id = 'pro'),
    bool_or(s.plan_id = 'destacado'),
    bool_or(p.includes_verification)
  into has_pro, has_destacado, has_verif
  from public.subscriptions s
  join public.plans p on p.id = s.plan_id
  where s.user_id = p_user_id and s.paid_through > now();

  has_pro := coalesce(has_pro, false);
  has_destacado := coalesce(has_destacado, false);
  has_verif := coalesce(has_verif, false);

  -- Nivel del perfil (lo usan el inicio "Destacados" y el buscador).
  update public.profiles
  set plan_tier = case when has_pro then 'pro' when has_destacado then 'destacado' else 'free' end
  where id = p_user_id
    and plan_tier is distinct from (case when has_pro then 'pro' when has_destacado then 'destacado' else 'free' end);

  -- Emprendimientos Pro: los que tienen una suscripción Pro al día.
  update public.businesses b
  set plan_tier = 'pro', search_boost = 0.5
  where b.owner_id = p_user_id
    and exists (
      select 1 from public.subscriptions s
      where s.business_id = b.id and s.plan_id = 'pro' and s.paid_through > now()
    )
    and (b.plan_tier <> 'pro' or b.search_boost <> 0.5);

  update public.businesses b
  set plan_tier = 'free', search_boost = 0
  where b.owner_id = p_user_id
    and b.plan_tier <> 'free'
    and not exists (
      select 1 from public.subscriptions s
      where s.business_id = b.id and s.plan_id = 'pro' and s.paid_through > now()
    );

  -- Tilde paga: con verificación al día y DNI aprobado.
  select exists (
    select 1 from public.verification_requests v where v.user_id = p_user_id and v.status = 'approved'
  ) into approved_doc;

  if has_verif and approved_doc then
    update public.profiles
    set verified_at = coalesce(verified_at, now()),
        verified_source = coalesce(verified_source, 'paid')
    where id = p_user_id and (verified_at is null or verified_source is null);
  elsif not has_verif then
    update public.profiles
    set verified_at = null, verified_source = null
    where id = p_user_id and verified_source = 'paid';
  end if;
end;
$$;

revoke execute on function public.refresh_entitlements(uuid) from public, anon, authenticated;

-- ¿El usuario actual tiene un plan con verificación al día?
create or replace function public.has_verification_plan()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.subscriptions s
    join public.plans p on p.id = s.plan_id
    where s.user_id = (select auth.uid()) and s.paid_through > now() and p.includes_verification
  );
$$;

revoke execute on function public.has_verification_plan() from public, anon;
grant  execute on function public.has_verification_plan() to authenticated;

-- -----------------------------------------------------------------------------
-- Empezar una suscripción (la llama el usuario; queda "pendiente" hasta que
-- Mercado Pago confirme). El servidor después crea el preapproval y lo asocia.
-- -----------------------------------------------------------------------------
create or replace function public.start_subscription(p_plan_id text, p_business_id uuid, p_payer_email text)
returns table (id uuid, price numeric, plan_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  me    uuid := (select auth.uid());
  plan  public.plans%rowtype;
  sub   uuid;
  email text := lower(btrim(coalesce(p_payer_email, '')));
begin
  if me is null or not public.is_active_user() then
    raise exception 'Ingresá con una cuenta activa para suscribirte' using errcode = '42501';
  end if;

  select * into plan from public.plans pl where pl.id = p_plan_id and pl.active;
  if plan.id is null then
    raise exception 'Ese plan no está disponible' using errcode = '42501';
  end if;

  if plan.requires_business then
    if p_business_id is null or not exists (
      select 1 from public.businesses b
      where b.id = p_business_id and b.owner_id = me and b.deleted_at is null and b.status in ('active', 'inactive', 'draft')
    ) then
      raise exception 'Elegí uno de tus emprendimientos para el plan Pro' using errcode = '42501';
    end if;
  else
    p_business_id := null;
  end if;

  if email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Escribí el email de tu cuenta de Mercado Pago' using errcode = '23514';
  end if;

  if exists (
    select 1 from public.subscriptions s
    where s.user_id = me and s.plan_id = plan.id
      and s.business_id is not distinct from p_business_id
      and s.status in ('authorized', 'paused')
  ) then
    raise exception 'Ya tenés este plan activo' using errcode = '42501';
  end if;

  -- Un intento anterior que no se pagó se descarta.
  update public.subscriptions s
  set status = 'cancelled', cancelled_at = now()
  where s.user_id = me and s.plan_id = plan.id
    and s.business_id is not distinct from p_business_id
    and s.status = 'pending';

  insert into public.subscriptions (user_id, plan_id, business_id, price, currency, payer_email)
  values (me, plan.id, p_business_id, plan.price, plan.currency, email)
  returning subscriptions.id into sub;

  return query select sub, plan.price, plan.name;
end;
$$;

revoke execute on function public.start_subscription(text, uuid, text) from public, anon;
grant  execute on function public.start_subscription(text, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Funciones del servidor (service_role): datos que vienen de Mercado Pago
-- -----------------------------------------------------------------------------
create or replace function public.sub_attach_preapproval(p_subscription_id uuid, p_preapproval_id text, p_init_point text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.subscriptions
  set mp_preapproval_id = p_preapproval_id, init_point = p_init_point
  where id = p_subscription_id and status = 'pending' and mp_preapproval_id is null;
$$;

-- Estado del preapproval según Mercado Pago.
create or replace function public.sub_sync(
  p_subscription_id  uuid,
  p_preapproval_id   text,
  p_status           text,
  p_next_payment_at  timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  sub        public.subscriptions%rowtype;
  new_status public.subscription_status;
begin
  select * into sub from public.subscriptions s where s.id = p_subscription_id;
  if sub.id is null or (sub.mp_preapproval_id is not null and sub.mp_preapproval_id <> p_preapproval_id) then
    raise exception 'La suscripción no coincide con Mercado Pago' using errcode = '42501';
  end if;

  new_status := case p_status
    when 'authorized' then 'authorized'
    when 'paused' then 'paused'
    when 'cancelled' then 'cancelled'
    else 'pending'
  end::public.subscription_status;

  -- Una suscripción cancelada no vuelve atrás.
  if sub.status = 'cancelled' then
    new_status := 'cancelled';
  end if;

  update public.subscriptions
  set status = new_status,
      mp_preapproval_id = coalesce(mp_preapproval_id, p_preapproval_id),
      next_payment_at = case when new_status = 'authorized' then p_next_payment_at else null end,
      started_at = case when new_status = 'authorized' then coalesce(started_at, now()) else started_at end,
      cancelled_at = case when new_status = 'cancelled' then coalesce(cancelled_at, now()) else cancelled_at end
  where id = sub.id;

  perform public.refresh_entitlements(sub.user_id);
end;
$$;

-- Un cobro de la suscripción (idempotente por mp_payment_id).
create or replace function public.sub_record_payment(
  p_preapproval_id           text,
  p_mp_payment_id            text,
  p_mp_authorized_payment_id text,
  p_status                   text,
  p_amount                   numeric,
  p_fee                      numeric,
  p_net                      numeric,
  p_paid_at                  timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  sub          public.subscriptions%rowtype;
  prev_status  text;
  first_paid   boolean;
begin
  select * into sub from public.subscriptions s where s.mp_preapproval_id = p_preapproval_id;
  if sub.id is null then
    raise exception 'No hay una suscripción con ese preapproval' using errcode = '42501';
  end if;

  select sp.status into prev_status from public.subscription_payments sp where sp.mp_payment_id = p_mp_payment_id;
  first_paid := not exists (select 1 from public.subscription_payments sp where sp.subscription_id = sub.id and sp.status = 'approved');

  insert into public.subscription_payments
    (subscription_id, user_id, plan_id, mp_payment_id, mp_authorized_payment_id, status, amount, fee, net, currency, paid_at)
  values
    (sub.id, sub.user_id, sub.plan_id, p_mp_payment_id, p_mp_authorized_payment_id, p_status,
     coalesce(p_amount, 0), coalesce(p_fee, 0), coalesce(p_net, 0), sub.currency, p_paid_at)
  on conflict (mp_payment_id) do update
    set status = excluded.status,
        amount = excluded.amount,
        fee = excluded.fee,
        net = excluded.net,
        paid_at = coalesce(excluded.paid_at, public.subscription_payments.paid_at),
        mp_authorized_payment_id = coalesce(excluded.mp_authorized_payment_id, public.subscription_payments.mp_authorized_payment_id);

  -- Solo un pago nuevo acreditado extiende el período (los reintentos del mismo aviso no).
  if p_status = 'approved' and prev_status is distinct from 'approved' then
    update public.subscriptions
    -- paid_through = hasta cuándo está cubierto + 3 días de gracia (reintentos de cobro).
    set paid_through = greatest(coalesce(paid_through - interval '3 days', coalesce(p_paid_at, now())), coalesce(p_paid_at, now()))
                       + interval '1 month 3 days'
    where id = sub.id;

    if first_paid then
      insert into public.notifications (recipient_id, actor_id, type, subscription_id)
      values (sub.user_id, null, 'plan_activated', sub.id);
    end if;
  elsif p_status = 'rejected' and prev_status is distinct from 'rejected' then
    insert into public.notifications (recipient_id, actor_id, type, subscription_id)
    values (sub.user_id, null, 'plan_payment_failed', sub.id);
  end if;

  perform public.refresh_entitlements(sub.user_id);
end;
$$;

-- Limpieza diaria: quita beneficios vencidos.
create or replace function public.expire_entitlements()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid   uuid;
  total integer := 0;
begin
  for uid in
    select p.id from public.profiles p where p.plan_tier <> 'free' or p.verified_source = 'paid'
    union
    select b.owner_id from public.businesses b where b.plan_tier <> 'free'
  loop
    perform public.refresh_entitlements(uid);
    total := total + 1;
  end loop;
  return total;
end;
$$;

revoke execute on function public.sub_attach_preapproval(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.sub_sync(uuid, text, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.sub_record_payment(text, text, text, text, numeric, numeric, numeric, timestamptz) from public, anon, authenticated;
revoke execute on function public.expire_entitlements() from public, anon, authenticated;
grant execute on function public.sub_attach_preapproval(uuid, text, text) to service_role;
grant execute on function public.sub_sync(uuid, text, text, timestamptz) to service_role;
grant execute on function public.sub_record_payment(text, text, text, text, numeric, numeric, numeric, timestamptz) to service_role;
grant execute on function public.expire_entitlements() to service_role;

-- -----------------------------------------------------------------------------
-- Verificación: el usuario manda DNI + selfie; administración decide
-- -----------------------------------------------------------------------------
create or replace function public.submit_verification(p_document_path text, p_selfie_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me  uuid := (select auth.uid());
  req uuid;
begin
  if me is null or not public.is_active_user() then
    raise exception 'Ingresá con una cuenta activa' using errcode = '42501';
  end if;
  if not public.has_verification_plan() then
    raise exception 'Necesitás el plan Verificación o Emprendimiento Pro al día' using errcode = '42501';
  end if;
  if exists (select 1 from public.verification_requests v where v.user_id = me and v.status = 'pending') then
    raise exception 'Ya mandaste tu documentación: la estamos revisando' using errcode = '42501';
  end if;
  if exists (select 1 from public.verification_requests v where v.user_id = me and v.status = 'approved') then
    raise exception 'Tu identidad ya está verificada' using errcode = '42501';
  end if;

  -- Las imágenes tienen que ser del propio usuario y existir en el bucket privado.
  if split_part(coalesce(p_document_path, ''), '/', 1) <> me::text
     or split_part(coalesce(p_selfie_path, ''), '/', 1) <> me::text
     or p_document_path = p_selfie_path
     or not exists (select 1 from storage.objects o where o.bucket_id = 'verification' and o.name like p_document_path || '/%')
     or not exists (select 1 from storage.objects o where o.bucket_id = 'verification' and o.name like p_selfie_path || '/%') then
    raise exception 'Subí las dos fotos de nuevo' using errcode = '42501';
  end if;

  insert into public.verification_requests (user_id, document_path, selfie_path)
  values (me, p_document_path, p_selfie_path)
  returning id into req;
  return req;
end;
$$;

revoke execute on function public.submit_verification(text, text) from public, anon;
grant  execute on function public.submit_verification(text, text) to authenticated;

create or replace function public.review_verification(p_request_id uuid, p_approve boolean, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me  uuid := (select auth.uid());
  req public.verification_requests%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not (select public.has_role('admin')) then
    raise exception 'Solo la administración revisa verificaciones' using errcode = '42501';
  end if;
  select * into req from public.verification_requests v where v.id = p_request_id;
  if req.id is null or req.status <> 'pending' then
    raise exception 'Ese pedido ya fue revisado' using errcode = '42501';
  end if;
  if req.user_id = me then
    raise exception 'No podés revisar tu propio pedido' using errcode = '42501';
  end if;
  if not p_approve and v_reason is null then
    raise exception 'Contale a la persona por qué la rechazás' using errcode = '23514';
  end if;

  update public.verification_requests
  set status = case when p_approve then 'approved' else 'rejected' end::public.verification_request_status,
      reject_reason = case when p_approve then null else left(v_reason, 300) end,
      reviewed_by = me,
      reviewed_at = now()
  where id = req.id;

  insert into public.notifications (recipient_id, actor_id, type)
  values (req.user_id, null, case when p_approve then 'verification_approved' else 'verification_rejected' end::public.notification_type);

  perform public.refresh_entitlements(req.user_id);

  insert into public.moderation_actions (moderator_id, target_type, target_id, action, note)
  values (me, 'profile', req.user_id, case when p_approve then 'verify' else 'verify_rejected' end, v_reason);
end;
$$;

revoke execute on function public.review_verification(uuid, boolean, text) from public, anon;
grant  execute on function public.review_verification(uuid, boolean, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Ingresos (solo administración)
-- -----------------------------------------------------------------------------
create or replace function public.admin_revenue_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  month_start timestamptz := date_trunc('month', now() at time zone 'America/Argentina/Cordoba') at time zone 'America/Argentina/Cordoba';
  prev_start  timestamptz := (date_trunc('month', now() at time zone 'America/Argentina/Cordoba') - interval '1 month') at time zone 'America/Argentina/Cordoba';
begin
  if not (select public.has_role('admin')) then
    raise exception 'Solo administración' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'active_subscribers', (select count(distinct s.user_id) from public.subscriptions s where s.paid_through > now()),
    'active_subscriptions', (select count(*) from public.subscriptions s where s.paid_through > now()),
    -- Ingreso mensual recurrente: suscripciones que se siguen cobrando.
    'mrr', (select coalesce(sum(s.price), 0) from public.subscriptions s where s.status = 'authorized'),
    'month_gross', (select coalesce(sum(p.amount), 0) from public.subscription_payments p where p.status = 'approved' and p.paid_at >= month_start),
    'month_fee', (select coalesce(sum(p.fee), 0) from public.subscription_payments p where p.status = 'approved' and p.paid_at >= month_start),
    'month_net', (select coalesce(sum(p.net), 0) from public.subscription_payments p where p.status = 'approved' and p.paid_at >= month_start),
    'month_payments', (select count(*) from public.subscription_payments p where p.status = 'approved' and p.paid_at >= month_start),
    'prev_gross', (select coalesce(sum(p.amount), 0) from public.subscription_payments p where p.status = 'approved' and p.paid_at >= prev_start and p.paid_at < month_start),
    'prev_net', (select coalesce(sum(p.net), 0) from public.subscription_payments p where p.status = 'approved' and p.paid_at >= prev_start and p.paid_at < month_start),
    'month_new', (select count(*) from public.subscriptions s where s.started_at >= month_start),
    'month_cancelled', (select count(*) from public.subscriptions s where s.cancelled_at >= month_start and s.started_at is not null),
    'month_failed', (select count(*) from public.subscription_payments p where p.status = 'rejected' and p.created_at >= month_start),
    'pending_verifications', (select count(*) from public.verification_requests v where v.status = 'pending'),
    'by_plan', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'plan_id', pl.id,
        'name', pl.name,
        'price', pl.price,
        'active', (select count(*) from public.subscriptions s where s.plan_id = pl.id and s.paid_through > now()),
        'mrr', (select coalesce(sum(s.price), 0) from public.subscriptions s where s.plan_id = pl.id and s.status = 'authorized'),
        'month_gross', (select coalesce(sum(p.amount), 0) from public.subscription_payments p where p.plan_id = pl.id and p.status = 'approved' and p.paid_at >= month_start)
      ) order by pl.sort), '[]'::jsonb)
      from public.plans pl
    ),
    'monthly', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'month', to_char(m.month, 'YYYY-MM'),
        'gross', coalesce(x.gross, 0),
        'net', coalesce(x.net, 0),
        'payments', coalesce(x.payments, 0),
        'subscribers', coalesce(x.subscribers, 0)
      ) order by m.month), '[]'::jsonb)
      from generate_series(
        date_trunc('month', now() at time zone 'America/Argentina/Cordoba') - interval '11 months',
        date_trunc('month', now() at time zone 'America/Argentina/Cordoba'),
        interval '1 month'
      ) as m(month)
      left join (
        select date_trunc('month', p.paid_at at time zone 'America/Argentina/Cordoba') as month,
               sum(p.amount) as gross, sum(p.net) as net, count(*) as payments, count(distinct p.user_id) as subscribers
        from public.subscription_payments p
        where p.status = 'approved'
        group by 1
      ) x on x.month = m.month
    )
  );
end;
$$;

revoke execute on function public.admin_revenue_summary() from public, anon;
grant  execute on function public.admin_revenue_summary() to authenticated;

-- -----------------------------------------------------------------------------
-- Propuestas: límite mensual para cuentas sin plan
-- -----------------------------------------------------------------------------
create or replace function public.tg_proposals_free_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_system_call() then
    return new;
  end if;
  if (select p.plan_tier from public.profiles p where p.id = new.author_id) = 'free'
     and (
       select count(*) from public.proposals pr
       where pr.author_id = new.author_id
         and pr.created_at >= date_trunc('month', now() at time zone 'America/Argentina/Cordoba') at time zone 'America/Argentina/Cordoba'
     ) >= public.setting_int('limits.free_proposals_per_month', 10) then
    raise exception 'Llegaste a las propuestas gratis de este mes. Con el plan Destacado mandás sin límite.'
      using errcode = 'P0001', hint = 'quota_exceeded';
  end if;
  return new;
end;
$$;

-- Corre después de "proposals_before_write" (orden alfabético), con el autor ya fijado.
create trigger proposals_free_limit
  before insert on public.proposals
  for each row execute function public.tg_proposals_free_limit();

insert into public.settings (key, value, is_public, description) values
  ('limits.free_proposals_per_month', '10', false, 'Propuestas por mes para cuentas sin plan')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Seguridad (RLS)
-- -----------------------------------------------------------------------------
alter table public.plans enable row level security;
alter table public.subscriptions enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.verification_requests enable row level security;

create policy "plans: públicos" on public.plans
  for select to anon, authenticated
  using (active or (select public.has_role('admin')));

create policy "plans: administración edita" on public.plans
  for update to authenticated
  using ((select public.has_role('admin')))
  with check ((select public.has_role('admin')));

revoke all on public.plans from anon, authenticated;
grant select on public.plans to anon, authenticated;
grant update (name, description, features, price, active) on public.plans to authenticated;

create policy "subscriptions: las mías o administración" on public.subscriptions
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.has_role('admin')));

revoke all on public.subscriptions from anon, authenticated;
grant select on public.subscriptions to authenticated;

create policy "subscription_payments: los míos o administración" on public.subscription_payments
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.has_role('admin')));

revoke all on public.subscription_payments from anon, authenticated;
grant select on public.subscription_payments to authenticated;

create policy "verification_requests: los míos o administración" on public.verification_requests
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.has_role('admin')));

revoke all on public.verification_requests from anon, authenticated;
grant select on public.verification_requests to authenticated;

-- Los documentos privados: solo la persona y administración (antes también moderación).
drop policy if exists "verification: leer lo mío o moderación" on storage.objects;
create policy "verification: leer lo mío o administración" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'verification'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (select public.has_role('admin'))
    )
  );

notify pgrst, 'reload schema';
