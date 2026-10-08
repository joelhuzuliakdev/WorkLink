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
}

/**
 * Perfil del usuario actual, consultado una sola vez por request aunque lo
 * pidan varios componentes (queda guardado en locals).
 */
export function getViewerProfile(locals: App.Locals): Promise<ViewerProfile | null> {
  if (!locals.user) return Promise.resolve(null);
  locals.viewerProfile ??= (async () => {
    const { data, error } = await locals.supabase
      .from("profiles")
      .select("id, username, first_name, last_name, avatar_path, situation, headline, following_count")
      .eq("id", locals.user!.id)
      .maybeSingle();
    if (error) {
      console.error("[viewer]", error.message);
      return null;
    }
    return (data as ViewerProfile | null) ?? null;
  })();
  return locals.viewerProfile;
}
