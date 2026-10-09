import type { AstroGlobal } from "astro";
import { actions } from "astro:actions";

/**
 * Formularios de las reseñas (responder, denunciar, borrar) que se envían
 * desde la página del emprendimiento o del perfil. Si salió bien devuelve la
 * redirección (PRG: recargar no reenvía); si falló, el mensaje para mostrar.
 */
export function handleReviewActions(Astro: AstroGlobal, returnTo: string): { redirect: string | null; error: string | null } {
  const reply = Astro.getActionResult(actions.reviews.reply);
  const report = Astro.getActionResult(actions.reviews.report);
  const remove = Astro.getActionResult(actions.reviews.remove);
  if (reply && !reply.error) {
    return { redirect: `${returnTo}?resena=${reply.data.removed ? "respuesta-borrada" : "respondida"}#r-${reply.data.id}`, error: null };
  }
  if (report && !report.error) return { redirect: `${returnTo}?resena=denunciada#resenas`, error: null };
  if (remove && !remove.error) return { redirect: `${returnTo}?resena=borrada#resenas`, error: null };
  const failed = reply?.error ?? report?.error ?? remove?.error;
  return { redirect: null, error: failed ? failed.message || "No pudimos guardar el cambio." : null };
}

export const REVIEW_NOTICES: Record<string, string> = {
  publicada: "¡Gracias! Publicamos tu reseña.",
  editada: "Guardamos los cambios de tu reseña.",
  borrada: "Borraste tu reseña.",
  respondida: "Publicamos tu respuesta.",
  "respuesta-borrada": "Borraste tu respuesta.",
  denunciada: "Gracias por avisarnos. Vamos a revisar la reseña.",
};
