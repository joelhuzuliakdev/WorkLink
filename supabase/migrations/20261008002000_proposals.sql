-- =============================================================================
-- 0020 · Propuestas a necesidades (Etapa 10)
-- =============================================================================
-- * Una persona (o uno de sus emprendimientos) le manda a una necesidad una
--   propuesta: mensaje, precio opcional y disponibilidad. Una por persona.
-- * Las propuestas son privadas: solo las ven quien la mandó y quien publicó
--   la necesidad. El resto solo ve cuántas hay.
-- * Quien publicó acepta una (la necesidad pasa a "resuelta", el resto queda
--   rechazado y se abre un chat con quien ganó) o rechaza alguna.
-- * Avisos: propuesta nueva → a quien publicó; propuesta aceptada → a quien la
--   mandó; necesidad nueva → a los emprendimientos de ese rubro en esa ciudad.
-- * Vencimiento: la limpieza diaria marca como vencidas las necesidades cuyo
--   plazo pasó (sin pg_cron).
-- =============================================================================


alter table public.notifications
  add column if not exists need_id uuid references public.needs (id) on delete cascade,
  add column if not exists proposal_id uuid;

create table public.proposals (
  id            uuid primary key default gen_random_uuid(),
  need_id       uuid not null references public.needs (id) on delete cascade,
  author_id     uuid not null references public.profiles (id) on delete cascade,
  business_id   uuid references public.businesses (id) on delete set null,
  message       text not null,
  amount        numeric(14, 2),
  currency      char(3) not null default 'ARS',
  availability  text,
  status        public.proposal_status not null default 'pending',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  decided_at    timestamptz,
  constraint proposals_message_len check (char_length(btrim(message)) between 20 and 2000),
  constraint proposals_amount check (amount is null or amount >= 0),
  constraint proposals_availability_len check (char_length(availability) <= 120),
  constraint proposals_one_per_person unique (need_id, author_id)
);

create index proposals_need_idx on public.proposals (need_id, created_at);
create index proposals_author_idx on public.proposals (author_id, created_at desc);

alter table public.needs
  add constraint needs_awarded_proposal_fk foreign key (awarded_proposal_id) references public.proposals (id) on delete set null;

alter table public.notifications
  add constraint notifications_proposal_fk foreign key (proposal_id) references public.proposals (id) on delete cascade;

create unique index if not exists notifications_need_match_once
  on public.notifications (recipient_id, need_id) where type = 'need_match';

create trigger proposals_set_updated_at
  before update on public.proposals
  for each row execute function public.set_updated_at();

-- ¿El usuario actual mandó esta propuesta o publicó la necesidad?
create or replace function public.can_see_proposal(p_need_id uuid, p_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_author_id = (select auth.uid())
      or exists (select 1 from public.needs n where n.id = p_need_id and n.author_id = (select auth.uid()));
$$;

revoke execute on function public.can_see_proposal(uuid, uuid) from public, anon;
grant  execute on function public.can_see_proposal(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Reglas al crear y editar propuestas
-- -----------------------------------------------------------------------------
create or replace function public.tg_proposals_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  need public.needs;
begin
  new.message := btrim(new.message);
  new.availability := nullif(btrim(coalesce(new.availability, '')), '');
  if public.is_system_call() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.author_id := (select auth.uid());
    new.status := 'pending';
    new.decided_at := null;
    new.created_at := now();

    select * into need from public.needs n where n.id = new.need_id and n.deleted_at is null;
    if not found then
      raise exception 'La necesidad no existe' using errcode = '42501';
    end if;
    if need.author_id = new.author_id then
      raise exception 'No podés mandarte una propuesta a vos' using errcode = '42501';
    end if;
    if need.status not in ('open', 'in_review') or need.expires_at < now() then
      raise exception 'Esta necesidad ya no recibe propuestas' using errcode = '42501';
    end if;
    if public.is_blocked_between(new.author_id, need.author_id) then
      raise exception 'No podés mandarle una propuesta a esta persona' using errcode = '42501';
    end if;
    if new.business_id is not null and not public.is_business_member(new.business_id) then
      raise exception 'Ese emprendimiento no es tuyo' using errcode = '42501';
    end if;

    perform public.enforce_rate_limit(
      (select count(*) from public.proposals p
        where p.author_id = new.author_id and p.created_at > now() - interval '24 hours'),
      'limits.proposals_per_day', 30,
      'Mandaste muchas propuestas hoy. Probá de nuevo mañana.'
    );
    return new;
  end if;

  -- UPDATE por quien la mandó: solo texto, precio y disponibilidad, mientras esté pendiente
  -- (o retirarla).
  if new.need_id <> old.need_id or new.author_id <> old.author_id or new.created_at <> old.created_at
     or new.business_id is distinct from old.business_id or new.decided_at is distinct from old.decided_at then
    raise exception 'Campo administrado por el sistema' using errcode = '42501';
  end if;
  if old.status <> 'pending' then
    raise exception 'La propuesta ya fue respondida' using errcode = '42501';
  end if;
  if new.status <> old.status and new.status <> 'withdrawn' then
    raise exception 'Solo podés retirar tu propuesta' using errcode = '42501';
  end if;
  if new.status = 'withdrawn' then
    new.decided_at := now();
  end if;
  return new;
end;
$$;

create trigger proposals_before_write
  before insert or update on public.proposals
  for each row execute function public.tg_proposals_before_write();

-- Contador, estado "en revisión" y aviso a quien publicó.
create or replace function public.tg_proposals_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  need_author uuid;
begin
  if tg_op = 'INSERT' then
    update public.needs
    set proposals_count = proposals_count + 1,
        status = case when status = 'open' then 'in_review'::public.need_status else status end
    where id = new.need_id
    returning author_id into need_author;

    if need_author is not null and not public.is_blocked_between(need_author, new.author_id) then
      insert into public.notifications (recipient_id, actor_id, type, need_id, proposal_id)
      values (need_author, new.author_id, 'need_proposal', new.need_id, new.id);
    end if;
  elsif tg_op = 'UPDATE' and new.status = 'withdrawn' and old.status <> 'withdrawn' then
    update public.needs set proposals_count = greatest(proposals_count - 1, 0) where id = new.need_id;
    delete from public.notifications where proposal_id = new.id and type = 'need_proposal';
  end if;
  return null;
end;
$$;

create trigger proposals_after_write
  after insert or update of status on public.proposals
  for each row execute function public.tg_proposals_after_write();

-- -----------------------------------------------------------------------------
-- Aceptar / rechazar (solo quien publicó la necesidad)
-- -----------------------------------------------------------------------------
create or replace function public.accept_proposal(p_proposal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me    uuid := (select auth.uid());
  prop  public.proposals;
  need  public.needs;
  conv  uuid;
begin
  select * into prop from public.proposals where id = p_proposal_id for update;
  if not found then
    raise exception 'La propuesta no existe' using errcode = '42501';
  end if;
  select * into need from public.needs where id = prop.need_id for update;
  if need.author_id is distinct from me then
    raise exception 'Solo quien publicó la necesidad puede aceptar propuestas' using errcode = '42501';
  end if;
  if need.status not in ('open', 'in_review') then
    raise exception 'Esta necesidad ya está resuelta o cerrada' using errcode = '42501';
  end if;
  if prop.status <> 'pending' then
    raise exception 'Esta propuesta ya no está disponible' using errcode = '42501';
  end if;

  update public.proposals set status = 'accepted', decided_at = now() where id = prop.id;
  update public.proposals set status = 'declined', decided_at = now()
  where need_id = need.id and id <> prop.id and status = 'pending';
  update public.needs
  set status = 'awarded', awarded_proposal_id = prop.id, closed_at = now()
  where id = need.id;

  insert into public.notifications (recipient_id, actor_id, type, need_id, proposal_id)
  values (prop.author_id, me, 'proposal_accepted', need.id, prop.id);

  -- Chat con quien ganó, con un primer mensaje automático.
  conv := public.start_conversation(prop.author_id);
  insert into public.messages (conversation_id, sender_id, body)
  values (conv, me, '¡Hola! Acepté tu propuesta para “' || need.title || '”. Sigamos por acá para coordinar.');
  return conv;
end;
$$;

revoke execute on function public.accept_proposal(uuid) from public, anon;
grant  execute on function public.accept_proposal(uuid) to authenticated;

create or replace function public.decline_proposal(p_proposal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  prop public.proposals;
begin
  select * into prop from public.proposals where id = p_proposal_id;
  if not found or not exists (
    select 1 from public.needs n where n.id = prop.need_id and n.author_id = (select auth.uid())
  ) then
    raise exception 'Solo quien publicó la necesidad puede rechazar propuestas' using errcode = '42501';
  end if;
  if prop.status <> 'pending' then
    raise exception 'Esta propuesta ya fue respondida' using errcode = '42501';
  end if;
  update public.proposals set status = 'declined', decided_at = now() where id = prop.id;
end;
$$;

revoke execute on function public.decline_proposal(uuid) from public, anon;
grant  execute on function public.decline_proposal(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Necesidad nueva: aviso a los emprendimientos de ese rubro en esa ciudad.
-- -----------------------------------------------------------------------------
create or replace function public.tg_needs_notify_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (recipient_id, actor_id, type, need_id)
  select distinct b.owner_id, new.author_id, 'need_match'::public.notification_type, new.id
  from public.businesses b
  join public.profiles p on p.id = b.owner_id and p.status = 'active'
  where b.category_id = new.category_id
    and b.city_id = new.city_id
    and b.status = 'active'
    and b.deleted_at is null
    and b.owner_id <> new.author_id
    and not public.is_blocked_between(b.owner_id, new.author_id)
  limit 300
  on conflict do nothing;
  return null;
end;
$$;

create trigger needs_notify_match
  after insert on public.needs
  for each row execute function public.tg_needs_notify_match();

-- Vencimiento (lo llama la limpieza diaria con la clave del sistema).
create or replace function public.expire_needs()
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    update public.needs set status = 'expired'
    where status in ('open', 'in_review') and expires_at < now() and deleted_at is null
    returning 1
  )
  select count(*)::integer from expired;
$$;

revoke execute on function public.expire_needs() from public, anon, authenticated;
grant  execute on function public.expire_needs() to service_role;

-- -----------------------------------------------------------------------------
-- Seguridad
-- -----------------------------------------------------------------------------
alter table public.proposals enable row level security;

create policy "proposals: quien la mandó y quien publicó" on public.proposals
  for select to authenticated
  using ((select public.can_see_proposal(need_id, author_id)) or (select public.has_role('moderator')));

create policy "proposals: usuarios activos proponen" on public.proposals
  for insert to authenticated
  with check (author_id = (select auth.uid()) and (select public.is_active_user()));

create policy "proposals: quien la mandó la edita o retira" on public.proposals
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

revoke all on public.proposals from anon, authenticated;
grant select, insert on public.proposals to authenticated;
grant update (message, amount, availability, status) on public.proposals to authenticated;

-- Las necesidades: columnas que puede tocar el autor (estado para cerrar o renovar).
insert into public.settings (key, value, is_public, description) values
  ('limits.proposals_per_day', '30', false, 'Propuestas que una persona puede mandar cada 24 h')
on conflict (key) do nothing;

notify pgrst, 'reload schema';
