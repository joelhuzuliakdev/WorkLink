-- =============================================================================
-- 0005 · Emprendimientos, miembros, subcategorías, productos y servicios
-- =============================================================================
-- * Un usuario puede tener varios emprendimientos (límite en settings).
-- * Los permisos de edición salen de business_members, no de owner_id: así un
--   socio o empleado puede administrar el perfil sin compartir contraseña.
-- * Columnas que solo cambia el sistema o moderación (verificación, estado
--   "suspended", contadores, reputación, plan) están protegidas por trigger.
-- * Contacto directo (whatsapp, teléfono) oculto para visitantes anónimos.
-- =============================================================================

create table public.businesses (
    id                   uuid primary key default gen_random_uuid(),
    owner_id             uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    slug                 extensions.citext not null unique,
    name                 text not null,
    tagline              text,
    description          text,
    logo_path            text,
    cover_path           text,
    category_id          integer not null references public.categories (id),
    category_request_id  uuid references public.category_requests (id) on delete set null,
    province_id          smallint references public.provinces (id),
    city_id              integer  references public.cities (id),
    zone_id              integer  references public.zones (id),
    -- Punto aproximado (nunca la dirección exacta) para "cerca mío".
    lat                  numeric(8, 5),
    lng                  numeric(8, 5),
    whatsapp             text,
    phone                text,
    email                extensions.citext,
    instagram            text,
    facebook             text,
    tiktok               text,
    website              text,
    -- {"mon":[["09:00","18:00"]], "tue":[...], ...}
    hours                jsonb,
    availability         text,
    status               public.business_status     not null default 'active',
    verification         public.verification_status not null default 'none',
    verified_at          timestamptz,
    followers_count      integer not null default 0,
    posts_count          integer not null default 0,
    rating_sum           integer not null default 0,
    rating_count         integer not null default 0,
    rating_dist          integer[] not null default '{0,0,0,0,0}',
    plan_tier            text    not null default 'free',
    search_boost         numeric(4, 3) not null default 0,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    deleted_at           timestamptz,

    constraint businesses_slug_format     check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 3 and 80),
    constraint businesses_name_len        check (char_length(name) between 2 and 80),
    constraint businesses_tagline_len     check (char_length(tagline) <= 140),
    constraint businesses_desc_len        check (char_length(description) <= 3000),
    constraint businesses_availability_len check (char_length(availability) <= 200),
    constraint businesses_whatsapp_format check (whatsapp is null or whatsapp ~ '^\+?[0-9]{8,15}$'),
    constraint businesses_phone_format    check (phone    is null or phone    ~ '^\+?[0-9]{8,15}$'),
    constraint businesses_website_format  check (website  is null or website  ~* '^https?://'),
    constraint businesses_social_len      check (
        coalesce(char_length(instagram), 0) <= 60 and coalesce(char_length(facebook), 0) <= 120 and
        coalesce(char_length(tiktok), 0)    <= 60 and coalesce(char_length(website), 0)  <= 200
    ),
    constraint businesses_hours_object    check (hours is null or jsonb_typeof(hours) = 'object'),
    constraint businesses_lat_range       check (lat is null or lat between -90 and 90),
    constraint businesses_lng_range       check (lng is null or lng between -180 and 180),
    constraint businesses_counters_nonneg check (followers_count >= 0 and posts_count >= 0 and rating_sum >= 0 and rating_count >= 0),
    constraint businesses_rating_dist_len check (cardinality(rating_dist) = 5),
    constraint businesses_boost_range     check (search_boost between 0 and 1)
);

create index businesses_owner_idx on public.businesses (owner_id);
-- Listados y landings: "fotografía en Córdoba" (solo activos).
create index businesses_cat_city_idx on public.businesses (category_id, city_id, created_at desc)
    where status = 'active' and deleted_at is null;
create index businesses_city_idx on public.businesses (city_id, created_at desc)
    where status = 'active' and deleted_at is null;
create index businesses_created_idx on public.businesses (created_at desc);

create trigger businesses_set_updated_at
    before update on public.businesses
    for each row execute function public.set_updated_at();

create trigger businesses_location_consistency
    before insert or update of province_id, city_id, zone_id on public.businesses
    for each row execute function public.tg_location_consistency();

-- -----------------------------------------------------------------------------
-- Miembros
-- -----------------------------------------------------------------------------
create table public.business_members (
    business_id  uuid not null references public.businesses (id) on delete cascade,
    user_id      uuid not null references public.profiles (id)   on delete cascade,
    role         public.member_role not null default 'editor',
    created_at   timestamptz not null default now(),
    primary key (business_id, user_id)
);

create index business_members_user_idx on public.business_members (user_id);

-- is_business_member(id)            -> editor u owner
-- is_business_member(id, 'owner')   -> solo owner
create or replace function public.is_business_member(
    p_business_id uuid,
    p_min_role    public.member_role default 'editor'
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.business_members bm
        where bm.business_id = p_business_id
        and bm.user_id = (select auth.uid())
        and bm.role >= p_min_role
    );
$$;

revoke execute on function public.is_business_member(uuid, public.member_role) from public;
grant  execute on function public.is_business_member(uuid, public.member_role) to anon, authenticated, service_role;

-- ¿El emprendimiento es visible públicamente?
create or replace function public.is_business_public(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.businesses b
        where b.id = p_business_id and b.status = 'active' and b.deleted_at is null
    );
$$;

revoke execute on function public.is_business_public(uuid) from public;
grant  execute on function public.is_business_public(uuid) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Reglas de negocio de businesses
-- -----------------------------------------------------------------------------
create or replace function public.tg_businesses_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if public.is_system_call() then
        return new;
    end if;

    new.owner_id := (select auth.uid());

    -- Valores que el usuario nunca define al crear.
    new.status          := case when new.status = 'draft' then 'draft' else 'active' end;
    new.verification    := 'none';
    new.verified_at     := null;
    new.followers_count := 0;
    new.posts_count     := 0;
    new.rating_sum      := 0;
    new.rating_count    := 0;
    new.rating_dist     := '{0,0,0,0,0}';
    new.plan_tier       := 'free';
    new.search_boost    := 0;
    new.deleted_at      := null;

    if (
        select count(*) from public.businesses b
        where b.owner_id = new.owner_id and b.deleted_at is null
    ) >= public.setting_int('limits.max_businesses_per_user', 3) then
        raise exception 'Alcanzaste el máximo de emprendimientos por cuenta'
        using errcode = 'P0001', hint = 'quota_exceeded';
    end if;

    return new;
end;
$$;

create trigger businesses_before_insert
    before insert on public.businesses
    for each row execute function public.tg_businesses_before_insert();

-- El creador queda como owner en business_members.
create or replace function public.tg_businesses_add_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.business_members (business_id, user_id, role)
    values (new.id, new.owner_id, 'owner')
    on conflict (business_id, user_id) do update set role = 'owner';
    return new;
end;
$$;

create trigger businesses_add_owner
    after insert on public.businesses
    for each row execute function public.tg_businesses_add_owner();

create or replace function public.tg_businesses_protect()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    is_staff boolean;
begin
    if public.is_system_call() then
        return new;
    end if;

    is_staff := (select public.has_role('moderator'));

    -- Nunca editables por usuarios (ni moderación): los mantiene el sistema.
    if new.id <> old.id
        or new.created_at      <> old.created_at
        or new.followers_count <> old.followers_count
        or new.posts_count     <> old.posts_count
        or new.rating_sum      <> old.rating_sum
        or new.rating_count    <> old.rating_count
        or new.rating_dist     <> old.rating_dist
        or new.plan_tier       <> old.plan_tier
        or new.search_boost    <> old.search_boost then
        raise exception 'Campo administrado por el sistema' using errcode = '42501';
    end if;

    if not is_staff then
        if new.owner_id <> old.owner_id then
        raise exception 'La titularidad se transfiere con un proceso específico' using errcode = '42501';
        end if;
        if new.verification is distinct from old.verification
        and not (old.verification in ('none', 'rejected') and new.verification = 'pending') then
        raise exception 'Solo moderación decide la verificación' using errcode = '42501';
        end if;
        if new.verified_at is distinct from old.verified_at then
        raise exception 'Solo moderación decide la verificación' using errcode = '42501';
        end if;
        if old.status = 'suspended' and new.status <> 'suspended' then
        raise exception 'El emprendimiento está suspendido por moderación' using errcode = '42501';
        end if;
        if new.status = 'suspended' and old.status <> 'suspended' then
        raise exception 'Solo moderación puede suspender' using errcode = '42501';
        end if;
        if new.deleted_at is distinct from old.deleted_at
        and not (select public.is_business_member(old.id, 'owner')) then
        raise exception 'Solo el titular puede eliminar el emprendimiento' using errcode = '42501';
        end if;
    end if;

    if new.verification = 'verified' and old.verification <> 'verified' then
        new.verified_at := now();
    elsif new.verification <> 'verified' then
        new.verified_at := null;
    end if;

    return new;
end;
$$;

create trigger businesses_protect
    before update on public.businesses
    for each row execute function public.tg_businesses_protect();

-- Solo el owner gestiona miembros; no se puede quitar al único owner.
create or replace function public.tg_business_members_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if public.is_system_call() then
        return coalesce(new, old);
    end if;

    if tg_op in ('UPDATE', 'DELETE') and old.role = 'owner' and (
        select count(*) from public.business_members bm
        where bm.business_id = old.business_id and bm.role = 'owner'
    ) <= 1 and (tg_op = 'DELETE' or new.role <> 'owner') then
        raise exception 'El emprendimiento debe tener al menos un titular' using errcode = '42501';
    end if;

    return coalesce(new, old);
end;
$$;

create trigger business_members_guard
    before insert or update or delete on public.business_members
    for each row execute function public.tg_business_members_guard();

-- -----------------------------------------------------------------------------
-- Subcategorías del emprendimiento (deben ser de su categoría; máximo 10)
-- -----------------------------------------------------------------------------
create table public.business_subcategories (
    business_id     uuid    not null references public.businesses (id)    on delete cascade,
    subcategory_id  integer not null references public.subcategories (id) on delete cascade,
    created_at      timestamptz not null default now(),
    primary key (business_id, subcategory_id)
);

create index business_subcategories_sub_idx on public.business_subcategories (subcategory_id);

create or replace function public.tg_business_subcategories_check()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if not exists (
        select 1
        from public.businesses b
        join public.subcategories s on s.category_id = b.category_id
        where b.id = new.business_id and s.id = new.subcategory_id
    ) then
        raise exception 'La subcategoría no pertenece a la categoría del emprendimiento'
        using errcode = '23514';
    end if;

    if (select count(*) from public.business_subcategories x where x.business_id = new.business_id) >= 10 then
        raise exception 'Máximo 10 subcategorías por emprendimiento' using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger business_subcategories_check
    before insert on public.business_subcategories
    for each row execute function public.tg_business_subcategories_check();

-- -----------------------------------------------------------------------------
-- Productos y servicios (catálogo)
-- -----------------------------------------------------------------------------
create table public.products (
    id           uuid primary key default gen_random_uuid(),
    business_id  uuid not null references public.businesses (id) on delete cascade,
    name         text not null,
    slug         text not null,
    description  text,
    price        numeric(14, 2),
    currency     char(3) not null default 'ARS',
    price_type   public.price_type     not null default 'fixed',
    cover_path   text,
    status       public.catalog_status not null default 'active',
    sort_order   integer not null default 100,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    deleted_at   timestamptz,
    constraint products_name_len    check (char_length(name) between 2 and 120),
    constraint products_desc_len    check (char_length(description) <= 3000),
    constraint products_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    constraint products_price       check (price is null or price >= 0),
    constraint products_price_type  check (price_type = 'ask' or price is not null),
    constraint products_currency    check (currency ~ '^[A-Z]{3}$'),
    constraint products_business_slug_key unique (business_id, slug)
);

create index products_business_idx on public.products (business_id, sort_order)
    where deleted_at is null;

create trigger products_set_updated_at
    before update on public.products
    for each row execute function public.set_updated_at();

create table public.services (
    id            uuid primary key default gen_random_uuid(),
    business_id   uuid not null references public.businesses (id) on delete cascade,
    name          text not null,
    slug          text not null,
    description   text,
    price         numeric(14, 2),
    currency      char(3) not null default 'ARS',
    price_type    public.price_type     not null default 'from',
    duration_min  integer,
    service_area  text,
    cover_path    text,
    status        public.catalog_status not null default 'active',
    sort_order    integer not null default 100,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    deleted_at    timestamptz,
    constraint services_name_len     check (char_length(name) between 2 and 120),
    constraint services_desc_len     check (char_length(description) <= 3000),
    constraint services_area_len     check (char_length(service_area) <= 200),
    constraint services_slug_format  check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    constraint services_price        check (price is null or price >= 0),
    constraint services_price_type   check (price_type = 'ask' or price is not null),
    constraint services_duration     check (duration_min is null or duration_min between 5 and 100000),
    constraint services_currency     check (currency ~ '^[A-Z]{3}$'),
    constraint services_business_slug_key unique (business_id, slug)
);

create index services_business_idx on public.services (business_id, sort_order)
    where deleted_at is null;

create trigger services_set_updated_at
    before update on public.services
    for each row execute function public.set_updated_at();

-- Un producto/servicio no puede cambiar de emprendimiento.
create or replace function public.tg_catalog_protect()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if not public.is_system_call()
        and (new.business_id <> old.business_id or new.created_at <> old.created_at) then
        raise exception 'No se puede mover el ítem a otro emprendimiento' using errcode = '42501';
    end if;
    return new;
end;
$$;

create trigger products_protect before update on public.products
    for each row execute function public.tg_catalog_protect();
create trigger services_protect before update on public.services
    for each row execute function public.tg_catalog_protect();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.businesses             enable row level security;
alter table public.business_members       enable row level security;
alter table public.business_subcategories enable row level security;
alter table public.products               enable row level security;
alter table public.services               enable row level security;

-- businesses ----------------------------------------------------------------
create policy "businesses: públicos activos; miembros y moderación ven todo" on public.businesses
    for select to anon, authenticated
    using (
        (status = 'active' and deleted_at is null)
        or owner_id = (select auth.uid())
        or (select public.is_business_member(id))
        or (select public.has_role('moderator'))
    );

create policy "businesses: usuarios activos crean" on public.businesses
    for insert to authenticated
    with check (owner_id = (select auth.uid()) and (select public.is_active_user()));

create policy "businesses: miembros editan" on public.businesses
    for update to authenticated
    using ((select public.is_business_member(id)) and deleted_at is null)
    with check ((select public.is_business_member(id)));

create policy "businesses: moderación edita" on public.businesses
    for update to authenticated
    using ((select public.has_role('moderator')))
    with check ((select public.has_role('moderator')));

-- Sin DELETE físico: se usa deleted_at (soft delete).

revoke select on public.businesses from anon;
grant select (
    id, owner_id, slug, name, tagline, description, logo_path, cover_path,
    category_id, province_id, city_id, zone_id, lat, lng,
    instagram, facebook, tiktok, website, hours, availability,
    status, verification, verified_at, followers_count, posts_count,
    rating_sum, rating_count, rating_dist, plan_tier, created_at, updated_at, deleted_at
) on public.businesses to anon;

-- business_members ----------------------------------------------------------
create policy "business_members: miembros ven el equipo" on public.business_members
    for select to authenticated
    using (user_id = (select auth.uid()) or (select public.is_business_member(business_id)));

create policy "business_members: el titular agrega" on public.business_members
    for insert to authenticated
    with check ((select public.is_business_member(business_id, 'owner')));

create policy "business_members: el titular cambia roles" on public.business_members
    for update to authenticated
    using ((select public.is_business_member(business_id, 'owner')))
    with check ((select public.is_business_member(business_id, 'owner')));

create policy "business_members: el titular quita o uno se va" on public.business_members
    for delete to authenticated
    using (user_id = (select auth.uid()) or (select public.is_business_member(business_id, 'owner')));

-- business_subcategories ----------------------------------------------------
create policy "business_subcategories: lectura si el emprendimiento es visible" on public.business_subcategories
    for select to anon, authenticated
    using ((select public.is_business_public(business_id)) or (select public.is_business_member(business_id)));

create policy "business_subcategories: miembros agregan" on public.business_subcategories
    for insert to authenticated
    with check ((select public.is_business_member(business_id)));

create policy "business_subcategories: miembros quitan" on public.business_subcategories
    for delete to authenticated
    using ((select public.is_business_member(business_id)));

-- products / services -------------------------------------------------------
create policy "products: lectura pública de activos" on public.products
    for select to anon, authenticated
    using (
        (status = 'active' and deleted_at is null and (select public.is_business_public(business_id)))
        or (select public.is_business_member(business_id))
        or (select public.has_role('moderator'))
    );

create policy "products: miembros crean" on public.products
    for insert to authenticated
    with check ((select public.is_business_member(business_id)) and (select public.is_active_user()));

create policy "products: miembros editan" on public.products
    for update to authenticated
    using ((select public.is_business_member(business_id)) or (select public.has_role('moderator')))
    with check ((select public.is_business_member(business_id)) or (select public.has_role('moderator')));

create policy "services: lectura pública de activos" on public.services
    for select to anon, authenticated
    using (
        (status = 'active' and deleted_at is null and (select public.is_business_public(business_id)))
        or (select public.is_business_member(business_id))
        or (select public.has_role('moderator'))
    );

create policy "services: miembros crean" on public.services
    for insert to authenticated
    with check ((select public.is_business_member(business_id)) and (select public.is_active_user()));

create policy "services: miembros editan" on public.services
    for update to authenticated
    using ((select public.is_business_member(business_id)) or (select public.has_role('moderator')))
    with check ((select public.is_business_member(business_id)) or (select public.has_role('moderator')));