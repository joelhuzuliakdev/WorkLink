import type { SupabaseClient } from "@supabase/supabase-js";

/** Datos mínimos del usuario autenticado disponibles en cada request. */
export interface SessionUser {
  id: string;
  email: string | null;
}

/**
 * Obtiene el usuario de la sesión verificando el JWT.
 *
 * `getClaims()` valida la firma del token (localmente si el proyecto usa
 * claves asimétricas, o contra Auth si no) y no confía en datos de cookies
 * sin verificar. Nunca usar `getSession()` para decidir permisos en el servidor.
 */
export async function getSessionUser(supabase: SupabaseClient): Promise<SessionUser | null> {
  const { data, error } = await supabase.auth.getClaims();
  if (error || !data?.claims?.sub) return null;

  return {
    id: data.claims.sub,
    email: typeof data.claims.email === "string" ? data.claims.email : null,
  };
}

/** Nivel mínimo de staff. El orden coincide con el enum staff_role de la base. */
export type StaffRole = "moderator" | "admin" | "super_admin";

/**
 * ¿El usuario actual tiene al menos el rol indicado?
 * Consulta la base (función has_role), no el frontend: la fuente de verdad
 * es user_roles, protegida por RLS.
 */
export async function hasRole(supabase: SupabaseClient, minRole: StaffRole): Promise<boolean> {
  const { data, error } = await supabase.rpc("has_role", { min_role: minRole });
  if (error) return false;
  return data === true;
}
