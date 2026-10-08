-- =============================================================================
-- 0016 · Verificación de personas (tilde azul)
-- =============================================================================
-- * verified_at: fecha en que WorkLink verificó la cuenta (null = no
--   verificada). Se muestra como tilde azul junto al nombre.
-- * Solo lo puede cambiar el sistema o un administrador: el usuario no puede
--   verificarse solo.
-- =============================================================================

alter table public.profiles add column if not exists verified_at timestamptz;

grant select (verified_at) on public.profiles to anon;

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

  if new.followers_count <> old.followers_count
     or new.following_count <> old.following_count
     or new.plan_tier <> old.plan_tier then
    raise exception 'Campo administrado por el sistema' using errcode = '42501';
  end if;

  if new.verified_at is distinct from old.verified_at and not (select public.has_role('admin')) then
    raise exception 'Solo la administración puede verificar cuentas' using errcode = '42501';
  end if;

  if new.status is distinct from old.status and not (select public.has_role('moderator')) then
    raise exception 'Solo moderación puede cambiar el estado de una cuenta' using errcode = '42501';
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';
