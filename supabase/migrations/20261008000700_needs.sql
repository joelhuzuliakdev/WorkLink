-- =============================================================================
-- 0007 · Necesidades (solicitudes)
-- =============================================================================
-- "Busco fotógrafo para casamiento en noviembre": una solicitud con ciclo de
-- vida propio, separada de posts (decisión D1).
--
--   open ──(llega la 1.ª propuesta)──> in_review ──(acepta una)──> awarded
--     │                                   │                           │
--     └──────────── closed <──────────────┴───────────────────────────┘
--     └──(vence expires_at)──> expired ──(renueva)──> open
--
-- El autor solo puede: cerrarla, o renovarla si venció. Los pasos a
-- in_review / awarded / expired los hace el sistema (propuestas en Etapa 10,
-- vencimiento por pg_cron). La tabla proposals se crea en la Etapa 10; la FK
-- awarded_proposal_id se agrega ahí.
-- =============================================================================

create table public.needs (
    id                   uuid primary key default gen_random_uuid(),
    author_id            uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    slug                 text not null,
    title                text not null,
    description          text not null,
    category_id          integer not null references public.categories (id),
    subcategory_id       integer references public.subcategories (id),
    category_request_id  uuid references public.category_requests (id) on delete set null,
    province_id          smallint references public.provinces (id),
    city_id              integer not null references public.cities (id),
    zone_id              integer references public.zones (id),
    needed_by            date,
    budget_min           numeric(14, 2),
    budget_max           numeric(14, 2),
    currency             char(3) not null default 'ARS',
    status               public.need_status not null default 'open',
    proposals_count      integer not null default 0,
    views_count          integer not null default 0,
    awarded_proposal_id  uuid,
    expires_at           timestamptz not null default (now() + interval '30 days'),
    closed_at            timestamptz,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    deleted_at           timestamptz,

    constraint needs_title_len    check (char_length(title) between 10 and 140),
    constraint needs_desc_len     check (char_length(description) between 20 and 5000),
    constraint needs_slug_format  check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    constraint needs_budget       check (
        (budget_min is null or budget_min >= 0) and (budget_max is null or budget_max >= 0)
        and (budget_min is null or budget_max is null or budget_min <= budget_max)
    ),
    constraint needs_currency     check (currency ~ '^[A-Z]{3}$'),
    constraint needs_counters     check (proposals_count >= 0 and views_count >= 0)
);

-- Listado y filtros de "Necesidades": abiertas por categoría y ciudad.
create index needs_open_cat_city_idx on public.needs (category_id, city_id, created_at desc)
    where status in ('open', 'in_review') and deleted_at is null;
create index needs_open_recent_idx on public.needs (created_at desc, id desc)
    where status in ('open', 'in_review') and deleted_at is null;
create index needs_author_idx  on public.needs (author_id, created_at desc);
-- Job de vencimiento.
create index needs_expiry_idx  on public.needs (expires_at) where status in ('open', 'in_review');

create trigger needs_set_updated_at
    before update on public.needs
    for each row execute function public.set_updated_at();

create trigger needs_location_consistency
    before insert or update of province_id, city_id, zone_id on public.needs
    for each row execute function public.tg_location_consistency();

create trigger needs_category_consistency
    before insert or update of category_id, subcategory_id on public.needs
    for each row execute function public.tg_content_category_consistency();

create or replace function public.tg_needs_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' or new.title <> old.title then
        new.slug := coalesce(nullif(left(public.slugify(new.title), 70), ''), 'necesidad');
    end if;

    if new.needed_by is not null and (tg_op = 'INSERT' or new.needed_by is distinct from old.needed_by)
        and new.needed_by < (now() at time zone 'America/Argentina/Cordoba')::date then
        raise exception 'La fecha requerida no puede estar en el pasado' using errcode = '23514';
    end if;

    if public.is_system_call() then
        return new;
    end if;

    if tg_op = 'INSERT' then
        new.author_id           := (select auth.uid());
        new.status              := 'open';
        new.proposals_count     := 0;
        new.views_count         := 0;
        new.awarded_proposal_id := null;
        new.closed_at           := null;
        new.deleted_at          := null;
        new.expires_at          := now() + make_interval(days => public.setting_int('needs.expiry_days', 30));

        if (
        select count(*) from public.needs n
        where n.author_id = new.author_id and n.created_at > now() - interval '24 hours'
        ) >= public.setting_int('limits.needs_per_day', 5) then
        raise exception 'Alcanzaste el límite de necesidades por día'
            using errcode = 'P0001', hint = 'rate_limited';
        end if;
        return new;
    end if;

    -- UPDATE por el autor o moderación
    if new.author_id <> old.author_id or new.created_at <> old.created_at
        or new.proposals_count <> old.proposals_count or new.views_count <> old.views_count
        or new.awarded_proposal_id is distinct from old.awarded_proposal_id then
        raise exception 'Campo administrado por el sistema' using errcode = '42501';
    end if;

    if new.status is distinct from old.status then
        if new.status = 'closed' and old.status in ('open', 'in_review', 'awarded') then
        new.closed_at := now();
        elsif new.status = 'open' and old.status = 'expired' then
        -- Renovación
        new.expires_at := now() + make_interval(days => public.setting_int('needs.expiry_days', 30));
        new.closed_at  := null;
        elsif not (select public.has_role('moderator')) then
        raise exception 'Cambio de estado no permitido (% → %)', old.status, new.status
            using errcode = '42501';
        end if;
    elsif new.expires_at is distinct from old.expires_at and not (select public.has_role('moderator')) then
        raise exception 'El vencimiento se renueva con el flujo de renovación' using errcode = '42501';
    end if;

    if old.status in ('closed', 'awarded', 'expired') and new.status = old.status
        and (new.title <> old.title or new.description <> old.description
            or new.budget_min is distinct from old.budget_min or new.budget_max is distinct from old.budget_max)
        and not (select public.has_role('moderator')) then
        raise exception 'No se puede editar una necesidad cerrada' using errcode = '42501';
    end if;

    return new;
end;
$$;

create trigger needs_before_write
    before insert or update on public.needs
    for each row execute function public.tg_needs_before_write();

create or replace function public.is_need_public(p_need_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.needs n
        where n.id = p_need_id and n.deleted_at is null
    );
$$;

revoke execute on function public.is_need_public(uuid) from public;
grant  execute on function public.is_need_public(uuid) to anon, authenticated, service_role;

create or replace function public.is_need_author(p_need_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.needs n
        where n.id = p_need_id and n.author_id = (select auth.uid()) and n.deleted_at is null
    );
$$;

revoke execute on function public.is_need_author(uuid) from public, anon;
grant  execute on function public.is_need_author(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Imágenes de referencia de la necesidad (opcionales, máximo 5)
-- -----------------------------------------------------------------------------
create table public.need_media (
    need_id    uuid not null references public.needs (id) on delete cascade,
    media_id   uuid not null unique references public.media (id) on delete cascade,
    position   smallint not null,
    created_at timestamptz not null default now(),
    primary key (need_id, position),
    constraint need_media_position check (position between 0 and 4)
);

create trigger need_media_attach
    after insert or delete on public.need_media
    for each row execute function public.tg_attach_media();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.needs      enable row level security;
alter table public.need_media enable row level security;

-- Las necesidades no borradas son públicas (las cerradas se muestran con
-- noindex). No exponen datos de contacto: el contacto es vía propuesta + chat.
create policy "needs: lectura pública" on public.needs
    for select to anon, authenticated
    using (
        deleted_at is null
        or author_id = (select auth.uid())
        or (select public.has_role('moderator'))
    );

create policy "needs: usuarios activos publican" on public.needs
    for insert to authenticated
    with check (author_id = (select auth.uid()) and (select public.is_active_user()));

create policy "needs: el autor edita" on public.needs
    for update to authenticated
    using (author_id = (select auth.uid()) and deleted_at is null)
    with check (author_id = (select auth.uid()));

create policy "needs: moderación edita" on public.needs
    for update to authenticated
    using ((select public.has_role('moderator')))
    with check ((select public.has_role('moderator')));

create policy "need_media: visible si la necesidad lo es" on public.need_media
    for select to anon, authenticated
    using ((select public.is_need_public(need_id)) or (select public.is_need_author(need_id)));

create policy "need_media: el autor agrega" on public.need_media
    for insert to authenticated
    with check (
        (select public.is_need_author(need_id))
        and (select public.owns_free_media(media_id, 'post-media'))
    );

create policy "need_media: el autor quita" on public.need_media
    for delete to authenticated
    using ((select public.is_need_author(need_id)));