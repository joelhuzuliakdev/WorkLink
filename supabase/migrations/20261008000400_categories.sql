-- =============================================================================
-- 0004 · Categorías, subcategorías y propuestas de nuevas categorías
-- =============================================================================
-- * Nada de categorías hardcodeadas: todo vive acá y se edita desde admin.
-- * seo_noun: forma plural "de oficio" para títulos y landings
--   ("Fotografía" -> "fotógrafos", "Desarrollo web" -> "desarrolladores web").
-- * Desactivar != borrar: active = false las saca de selectores, pero el
--   contenido y las URLs existentes siguen funcionando.
-- * category_requests: propuestas de usuarios con estado
--   pending / approved / rejected / merged. El flujo de aprobación (RPC) está
--   en 0008, porque reasigna emprendimientos y publicaciones creados después.
-- =============================================================================

create table public.categories (
    id                       integer generated always as identity primary key,
    name                     text    not null,
    slug                     text    not null unique,
    seo_noun                 text,
    description              text,
    icon                     text,
    sort_order               integer not null default 100,
    active                   boolean not null default true,
    created_from_request_id  uuid,          -- FK agregada más abajo
    created_at               timestamptz not null default now(),
    updated_at               timestamptz not null default now(),
    constraint categories_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    constraint categories_name_len    check (char_length(name) between 2 and 60),
    constraint categories_desc_len    check (char_length(description) <= 500)
);

-- Un nombre (normalizado) no puede repetirse: evita "Fotografia" y "Fotografía".
create unique index categories_name_norm_key on public.categories (public.normalize_text(name));
create index categories_active_order_idx on public.categories (sort_order, name) where active;

create trigger categories_set_updated_at
    before update on public.categories
    for each row execute function public.set_updated_at();

create table public.subcategories (
    id           integer generated always as identity primary key,
    category_id  integer not null references public.categories (id) on delete restrict,
    name         text    not null,
    slug         text    not null,
    seo_noun     text,
    sort_order   integer not null default 100,
    active       boolean not null default true,
    created_from_request_id uuid,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    constraint subcategories_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    constraint subcategories_name_len    check (char_length(name) between 2 and 60),
    constraint subcategories_category_slug_key unique (category_id, slug)
);

create unique index subcategories_name_norm_key
    on public.subcategories (category_id, public.normalize_text(name));
create index subcategories_category_idx on public.subcategories (category_id, sort_order) where active;

create trigger subcategories_set_updated_at
    before update on public.subcategories
    for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Propuestas de categorías
-- -----------------------------------------------------------------------------
create table public.category_requests (
    id                       uuid primary key default gen_random_uuid(),
    requested_by             uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    kind                     public.request_kind   not null,
    parent_category_id       integer references public.categories (id) on delete set null,
    proposed_name            text not null,
    normalized_name          text generated always as (public.normalize_text(proposed_name)) stored,
    reason                   text,
    status                   public.request_status not null default 'pending',
    resolved_category_id     integer references public.categories (id)    on delete set null,
    resolved_subcategory_id  integer references public.subcategories (id) on delete set null,
    reviewed_by              uuid references public.profiles (id) on delete set null,
    review_note              text,
    reviewed_at              timestamptz,
    created_at               timestamptz not null default now(),
    constraint category_requests_name_len   check (char_length(proposed_name) between 3 and 60),
    constraint category_requests_reason_len check (char_length(reason) <= 500),
    constraint category_requests_parent     check (kind = 'category' or parent_category_id is not null)
);

-- Un mismo usuario no puede tener dos propuestas pendientes con el mismo nombre.
create unique index category_requests_pending_dedupe
    on public.category_requests (requested_by, kind, coalesce(parent_category_id, 0), normalized_name)
    where status = 'pending';
create index category_requests_pending_idx on public.category_requests (created_at) where status = 'pending';
create index category_requests_name_trgm_idx on public.category_requests
    using gin (normalized_name extensions.gin_trgm_ops) where status = 'pending';
create index category_requests_requested_by_idx on public.category_requests (requested_by, created_at desc);

alter table public.categories
    add constraint categories_created_from_request_fk
    foreign key (created_from_request_id) references public.category_requests (id) on delete set null;
alter table public.subcategories
    add constraint subcategories_created_from_request_fk
    foreign key (created_from_request_id) references public.category_requests (id) on delete set null;

-- Antispam: máximo N propuestas por usuario cada 7 días (settings).
-- Además, el usuario no puede autoaprobarse: se fuerza status = pending.
create or replace function public.tg_category_requests_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if public.is_system_call() then
        return new;
    end if;

    new.requested_by := (select auth.uid());
    new.status := 'pending';
    new.resolved_category_id := null;
    new.resolved_subcategory_id := null;
    new.reviewed_by := null;
    new.review_note := null;
    new.reviewed_at := null;

    if (
        select count(*) from public.category_requests r
        where r.requested_by = new.requested_by and r.created_at > now() - interval '7 days'
    ) >= public.setting_int('limits.category_requests_per_week', 3) then
        raise exception 'Alcanzaste el límite de propuestas de categorías por semana'
        using errcode = 'P0001', hint = 'rate_limited';
    end if;

    return new;
end;
$$;

create trigger category_requests_before_insert
    before insert on public.category_requests
    for each row execute function public.tg_category_requests_before_insert();

-- -----------------------------------------------------------------------------
-- Sugerencias para el selector: antes de proponer, mostrar parecidas.
-- suggest_categories('fotografo') -> Fotografía, Fotografía de bodas...
-- -----------------------------------------------------------------------------
create or replace function public.suggest_categories(q text, max_results integer default 8)
returns table (
    category_id     integer,
    subcategory_id  integer,
    label           text,
    score           real
)
language sql
stable
set search_path = ''
as $$
    with term as (select public.normalize_text(q) as t)
    select * from (
        select c.id, null::integer, c.name,
            extensions.word_similarity((select t from term), public.normalize_text(c.name))
        from public.categories c
        where c.active
        union all
        select s.category_id, s.id, c.name || ' › ' || s.name,
            extensions.word_similarity((select t from term), public.normalize_text(s.name))
        from public.subcategories s
        join public.categories c on c.id = s.category_id
        where s.active and c.active
    ) x (category_id, subcategory_id, label, score)
    where score >= 0.3
    order by score desc, label
    limit least(greatest(max_results, 1), 20);
$$;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.categories        enable row level security;
alter table public.subcategories     enable row level security;
alter table public.category_requests enable row level security;

create policy "categories: lectura pública de activas" on public.categories
    for select to anon, authenticated using (active);

create policy "categories: admin gestiona" on public.categories
    for all to authenticated
    using ((select public.has_role('admin')))
    with check ((select public.has_role('admin')));

create policy "subcategories: lectura pública de activas" on public.subcategories
    for select to anon, authenticated using (active);

create policy "subcategories: admin gestiona" on public.subcategories
    for all to authenticated
    using ((select public.has_role('admin')))
    with check ((select public.has_role('admin')));

create policy "category_requests: veo las mías; moderación ve todas" on public.category_requests
    for select to authenticated
    using (requested_by = (select auth.uid()) or (select public.has_role('moderator')));

create policy "category_requests: usuarios activos proponen" on public.category_requests
    for insert to authenticated
    with check (requested_by = (select auth.uid()) and (select public.is_active_user()));

-- La revisión (aprobar/rechazar/fusionar) se hace solo por las RPC de 0008.