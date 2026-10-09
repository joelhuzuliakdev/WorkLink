import type { SupabaseClient } from "@supabase/supabase-js";
import { getPayment, getPreapproval, paymentAmounts, searchAuthorizedPayments } from "../lib/mercadopago";

/**
 * Planes, suscripciones y pagos. Lo que pagó cada persona lo escribe solo el
 * servidor (con la service role) después de consultarlo a Mercado Pago.
 */

export type PlanId = "destacado" | "pro" | "verificacion";
export type SubscriptionStatus = "pending" | "authorized" | "paused" | "cancelled";

export interface Plan {
  id: PlanId;
  name: string;
  description: string;
  features: string[];
  price: number;
  currency: string;
  includes_verification: boolean;
  requires_business: boolean;
  active: boolean;
  sort: number;
}

export interface SubscriptionView {
  id: string;
  user_id: string;
  plan_id: PlanId;
  business_id: string | null;
  status: SubscriptionStatus;
  price: number;
  payer_email: string;
  mp_preapproval_id: string | null;
  init_point: string | null;
  paid_through: string | null;
  next_payment_at: string | null;
  started_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  plan: { name: string } | null;
  business: { slug: string; name: string } | null;
}

export interface VerificationRequest {
  id: string;
  user_id: string;
  document_path: string;
  selfie_path: string;
  status: "pending" | "approved" | "rejected";
  reject_reason: string | null;
  reviewed_at: string | null;
  created_at: string;
}

const num = (v: unknown) => (v === null || v === undefined ? 0 : Number(v));

export async function getPlans(supabase: SupabaseClient, { includeInactive = false } = {}): Promise<Plan[]> {
  let query = supabase.from("plans").select("*").order("sort");
  if (!includeInactive) query = query.eq("active", true);
  const { data, error } = await query;
  if (error) throw error;
  return ((data ?? []) as Plan[]).map((p) => ({ ...p, price: num(p.price) }));
}

const SUB_COLUMNS = `id, user_id, plan_id, business_id, status, price, payer_email, mp_preapproval_id, init_point, paid_through,
  next_payment_at, started_at, cancelled_at, created_at, plan:plans ( name ), business:businesses ( slug, name )`;

/** Suscripciones del usuario (las que importan: vivas o con beneficios vigentes). */
export async function getMySubscriptions(supabase: SupabaseClient, userId: string): Promise<SubscriptionView[]> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select(SUB_COLUMNS)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(30);
  if (error) throw error;
  const now = Date.now();
  return ((data ?? []) as unknown as SubscriptionView[])
    .map((s) => ({ ...s, price: num(s.price) }))
    .filter((s) => s.status !== "cancelled" || (s.paid_through && new Date(s.paid_through).getTime() > now));
}

export async function getMyPayments(supabase: SupabaseClient, userId: string) {
  const { data, error } = await supabase
    .from("subscription_payments")
    .select("id, plan_id, status, amount, paid_at, created_at, plan:plans ( name )")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(24);
  if (error) throw error;
  return ((data ?? []) as unknown as { id: string; plan_id: PlanId; status: string; amount: number; paid_at: string | null; created_at: string; plan: { name: string } | null }[]).map(
    (p) => ({ ...p, amount: num(p.amount) }),
  );
}

export async function getMyVerification(supabase: SupabaseClient, userId: string): Promise<VerificationRequest | null> {
  const { data, error } = await supabase
    .from("verification_requests")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return (data as VerificationRequest | null) ?? null;
}

/** Hasta cuándo está pago (paid_through incluye 3 días de gracia para reintentos de cobro). */
export const coveredUntil = (paidThrough: string) => new Date(new Date(paidThrough).getTime() - 3 * 24 * 60 * 60 * 1000).toISOString();

export const isEntitled = (s: Pick<SubscriptionView, "paid_through">) => Boolean(s.paid_through && new Date(s.paid_through).getTime() > Date.now());

export const SUBSCRIPTION_STATUS: Record<SubscriptionStatus, { label: string; class: string }> = {
  pending: { label: "Esperando el pago", class: "bg-warning-soft text-warning" },
  authorized: { label: "Activa", class: "bg-success-soft text-success" },
  paused: { label: "Pausada", class: "bg-warning-soft text-warning" },
  cancelled: { label: "Cancelada", class: "bg-surface-muted text-ink-muted" },
};

export const PAYMENT_STATUS: Record<string, string> = {
  approved: "Acreditado",
  pending: "Pendiente",
  in_process: "En proceso",
  rejected: "Rechazado",
  refunded: "Devuelto",
  cancelled: "Cancelado",
  charged_back: "Contracargo",
};

/**
 * Trae de Mercado Pago el estado de la suscripción y todos sus cobros, y los
 * guarda (con el cliente de la service role). Idempotente: se puede llamar
 * desde el aviso de Mercado Pago, al volver del pago o desde el cron.
 */
export async function syncSubscription(admin: SupabaseClient, sub: { id: string; mp_preapproval_id: string | null }): Promise<void> {
  if (!sub.mp_preapproval_id) return;
  const pre = await getPreapproval(sub.mp_preapproval_id);
  if (pre.external_reference !== sub.id) throw new Error("El preapproval no corresponde a esta suscripción");

  const synced = await admin.rpc("sub_sync", {
    p_subscription_id: sub.id,
    p_preapproval_id: pre.id,
    p_status: pre.status,
    p_next_payment_at: pre.next_payment_date ?? null,
  });
  if (synced.error) throw synced.error;

  const charges = await searchAuthorizedPayments(pre.id);
  for (const charge of charges) {
    if (!charge.payment?.id) continue; // cobro programado, todavía sin pago
    const payment = await getPayment(String(charge.payment.id));
    const { amount, fee, net } = paymentAmounts(payment);
    const recorded = await admin.rpc("sub_record_payment", {
      p_preapproval_id: pre.id,
      p_mp_payment_id: String(payment.id),
      p_mp_authorized_payment_id: String(charge.id),
      p_status: payment.status,
      p_amount: amount,
      p_fee: fee,
      p_net: net,
      p_paid_at: payment.date_approved ?? null,
    });
    if (recorded.error) throw recorded.error;
  }
}

// -----------------------------------------------------------------------------
// Administración: ingresos
// -----------------------------------------------------------------------------
export interface RevenueSummary {
  active_subscribers: number;
  active_subscriptions: number;
  mrr: number;
  month_gross: number;
  month_fee: number;
  month_net: number;
  month_payments: number;
  prev_gross: number;
  prev_net: number;
  month_new: number;
  month_cancelled: number;
  month_failed: number;
  pending_verifications: number;
  by_plan: { plan_id: PlanId; name: string; price: number; active: number; mrr: number; month_gross: number }[];
  monthly: { month: string; gross: number; net: number; payments: number; subscribers: number }[];
}

export async function getRevenueSummary(supabase: SupabaseClient): Promise<RevenueSummary | null> {
  const { data, error } = await supabase.rpc("admin_revenue_summary");
  if (error) {
    console.error("[ingresos]", error.message);
    return null;
  }
  return data as RevenueSummary;
}

export interface AdminSubscription extends SubscriptionView {
  user: { username: string; first_name: string | null; last_name: string | null } | null;
}

export async function getAdminSubscriptions(
  supabase: SupabaseClient,
  { status, q }: { status: "live" | "all" | "cancelled" | "pending"; q: string },
): Promise<AdminSubscription[]> {
  let query = supabase
    .from("subscriptions")
    .select(`${SUB_COLUMNS}, user:profiles!subscriptions_user_id_fkey ( username, first_name, last_name )`)
    .order("created_at", { ascending: false })
    .limit(200);
  if (status === "live") query = query.in("status", ["authorized", "paused"]);
  if (status === "cancelled") query = query.eq("status", "cancelled");
  if (status === "pending") query = query.eq("status", "pending");
  const { data, error } = await query;
  if (error) throw error;
  let rows = ((data ?? []) as unknown as AdminSubscription[]).map((s) => ({ ...s, price: num(s.price) }));
  const term = q.trim().toLowerCase();
  if (term) {
    rows = rows.filter((s) =>
      [s.user?.username, s.user?.first_name, s.user?.last_name, s.payer_email, s.business?.name].some((v) => v?.toLowerCase().includes(term)),
    );
  }
  return rows;
}

export interface AdminPayment {
  id: string;
  mp_payment_id: string;
  plan_id: PlanId;
  status: string;
  amount: number;
  fee: number;
  net: number;
  paid_at: string | null;
  created_at: string;
  user: { username: string; first_name: string | null; last_name: string | null } | null;
  plan: { name: string } | null;
}

/** Pagos de un mes ("2026-10"), del más nuevo al más viejo. */
export async function getAdminPayments(supabase: SupabaseClient, month: string): Promise<AdminPayment[]> {
  const [y, m] = month.split("-").map(Number);
  // Mes en hora de Córdoba (UTC-3).
  const from = new Date(Date.UTC(y, m - 1, 1, 3)).toISOString();
  const to = new Date(Date.UTC(y, m, 1, 3)).toISOString();
  const { data, error } = await supabase
    .from("subscription_payments")
    .select(
      `id, mp_payment_id, plan_id, status, amount, fee, net, paid_at, created_at,
       user:profiles!subscription_payments_user_id_fkey ( username, first_name, last_name ), plan:plans ( name )`,
    )
    .gte("created_at", from)
    .lt("created_at", to)
    .order("created_at", { ascending: false })
    .limit(1000);
  if (error) throw error;
  return ((data ?? []) as unknown as AdminPayment[]).map((p) => ({ ...p, amount: num(p.amount), fee: num(p.fee), net: num(p.net) }));
}

export async function getPendingVerifications(supabase: SupabaseClient) {
  const { data, error } = await supabase
    .from("verification_requests")
    .select("*, user:profiles!verification_requests_user_id_fkey ( id, username, first_name, last_name, avatar_path, created_at )")
    .eq("status", "pending")
    .order("created_at")
    .limit(50);
  if (error) throw error;
  return (data ?? []) as unknown as (VerificationRequest & {
    user: { id: string; username: string; first_name: string | null; last_name: string | null; avatar_path: string | null; created_at: string } | null;
  })[];
}
