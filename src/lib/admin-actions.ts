import type { AstroGlobal } from "astro";
import { actions } from "astro:actions";

/**
 * Formularios del panel (moderar y cambiar roles): si salió bien devuelve la
 * redirección (PRG); si falló, el mensaje.
 */
export function handleAdminActions(Astro: AstroGlobal, returnTo: string): { redirect: string | null; error: string | null } {
  const moderate = Astro.getActionResult(actions.admin.moderate);
  const role = Astro.getActionResult(actions.admin.setRole);
  const sep = returnTo.includes("?") ? "&" : "?";
  if (moderate && !moderate.error) return { redirect: `${returnTo}${sep}hecho=${moderate.data.action}`, error: null };
  if (role && !role.error) return { redirect: `${returnTo}${sep}hecho=role`, error: null };
  const failed = moderate?.error ?? role?.error;
  return { redirect: null, error: failed ? failed.message || "No pudimos aplicar el cambio." : null };
}

export const DONE_MESSAGES: Record<string, string> = {
  hide: "Listo: el contenido ya no se ve.",
  restore: "Listo: el contenido se ve de nuevo.",
  delete: "Listo: se borró.",
  suspend: "Listo: la cuenta quedó suspendida.",
  reactivate: "Listo: la cuenta está activa de nuevo.",
  verify: "Listo: quedó verificada.",
  unverify: "Listo: se quitó la verificación.",
  dismiss: "Listo: descartaste la denuncia.",
  role: "Listo: cambiaste el rol.",
};
