import type { ProfileSituation } from "../services/posts";

/** Datos básicos del perfil del usuario logueado (encabezado, inicio, panel). */
export interface ViewerProfile {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  situation: ProfileSituation | null;
  headline: string | null;
  following_count: number;
  verified_at: string | null;
  status: "active" | "suspended" | "banned";
  /** Perfil completo: foto, descripción, ciudad y teléfono (los "primeros pasos"). */
  profileComplete: boolean;
  /** Rol en el equipo de WorkLink (null si no es staff). */
  role: "moderator" | "admin" | "super_admin" | null;
}

/**
 * Perfil del usuario actual, consultado una sola vez por request aunque lo
 * pidan varios componentes (queda guardado en locals).
 */
export function getViewerProfile(locals: App.Locals): Promise<ViewerProfile | null> {
  if (!locals.user) return Promise.resolve(null);
  locals.viewerProfile ??= (async () => {
    const [{ data, error }, { data: role }] = await Promise.all([
      locals.supabase
        .from("profiles")
        .select("id, username, first_name, last_name, avatar_path, situation, headline, following_count, verified_at, status, bio, city_id, whatsapp, phone")
        .eq("id", locals.user!.id)
        .maybeSingle(),
      locals.supabase.from("user_roles").select("role").eq("user_id", locals.user!.id).maybeSingle(),
    ]);
    if (error) {
      console.error("[viewer]", error.message);
      return null;
    }
    if (!data) return null;
    const { bio, city_id, whatsapp, phone, ...rest } = data as Record<string, unknown>;
    return {
      ...rest,
      role: (role?.role as ViewerProfile["role"]) ?? null,
      profileComplete: Boolean(rest.avatar_path && bio && city_id && (whatsapp || phone)),
    } as ViewerProfile;
  })();
  return locals.viewerProfile;
}
