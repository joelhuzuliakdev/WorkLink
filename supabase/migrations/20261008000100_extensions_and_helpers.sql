-- =============================================================================
-- 0001 · Extensiones, tipos enumerados y funciones auxiliares
-- =============================================================================
-- Base común para todas las migraciones siguientes:
--   * Extensiones: citext (usernames sin distinguir mayúsculas), unaccent y
--     pg_trgm (búsqueda en español y tolerancia a errores de tipeo).
--   * Tipos enumerados de todos los estados del dominio (Etapa 2).
--   * Funciones utilitarias: updated_at automático, slugify, normalización
--     de texto, y detección de "llamada del sistema" (service role / postgres).
--
-- Nota: PostGIS (cercanía) se habilita en la migración del buscador (Etapa 7).
-- Hasta entonces las coordenadas se guardan como lat/lng numéricos.
-- =============================================================================

create schema if not exists extensions;

create extension if not exists citext   with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm  with schema extensions;

-- -----------------------------------------------------------------------------
-- Tipos enumerados
-- -----------------------------------------------------------------------------
create type public.user_intent         as enum ('seeker', 'provider');
create type public.profile_status      as enum ('active', 'suspended', 'banned');
-- Orden de menor a mayor permiso: moderator < admin < super_admin.
create type public.staff_role          as enum ('moderator', 'admin', 'super_admin');

create type public.business_status     as enum ('draft', 'active', 'inactive', 'suspended');
create type public.verification_status as enum ('none', 'pending', 'verified', 'rejected');
-- Orden de menor a mayor permiso: editor < owner (permite comparar con >=).
create type public.member_role         as enum ('editor', 'owner');
create type public.price_type          as enum ('fixed', 'from', 'ask');
create type public.catalog_status      as enum ('active', 'hidden', 'archived');

create type public.request_kind        as enum ('category', 'subcategory');
create type public.request_status      as enum ('pending', 'approved', 'rejected', 'merged');

create type public.post_type           as enum ('offer', 'seeking', 'product', 'service', 'promotion');
create type public.content_status      as enum ('published', 'hidden', 'removed');
create type public.media_kind          as enum ('image', 'video');
create type public.media_status        as enum ('pending', 'attached', 'orphan');

create type public.need_status         as enum ('open', 'in_review', 'awarded', 'closed', 'expired');

-- -----------------------------------------------------------------------------
-- updated_at automático
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Normalización de texto: minúsculas, sin tildes, espacios colapsados.
-- IMMUTABLE para poder usarla en índices (unaccent por sí sola es STABLE).
-- -----------------------------------------------------------------------------
create or replace function public.normalize_text(input text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
    select nullif(
        regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(input, ''))), '\s+', ' ', 'g'),
        ''
    );
$$;

-- -----------------------------------------------------------------------------
-- slugify('Fotografía de Bodas & Eventos') -> 'fotografia-de-bodas-eventos'
-- -----------------------------------------------------------------------------
create or replace function public.slugify(input text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
    select left(
        trim(both '-' from regexp_replace(coalesce(public.normalize_text(input), ''), '[^a-z0-9]+', '-', 'g')),
        80
    );
$$;

-- -----------------------------------------------------------------------------
-- ¿La operación la ejecuta el sistema (migraciones, funciones SECURITY DEFINER,
-- webhooks con service role) y no un usuario final?
-- Se usa en triggers que protegen columnas sensibles.
-- -----------------------------------------------------------------------------
create or replace function public.is_system_call()
returns boolean
language sql
stable
set search_path = ''
as $$
    select current_user in ('postgres', 'supabase_admin', 'service_role')
        or coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '') = 'service_role';
$$;