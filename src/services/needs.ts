import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Necesidades (lo que alguien busca) y sus propuestas. Las propuestas solo las
 * ven quien las mandó y quien publicó la necesidad (RLS).
 */

export type NeedStatus = "open" | "in_review" | "awarded" | "closed" | "expired";
export type ProposalStatus = "pending" | "accepted" | "declined" | "withdrawn";

export interface NeedView {
  id: string;
  slug: string;
  title: string;
  description: string;
  author_id: string;
  category_id: number;
  subcategory_id: number | null;
  city_id: number;
  needed_by: string | null;
  budget_min: number | null;
  budget_max: number | null;
  status: NeedStatus;
  proposals_count: number;
  expires_at: string;
  created_at: string;
  author: { username: string; first_name: string | null; last_name: string | null; avatar_path: string | null; verified_at: string | null } | null;
  category: { name: string; slug: string } | null;
  subcategory: { name: string } | null;
  city: { name: string; slug: string; provinces: { name: string; slug: string } | null } | null;
}

export interface ProposalView {
  id: string;
  need_id: string;
  author_id: string;
  business_id: string | null;
  message: string;
  amount: number | null;
  availability: string | null;
  status: ProposalStatus;
  created_at: string;
  author: {
    username: string;
    first_name: string | null;
    last_name: string | null;
    avatar_path: string | null;
    verified_at: string | null;
    headline: string | null;
    rating_sum: number;
    rating_count: number;
  } | null;
  business: { slug: string; name: string; logo_path: string | null; rating_sum: number; rating_count: number } | null;
}

const NEED_COLUMNS = `id, slug, title, description, author_id, category_id, subcategory_id, city_id, needed_by,
  budget_min, budget_max, status, proposals_count, expires_at, created_at,
  author:profiles!needs_author_id_fkey ( username, first_name, last_name, avatar_path, verified_at ),
  category:categories ( name, slug ),
  subcategory:subcategories ( name ),
  city:cities ( name, slug, provinces ( name, slug ) )`;

const PROPOSAL_COLUMNS = `id, need_id, author_id, business_id, message, amount, availability, status, created_at,
  author:profiles!proposals_author_id_fkey ( username, first_name, last_name, avatar_path, verified_at, headline, rating_sum, rating_count ),
  business:businesses ( slug, name, logo_path, rating_sum, rating_count )`;

const num = (v: unknown) => (v === null || v === undefined ? null : Number(v));
const toNeed = (row: NeedView): NeedView => ({ ...row, budget_min: num(row.budget_min), budget_max: num(row.budget_max) });
const toProposal = (row: ProposalView): ProposalView => ({ ...row, amount: num(row.amount) });

export const NEEDS_PAGE = 20;
export const OPEN_STATUSES: NeedStatus[] = ["open", "in_review"];

export async function getOpenNeeds(
  supabase: SupabaseClient,
  { categoryId, cityId, page = 1 }: { categoryId?: number | null; cityId?: number | null; page?: number } = {},
): Promise<{ needs: NeedView[]; hasMore: boolean }> {
  const from = (page - 1) * NEEDS_PAGE;
  let query = supabase
    .from("needs")
    .select(NEED_COLUMNS)
    .in("status", OPEN_STATUSES)
    .is("deleted_at", null)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .range(from, from + NEEDS_PAGE);
  if (categoryId) query = query.eq("category_id", categoryId);
  if (cityId) query = query.eq("city_id", cityId);
  const { data, error } = await query;
  if (error) throw error;
  const rows = ((data ?? []) as unknown as NeedView[]).filter((n) => n.author).map(toNeed);
  return { needs: rows.slice(0, NEEDS_PAGE), hasMore: rows.length > NEEDS_PAGE };
}

/** Necesidades por id, en el mismo orden (para inicio y buscador). */
export async function getNeedsByIds(supabase: SupabaseClient, ids: string[]): Promise<NeedView[]> {
  if (!ids.length) return [];
  const { data, error } = await supabase.from("needs").select(NEED_COLUMNS).in("id", ids).is("deleted_at", null);
  if (error) throw error;
  const byId = new Map(((data ?? []) as unknown as NeedView[]).filter((n) => n.author).map((n) => [n.id, toNeed(n)]));
  return ids.map((id) => byId.get(id)).filter((n): n is NeedView => Boolean(n));
}

/** Necesidades abiertas para el inicio: primero su ciudad, gente que sigue y su rubro. */
export async function getHomeNeeds(supabase: SupabaseClient, limit = 3): Promise<NeedView[]> {
  const { data, error } = await supabase.rpc("home_need_ids", { p_limit: limit });
  if (error) {
    console.error("[necesidades]", error.message);
    return [];
  }
  return getNeedsByIds(supabase, ((data ?? []) as { id: string }[]).map((r) => r.id));
}

export async function getNeed(supabase: SupabaseClient, id: string): Promise<NeedView | null> {
  const { data, error } = await supabase.from("needs").select(NEED_COLUMNS).eq("id", id).is("deleted_at", null).maybeSingle();
  if (error) throw error;
  return data ? toNeed(data as unknown as NeedView) : null;
}

/** Propuestas que el usuario puede ver de una necesidad (todas si es el autor; la propia si no). */
export async function getProposals(supabase: SupabaseClient, needId: string): Promise<ProposalView[]> {
  const { data, error } = await supabase.from("proposals").select(PROPOSAL_COLUMNS).eq("need_id", needId).order("created_at");
  if (error) throw error;
  return ((data ?? []) as unknown as ProposalView[]).map(toProposal);
}

export async function getMyNeeds(supabase: SupabaseClient, userId: string): Promise<NeedView[]> {
  const { data, error } = await supabase
    .from("needs")
    .select(NEED_COLUMNS)
    .eq("author_id", userId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) throw error;
  return ((data ?? []) as unknown as NeedView[]).map(toNeed);
}

export async function getMyProposals(supabase: SupabaseClient, userId: string) {
  const { data, error } = await supabase
    .from("proposals")
    .select(`id, need_id, status, amount, created_at, need:needs!proposals_need_id_fkey ( id, slug, title, status, city:cities ( name ) )`)
    .eq("author_id", userId)
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) throw error;
  return (data ?? []) as unknown as {
    id: string;
    need_id: string;
    status: ProposalStatus;
    amount: number | null;
    created_at: string;
    need: { id: string; slug: string; title: string; status: NeedStatus; city: { name: string } | null } | null;
  }[];
}

export const NEED_STATUS_LABELS: Record<NeedStatus, { label: string; class: string }> = {
  open: { label: "Recibe propuestas", class: "bg-success-soft text-success" },
  in_review: { label: "Recibe propuestas", class: "bg-success-soft text-success" },
  awarded: { label: "Resuelta", class: "bg-seek-soft text-seek" },
  closed: { label: "Cerrada", class: "bg-surface-muted text-ink-muted" },
  expired: { label: "Vencida", class: "bg-warning-soft text-warning" },
};

export const PROPOSAL_STATUS_LABELS: Record<ProposalStatus, { label: string; class: string }> = {
  pending: { label: "Esperando respuesta", class: "bg-surface-muted text-ink" },
  accepted: { label: "Aceptada", class: "bg-success-soft text-success" },
  declined: { label: "No elegida", class: "bg-surface-muted text-ink-muted" },
  withdrawn: { label: "Retirada", class: "bg-surface-muted text-ink-muted" },
};

/** "$ 20.000 a $ 50.000", "Hasta $ 50.000", "Desde $ 20.000" o null. */
export function budgetLabel(min: number | null, max: number | null, format: (n: number) => string): string | null {
  if (min != null && max != null) return min === max ? format(min) : `${format(min)} a ${format(max)}`;
  if (max != null) return `Hasta ${format(max)}`;
  if (min != null) return `Desde ${format(min)}`;
  return null;
}

export const isOpen = (need: Pick<NeedView, "status" | "expires_at">) =>
  OPEN_STATUSES.includes(need.status) && new Date(need.expires_at) > new Date();
