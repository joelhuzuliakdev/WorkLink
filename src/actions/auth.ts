import { ActionError, defineAction } from "astro:actions";
import { z } from "astro/zod";
import { PUBLIC_SITE_URL } from "astro:env/client";
import { forgotPasswordSchema, resetPasswordSchema, signInSchema, signUpSchema } from "../schemas/auth";
import { toActionError } from "../lib/auth/errors";
import { routes, safeNextPath } from "../config/site";

/** URL absoluta para los links de los emails de Supabase. */
const confirmUrl = (next: string) =>
  new URL(`${routes.authConfirm}?next=${encodeURIComponent(next)}`, PUBLIC_SITE_URL).toString();

/**
 * Acciones de autenticación. Se ejecutan SIEMPRE en el servidor, validan con
 * Zod y usan el cliente de Supabase de la request (locals.supabase), que
 * escribe la sesión en cookies httpOnly.
 */
export const auth = {
  signUp: defineAction({
    accept: "form",
    input: signUpSchema,
    handler: async (input, { locals }) => {
      const { data, error } = await locals.supabase.auth.signUp({
        email: input.email,
        password: input.password,
        options: {
          // Metadata leída por el trigger handle_new_user para crear el perfil.
          data: {
            first_name: input.first_name,
            last_name: input.last_name,
            intent: input.intent,
          },
          emailRedirectTo: confirmUrl(routes.home),
        },
      });

      if (error) throw toActionError(error, "No pudimos crear tu cuenta. Probá de nuevo.");

      // Con confirmación de email activada no hay sesión hasta confirmar.
      // Si el email ya existía, Supabase responde igual (no se revela).
      return { needsConfirmation: !data.session, email: input.email };
    },
  }),

  signIn: defineAction({
    accept: "form",
    input: signInSchema,
    handler: async (input, { locals }) => {
      const { error } = await locals.supabase.auth.signInWithPassword({
        email: input.email,
        password: input.password,
      });

      if (error) throw toActionError(error);

      return { redirectTo: safeNextPath(input.next, routes.home) };
    },
  }),

  /** Ingresar o crear cuenta con Google: devuelve la URL de Google a la que hay que ir. */
  google: defineAction({
    accept: "form",
    input: z.object({ next: z.string().optional() }),
    handler: async ({ next }, { locals }) => {
      const { data, error } = await locals.supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          // Vuelve a /auth/confirm (?code=...), que abre la sesión y redirige.
          redirectTo: confirmUrl(safeNextPath(next, routes.home)),
          queryParams: { prompt: "select_account" },
        },
      });
      if (error) throw toActionError(error, "No pudimos conectar con Google. Probá de nuevo.");
      if (!data.url) throw new ActionError({ code: "INTERNAL_SERVER_ERROR", message: "No pudimos conectar con Google. Probá de nuevo." });
      return { url: data.url };
    },
  }),

  signOut: defineAction({
    accept: "form",
    handler: async (_input, { locals }) => {
      // scope "local": cierra solo este dispositivo.
      const { error } = await locals.supabase.auth.signOut({ scope: "local" });
      if (error) throw toActionError(error);
      return { redirectTo: routes.home };
    },
  }),

  requestPasswordReset: defineAction({
    accept: "form",
    input: forgotPasswordSchema,
    handler: async (input, { locals }) => {
      const { error } = await locals.supabase.auth.resetPasswordForEmail(input.email, {
        redirectTo: confirmUrl(routes.resetPassword),
      });

      // Ante errores de límite avisamos; ante cualquier otro, respondemos
      // igual que si hubiera funcionado para no revelar qué emails existen.
      if (error && error.code?.startsWith("over_")) throw toActionError(error);
      if (error) console.error("[auth] reset", error.code, error.message);

      return { sent: true };
    },
  }),

  updatePassword: defineAction({
    accept: "form",
    input: resetPasswordSchema,
    handler: async (input, { locals }) => {
      if (!locals.user) {
        throw new ActionError({
          code: "UNAUTHORIZED",
          message: "El enlace venció. Pedí uno nuevo para cambiar tu contraseña.",
        });
      }

      const { error } = await locals.supabase.auth.updateUser({ password: input.password });
      if (error) throw toActionError(error, "No pudimos cambiar tu contraseña. Probá de nuevo.");

      return { redirectTo: routes.dashboard };
    },
  }),
};
