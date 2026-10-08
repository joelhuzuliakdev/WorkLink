-- =============================================================================
-- 0006 · Archivos (media) y publicaciones
-- =============================================================================
-- * media: una fila por archivo subido a Storage (todas las entidades). El
--   archivo vive en Storage; acá solo ruta, tipo, tamaño, dimensiones y
--   variantes ({"320": "...", "800": "...", "1600": "..."}).
--   Ciclo: pending (subido, sin usar) -> attached (vinculado) / orphan.
--   Un cron limpia los pending viejos (Etapa 5).
-- * posts: tipos offer / seeking / product / service / promotion.
--   Las necesidades NO son posts: tienen su propia tabla (0007, decisión D1).
-- * Contadores desnormalizados; los mantienen triggers del sistema social
--   (Etapa 8). Los usuarios no pueden escribirlos.
-- =============================================================================

create table public.media (
    id           uuid primary key default gen_random_uuid(),
    owner_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    bucket       text not null,
    path         text not null,
    kind         public.media_kind   not null,
    mime         text not null,
    bytes        bigint not null,
    width        integer,
    height       integer,
    duration_s   numeric(6, 2),
    variants     jsonb not null default '{}'::jsonb,
    blurhash     text,
    alt          text,
    poster_path  text,
    status       public.media_status not null default 'pending',
    created_at   timestamptz not null default now(),
    attached_at  timestamptz,

    constraint media_bucket_path_key unique (bucket, path),
    constraint media_bucket_valid    check (bucket in ('avatars', 'covers', 'post-media', 'chat-attachments', 'verification')),
    -- La ruta siempre empieza con la carpeta del dueño: {owner_id}/...
    constraint media_path_owner      check (path like owner_id::text || '/%'),
    constraint media_mime_by_kind    check (
        (kind = 'image' and mime in ('image/webp', 'image/jpeg', 'image/png', 'image/avif'))
        or (kind = 'video' and mime in ('video/mp4', 'video/webm'))
    ),
    constraint media_size_by_kind    check (
        bytes > 0 and (
        (kind = 'image' and bytes <= 10 * 1024 * 1024)
        or (kind = 'video' and bytes <= 50 * 1024 * 1024)
        )
    ),
    constraint media_video_duration  check (kind <> 'video' or (duration_s is not null and duration_s <= 180)),
    constraint media_dimensions      check (
        (width is null or width between 1 and 10000) and (height is null or height between 1 and 10000)
    ),
    constraint media_variants_object check (jsonb_typeof(variants) = 'object'),
    constraint media_alt_len         check (char_length(alt) <= 300)
);

create index media_owner_idx   on public.media (owner_id, created_at desc);
create index media_cleanup_idx on public.media (created_at) where status in ('pending', 'orphan');

-- El usuario no fuerza el estado ni cambia ruta o dueño.
create or replace function public.tg_media_protect()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if public.is_system_call() then
        return coalesce(new, old);
    end if;

    if tg_op = 'INSERT' then
        new.owner_id    := (select auth.uid());
        new.status      := 'pending';
        new.attached_at := null;
        return new;
    end if;

    if new.owner_id <> old.owner_id or new.bucket <> old.bucket or new.path <> old.path
        or new.kind <> old.kind or new.status <> old.status
        or new.attached_at is distinct from old.attached_at then
        raise exception 'Campo administrado por el sistema' using errcode = '42501';
    end if;

    return new;
end;
$$;

create trigger media_protect
    before insert or update on public.media
    for each row execute function public.tg_media_protect();

-- -----------------------------------------------------------------------------
-- Publicaciones
-- -----------------------------------------------------------------------------
create table public.posts (
    id                   uuid primary key default gen_random_uuid(),
    author_id            uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    business_id          uuid references public.businesses (id) on delete cascade,
    type                 public.post_type not null,
    title                text,
    body                 text not null,
    price                numeric(14, 2),
    currency             char(3) not null default 'ARS',
    product_id           uuid references public.products (id) on delete set null,
    service_id           uuid references public.services (id) on delete set null,
    category_id          integer references public.categories (id),
    subcategory_id       integer references public.subcategories (id),
    category_request_id  uuid references public.category_requests (id) on delete set null,
    province_id          smallint references public.provinces (id),
    city_id              integer  references public.cities (id),
    zone_id              integer  references public.zones (id),
    tags                 text[] not null default '{}',
    status               public.content_status not null default 'published',
    likes_count          integer not null default 0,
    comments_count       integer not null default 0,
    saves_count          integer not null default 0,
    shares_count         integer not null default 0,
    views_count          integer not null default 0,
    published_at         timestamptz not null default now(),
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    deleted_at           timestamptz,

    constraint posts_title_len      check (char_length(title) <= 140),
    constraint posts_body_len       check (char_length(body) between 1 and 5000),
    constraint posts_price          check (price is null or price >= 0),
    constraint posts_currency       check (currency ~ '^[A-Z]{3}$'),
    constraint posts_tags_limit     check (cardinality(tags) <= 10),
    constraint posts_business_types check (type not in ('product', 'service', 'promotion') or business_id is not null),
    constraint posts_catalog_link   check ((product_id is null and service_id is null) or business_id is not null),
    constraint posts_counters       check (likes_count >= 0 and comments_count >= 0 and saves_count >= 0
                                        and shares_count >= 0 and views_count >= 0)
);

-- Feed general (cursor sobre published_at, id).
create index posts_feed_idx on public.posts (published_at desc, id desc)
    where status = 'published' and deleted_at is null;
-- Feed local / landings: ciudad + categoría.
create index posts_city_cat_idx on public.posts (city_id, category_id, published_at desc)
    where status = 'published' and deleted_at is null;
create index posts_business_idx on public.posts (business_id, published_at desc) where business_id is not null;
create index posts_author_idx   on public.posts (author_id, published_at desc);
create index posts_tags_idx     on public.posts using gin (tags);

create trigger posts_set_updated_at
    before update on public.posts
    for each row execute function public.set_updated_at();

create trigger posts_location_consistency
    before insert or update of province_id, city_id, zone_id on public.posts
    for each row execute function public.tg_location_consistency();

-- Coherencias que dependen de otras tablas.
create or replace function public.tg_content_category_consistency()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.subcategory_id is not null then
        if new.category_id is null then
        select s.category_id into new.category_id from public.subcategories s where s.id = new.subcategory_id;
        elsif not exists (
        select 1 from public.subcategories s where s.id = new.subcategory_id and s.category_id = new.category_id
        ) then
        raise exception 'La subcategoría no pertenece a la categoría' using errcode = '23514';
        end if;
    end if;
    return new;
end;
$$;

create trigger posts_category_consistency
    before insert or update of category_id, subcategory_id on public.posts
    for each row execute function public.tg_content_category_consistency();

create or replace function public.tg_posts_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    -- Normalización de tags: minúsculas, sin tildes, sin duplicados ni vacíos.
    new.tags := coalesce((
        select array_agg(distinct t) from (
        select left(public.slugify(x), 40) as t from unnest(new.tags) as x
        ) s where t <> ''
    ), '{}');

    -- Producto/servicio vinculado debe ser del mismo emprendimiento.
    if new.product_id is not null and not exists (
        select 1 from public.products p where p.id = new.product_id and p.business_id = new.business_id
    ) then
        raise exception 'El producto no pertenece al emprendimiento' using errcode = '23514';
    end if;
    if new.service_id is not null and not exists (
        select 1 from public.services s where s.id = new.service_id and s.business_id = new.business_id
    ) then
        raise exception 'El servicio no pertenece al emprendimiento' using errcode = '23514';
    end if;

    if public.is_system_call() then
        return new;
    end if;

    if tg_op = 'INSERT' then
        new.author_id      := (select auth.uid());
        new.likes_count    := 0;
        new.comments_count := 0;
        new.saves_count    := 0;
        new.shares_count   := 0;
        new.views_count    := 0;
        new.published_at   := now();
        new.deleted_at     := null;
        if new.status = 'removed' then
        new.status := 'published';
        end if;

        if (
        select count(*) from public.posts p
        where p.author_id = new.author_id and p.created_at > now() - interval '24 hours'
        ) >= public.setting_int('limits.posts_per_day', 20) then
        raise exception 'Alcanzaste el límite de publicaciones por día'
            using errcode = 'P0001', hint = 'rate_limited';
        end if;
        return new;
    end if;

    -- UPDATE
    if new.author_id <> old.author_id
        or new.business_id is distinct from old.business_id
        or new.created_at <> old.created_at
        or new.published_at <> old.published_at
        or new.likes_count <> old.likes_count or new.comments_count <> old.comments_count
        or new.saves_count <> old.saves_count or new.shares_count <> old.shares_count
        or new.views_count <> old.views_count then
        raise exception 'Campo administrado por el sistema' using errcode = '42501';
    end if;

    if not (select public.has_role('moderator')) then
        if old.status = 'removed' and new.status <> 'removed' then
        raise exception 'La publicación fue removida por moderación' using errcode = '42501';
        end if;
        if new.status = 'removed' and old.status <> 'removed' then
        raise exception 'Solo moderación puede remover publicaciones' using errcode = '42501';
        end if;
    end if;

    return new;
end;
$$;

create trigger posts_before_write
    before insert or update on public.posts
    for each row execute function public.tg_posts_before_write();

-- ¿El usuario actual puede editar la publicación? (autor o miembro del business)
create or replace function public.can_edit_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.posts p
        where p.id = p_post_id
        and p.deleted_at is null
        and (
            p.author_id = (select auth.uid())
            or (p.business_id is not null and exists (
            select 1 from public.business_members bm
            where bm.business_id = p.business_id and bm.user_id = (select auth.uid())
            ))
        )
    );
$$;

revoke execute on function public.can_edit_post(uuid) from public, anon;
grant  execute on function public.can_edit_post(uuid) to authenticated, service_role;

create or replace function public.is_post_public(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.posts p
        where p.id = p_post_id and p.status = 'published' and p.deleted_at is null
    );
$$;

revoke execute on function public.is_post_public(uuid) from public;
grant  execute on function public.is_post_public(uuid) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Archivos de una publicación (máximo 10, orden por position)
-- -----------------------------------------------------------------------------
create table public.post_media (
    post_id    uuid not null references public.posts (id) on delete cascade,
    media_id   uuid not null unique references public.media (id) on delete cascade,
    position   smallint not null,
    created_at timestamptz not null default now(),
    primary key (post_id, position),
    constraint post_media_position check (position between 0 and 9)
);

-- ¿El archivo es del usuario actual, está en el bucket indicado y sin vincular?
create or replace function public.owns_free_media(p_media_id uuid, p_bucket text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.media m
        where m.id = p_media_id
        and m.owner_id = (select auth.uid())
        and m.bucket = p_bucket
        and m.status in ('pending', 'orphan')
    );
$$;

revoke execute on function public.owns_free_media(uuid, text) from public, anon;
grant  execute on function public.owns_free_media(uuid, text) to authenticated, service_role;

-- Al vincular un archivo pasa a 'attached'; al desvincularlo, a 'orphan' para
-- que el cron de limpieza lo borre de Storage. La validación de dueño y bucket
-- está en la política de INSERT (owns_free_media).
create or replace function public.tg_attach_media()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        update public.media set status = 'attached', attached_at = now() where id = new.media_id;
        return new;
    end if;

    update public.media set status = 'orphan', attached_at = null where id = old.media_id;
    return old;
end;
$$;

create trigger post_media_attach
    after insert or delete on public.post_media
    for each row execute function public.tg_attach_media();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.media      enable row level security;
alter table public.posts      enable row level security;
alter table public.post_media enable row level security;

-- media ---------------------------------------------------------------------
create policy "media: el dueño ve todo; el resto, lo vinculado" on public.media
    for select to anon, authenticated
    using (
        owner_id = (select auth.uid())
        or (status = 'attached' and bucket in ('avatars', 'covers', 'post-media'))
        or (select public.has_role('moderator'))
    );

create policy "media: usuarios activos registran archivos" on public.media
    for insert to authenticated
    with check (owner_id = (select auth.uid()) and (select public.is_active_user()));

create policy "media: el dueño actualiza metadatos" on public.media
    for update to authenticated
    using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));

create policy "media: el dueño borra lo no vinculado" on public.media
    for delete to authenticated
    using (owner_id = (select auth.uid()) and status <> 'attached');

-- posts ---------------------------------------------------------------------
create policy "posts: lectura de publicadas; autores y moderación ven todo" on public.posts
    for select to anon, authenticated
    using (
        (status = 'published' and deleted_at is null)
        or author_id = (select auth.uid())
        or (business_id is not null and (select public.is_business_member(business_id)))
        or (select public.has_role('moderator'))
    );

create policy "posts: usuarios activos publican" on public.posts
    for insert to authenticated
    with check (
        author_id = (select auth.uid())
        and (select public.is_active_user())
        and (business_id is null or (select public.is_business_member(business_id)))
    );

create policy "posts: autor o equipo edita" on public.posts
    for update to authenticated
    using (
        deleted_at is null and (
        author_id = (select auth.uid())
        or (business_id is not null and (select public.is_business_member(business_id)))
        )
    )
    with check (
        author_id = (select auth.uid())
        or (business_id is not null and (select public.is_business_member(business_id)))
    );

create policy "posts: moderación edita" on public.posts
    for update to authenticated
    using ((select public.has_role('moderator')))
    with check ((select public.has_role('moderator')));

-- post_media ----------------------------------------------------------------
create policy "post_media: visible si la publicación lo es" on public.post_media
    for select to anon, authenticated
    using ((select public.is_post_public(post_id)) or (select public.can_edit_post(post_id))
            or (select public.has_role('moderator')));

create policy "post_media: quien edita la publicación agrega" on public.post_media
    for insert to authenticated
    with check (
        (select public.can_edit_post(post_id))
        and (select public.owns_free_media(media_id, 'post-media'))
    );

create policy "post_media: quien edita la publicación quita" on public.post_media
    for delete to authenticated
    using ((select public.can_edit_post(post_id)));