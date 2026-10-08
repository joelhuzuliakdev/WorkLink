-- =============================================================================
-- 0002 · Ubicaciones: Argentina → provincia → ciudad (localidad) → zona
-- =============================================================================
-- * provinces: las 24 jurisdicciones (seed). id = código INDEC de 2 dígitos.
-- * cities:    localidades. georef_id guarda el id del dataset oficial Georef
--              para poder reimportar/actualizar sin duplicar.
-- * zones:     barrios o zonas dentro de una ciudad (curadas por admin).
--
-- Lectura pública; escritura solo admin (la política se crea en 0003, cuando
-- existe la función has_role()).
-- =============================================================================

create table public.provinces (
    id          smallint primary key,                       -- código INDEC
    name        text     not null,
    slug        text     not null unique,
    created_at  timestamptz not null default now(),
    constraint provinces_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

create table public.cities (
    id           integer generated always as identity primary key,
    province_id  smallint not null references public.provinces (id) on delete restrict,
    name         text     not null,
    slug         text     not null,
    -- Coordenadas aproximadas del centro de la localidad (WGS84).
    lat          numeric(8, 5),
    lng          numeric(8, 5),
    population   integer,
    georef_id    text unique,
    active       boolean  not null default true,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    constraint cities_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    constraint cities_lat_range  check (lat is null or lat between -90 and 90),
    constraint cities_lng_range  check (lng is null or lng between -180 and 180),
    constraint cities_province_slug_key unique (province_id, slug)
);

create index cities_province_idx on public.cities (province_id) where active;
-- Autocompletado tolerante a errores: "villa maria", "Vila María"...
create index cities_name_trgm_idx on public.cities
    using gin (public.normalize_text(name) extensions.gin_trgm_ops);

create trigger cities_set_updated_at
    before update on public.cities
    for each row execute function public.set_updated_at();

create table public.zones (
    id          integer generated always as identity primary key,
    city_id     integer not null references public.cities (id) on delete cascade,
    name        text    not null,
    slug        text    not null,
    active      boolean not null default true,
    created_at  timestamptz not null default now(),
    constraint zones_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    constraint zones_city_slug_key unique (city_id, slug)
);

create index zones_city_idx on public.zones (city_id) where active;

-- -----------------------------------------------------------------------------
-- RLS (políticas de escritura en 0003)
-- -----------------------------------------------------------------------------
alter table public.provinces enable row level security;
alter table public.cities    enable row level security;
alter table public.zones     enable row level security;

create policy "provinces: lectura pública" on public.provinces
    for select to anon, authenticated using (true);

create policy "cities: lectura pública de activas" on public.cities
    for select to anon, authenticated using (active);

create policy "zones: lectura pública de activas" on public.zones
    for select to anon, authenticated using (active);

-- -----------------------------------------------------------------------------
-- Coherencia jerárquica: la ciudad debe pertenecer a la provincia y la zona a
-- la ciudad. Se reutiliza desde perfiles, emprendimientos, posts y necesidades.
-- -----------------------------------------------------------------------------
create or replace function public.assert_location(
    p_province_id smallint,
    p_city_id     integer,
    p_zone_id     integer
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
    if p_city_id is not null and p_province_id is not null and not exists (
        select 1 from public.cities c where c.id = p_city_id and c.province_id = p_province_id
    ) then
        raise exception 'La ciudad % no pertenece a la provincia %', p_city_id, p_province_id
        using errcode = '23514';
    end if;

    if p_zone_id is not null and (p_city_id is null or not exists (
        select 1 from public.zones z where z.id = p_zone_id and z.city_id = p_city_id
    )) then
        raise exception 'La zona % no pertenece a la ciudad %', p_zone_id, p_city_id
        using errcode = '23514';
    end if;
end;
$$;

-- Trigger genérico: cualquier tabla con province_id/city_id/zone_id.
-- Si llega city_id sin province_id, la completa.
create or replace function public.tg_location_consistency()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.city_id is not null and new.province_id is null then
        select c.province_id into new.province_id from public.cities c where c.id = new.city_id;
    end if;
    perform public.assert_location(new.province_id, new.city_id, new.zone_id);
    return new;
end;
$$;