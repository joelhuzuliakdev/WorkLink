import { auth } from "./auth";
import { profile } from "./profile";
import { business } from "./business";
import { catalog } from "./catalog";
import { posts } from "./posts";
import { social } from "./social";
import { messages } from "./messages";
import { needs } from "./needs";
import { reviews } from "./reviews";
import { admin } from "./admin";
import { billing } from "./billing";

/**
 * Registro central de Astro Actions. Cada dominio agrega su grupo:
 *   actions.auth.signIn, actions.profile.update, actions.business.create...
 */
export const server = {
  auth,
  profile,
  business,
  catalog,
  posts,
  social,
  messages,
  needs,
  reviews,
  admin,
  billing,
};
