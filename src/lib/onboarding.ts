import type { AstroCookies } from "astro";
import type { ViewerProfile } from "./viewer";

/**
 * "Primeros pasos" del panel: se muestran hasta que el perfil esté completo
 * o hasta que la persona toque "No mostrar más" (se recuerda en este navegador).
 */
export const skipCookie = (userId: string) => `wl-pasos-${userId.slice(0, 8)}`;

export function showOnboarding(viewer: ViewerProfile | null, cookies: AstroCookies): boolean {
  if (!viewer || viewer.profileComplete) return false;
  return cookies.get(skipCookie(viewer.id))?.value !== "listo";
}
