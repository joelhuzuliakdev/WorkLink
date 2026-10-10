import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Botón de arrepentimiento: plazo legal, pedidos y planes relacionados.
 * La persona tiene 10 días corridos desde que contrató (Ley 24.240 art. 34).
 */
export const WITHDRAWAL_DAYS = 10;
const DAY = 24 * 60 * 60 * 1000;

export type WithdrawalStatus = "pending" | "refunded" | "rejected" | "closed";

export const WITHDRAWAL_STATUS: Record<WithdrawalStatus, { label: string; class: string }> = {
  pending: { label: "Pendiente", class: "bg-warning-soft text-warning" },
  refunded: { label: "Devuelto", class: "bg-success-soft text-success" },
  rejected: { label: "Rechazado", class: "bg-danger-soft text-danger" },
  closed: { label: "Resuelto", class: "bg-surface-muted text-ink-muted" },
};

/** Fecha desde la que corre el plazo: el primer cobro (o la creación si todavía no se cobró). */
export const contractedAt = (sub: { started_at: string | null; created_at: string }) => sub.started_at ?? sub.created_at;

export const withdrawalDeadline = (sub: { started_at: string | null; created_at: string }) =>
  new Date(new Date(contractedAt(sub)).getTime() + WITHDRAWAL_DAYS * DAY);

export const canWithdraw = (sub: { started_at: string | null; created_at: string; status: string }, at = new Date()) =>
  sub.status !== "cancelled" && at.getTime() <= withdrawalDeadline(sub).getTime();

export interface PlanOption {
  id: string;
  label: string;
  status: string;
  started_at: string | null;
  created_at: string;
}

/** Planes de la persona con sesión que todavía puede revocar (para el formulario). */
export async function getWithdrawablePlans(supabase: SupabaseClient, userId: string): Promise<PlanOption[]> {
  const { data } = await supabase
    .from("subscriptions")
    .select("id, status, price, started_at, created_at, plan:plans ( name ), business:businesses ( name )")
    .eq("user_id", userId)
    .neq("status", "cancelled")
    .order("created_at", { ascending: false })
    .limit(10);
  return ((data ?? []) as unknown as {
    id: string;
    status: string;
    price: number;
    started_at: string | null;
    created_at: string;
    plan: { name: string } | null;
    business: { name: string } | null;
  }[])
    .filter((s) => canWithdraw(s))
    .map((s) => ({
      id: s.id,
      status: s.status,
      started_at: s.started_at,
      created_at: s.created_at,
      label: `${s.plan?.name ?? "Plan"}${s.business ? ` · ${s.business.name}` : ""}`,
    }));
}

export interface WithdrawalPayment {
  id: string;
  mp_payment_id: string;
  status: string;
  amount: number;
  paid_at: string | null;
}

export interface WithdrawalSubscription {
  id: string;
  user_id: string | null;
  status: string;
  price: number;
  payer_email: string;
  mp_preapproval_id: string | null;
  started_at: string | null;
  created_at: string;
  plan: { name: string } | null;
  payments: WithdrawalPayment[];
}

export interface WithdrawalView {
  id: string;
  code: string;
  user_id: string | null;
  subscription_id: string | null;
  full_name: string;
  email: string;
  dni: string | null;
  detail: string | null;
  status: WithdrawalStatus;
  admin_note: string | null;
  refunded_amount: number | null;
  resolved_at: string | null;
  created_at: string;
  user: { username: string; first_name: string | null; last_name: string | null } | null;
  /** Planes que pueden ser los de este pedido (el elegido, los de su cuenta o los pagados con su email). */
  candidates: WithdrawalSubscription[];
}

const SUB_COLS = `id, user_id, status, price, payer_email, mp_preapproval_id, started_at, created_at, plan:plans ( name ),
  payments:subscription_payments ( id, mp_payment_id, status, amount, paid_at )`;

/** Pedidos para la administración (la base solo los muestra a admin). */
export async function getWithdrawals(supabase: SupabaseClient, status: WithdrawalStatus | "all"): Promise<WithdrawalView[]> {
  let query = supabase
    .from("withdrawal_requests")
    .select("*, user:profiles!withdrawal_requests_user_id_fkey ( username, first_name, last_name )")
    .order("created_at", { ascending: false })
    .limit(100);
  if (status !== "all") query = query.eq("status", status);
  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as Omit<WithdrawalView, "candidates">[];

  return Promise.all(
    rows.map(async (row) => {
      const filters = [`payer_email.eq."${row.email.toLowerCase().replace(/["\\]/g, "")}"`];
      if (row.subscription_id) filters.push(`id.eq.${row.subscription_id}`);
      if (row.user_id) filters.push(`user_id.eq.${row.user_id}`);
      const { data: subs } = await supabase
        .from("subscriptions")
        .select(SUB_COLS)
        .or(filters.join(","))
        .order("created_at", { ascending: false })
        .limit(5);
      const candidates = ((subs ?? []) as unknown as WithdrawalSubscription[]).map((s) => ({
        ...s,
        price: Number(s.price),
        payments: (s.payments ?? []).map((p) => ({ ...p, amount: Number(p.amount) })),
      }));
      // El plan que eligió la persona va primero.
      candidates.sort((a, b) => Number(b.id === row.subscription_id) - Number(a.id === row.subscription_id));
      return { ...row, refunded_amount: row.refunded_amount === null ? null : Number(row.refunded_amount), candidates };
    }),
  );
}

export async function countPendingWithdrawals(supabase: SupabaseClient): Promise<number> {
  const { count } = await supabase.from("withdrawal_requests").select("id", { count: "exact", head: true }).eq("status", "pending");
  return count ?? 0;
}
