import { ActionError } from "astro:actions";
import type { AuthError } from "@supabase/supabase-js";

/**
 * Traduce errores de Supabase Auth a mensajes en español y a códigos de
 * Astro Actions. No revela si un email existe o no (evita enumerar cuentas).
 */
export function toActionError(error: AuthError, fallback = "No pudimos completar la operación. Probá de nuevo."): ActionError {
  switch (error.code) {
    case "invalid_credentials":
      return new ActionError({ code: "UNAUTHORIZED", message: "Email o contraseña incorrectos." });
    case "email_not_confirmed":
      return new ActionError({
        code: "FORBIDDEN",
        message: "Tenés que confirmar tu email. Revisá tu bandeja de entrada (y la carpeta de spam).",
      });
    case "weak_password":
      return new ActionError({
        code: "BAD_REQUEST",
        message: "La contraseña es muy débil o aparece en filtraciones conocidas. Elegí otra.",
      });
    case "same_password":
      return new ActionError({ code: "BAD_REQUEST", message: "La nueva contraseña tiene que ser distinta de la anterior." });
    case "over_email_send_rate_limit":
    case "over_request_rate_limit":
    case "over_sms_send_rate_limit":
      return new ActionError({
        code: "TOO_MANY_REQUESTS",
        message: "Hiciste demasiados intentos. Esperá unos minutos y volvé a probar.",
      });
    case "signup_disabled":
      return new ActionError({ code: "FORBIDDEN", message: "El registro está deshabilitado temporalmente." });
    case "user_banned":
      return new ActionError({ code: "FORBIDDEN", message: "Esta cuenta está suspendida." });
    case "session_not_found":
    case "session_expired":
      return new ActionError({ code: "UNAUTHORIZED", message: "Tu sesión venció. Ingresá de nuevo." });
    default:
      console.error("[auth]", error.code, error.message);
      return new ActionError({ code: "INTERNAL_SERVER_ERROR", message: fallback });
  }
}
