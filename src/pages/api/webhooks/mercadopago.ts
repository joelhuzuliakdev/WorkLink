import type { APIRoute } from "astro";
import { getSecret } from "astro:env/server";
import { createSupabaseAdminClient } from "../../../lib/supabase/admin";
import { getAuthorizedPayment, getPayment, getPreapproval, verifyWebhookSignature } from "../../../lib/mercadopago";
import { syncSubscription } from "../../../services/billing";

/**
 * Avisos (webhooks) de Mercado Pago: suscripciones y cobros.
 *
 * Seguridad:
 *  - Se valida la firma (x-signature) con MP_WEBHOOK_SECRET.
 *  - El aviso solo dice "algo cambió en el recurso X": los datos reales se
 *    consultan a la API de Mercado Pago con nuestro token. Un aviso falso no
 *    puede marcar a nadie como pago.
 *
 * Configuración en Mercado Pago: Tus integraciones → tu app → Webhooks →
 * URL https://TU-DOMINIO/api/webhooks/mercadopago con los eventos
 * "Planes y suscripciones" y "Pagos".
 */
export const POST: APIRoute = async ({ request, url }) => {
  let body: { type?: string; topic?: string; action?: string; data?: { id?: string | number } } = {};
  try {
    body = await request.json();
  } catch {
    /* algunos avisos vienen solo con parámetros en la URL */
  }
  const type = body.type ?? body.topic ?? url.searchParams.get("type") ?? url.searchParams.get("topic") ?? "";
  const dataId = String(url.searchParams.get("data.id") ?? body.data?.id ?? url.searchParams.get("id") ?? "");
  if (!dataId || !/^[\w-]{1,64}$/.test(dataId)) return new Response("ok", { status: 200 });

  const secret = getSecret("MP_WEBHOOK_SECRET");
  if (secret) {
    const valid = verifyWebhookSignature({
      signature: request.headers.get("x-signature"),
      requestId: request.headers.get("x-request-id"),
      dataId: String(url.searchParams.get("data.id") ?? dataId),
      secret,
    });
    if (!valid) return new Response("Firma inválida", { status: 401 });
  }

  try {
    const admin = createSupabaseAdminClient();
    // ¿Qué suscripción tocó este aviso?
    let preapprovalId: string | null = null;
    if (type === "subscription_preapproval" || type === "preapproval") {
      preapprovalId = (await getPreapproval(dataId)).id;
    } else if (type === "subscription_authorized_payment" || type === "authorized_payment") {
      preapprovalId = (await getAuthorizedPayment(dataId)).preapproval_id;
    } else if (type === "payment") {
      const payment = await getPayment(dataId);
      preapprovalId =
        payment.point_of_interaction?.transaction_data?.subscription_id ??
        (typeof payment.metadata?.preapproval_id === "string" ? payment.metadata.preapproval_id : null);
    }
    if (!preapprovalId) return new Response("ok", { status: 200 });

    const { data: sub } = await admin.from("subscriptions").select("id, mp_preapproval_id").eq("mp_preapproval_id", preapprovalId).maybeSingle();
    if (!sub) return new Response("ok", { status: 200 }); // no es una suscripción de WorkLink
    await syncSubscription(admin, sub);
    return new Response("ok", { status: 200 });
  } catch (error) {
    console.error("[webhook mercadopago]", type, dataId, error);
    // 500: Mercado Pago reintenta más tarde.
    return new Response("Error", { status: 500 });
  }
};
