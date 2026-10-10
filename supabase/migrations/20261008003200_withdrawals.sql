-- =============================================================================
-- 0032 · Botón de arrepentimiento (Ley 24.240 art. 34 y Res. SCI 424/2020)
-- =============================================================================
-- * Cualquier persona, CON o SIN cuenta, puede pedir revocar la contratación
--   de un plan dentro de los 10 días corridos. No se exige registrarse.
-- * Al pedirlo recibe al instante un código de identificación (ARR-XXXXXXXX).
-- * La administración ve los pedidos, cancela el plan en Mercado Pago y
--   devuelve el dinero (lo hace el servidor), o lo rechaza con un motivo.
-- * Nadie puede leer pedidos ajenos: solo la persona (si tenía sesión) y la
--   administración. Se escribe solo a través de funciones con controles.
-- =============================================================================

create table public.withdrawal_requests (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique,
  user_id          uuid references public.profiles (id) on delete set null,
  subscription_id  uuid references public.subscriptions (id) on delete set null,
  full_name        text not null,
  email            text not null,
  dni              text,
  detail           text,
  status           public.withdrawal_status not null default 'pending',
  admin_note       text,
  refunded_amount  numeric(12, 2),
  resolved_by      uuid references public.profiles (id) on delete set null,
  resolved_at      timestamptz,
  created_at       timestamptz not null default now(),
  constraint withdrawal_name check (char_length(btrim(full_name)) between 3 and 120),
  constraint withdrawal_email check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 200),
  constraint withdrawal_dni check (dni is null or dni ~ '^[0-9]{7,8}$'),
  constraint withdrawal_detail check (detail is null or char_length(detail) <= 1000),
  constraint withdrawal_note check (admin_note is null or char_length(admin_note) <= 1000)
);

create index withdrawal_requests_status_idx on public.withdrawal_requests (status, created_at desc);
create index withdrawal_requests_email_idx on public.withdrawal_requests (lower(email), created_at desc);
create index withdrawal_requests_user_idx on public.withdrawal_requests (user_id) where user_id is not null;

alter table public.withdrawal_requests enable row level security;

revoke all on public.withdrawal_requests from anon, authenticated;
grant select on public.withdrawal_requests to authenticated;

create policy "withdrawal_requests: propios y administración" on public.withdrawal_requests
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.has_role('admin')));

-- -----------------------------------------------------------------------------
-- Pedir el arrepentimiento (anónimo o con sesión). Devuelve el código.
-- Límites: 3 pedidos por email por día y 40 por hora en total (anti abuso).
-- -----------------------------------------------------------------------------
create or replace function public.request_withdrawal(
  p_full_name        text,
  p_email            text,
  p_dni              text,
  p_detail           text,
  p_subscription_id  uuid
)
returns table (code text, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  me      uuid := (select auth.uid());
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_name  text := btrim(coalesce(p_full_name, ''));
  v_dni   text := nullif(regexp_replace(coalesce(p_dni, ''), '[^0-9]', '', 'g'), '');
  v_det   text := nullif(btrim(coalesce(p_detail, '')), '');
  v_sub   uuid;
  v_code  text;
  v_id    uuid;
  v_at    timestamptz;
begin
  if char_length(v_name) < 3 or char_length(v_name) > 120 then
    raise exception 'Escribí tu nombre y apellido' using errcode = '23514';
  end if;
  if v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 200 then
    raise exception 'Escribí un email válido' using errcode = '23514';
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{7,8}$' then
    raise exception 'El DNI tiene que tener 7 u 8 números' using errcode = '23514';
  end if;
  if v_det is not null and char_length(v_det) > 1000 then
    raise exception 'El comentario puede tener hasta 1000 caracteres' using errcode = '23514';
  end if;

  if (select count(*) from public.withdrawal_requests w
      where lower(w.email) = v_email and w.created_at > now() - interval '1 day') >= 3
     or (select count(*) from public.withdrawal_requests w where w.created_at > now() - interval '1 hour') >= 40 then
    raise exception 'Ya recibimos tu pedido. Si necesitás otra cosa, escribinos.' using errcode = 'P0001', hint = 'rate_limited';
  end if;

  -- El plan elegido solo se guarda si es de quien tiene la sesión.
  if p_subscription_id is not null and me is not null then
    select s.id into v_sub from public.subscriptions s where s.id = p_subscription_id and s.user_id = me;
  end if;

  loop
    v_code := 'ARR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from public.withdrawal_requests w where w.code = v_code);
  end loop;

  insert into public.withdrawal_requests (code, user_id, subscription_id, full_name, email, dni, detail)
  values (v_code, me, v_sub, v_name, v_email, v_dni, v_det)
  returning id, withdrawal_requests.created_at into v_id, v_at;

  -- Aviso a la administración.
  insert into public.notifications (recipient_id, actor_id, type)
  select r.user_id, null, 'withdrawal_request'::public.notification_type
  from public.user_roles r
  where r.role in ('admin', 'super_admin');

  return query select v_code, v_at;
end;
$$;

revoke execute on function public.request_withdrawal(text, text, text, text, uuid) from public;
grant execute on function public.request_withdrawal(text, text, text, text, uuid) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Resolver un pedido (solo administración).
-- -----------------------------------------------------------------------------
create or replace function public.resolve_withdrawal(
  p_id               uuid,
  p_status           public.withdrawal_status,
  p_note             text,
  p_refunded_amount  numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me  uuid := (select auth.uid());
  req public.withdrawal_requests%rowtype;
begin
  if not (select public.has_role('admin')) then
    raise exception 'Solo la administración puede resolver pedidos' using errcode = '42501';
  end if;
  if p_status = 'pending' then
    raise exception 'Elegí cómo se resolvió el pedido' using errcode = '23514';
  end if;
  if p_status = 'rejected' and char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception 'Escribí el motivo (lo ve la persona)' using errcode = '23514';
  end if;

  select * into req from public.withdrawal_requests w where w.id = p_id for update;
  if req.id is null then
    raise exception 'No encontramos ese pedido' using errcode = '23514';
  end if;

  update public.withdrawal_requests
  set status = p_status,
      admin_note = nullif(btrim(coalesce(p_note, '')), ''),
      refunded_amount = case when p_status = 'refunded' then coalesce(p_refunded_amount, 0) else refunded_amount end,
      resolved_by = me,
      resolved_at = now()
  where id = req.id;

  if req.user_id is not null then
    insert into public.notifications (recipient_id, actor_id, type)
    values (req.user_id, null, 'withdrawal_resolved');
  end if;
end;
$$;

revoke execute on function public.resolve_withdrawal(uuid, public.withdrawal_status, text, numeric) from public, anon;
grant execute on function public.resolve_withdrawal(uuid, public.withdrawal_status, text, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- Quitar un plan en el acto (después de devolver el dinero). Solo servidor.
-- -----------------------------------------------------------------------------
create or replace function public.sub_revoke(p_subscription_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  update public.subscriptions
  set status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, now()),
      paid_through = least(coalesce(paid_through, now()), now()),
      next_payment_at = null
  where id = p_subscription_id
  returning user_id into v_user;

  if v_user is not null then
    perform public.refresh_entitlements(v_user);
  end if;
end;
$$;

revoke execute on function public.sub_revoke(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Cobros: un pago devuelto (arrepentimiento) nunca vuelve a "aprobado" ni
-- extiende el plan, aunque Mercado Pago mande tarde un aviso anterior.
-- (Misma función de la migración 0026 con ese cambio.)
-- -----------------------------------------------------------------------------
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
    -- Un pago devuelto queda devuelto (aunque llegue tarde un aviso viejo).
    set status = case when public.subscription_payments.status = 'refunded' then 'refunded' else excluded.status end,
        amount = excluded.amount,
        fee = excluded.fee,
        net = excluded.net,
        paid_at = coalesce(excluded.paid_at, public.subscription_payments.paid_at),
        mp_authorized_payment_id = coalesce(excluded.mp_authorized_payment_id, public.subscription_payments.mp_authorized_payment_id);

  -- Solo un pago nuevo acreditado extiende el período (los reintentos del mismo aviso no).
  if p_status = 'approved' and prev_status is distinct from 'approved' and prev_status is distinct from 'refunded' then
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

notify pgrst, 'reload schema';
