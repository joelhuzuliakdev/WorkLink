-- =============================================================================
-- 0028 · Foto de portada en el perfil
-- =============================================================================
-- Carpeta de la imagen en el bucket público "covers" (`{user_id}/{uuid}`),
-- igual que la portada de los emprendimientos. La app verifica que la carpeta
-- sea del usuario y que el archivo exista antes de guardarla.
-- =============================================================================

alter table public.profiles
  add column if not exists cover_path text,
  add constraint profiles_cover_path_format check (cover_path is null or cover_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}$');

-- Visible también para visitantes (como la foto de perfil).
grant select (cover_path) on public.profiles to anon;

notify pgrst, 'reload schema';
