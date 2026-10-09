import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Reseñas de emprendimientos y personas. Quién puede opinar, los promedios y
 * las respuestas los controla la base (RLS + funciones); acá solo se leen.
 */

export type ReviewSubject = { type: "business"; id: string } | { type: "profile"; id: string };

/** Respuesta de la base sobre si el usuario actual puede opinar. */
export type ReviewEligibility = "hired" | "contacted" | "login" | "invalid" | "self" | "unavailable" | "blocked" | "none";

export interface ReviewView {
  id: string;
  author_id: string;
  business_id: string | null;
  profile_id: string | null;
  rating: number;
  body: string | null;
  verified: boolean;
  reply: string | null;
  reply_at: string | null;
  status: "published" | "hidden" | "removed";
  created_at: string;
  edited_at: string | null;
  author: { username: string; first_name: string | null; last_name: string | null; avatar_path: string | null; verified_at: string | null } | null;
}

export const REVIEWS_PAGE = 10;

const COLUMNS = `id, author_id, business_id, profile_id, rating, body, verified, reply, reply_at, status, created_at, edited_at,
  author:profiles!reviews_author_id_fkey ( username, first_name, last_name, avatar_path, verified_at )`;

const column = (subject: ReviewSubject) => (subject.type === "business" ? "business_id" : "profile_id");

/** Reseñas publicadas, de la más nueva a la más vieja. */
export async function getReviews(
  supabase: SupabaseClient,
  subject: ReviewSubject,
  { page = 1, limit = REVIEWS_PAGE }: { page?: number; limit?: number } = {},
): Promise<{ reviews: ReviewView[]; hasMore: boolean }> {
  const from = (page - 1) * limit;
  const { data, error } = await supabase
    .from("reviews")
    .select(COLUMNS)
    .eq(column(subject), subject.id)
    .eq("status", "published")
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .range(from, from + limit);
  if (error) throw error;
  // Si la cuenta de quien opinó fue suspendida, RLS devuelve author null: se omite.
  const rows = ((data ?? []) as unknown as ReviewView[]).filter((r) => r.author);
  return { reviews: rows.slice(0, limit), hasMore: (data?.length ?? 0) > limit };
}

/** La reseña que el usuario ya escribió (para editarla), aunque esté oculta. */
export async function getMyReview(supabase: SupabaseClient, userId: string, subject: ReviewSubject): Promise<ReviewView | null> {
  const { data, error } = await supabase.from("reviews").select(COLUMNS).eq("author_id", userId).eq(column(subject), subject.id).maybeSingle();
  if (error) throw error;
  return (data as unknown as ReviewView) ?? null;
}

export async function getEligibility(supabase: SupabaseClient, subject: ReviewSubject): Promise<ReviewEligibility> {
  const { data, error } = await supabase.rpc("review_eligibility", {
    p_business_id: subject.type === "business" ? subject.id : null,
    p_profile_id: subject.type === "profile" ? subject.id : null,
  });
  if (error) {
    console.error("[reseñas]", error.message);
    return "none";
  }
  return data as ReviewEligibility;
}

/** Lo que ve un usuario en la sección de reseñas: si puede opinar y si ya opinó. */
export async function getViewerReviewState(supabase: SupabaseClient, userId: string | undefined, subject: ReviewSubject) {
  if (!userId) return { eligibility: "login" as ReviewEligibility, mine: null };
  const [eligibility, mine] = await Promise.all([getEligibility(supabase, subject), getMyReview(supabase, userId, subject)]);
  return { eligibility, mine };
}

export const canReview = (e: ReviewEligibility) => e === "hired" || e === "contacted";

/** Promedio con un decimal (null si no hay reseñas). */
export function ratingAverage(sum: number, count: number): number | null {
  return count > 0 ? Math.round((sum / count) * 10) / 10 : null;
}

const decimal = new Intl.NumberFormat("es-AR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
export const formatRating = (value: number) => decimal.format(value);

export const reviewsLabel = (count: number) => (count === 1 ? "1 reseña" : `${count.toLocaleString("es-AR")} reseñas`);

/** Enlace para escribir (o editar) una reseña. */
export function writeReviewPath(subject: { type: "business"; slug: string } | { type: "profile"; username: string }): string {
  return subject.type === "business" ? `/resenas/escribir?emprendimiento=${subject.slug}` : `/resenas/escribir?persona=${subject.username}`;
}

export const RATING_WORDS = ["", "Muy malo", "Malo", "Regular", "Bueno", "Excelente"] as const;
