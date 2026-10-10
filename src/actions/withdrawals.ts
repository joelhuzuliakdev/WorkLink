import { ActionError, defineAction } from "astro:actions";
import { PUBLIC_SITE_URL } from "astro:env/client";
import { refundWithdrawalSchema, resolveWithdrawalSchema, withdrawalSchema } from "../schemas/withdrawal";
import { dbError, requireUser } from "../lib/auth/guards";
import { createSupabaseAdminClient } from "../lib/supabase/admin";
import { cancelPreapproval, isMercadoPagoConfigured, MercadoPagoError, refundPayment } from "../lib/mercadopago";
import { escapeHtml, layout, sendEmail } from "../lib/email";
import { legal } from "../config/legal";
import { formatMoney } from "../lib/format";
import { WITHDRAWAL_DAYS } from "../services/withdrawals";

const site = () => PUBLIC_SITE_URL.replace(/\/$/, "");

async function requireAdminRole(locals: App.Locals) {
  requireUser(locals.user);
  const { data } = await locals.supabase.rpc("has_role", { min_role: "admin" });
  if (data !== true) throw new ActionError({ code: "FORBIDDEN", message: "Solo la administración puede hacer esto." });
}

/** Avisa por email a la persona (si el envío de emails está configurado). */
async function notifyCustomer(to: string, code: string, subject: string, lines: string[]) {
  await sendEmail({
    to,
    subject: `${subject} (${code})`,
    replyTo: legal.contactEmail || undefined,
    text: [...lines, "", `Código: ${code}`].join("\n"),
    html: layout(subject, [...lines.map(escapeHtml), `Código de tu pedido: <strong>${escapeHtml(code)}</strong>`]),
  });
}

/**
 * Botón de arrepentimiento (Ley 24.240 art. 34, Res. SCI 424/2020).
 *  - request: cualquier persona, con o sin cuenta, pide revocar un plan y
 *    recibe al instante su código (en pantalla y, si hay email configurado,
 *    también por email).
 *  - refund / resolve: la administración devuelve el dinero y cancela el
 *    plan en Mercado Pago, o rechaza el pedido con un motivo.
 */
export const withdrawals = {
  request: defineAction({
    accept: "form",
    input: withdrawalSchema,
    handler: async (input, { locals }) => {
      const { data, error } = await locals.supabase.rpc("request_withdrawal", {
        p_full_name: input.full_name,
        p_email: input.email,
        p_dni: input.dni ?? null,
        p_detail: input.detail ?? null,
        p_subscription_id: input.subscription_id ?? null,
      });
      if (error) {
        if (error.hint === "rate_limited" || error.code === "23514") {
          throw new ActionError({ code: "BAD_REQUEST", message: error.message });
        }
        throw dbError(error, "No pudimos registrar tu pedido. Probá de nuevo o escribinos.");
      }
      const row = (Array.isArray(data) ? data[0] : data) as { code: string; created_at: string };

      await notifyCustomer(input.email, row.code, "Recibimos tu pedido de arrepentimiento", [
        `Hola ${input.full_name.split(" ")[0]}:`,
        `Recibimos tu pedido para revocar la contratación de tu plan de WorkLink. Si lo pediste dentro de los ${WITHDRAWAL_DAYS} días corridos desde que lo contrataste, vamos a cancelar el plan y devolverte el total por el mismo medio de pago.`,
        "Te avisamos por este medio cuando esté hecho. Si tenés dudas, respondé este email.",
      ]);
      if (legal.contactEmail) {
        await sendEmail({
          to: legal.contactEmail,
          subject: `Nuevo pedido de arrepentimiento ${row.code}`,
          text: `${input.full_name} (${input.email}) pidió arrepentirse de un plan. Revisalo en ${site()}/admin/arrepentimientos`,
          html: layout("Nuevo pedido de arrepentimiento", [
            `<strong>${escapeHtml(input.full_name)}</strong> (${escapeHtml(input.email)}) pidió arrepentirse de un plan.`,
            "Tenés que resolverlo lo antes posible: cancelar el plan y devolver el dinero.",
          ], { href: `${site()}/admin/arrepentimientos`, label: "Ver el pedido" }),
        });
      }
      return { code: row.code };
    },
  }),

  refund: defineAction({
    accept: "form",
    input: refundWithdrawalSchema,
    handler: async ({ withdrawal_id, subscription_id }, { locals }) => {
      await requireAdminRole(locals);
      const admin = createSupabaseAdminClient();

      const { data: req } = await admin.from("withdrawal_requests").select("id, code, email, full_name, status, created_at").eq("id", withdrawal_id).maybeSingle();
      if (!req) throw new ActionError({ code: "NOT_FOUND", message: "No encontramos ese pedido." });
      if (req.status !== "pending") throw new ActionError({ code: "CONFLICT", message: "Ese pedido ya está resuelto." });

      const { data: sub } = await admin
        .from("subscriptions")
        .select("id, status, mp_preapproval_id, payments:subscription_payments ( id, mp_payment_id, status, amount, paid_at )")
        .eq("id", subscription_id)
        .maybeSingle();
      if (!sub) throw new ActionError({ code: "NOT_FOUND", message: "No encontramos ese plan." });

      // Se devuelven los cobros hechos dentro del plazo (contado hacia atrás desde el pedido).
      const since = new Date(new Date(req.created_at).getTime() - (WITHDRAWAL_DAYS + 1) * 24 * 60 * 60 * 1000);
      const payments = (sub.payments as { id: string; mp_payment_id: string; status: string; amount: number; paid_at: string | null }[]).filter(
        (p) => p.status === "approved" && p.paid_at && new Date(p.paid_at) >= since,
      );

      let refunded = 0;
      try {
        if (sub.mp_preapproval_id && sub.status !== "cancelled") {
          if (!isMercadoPagoConfigured()) throw new MercadoPagoError("Mercado Pago no está configurado.", 503);
          await cancelPreapproval(sub.mp_preapproval_id);
        }
        for (const payment of payments) {
          await refundPayment(payment.mp_payment_id);
          await admin.from("subscription_payments").update({ status: "refunded" }).eq("id", payment.id);
          refunded += Number(payment.amount);
        }
      } catch (e) {
        console.error("[arrepentimiento] devolución", e);
        throw new ActionError({
          code: "BAD_GATEWAY",
          message: `Mercado Pago no pudo completar la devolución${refunded ? ` (se devolvieron ${formatMoney(refunded)})` : ""}. Probá de nuevo en unos minutos: no se devuelve dos veces lo mismo.`,
        });
      }

      const revoked = await admin.rpc("sub_revoke", { p_subscription_id: sub.id });
      if (revoked.error) console.error("[arrepentimiento] sub_revoke", revoked.error.message);

      const note = payments.length
        ? `Plan cancelado. Se devolvieron ${formatMoney(refunded)} por Mercado Pago.`
        : "Plan cancelado. No había cobros para devolver.";
      const { error } = await locals.supabase.rpc("resolve_withdrawal", {
        p_id: req.id,
        p_status: "refunded",
        p_note: note,
        p_refunded_amount: refunded,
      });
      if (error) throw dbError(error, "Se devolvió el dinero pero no pudimos marcar el pedido. Marcalo como resuelto.");

      await notifyCustomer(req.email, req.code, "Cancelamos tu plan y te devolvimos el dinero", [
        `Hola ${req.full_name.split(" ")[0]}:`,
        payments.length
          ? `Cancelamos tu plan y pedimos a Mercado Pago la devolución de ${formatMoney(refunded)} por el mismo medio de pago. Según tu banco o tarjeta, puede tardar unos días en verse.`
          : "Cancelamos tu plan. No se había hecho ningún cobro, así que no hay nada para devolver.",
      ]);
      return { refunded };
    },
  }),

  resolve: defineAction({
    accept: "form",
    input: resolveWithdrawalSchema,
    handler: async ({ withdrawal_id, status, note }, { locals }) => {
      await requireAdminRole(locals);
      const { data: req } = await locals.supabase.from("withdrawal_requests").select("code, email, full_name").eq("id", withdrawal_id).maybeSingle();
      const { error } = await locals.supabase.rpc("resolve_withdrawal", {
        p_id: withdrawal_id,
        p_status: status,
        p_note: note ?? null,
        p_refunded_amount: null,
      });
      if (error) {
        if (error.code === "23514") throw new ActionError({ code: "BAD_REQUEST", message: error.message });
        throw dbError(error, "No pudimos guardar la decisión.");
      }
      if (req && status === "rejected") {
        await notifyCustomer(req.email, req.code, "Sobre tu pedido de arrepentimiento", [
          `Hola ${req.full_name.split(" ")[0]}:`,
          `Revisamos tu pedido y no corresponde la devolución. Motivo: ${note ?? ""}`,
          "Si creés que hay un error, respondé este email y lo vemos.",
        ]);
      }
      return { status };
    },
  }),
};
