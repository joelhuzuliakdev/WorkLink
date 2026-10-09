import { ActionError, defineAction } from "astro:actions";
import { needRefSchema, needSchema, proposalRefSchema, proposalSchema, proposalUpdateSchema } from "../schemas/need";
import { dbError, requireUser } from "../lib/auth/guards";

/**
 * Necesidades y propuestas. Los permisos y reglas (quién puede proponer,
 * aceptar, límites, estados) los controla la base; acá se traducen errores.
 */
const forbidden = (error: { code?: string; message?: string }, fallback: string) =>
  error.code === "42501" && error.message && !error.message.startsWith("new row") && !error.message.startsWith("permission")
    ? new ActionError({ code: "FORBIDDEN", message: error.message })
    : dbError(error, fallback);

export const needs = {
  create: defineAction({
    accept: "form",
    input: needSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from("needs")
        .insert({
          title: input.title,
          description: input.description,
          category_id: input.category_id,
          subcategory_id: input.subcategory_id ?? null,
          city_id: input.city_id,
          province_id: null, // la completa la base a partir de la ciudad
          needed_by: input.needed_by ?? null,
          budget_min: input.budget_min ?? null,
          budget_max: input.budget_max ?? null,
          slug: "necesidad", // la base lo arma a partir del título
        })
        .select("id, slug")
        .single();
      if (error) throw forbidden(error, "No pudimos publicar tu necesidad. Probá de nuevo.");
      return data as { id: string; slug: string };
    },
  }),

  close: defineAction({
    accept: "form",
    input: needRefSchema,
    handler: async ({ need_id }, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase.from("needs").update({ status: "closed" }).eq("id", need_id).select("id");
      if (error) throw forbidden(error, "No pudimos cerrar la necesidad.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No podés cerrar esta necesidad." });
      return { ok: true };
    },
  }),

  renew: defineAction({
    accept: "form",
    input: needRefSchema,
    handler: async ({ need_id }, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase.from("needs").update({ status: "open" }).eq("id", need_id).eq("status", "expired").select("id");
      if (error) throw forbidden(error, "No pudimos renovar la necesidad.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "Esta necesidad no se puede renovar." });
      return { ok: true };
    },
  }),

  propose: defineAction({
    accept: "form",
    input: proposalSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const { error } = await locals.supabase.from("proposals").insert({
        need_id: input.need_id,
        author_id: user.id,
        business_id: input.business_id ?? null,
        message: input.message,
        amount: input.amount ?? null,
        availability: input.availability ?? null,
      });
      if (error) {
        if (error.code === "23505") throw new ActionError({ code: "CONFLICT", message: "Ya mandaste una propuesta para esta necesidad." });
        throw forbidden(error, "No pudimos enviar tu propuesta. Probá de nuevo.");
      }
      return { ok: true };
    },
  }),

  updateProposal: defineAction({
    accept: "form",
    input: proposalUpdateSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from("proposals")
        .update({ message: input.message, amount: input.amount ?? null, availability: input.availability ?? null })
        .eq("id", input.proposal_id)
        .select("id");
      if (error) throw forbidden(error, "No pudimos guardar los cambios.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No podés editar esta propuesta." });
      return { ok: true };
    },
  }),

  withdraw: defineAction({
    accept: "form",
    input: proposalRefSchema,
    handler: async ({ proposal_id }, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase.from("proposals").update({ status: "withdrawn" }).eq("id", proposal_id).select("id");
      if (error) throw forbidden(error, "No pudimos retirar la propuesta.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No podés retirar esta propuesta." });
      return { ok: true };
    },
  }),

  accept: defineAction({
    accept: "form",
    input: proposalRefSchema,
    handler: async ({ proposal_id }, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase.rpc("accept_proposal", { p_proposal_id: proposal_id });
      if (error) throw forbidden(error, "No pudimos aceptar la propuesta.");
      return { conversationId: data as string };
    },
  }),

  decline: defineAction({
    accept: "form",
    input: proposalRefSchema,
    handler: async ({ proposal_id }, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.rpc("decline_proposal", { p_proposal_id: proposal_id });
      if (error) throw forbidden(error, "No pudimos rechazar la propuesta.");
      return { ok: true };
    },
  }),
};
