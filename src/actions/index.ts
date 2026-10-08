import { auth } from "./auth";

/**
 * Registro central de Astro Actions. Cada dominio agrega su grupo:
 *   actions.auth.signIn, actions.posts.create (Etapa 5), etc.
 */
export const server = {
  auth,
};
