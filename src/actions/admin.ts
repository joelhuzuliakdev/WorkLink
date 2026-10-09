import { ActionError, defineAction } from "astro:actions";
import { moderateSchema, setRoleSchema } from "../schemas/admin";
import { dbError, requireUser } from "../lib/auth/guards";

/**
 * Decisiones de moderación. La base (moderate / set_staff_role) revisa el rol
 * de quien llama: aunque alguien envíe este formulario a mano, sin rol no pasa.
 */
const fromDb = (error: { code?: string; message?: string; hint?: string | null }, fallback: string) =>
  error.message && ["42501", "22023", "23514"].includes(error.code ?? "") && !error.message.startsWith("permission")
    ? new ActionError({ code: "FORBIDDEN", message: error.message })
    : dbError(error, fallback);

export const admin = {
  moderate: defineAction({
    accept: "form",
    input: moderateSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.rpc("moderate", {
        p_target_type: input.target_type,
        p_target_id: input.target_id,
        p_action: input.action,
        p_note: input.note ?? null,
      });
      if (error) throw fromDb(error, "No pudimos aplicar la decisión.");
      return { action: input.action, target: input.target_id };
    },
  }),

  setRole: defineAction({
    accept: "form",
    input: setRoleSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.rpc("set_staff_role", { p_user_id: input.user_id, p_role: input.role });
      if (error) throw fromDb(error, "No pudimos cambiar el rol.");
      return { role: input.role };
    },
  }),
};
