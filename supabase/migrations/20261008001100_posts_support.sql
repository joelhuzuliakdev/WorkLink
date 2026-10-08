-- =============================================================================
-- 0011 · Soporte para publicaciones (Etapa 5)
-- =============================================================================
-- * Contador businesses.posts_count mantenido por trigger (publicadas y no
--   eliminadas), para mostrarlo sin contar filas en cada visita.
-- * Al eliminar (soft delete) una publicación se desvinculan sus archivos:
--   pasan a 'orphan' y la limpieza diaria los borra de Storage.
-- * Índice para el feed filtrado por tipo.
-- =============================================================================

create or replace function public.tg_posts_business_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  was_visible boolean := false;
  is_visible  boolean := false;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    was_visible := old.business_id is not null and old.status = 'published' and old.deleted_at is null;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    is_visible := new.business_id is not null and new.status = 'published' and new.deleted_at is null;
  end if;

  if was_visible and not is_visible then
    update public.businesses set posts_count = greatest(posts_count - 1, 0) where id = old.business_id;
  elsif is_visible and not was_visible then
    update public.businesses set posts_count = posts_count + 1 where id = new.business_id;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger posts_business_counter
  after insert or update of status, deleted_at or delete on public.posts
  for each row execute function public.tg_posts_business_counter();

-- Publicación eliminada: sus archivos quedan huérfanos para la limpieza.
create or replace function public.tg_posts_release_media()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    delete from public.post_media where post_id = new.id;
  end if;
  return new;
end;
$$;

create trigger posts_release_media
  after update of deleted_at on public.posts
  for each row execute function public.tg_posts_release_media();

-- Feed filtrado por tipo ("solo Busco", "solo Promociones").
create index if not exists posts_type_feed_idx on public.posts (type, published_at desc, id desc)
  where status = 'published' and deleted_at is null;

-- Recalcula el contador por si ya existían publicaciones.
update public.businesses b
   set posts_count = (
     select count(*) from public.posts p
     where p.business_id = b.id and p.status = 'published' and p.deleted_at is null
   );

-- -----------------------------------------------------------------------------
-- Archivos de una publicación en un solo paso (alta, quitar y reordenar).
-- Cada archivo debe ser del usuario y estar libre, o ya pertenecer a esta
-- publicación. Máximo 10 fotos, o un único video.
-- -----------------------------------------------------------------------------
create or replace function public.set_post_media(p_post_id uuid, p_media_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  ids     uuid[] := coalesce(p_media_ids, '{}');
  n       integer := coalesce(array_length(p_media_ids, 1), 0);
  videos  integer;
begin
  if not public.can_edit_post(p_post_id) then
    raise exception 'No tenés permiso para editar esta publicación' using errcode = '42501';
  end if;

  if n > 10 then
    raise exception 'Una publicación puede tener hasta 10 fotos' using errcode = '23514';
  end if;

  if (select count(distinct x) from unnest(ids) as x) <> n then
    raise exception 'Hay archivos repetidos' using errcode = '23514';
  end if;

  if exists (
    select 1
    from unnest(ids) as m (id)
    where not exists (select 1 from public.post_media pm where pm.post_id = p_post_id and pm.media_id = m.id)
      and not exists (
        select 1 from public.media x
        where x.id = m.id
          and x.owner_id = (select auth.uid())
          and x.bucket = 'post-media'
          and x.status in ('pending', 'orphan')
      )
  ) then
    raise exception 'Archivo inválido o ajeno' using errcode = '42501';
  end if;

  select count(*) into videos from public.media where id = any (ids) and kind = 'video';
  if videos > 1 or (videos = 1 and n > 1) then
    raise exception 'Una publicación puede tener hasta 10 fotos o un video' using errcode = '23514';
  end if;

  -- Se reemplaza el conjunto completo: lo que sale queda 'orphan' y lo que
  -- entra 'attached' (triggers de post_media).
  delete from public.post_media where post_id = p_post_id;
  insert into public.post_media (post_id, media_id, position)
  select p_post_id, t.id, (t.ord - 1)::smallint
  from unnest(ids) with ordinality as t (id, ord);
end;
$$;

revoke execute on function public.set_post_media(uuid, uuid[]) from public, anon;
grant  execute on function public.set_post_media(uuid, uuid[]) to authenticated;

-- -----------------------------------------------------------------------------
-- Corrección: las políticas de lectura de post_media y need_media se evalúan
-- también para visitantes sin cuenta (rol anon) y llaman a estas funciones.
-- Sin permiso de ejecución, la consulta falla ("permission denied"). Son
-- seguras para anon: sin sesión, auth.uid() es null y devuelven false.
-- -----------------------------------------------------------------------------
grant execute on function public.can_edit_post(uuid)  to anon;
grant execute on function public.is_need_author(uuid) to anon;

notify pgrst, 'reload schema';
