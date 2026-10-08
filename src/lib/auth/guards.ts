import { ActionError } from "astro:actions";
import type { SessionUser } from "./session";

/** Exige sesión dentro de una Astro Action. */
export function requireUser(user: SessionUser | null): SessionUser {
  if (!user) {
    throw new ActionError({ code: "UNAUTHORIZED", message: "Tu sesión venció. Ingresá de nuevo." });
  }
  return user;
}

/** Traduce errores de PostgreSQL / PostgREST a mensajes para el usuario. */
export function dbError(error: { code?: string; message?: string; hint?: string | null }, fallback: string): ActionError {
  if (error.hint === "rate_limited" || error.hint === "quota_exceeded") {
    return new ActionError({ code: "TOO_MANY_REQUESTS", message: error.message ?? fallback });
  }
  switch (error.code) {
    case "42501": // permiso denegado (RLS o trigger de protección)
      return new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para hacer este cambio." });
    case "23514": // check constraint / validación de trigger
      return new ActionError({ code: "BAD_REQUEST", message: error.message?.startsWith("new row") ? fallback : (error.message ?? fallback) });
    default:
      console.error("[db]", error.code, error.message);
      return new ActionError({ code: "INTERNAL_SERVER_ERROR", message: fallback });
  }
}
