-- =============================================================================
-- 0003 · Identidad: perfiles, roles administrativos, bloqueos y configuración
-- =============================================================================
-- * La identidad es auth.users (Supabase Auth). profiles es 1:1 con ella y se
--   crea automáticamente al registrarse (trigger on_auth_user_created).
-- * intent ('seeker' | 'provider') solo personaliza la experiencia; NO otorga
--   permisos. Cualquiera puede crear emprendimientos.
-- * Roles administrativos en user_roles (ausencia de fila = usuario común).
-- * Datos de contacto (whatsapp, teléfono) no son legibles por visitantes
--   anónimos: privilegios por columna.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Perfiles
-- -----------------------------------------------------------------------------
create table public.profiles (
    id             uuid primary key references auth.users (id) on delete cascade,
    username       extensions.citext not null unique,
    first_name     text,
    last_name      text,
    bio            text,
    avatar_path    text,
    intent         public.user_intent    not null default 'seeker',
    province_id    smallint references public.provinces (id),
    city_id        integer  references public.cities (id),
    zone_id        integer  references public.zones (id),
    whatsapp       text,
    phone          text,
    instagram      text,
    facebook       text,
    tiktok         text,
    website        text,
    status         public.profile_status not null default 'active',
    last_seen_at   timestamptz,
    onboarded_at   timestamptz,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),

    constraint profiles_username_format check (username ~ '^[a-z0-9_.]{3,30}$'),
    constraint profiles_first_name_len  check (char_length(first_name) <= 60),
    constraint profiles_last_name_len   check (char_length(last_name)  <= 60),
    constraint profiles_bio_len         check (char_length(bio) <= 500),
    constraint profiles_whatsapp_format check (whatsapp is null or whatsapp ~ '^\+?[0-9]{8,15}$'),
    constraint profiles_phone_format    check (phone    is null or phone    ~ '^\+?[0-9]{8,15}$'),
    constraint profiles_social_len      check (
        coalesce(char_length(instagram), 0) <= 60 and coalesce(char_length(facebook), 0) <= 120 and
        coalesce(char_length(tiktok), 0)    <= 60 and coalesce(char_length(website), 0)  <= 200
    ),
    constraint profiles_website_format  check (website is null or website ~* '^https?://')
);

create index profiles_city_idx on public.profiles (city_id);

create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();

create trigger profiles_location_consistency
    before insert or update of province_id, city_id, zone_id on public.profiles
    for each row execute function public.tg_location_consistency();

-- -----------------------------------------------------------------------------
-- Roles administrativos
-- -----------------------------------------------------------------------------
create table public.user_roles (
    user_id     uuid primary key references public.profiles (id) on delete cascade,
    role        public.staff_role not null,
    granted_by  uuid references public.profiles (id) on delete set null,
    created_at  timestamptz not null default now()
);

-- has_role('moderator') es verdadero para moderator, admin y super_admin.
-- SECURITY DEFINER: lee user_roles sin depender de sus políticas (evita
-- recursión de RLS). STABLE: se evalúa una vez por consulta si se envuelve en
-- (select ...) dentro de las políticas.
create or replace function public.has_role(min_role public.staff_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.user_roles ur
        where ur.user_id = (select auth.uid())
        and ur.role >= min_role
    );
$$;

revoke execute on function public.has_role(public.staff_role) from public;
grant  execute on function public.has_role(public.staff_role) to anon, authenticated, service_role;

-- ¿El usuario actual tiene perfil activo? (no suspendido ni baneado)
create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.profiles p
        where p.id = (select auth.uid()) and p.status = 'active'
    );
$$;

revoke execute on function public.is_active_user() from public;
grant  execute on function public.is_active_user() to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Bloqueos entre usuarios
-- -----------------------------------------------------------------------------
create table public.user_blocks (
    blocker_id  uuid not null references public.profiles (id) on delete cascade,
    blocked_id  uuid not null references public.profiles (id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

create index user_blocks_blocked_idx on public.user_blocks (blocked_id);

-- ¿Hay bloqueo en cualquiera de los dos sentidos? (chat, comentarios, propuestas)
create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.user_blocks ub
        where (ub.blocker_id = a and ub.blocked_id = b)
        or (ub.blocker_id = b and ub.blocked_id = a)
    );
$$;

revoke execute on function public.is_blocked_between(uuid, uuid) from public, anon;
grant  execute on function public.is_blocked_between(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Configuración global (límites, umbrales SEO, textos), editable por admin
-- -----------------------------------------------------------------------------
create table public.settings (
    key          text primary key,
    value        jsonb not null,
    is_public    boolean not null default false,
    description  text,
    updated_at   timestamptz not null default now(),
    constraint settings_key_format check (key ~ '^[a-z0-9_.]+$')
);

create trigger settings_set_updated_at
    before update on public.settings
    for each row execute function public.set_updated_at();

-- Lectura de un límite numérico con valor por defecto (usado en triggers).
create or replace function public.setting_int(p_key text, p_default integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce((select (s.value #>> '{}')::integer from public.settings s where s.key = p_key), p_default);
$$;

revoke execute on function public.setting_int(text, integer) from public, anon;
grant  execute on function public.setting_int(text, integer) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Creación automática del perfil al registrarse
-- -----------------------------------------------------------------------------
-- Usa metadata enviada en signUp({ options: { data: { username, first_name,
-- last_name, intent } } }). Si el username falta o está tomado, genera uno
-- único a partir del email.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    meta       jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
    base_name  text;
    candidate  text;
    v_intent   public.user_intent;
    attempt    integer := 0;
begin
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
    values (
        new.id,
        candidate,
        left(nullif(trim(meta ->> 'first_name'), ''), 60),
        left(nullif(trim(meta ->> 'last_name'),  ''), 60),
        v_intent
    );

    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- Protección de columnas sensibles del perfil
-- -----------------------------------------------------------------------------
-- El usuario edita su perfil, pero no puede cambiar su estado (suspensión),
-- id, fecha de alta. Moderadores pueden cambiar status. El sistema, todo.
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

    if new.status is distinct from old.status and not (select public.has_role('moderator')) then
        raise exception 'Solo moderación puede cambiar el estado de una cuenta' using errcode = '42501';
    end if;

    return new;
end;
$$;

create trigger profiles_protect
    before update on public.profiles
    for each row execute function public.tg_profiles_protect();

-- Un super_admin no puede quitarse ni rebajarse a sí mismo (evita quedarse sin
-- administradores por error). Otro super_admin sí puede hacerlo.
create or replace function public.tg_user_roles_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if public.is_system_call() then
        return coalesce(new, old);
    end if;

    if tg_op in ('UPDATE', 'DELETE') and old.user_id = (select auth.uid()) then
        raise exception 'No podés modificar tu propio rol' using errcode = '42501';
    end if;

    if tg_op = 'INSERT' then
        new.granted_by := (select auth.uid());
    end if;

    return coalesce(new, old);
end;
$$;

create trigger user_roles_guard
    before insert or update or delete on public.user_roles
    for each row execute function public.tg_user_roles_guard();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.user_roles  enable row level security;
alter table public.user_blocks enable row level security;
alter table public.settings    enable row level security;

-- profiles ------------------------------------------------------------------
create policy "profiles: lectura de cuentas activas" on public.profiles
    for select to anon, authenticated
    using (
        status = 'active'
        or id = (select auth.uid())
        or (select public.has_role('moderator'))
    );

create policy "profiles: el usuario edita su perfil" on public.profiles
    for update to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

create policy "profiles: moderación edita perfiles" on public.profiles
    for update to authenticated
    using ((select public.has_role('moderator')))
    with check ((select public.has_role('moderator')));

-- Sin políticas de INSERT/DELETE: el alta la hace el trigger y la baja ocurre
-- al borrar la cuenta en auth.users (cascade).

-- Visitantes anónimos no ven datos de contacto directo.
revoke select on public.profiles from anon;
grant select (
    id, username, first_name, last_name, bio, avatar_path, intent,
    province_id, city_id, zone_id, instagram, facebook, tiktok, website,
    status, created_at
) on public.profiles to anon;

-- user_roles ----------------------------------------------------------------
create policy "user_roles: cada uno ve su rol, admin ve todos" on public.user_roles
    for select to authenticated
    using (user_id = (select auth.uid()) or (select public.has_role('admin')));

create policy "user_roles: solo super_admin asigna" on public.user_roles
    for insert to authenticated
    with check ((select public.has_role('super_admin')));

create policy "user_roles: solo super_admin modifica" on public.user_roles
    for update to authenticated
    using ((select public.has_role('super_admin')))
    with check ((select public.has_role('super_admin')));

create policy "user_roles: solo super_admin quita" on public.user_roles
    or delete to authenticated
    using ((select public.has_role('super_admin')));

-- user_blocks ---------------------------------------------------------------
create policy "user_blocks: veo mis bloqueos" on public.user_blocks
    for select to authenticated
    using (blocker_id = (select auth.uid()));

create policy "user_blocks: bloqueo a otros" on public.user_blocks
    for insert to authenticated
    with check (blocker_id = (select auth.uid()));

create policy "user_blocks: desbloqueo" on public.user_blocks
    for delete to authenticated
    using (blocker_id = (select auth.uid()));

-- settings ------------------------------------------------------------------
create policy "settings: públicas para todos, el resto para admin" on public.settings
    for select to anon, authenticated
    using (is_public or (select public.has_role('admin')));

create policy "settings: admin crea" on public.settings
    for insert to authenticated with check ((select public.has_role('admin')));

create policy "settings: admin edita" on public.settings
    for update to authenticated
    using ((select public.has_role('admin')))
    with check ((select public.has_role('admin')));

create policy "settings: admin borra" on public.settings
    for delete to authenticated using ((select public.has_role('admin')));

-- -----------------------------------------------------------------------------
-- Escritura de ubicaciones (tablas de 0002): solo admin
-- -----------------------------------------------------------------------------
create policy "provinces: admin escribe" on public.provinces
    for all to authenticated
    using ((select public.has_role('admin')))
    with check ((select public.has_role('admin')));

create policy "cities: admin lee todas y escribe" on public.cities
    for all to authenticated
    using ((select public.has_role('admin')))
    with check ((select public.has_role('admin')));

create policy "zones: admin lee todas y escribe" on public.zones
    for all to authenticated
    using ((select public.has_role('admin')))
    with check ((select public.has_role('admin')));