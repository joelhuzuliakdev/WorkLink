import { ActionError, defineAction } from "astro:actions";
import { PUBLIC_SITE_URL } from "astro:env/client";
import { reviewVerificationSchema, subscribeSchema, subscriptionRefSchema, updatePlanSchema, verificationSchema } from "../schemas/billing";
import { dbError, requireUser } from "../lib/auth/guards";
import { createSupabaseAdminClient } from "../lib/supabase/admin";
import { cancelPreapproval, createPreapproval, isMercadoPagoConfigured, MercadoPagoError } from "../lib/mercadopago";
import { syncSubscription } from "../services/billing";

/**
 * Suscripciones y verificación. Reglas y permisos en la base (funciones con
 * su propio control); los datos de pago solo los escribe el servidor después
 * de consultarlos a Mercado Pago.
 */
const fromDb = (error: { code?: string; message?: string; hint?: string | null }, fallback: string) =>
  error.message && ["42501", "23514"].includes(error.code ?? "") && !error.message.startsWith("permission") && !error.message.startsWith("new row")
    ? new ActionError({ code: "FORBIDDEN", message: error.message })
    : dbError(error, fallback);

const fromMp = (error: unknown, fallback: string) =>
  error instanceof MercadoPagoError
    ? new ActionError({ code: "BAD_GATEWAY", message: error.message })
    : (console.error("[billing]", error), new ActionError({ code: "INTERNAL_SERVER_ERROR", message: fallback }));

export const billing = {
  subscribe: defineAction({
    accept: "form",
    input: subscribeSchema,
    handler: async (input, { locals, url }) => {
      requireUser(locals.user);
      if (!isMercadoPagoConfigured()) {
        throw new ActionError({ code: "SERVICE_UNAVAILABLE", message: "Los pagos todavía no están habilitados. Probá más tarde." });
      }
      // 1) La base valida y crea la suscripción pendiente (con el precio de hoy).
      const { data, error } = await locals.supabase.rpc("start_subscription", {
        p_plan_id: input.plan_id,
        p_business_id: input.business_id ?? null,
        p_payer_email: input.payer_email,
      });
      if (error) throw fromDb(error, "No pudimos iniciar la suscripción.");
      const sub = (data as { id: string; price: number; plan_name: string }[])[0];

      // 2) Mercado Pago crea el cobro mensual y nos da el link de pago.
      const site = (PUBLIC_SITE_URL || url.origin).replace(/\/$/, "");
      let pre;
      try {
        pre = await createPreapproval({
          subscriptionId: sub.id,
          reason: `WorkLink · ${sub.plan_name}`,
          payerEmail: input.payer_email,
          amount: Number(sub.price),
          backUrl: `${site}/panel/plan?sub=${sub.id}`,
        });
      } catch (e) {
        throw fromMp(e, "No pudimos conectar con Mercado Pago.");
      }
      if (!pre.init_point) throw new ActionError({ code: "INTERNAL_SERVER_ERROR", message: "Mercado Pago no devolvió el link de pago." });

      // 3) Se guarda el id de Mercado Pago (solo el servidor puede hacerlo).
      const admin = createSupabaseAdminClient();
      const attached = await admin.rpc("sub_attach_preapproval", {
        p_subscription_id: sub.id,
        p_preapproval_id: pre.id,
        p_init_point: pre.init_point,
      });
      if (attached.error) throw dbError(attached.error, "No pudimos guardar la suscripción.");
      return { checkoutUrl: pre.init_point };
    },
  }),

  /** Consulta a Mercado Pago el estado actual (al volver del pago o con "Actualizar"). */
  sync: defineAction({
    accept: "form",
    input: subscriptionRefSchema,
    handler: async ({ subscription_id }, { locals }) => {
      const user = requireUser(locals.user);
      // RLS: solo se encuentra si es del usuario.
      const { data: sub } = await locals.supabase
        .from("subscriptions")
        .select("id, mp_preapproval_id, user_id")
        .eq("id", subscription_id)
        .eq("user_id", user.id)
        .maybeSingle();
      if (!sub) throw new ActionError({ code: "NOT_FOUND", message: "No encontramos esa suscripción." });
      try {
        await syncSubscription(createSupabaseAdminClient(), sub);
      } catch (e) {
        throw fromMp(e, "No pudimos consultar el estado del pago.");
      }
      return { ok: true };
    },
  }),

  cancel: defineAction({
    accept: "form",
    input: subscriptionRefSchema,
    handler: async ({ subscription_id }, { locals }) => {
      const user = requireUser(locals.user);
      const { data: sub } = await locals.supabase
        .from("subscriptions")
        .select("id, mp_preapproval_id, user_id, status")
        .eq("id", subscription_id)
        .eq("user_id", user.id)
        .maybeSingle();
      if (!sub || sub.status === "cancelled") throw new ActionError({ code: "NOT_FOUND", message: "No encontramos esa suscripción activa." });
      const admin = createSupabaseAdminClient();
      try {
        if (sub.mp_preapproval_id) {
          await cancelPreapproval(sub.mp_preapproval_id);
          await syncSubscription(admin, sub);
        } else {
          const done = await admin.rpc("sub_sync", { p_subscription_id: sub.id, p_preapproval_id: null, p_status: "cancelled", p_next_payment_at: null });
          if (done.error) throw done.error;
        }
      } catch (e) {
        throw fromMp(e, "No pudimos cancelar en Mercado Pago. Probá de nuevo.");
      }
      return { ok: true };
    },
  }),

  submitVerification: defineAction({
    accept: "form",
    input: verificationSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.rpc("submit_verification", {
        p_document_path: input.document_path,
        p_selfie_path: input.selfie_path,
      });
      if (error) throw fromDb(error, "No pudimos enviar tu documentación.");
      return { ok: true };
    },
  }),

  // --- Administración -------------------------------------------------------
  reviewVerification: defineAction({
    accept: "form",
    input: reviewVerificationSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.rpc("review_verification", {
        p_request_id: input.request_id,
        p_approve: input.decision === "approve",
        p_reason: input.reason ?? null,
      });
      if (error) throw fromDb(error, "No pudimos guardar la decisión.");
      return { decision: input.decision };
    },
  }),

  updatePlan: defineAction({
    accept: "form",
    input: updatePlanSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from("plans")
        .update({ price: input.price, active: input.active })
        .eq("id", input.plan_id)
        .select("id");
      if (error) throw fromDb(error, "No pudimos guardar el plan.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "Solo administración puede cambiar los planes." });
      return { ok: true };
    },
  }),
};
