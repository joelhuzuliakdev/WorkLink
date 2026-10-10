import { createHmac, timingSafeEqual } from "node:crypto";
import { getSecret } from "astro:env/server";

/**
 * Cliente mínimo de la API de Mercado Pago para suscripciones (preapproval).
 * Solo servidor: usa el Access Token secreto. Nunca importar desde código que
 * llegue al navegador.
 *
 * Regla de oro: los datos de un pago se leen SIEMPRE de esta API (con
 * nuestro token), nunca del aviso (webhook) ni del navegador.
 */

export class MercadoPagoError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export interface Preapproval {
  id: string;
  status: "pending" | "authorized" | "paused" | "cancelled" | string;
  external_reference: string | null;
  init_point?: string;
  next_payment_date?: string | null;
  payer_email?: string | null;
}

export interface AuthorizedPayment {
  id: number | string;
  preapproval_id: string;
  status: string;
  transaction_amount?: number;
  payment?: { id: number | string; status: string } | null;
}

export interface Payment {
  id: number | string;
  status: string;
  transaction_amount: number;
  date_approved: string | null;
  date_created: string;
  fee_details?: { amount: number }[];
  transaction_details?: { net_received_amount?: number };
  point_of_interaction?: { transaction_data?: { subscription_id?: string } };
  metadata?: Record<string, unknown>;
}

export const isMercadoPagoConfigured = () => Boolean(getSecret("MP_ACCESS_TOKEN"));

async function call<T>(method: "GET" | "POST" | "PUT", path: string, body?: unknown, idempotencyKey?: string): Promise<T> {
  const token = getSecret("MP_ACCESS_TOKEN");
  if (!token) throw new MercadoPagoError("Los pagos todavía no están configurados.", 503);
  const base = (getSecret("MP_API_URL") || "https://api.mercadopago.com").replace(/\/$/, "");
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(idempotencyKey ? { "X-Idempotency-Key": idempotencyKey } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  const text = await response.text();
  if (!response.ok) {
    console.error("[mercadopago]", method, path, response.status, text.slice(0, 500));
    throw new MercadoPagoError("Mercado Pago no respondió bien. Probá de nuevo en unos minutos.", response.status);
  }
  return (text ? JSON.parse(text) : {}) as T;
}

/** Crea la suscripción en Mercado Pago (queda pendiente hasta que la persona paga). */
export function createPreapproval(input: {
  subscriptionId: string;
  reason: string;
  payerEmail: string;
  amount: number;
  backUrl: string;
}): Promise<Preapproval> {
  return call<Preapproval>(
    "POST",
    "/preapproval",
    {
      reason: input.reason,
      external_reference: input.subscriptionId,
      payer_email: input.payerEmail,
      back_url: input.backUrl,
      status: "pending",
      auto_recurring: {
        frequency: 1,
        frequency_type: "months",
        transaction_amount: input.amount,
        currency_id: "ARS",
      },
    },
    input.subscriptionId,
  );
}

export const getPreapproval = (id: string) => call<Preapproval>("GET", `/preapproval/${encodeURIComponent(id)}`);

export const cancelPreapproval = (id: string) =>
  call<Preapproval>("PUT", `/preapproval/${encodeURIComponent(id)}`, { status: "cancelled" });

/**
 * Devuelve el total de un pago (arrepentimiento). La misma clave de
 * idempotencia evita devolver dos veces si se toca el botón de nuevo.
 */
export const refundPayment = (paymentId: string) =>
  call<{ id: number | string; status: string; amount: number }>(
    "POST",
    `/v1/payments/${encodeURIComponent(paymentId)}/refunds`,
    {},
    `refund-${paymentId}`,
  );

export const getAuthorizedPayment = (id: string) => call<AuthorizedPayment>("GET", `/authorized_payments/${encodeURIComponent(id)}`);

export async function searchAuthorizedPayments(preapprovalId: string): Promise<AuthorizedPayment[]> {
  const data = await call<{ results?: AuthorizedPayment[] }>(
    "GET",
    `/authorized_payments/search?preapproval_id=${encodeURIComponent(preapprovalId)}&limit=100`,
  );
  return data.results ?? [];
}

export const getPayment = (id: string) => call<Payment>("GET", `/v1/payments/${encodeURIComponent(id)}`);

/** Comisión total y neto de un pago. */
export function paymentAmounts(payment: Payment) {
  const fee = (payment.fee_details ?? []).reduce((sum, f) => sum + (Number(f.amount) || 0), 0);
  const net = payment.transaction_details?.net_received_amount ?? payment.transaction_amount - fee;
  return { amount: Number(payment.transaction_amount) || 0, fee, net: Number(net) || 0 };
}

/**
 * Valida la firma de un aviso de Mercado Pago (header x-signature).
 * Mensaje firmado: "id:<data.id>;request-id:<x-request-id>;ts:<ts>;" con HMAC-SHA256.
 */
export function verifyWebhookSignature(opts: { signature: string | null; requestId: string | null; dataId: string; secret: string }): boolean {
  if (!opts.signature) return false;
  const parts = Object.fromEntries(
    opts.signature.split(",").map((part) => {
      const [key, ...rest] = part.trim().split("=");
      return [key, rest.join("=")];
    }),
  );
  const ts = parts.ts;
  const v1 = parts.v1;
  if (!ts || !v1) return false;
  // Avisos de más de 15 minutos se rechazan (evita reenvíos viejos).
  const age = Math.abs(Date.now() - Number(ts) * (ts.length > 11 ? 1 : 1000));
  if (!Number.isFinite(age) || age > 15 * 60 * 1000) return false;
  const id = /^[a-z0-9]+$/i.test(opts.dataId) ? opts.dataId.toLowerCase() : opts.dataId;
  let manifest = `id:${id};`;
  if (opts.requestId) manifest += `request-id:${opts.requestId};`;
  manifest += `ts:${ts};`;
  const expected = createHmac("sha256", opts.secret).update(manifest).digest("hex");
  const a = Buffer.from(expected, "hex");
  const b = Buffer.from(v1, "hex");
  return a.length === b.length && timingSafeEqual(a, b);
}
