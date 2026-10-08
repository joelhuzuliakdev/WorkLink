-- =============================================================================
-- 0008 · Revisión de propuestas de categorías (aprobar / fusionar / rechazar)
-- =============================================================================
-- Funciones RPC para moderación. Al aprobar, la categoría o subcategoría se
-- vuelve GLOBAL (disponible para todos) y todo el contenido que esperaba esa
-- propuesta (emprendimientos, publicaciones, necesidades) se reasigna.
-- Otras propuestas pendientes con el mismo nombre se marcan como fusionadas.
--
-- Uso desde el servidor (Astro Action del panel admin):
--   supabase.rpc('approve_category_request', { p_request_id, p_name, p_slug, p_seo_noun })
-- =============================================================================

-- Reasigna el contenido que esperaba una propuesta a la categoría resultante.
create or replace function public._apply_category_resolution(
    p_request_id     uuid,
    p_category_id    integer,
    p_subcategory_id integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_subcategory_id is null then
        -- Propuesta de categoría: el contenido pasa a la categoría nueva.
        update public.businesses set category_id = p_category_id, category_request_id = null
        where category_request_id = p_request_id;
        update public.posts set category_id = p_category_id, subcategory_id = null, category_request_id = null
        where category_request_id = p_request_id;
        update public.needs set category_id = p_category_id, subcategory_id = null, category_request_id = null
        where category_request_id = p_request_id;
    else
        -- Propuesta de subcategoría: se agrega donde la categoría coincide.
        insert into public.business_subcategories (business_id, subcategory_id)
        select b.id, p_subcategory_id
        from public.businesses b
        where b.category_request_id = p_request_id
            and b.category_id = p_category_id
            and (select count(*) from public.business_subcategories x where x.business_id = b.id) < 10
        on conflict do nothing;
        update public.businesses set category_request_id = null
        where category_request_id = p_request_id;

        update public.posts set subcategory_id = p_subcategory_id, category_request_id = null
        where category_request_id = p_request_id and category_id = p_category_id;
        update public.posts set category_request_id = null where category_request_id = p_request_id;

        update public.needs set subcategory_id = p_subcategory_id, category_request_id = null
        where category_request_id = p_request_id and category_id = p_category_id;
        update public.needs set category_request_id = null where category_request_id = p_request_id;
    end if;
end;
$$;

revoke execute on function public._apply_category_resolution(uuid, integer, integer) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Aprobar
-- -----------------------------------------------------------------------------
create or replace function public.approve_category_request(
    p_request_id  uuid,
    p_name        text default null,   -- nombre final (moderación puede corregirlo)
    p_slug        text default null,
    p_seo_noun    text default null,
    p_note        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    req        public.category_requests;
    v_name     text;
    v_slug     text;
    v_cat_id   integer;
    v_sub_id   integer;
    v_twins    integer;
begin
    if not (select public.has_role('moderator')) then
        raise exception 'Permiso denegado' using errcode = '42501';
    end if;

    select * into req from public.category_requests where id = p_request_id for update;
    if not found then
        raise exception 'Propuesta inexistente' using errcode = 'P0002';
    end if;
    if req.status <> 'pending' then
        raise exception 'La propuesta ya fue revisada (%)', req.status using errcode = 'P0001';
    end if;

    v_name := coalesce(nullif(trim(p_name), ''), trim(req.proposed_name));
    v_slug := public.slugify(coalesce(nullif(trim(p_slug), ''), v_name));

    if req.kind = 'category' then
        insert into public.categories (name, slug, seo_noun, created_from_request_id)
        values (v_name, v_slug, nullif(trim(p_seo_noun), ''), req.id)
        returning id into v_cat_id;
    else
        v_cat_id := req.parent_category_id;
        insert into public.subcategories (category_id, name, slug, seo_noun, created_from_request_id)
        values (v_cat_id, v_name, v_slug, nullif(trim(p_seo_noun), ''), req.id)
        returning id into v_sub_id;
    end if;

    update public.category_requests
        set status = 'approved',
            resolved_category_id = v_cat_id,
            resolved_subcategory_id = v_sub_id,
            reviewed_by = (select auth.uid()),
            review_note = p_note,
            reviewed_at = now()
    where id = req.id;

    perform public._apply_category_resolution(req.id, v_cat_id, v_sub_id);

    -- Propuestas gemelas pendientes: quedan resueltas con el mismo resultado.
    with twins as (
        update public.category_requests r
        set status = 'merged',
            resolved_category_id = v_cat_id,
            resolved_subcategory_id = v_sub_id,
            reviewed_by = (select auth.uid()),
            review_note = 'Fusionada con una propuesta aprobada',
            reviewed_at = now()
        where r.status = 'pending'
        and r.kind = req.kind
        and coalesce(r.parent_category_id, 0) = coalesce(req.parent_category_id, 0)
        and r.normalized_name = public.normalize_text(v_name)
        returning r.id
    )
    select count(*) into v_twins from (
        select public._apply_category_resolution(t.id, v_cat_id, v_sub_id) from twins t
    ) applied;

    return jsonb_build_object('category_id', v_cat_id, 'subcategory_id', v_sub_id, 'merged_twins', v_twins);
exception
    when unique_violation then
        raise exception 'Ya existe una categoría con ese nombre o slug; usá "fusionar"'
        using errcode = '23505';
end;
$$;

-- -----------------------------------------------------------------------------
-- Fusionar con una existente (la propuesta era un sinónimo)
-- -----------------------------------------------------------------------------
create or replace function public.merge_category_request(
    p_request_id      uuid,
    p_category_id     integer,
    p_subcategory_id  integer default null,
    p_note            text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    req public.category_requests;
begin
    if not (select public.has_role('moderator')) then
        raise exception 'Permiso denegado' using errcode = '42501';
    end if;

    select * into req from public.category_requests where id = p_request_id for update;
    if not found or req.status <> 'pending' then
        raise exception 'Propuesta inexistente o ya revisada' using errcode = 'P0001';
    end if;

    if p_subcategory_id is not null and not exists (
        select 1 from public.subcategories s where s.id = p_subcategory_id and s.category_id = p_category_id
    ) then
        raise exception 'La subcategoría no pertenece a la categoría' using errcode = '23514';
    end if;

    update public.category_requests
        set status = 'merged',
            resolved_category_id = p_category_id,
            resolved_subcategory_id = p_subcategory_id,
            reviewed_by = (select auth.uid()),
            review_note = p_note,
            reviewed_at = now()
    where id = req.id;

    perform public._apply_category_resolution(req.id, p_category_id, p_subcategory_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- Rechazar: el contenido queda en la categoría que eligió el usuario como base.
-- -----------------------------------------------------------------------------
create or replace function public.reject_category_request(
    p_request_id  uuid,
    p_note        text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not (select public.has_role('moderator')) then
        raise exception 'Permiso denegado' using errcode = '42501';
    end if;

    update public.category_requests
        set status = 'rejected',
            reviewed_by = (select auth.uid()),
            review_note = p_note,
            reviewed_at = now()
    where id = p_request_id and status = 'pending';

    if not found then
        raise exception 'Propuesta inexistente o ya revisada' using errcode = 'P0001';
    end if;

    update public.businesses set category_request_id = null where category_request_id = p_request_id;
    update public.posts      set category_request_id = null where category_request_id = p_request_id;
    update public.needs      set category_request_id = null where category_request_id = p_request_id;
end;
$$;

revoke execute on function public.approve_category_request(uuid, text, text, text, text) from public, anon;
revoke execute on function public.merge_category_request(uuid, integer, integer, text)     from public, anon;
revoke execute on function public.reject_category_request(uuid, text)                     from public, anon;
grant  execute on function public.approve_category_request(uuid, text, text, text, text) to authenticated;
grant  execute on function public.merge_category_request(uuid, integer, integer, text)     to authenticated;
grant  execute on function public.reject_category_request(uuid, text)                     to authenticated;