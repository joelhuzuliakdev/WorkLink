-- =============================================================================
-- 0009 · Storage: buckets y políticas de acceso
-- =============================================================================
-- Convención de rutas: {user_id}/{uuid}.{ext}  (el nombre nunca lo elige el
-- usuario). Las políticas exigen que la primera carpeta sea el id del usuario
-- autenticado para subir, reemplazar o borrar.
--
-- Límites de tamaño y tipos MIME se fijan en el bucket: Storage rechaza el
-- archivo aunque el cliente mienta. config/limits.ts repite los valores para
-- avisar antes de subir.
--
-- chat-attachments: las políticas de lectura entre miembros de una
-- conversación se agregan en la Etapa 9 (Chat), cuando exista la tabla.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    ('avatars',          'avatars',          true,   2 * 1024 * 1024,
        array['image/webp', 'image/jpeg', 'image/png']),
    ('covers',           'covers',           true,   5 * 1024 * 1024,
        array['image/webp', 'image/jpeg', 'image/png']),
    ('post-media',       'post-media',       true,  50 * 1024 * 1024,
        array['image/webp', 'image/jpeg', 'image/png', 'image/avif', 'video/mp4', 'video/webm']),
    ('chat-attachments', 'chat-attachments', false, 15 * 1024 * 1024,
        array['image/webp', 'image/jpeg', 'image/png', 'application/pdf']),
    ('verification',     'verification',     false, 10 * 1024 * 1024,
        array['image/webp', 'image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do update
    set public             = excluded.public,
        file_size_limit    = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

-- -----------------------------------------------------------------------------
-- Buckets públicos: avatars, covers, post-media
-- -----------------------------------------------------------------------------
-- La lectura de archivos públicos va por URL pública + CDN y no necesita
-- política; esta permite además listar/consultar metadatos.
create policy "storage público: lectura" on storage.objects
    for select to anon, authenticated
    using (bucket_id in ('avatars', 'covers', 'post-media'));

create policy "storage público: subir a mi carpeta" on storage.objects
    for insert to authenticated
    with check (
        bucket_id in ('avatars', 'covers', 'post-media')
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and (select public.is_active_user())
    );

create policy "storage público: reemplazar en mi carpeta" on storage.objects
    for update to authenticated
    using (
        bucket_id in ('avatars', 'covers', 'post-media')
        and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    with check (
        bucket_id in ('avatars', 'covers', 'post-media')
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

create policy "storage público: borrar de mi carpeta" on storage.objects
    for delete to authenticated
    using (
        bucket_id in ('avatars', 'covers', 'post-media')
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

-- -----------------------------------------------------------------------------
-- chat-attachments (privado): por ahora, solo el propio usuario.
-- Ruta: {user_id}/{conversation_id}/{uuid}.{ext}
-- -----------------------------------------------------------------------------
create policy "chat-attachments: subir a mi carpeta" on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'chat-attachments'
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and (select public.is_active_user())
    );

create policy "chat-attachments: leer lo mío" on storage.objects
    for select to authenticated
    using (
        bucket_id = 'chat-attachments'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

-- -----------------------------------------------------------------------------
-- verification (privado): el usuario sube su documentación; solo moderación
-- y el propio usuario la leen. No se puede borrar (auditoría).
-- -----------------------------------------------------------------------------
create policy "verification: subir a mi carpeta" on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'verification'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

create policy "verification: leer lo mío o moderación" on storage.objects
    for select to authenticated
    using (
        bucket_id = 'verification'
        and (
        (storage.foldername(name))[1] = (select auth.uid())::text
        or (select public.has_role('moderator'))
        )
    );