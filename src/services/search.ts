import type { SupabaseClient } from "@supabase/supabase-js";
import { getPostsByIds, type PostView, type ProfileSituation } from "./posts";

/**
 * Buscador básico por palabra: personas, emprendimientos y publicaciones.
 * Usa ILIKE con índices de trigramas (rápido aun con muchos datos). En la
 * Etapa 7 se suma relevancia, rubros y ciudades.
 */

export const SEARCH_MIN = 2;
export const SEARCH_MAX = 100;

export function normalizeQuery(raw: string | null | undefined): string {
  return (raw ?? "").replace(/\s+/g, " ").trim().slice(0, SEARCH_MAX);
}

export interface PersonResult {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  headline: string | null;
  situation: ProfileSituation | null;
  followers_count: number;
  city: { name: string } | null;
}

export interface BusinessResult {
  id: string;
  slug: string;
  name: string;
  tagline: string | null;
  logo_path: string | null;
  verification: string;
  followers_count: number;
  category: { name: string } | null;
  city: { name: string } | null;
}

export interface SearchResults {
  people: PersonResult[];
  businesses: BusinessResult[];
  posts: PostView[];
}

/** Escapa los comodines de LIKE para buscar el texto tal cual. */
const likePattern = (q: string) => `%${q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;

export async function search(supabase: SupabaseClient, q: string): Promise<SearchResults> {
  if (q.length < SEARCH_MIN) return { people: [], businesses: [], posts: [] };

  const [peopleIds, businesses, postIds] = await Promise.all([
    supabase.rpc("search_profile_ids", { p_query: q, p_limit: 12 }),
    supabase
      .from("businesses")
      .select("id, slug, name, tagline, logo_path, verification, followers_count, category:categories ( name ), city:cities ( name )")
      .eq("status", "active")
      .is("deleted_at", null)
      .ilike("name", likePattern(q))
      .order("followers_count", { ascending: false })
      .limit(8),
    supabase.rpc("search_post_ids", { p_query: q, p_limit: 20 }),
  ]);
  if (peopleIds.error) throw peopleIds.error;
  if (businesses.error) throw businesses.error;
  if (postIds.error) throw postIds.error;

  const ids = ((peopleIds.data ?? []) as { id: string }[]).map((row) => row.id);
  let people: PersonResult[] = [];
  if (ids.length) {
    const { data, error } = await supabase
      .from("profiles")
      .select("id, username, first_name, last_name, avatar_path, headline, situation, followers_count, city:cities ( name )")
      .in("id", ids);
    if (error) throw error;
    const byId = new Map(((data ?? []) as unknown as PersonResult[]).map((p) => [p.id, p]));
    people = ids.map((id) => byId.get(id)).filter((p): p is PersonResult => Boolean(p));
  }

  const posts = await getPostsByIds(supabase, ((postIds.data ?? []) as { id: string }[]).map((row) => row.id));
  return { people, businesses: (businesses.data ?? []) as unknown as BusinessResult[], posts };
}
