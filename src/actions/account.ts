import { ActionError, defineAction } from "astro:actions";
import { PUBLIC_SITE_URL } from "astro:env/client";
import { changeEmailSchema, changePasswordSchema, deleteAccountSchema, profileRefSchema } from "../schemas/account";
import { dbError, requireUser } from "../lib/auth/guards";
import { toActionError } from "../lib/auth/errors";
import { routes } from "../config/site";
import { createSupabaseAdminClient } from "../lib/supabase/admin";
import { cancelLivePlans, checkPassword, deletionBlocker, getAccountInfo, removeUserFiles } from "../services/account";

const confirmUrl = (next: string) =>
  new URL(`${routes.authConfirm}?next=${encodeURIComponent(next)}`, PUBLIC_SITE_URL).toString();

const wrongPassword = () =>
  new ActionError({ code: "BAD_REQUEST", message: "La contraseña actual no es correcta." });

/**
 * Configuración de la cuenta. Todo se hace en el servidor con la sesión de
 * la persona; los cambios de acceso piden la contraseña actual (si tiene).
 */
export const account = {
  /** Cambiar el email: Supabase manda un enlace de confirmación; hasta que se confirma, sigue el email anterior. */
  changeEmail: defineAction({
    accept: "form",
    input: changeEmailSchema,
    handler: async ({ email }, { locals }) => {
      const user = requireUser(locals.user);
      if (user.email && email === user.email.toLowerCase()) {
        throw new ActionError({ code: "BAD_REQUEST", message: "Ese ya es tu email." });
      }
      const { error } = await locals.supabase.auth.updateUser({ email }, { emailRedirectTo: confirmUrl("/panel/cuenta?listo=email-confirmado") });
      if (error) throw toActionError(error, "No pudimos cambiar tu email. Probá de nuevo.");
      return { email };
    },
  }),

  /** Cambiar (o crear, si entró con Google) la contraseña. Cierra la sesión en los demás dispositivos. */
  changePassword: defineAction({
    accept: "form",
    input: changePasswordSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const info = await getAccountInfo(locals.supabase);
      if (!info) throw new ActionError({ code: "INTERNAL_SERVER_ERROR", message: "No pudimos leer tu cuenta. Probá de nuevo." });

      if (info.has_password) {
        if (!input.current_password) {
          throw new ActionError({ code: "BAD_REQUEST", message: "Escribí tu contraseña actual." });
        }
        if (!user.email || !(await checkPassword(user.email, input.current_password))) throw wrongPassword();
      }

      const { error } = await locals.supabase.auth.updateUser({ password: input.password });
      if (error) throw toActionError(error, "No pudimos cambiar tu contraseña. Probá de nuevo.");

      // Si alguien más tenía tu sesión abierta, la pierde.
      await locals.supabase.auth.signOut({ scope: "others" });
      return { created: !info.has_password };
    },
  }),

  /** Cerrar la sesión en todos los dispositivos (incluido este). */
  signOutEverywhere: defineAction({
    accept: "form",
    handler: async (_input, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.auth.signOut({ scope: "global" });
      if (error) throw toActionError(error);
      return { redirectTo: `${routes.login}?sesiones=cerradas` };
    },
  }),

  block: defineAction({
    accept: "form",
    input: profileRefSchema,
    handler: async ({ profile_id }, { locals }) => {
      const user = requireUser(locals.user);
      if (profile_id === user.id) throw new ActionError({ code: "BAD_REQUEST", message: "No podés bloquearte a vos mismo." });
      const { error } = await locals.supabase.from("user_blocks").insert({ blocker_id: user.id, blocked_id: profile_id });
      if (error && error.code !== "23505") throw dbError(error, "No pudimos bloquear a esta persona. Probá de nuevo.");
      return { blocked: true };
    },
  }),

  unblock: defineAction({
    accept: "form",
    input: profileRefSchema,
    handler: async ({ profile_id }, { locals }) => {
      const user = requireUser(locals.user);
      const { error } = await locals.supabase.from("user_blocks").delete().eq("blocker_id", user.id).eq("blocked_id", profile_id);
      if (error) throw dbError(error, "No pudimos desbloquear a esta persona. Probá de nuevo.");
      return { unblocked: true };
    },
  }),

  /**
   * Borrar la cuenta para siempre. Pasos:
   *  1. Confirmación ("BORRAR") y contraseña actual (si tiene).
   *  2. Que no sea la última persona con el rol principal de administración.
   *  3. Cancelar en Mercado Pago los planes que se siguen cobrando.
   *  4. Borrar el usuario: la base borra en cascada perfil, publicaciones,
   *     emprendimientos, mensajes, etc. (los registros de cobros quedan sin usuario).
   *  5. Borrar sus archivos (fotos, videos, DNI y selfie) y cerrar la sesión.
   */
  deleteAccount: defineAction({
    accept: "form",
    input: deleteAccountSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const info = await getAccountInfo(locals.supabase);
      if (!info) throw new ActionError({ code: "INTERNAL_SERVER_ERROR", message: "No pudimos leer tu cuenta. Probá de nuevo." });
      if (info.has_password) {
        if (!input.current_password) throw new ActionError({ code: "BAD_REQUEST", message: "Escribí tu contraseña para confirmar." });
        if (!user.email || !(await checkPassword(user.email, input.current_password))) throw wrongPassword();
      }

      const admin = createSupabaseAdminClient();
      const blocker = await deletionBlocker(admin, user.id);
      if (blocker) throw new ActionError({ code: "CONFLICT", message: blocker });

      try {
        await cancelLivePlans(admin, user.id);
      } catch (e) {
        console.error("[account] cancelar planes", e);
        throw new ActionError({
          code: "SERVICE_UNAVAILABLE",
          message: "No pudimos cancelar tu plan en Mercado Pago, así que todavía no borramos la cuenta. Cancelalo desde Mi plan y volvé a probar.",
        });
      }

      const { error } = await admin.auth.admin.deleteUser(user.id);
      if (error) {
        console.error("[account] borrar usuario", error.message);
        throw new ActionError({ code: "INTERNAL_SERVER_ERROR", message: "No pudimos borrar tu cuenta. Probá de nuevo en unos minutos." });
      }

      await removeUserFiles(admin, user.id).catch((e) => console.error("[account] archivos", e));
      // La sesión ya no sirve: se limpian las cookies de este navegador.
      await locals.supabase.auth.signOut({ scope: "local" }).catch(() => undefined);
      return { redirectTo: "/?cuenta=borrada" };
    },
  }),
};
