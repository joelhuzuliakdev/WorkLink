import type { SupabaseClient } from "@supabase/supabase-js";
import { getPostsByIds, type PostView, type ProfileSituation } from "./posts";
import type { PostType } from "../schemas/post";

/**
 * Buscador y directorio: personas, emprendimientos y publicaciones con
 * filtros opcionales (texto, rubro, ciudad, situación, tipo). Las funciones de
 * la base devuelven ids ya filtrados y ordenados; acá se traen sus datos.
 */

export const SEARCH_MIN = 2;
export const SEARCH_MAX = 100;
export const SEARCH_PAGE = 20;

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
  cover_path: string | null;
  verification: string;
  followers_count: number;
  posts_count: number;
  category: { name: string; slug: string } | null;
  city: { name: string; slug: string; provinces: { name: string; slug: string } | null } | null;
}

export interface SearchFilters {
  q: string;
  categoryId: number | null;
  cityId: number | null;
  situation: ProfileSituation | null;
  type: PostType | null;
}

export interface Paged<T> {
  items: T[];
  hasMore: boolean;
}

const ids = (data: unknown) => ((data ?? []) as { id: string }[]).map((row) => row.id);

function ordered<T extends { id: string }>(order: string[], rows: T[]): T[] {
  const byId = new Map(rows.map((row) => [row.id, row]));
  return order.map((id) => byId.get(id)).filter((row): row is T => Boolean(row));
}

/** Hay algo para buscar: texto válido o algún filtro. */
export function hasCriteria(f: SearchFilters): boolean {
  return f.q.length >= SEARCH_MIN || Boolean(f.categoryId || f.cityId || f.situation || f.type);
}

export async function searchPeople(supabase: SupabaseClient, f: SearchFilters, limit = SEARCH_PAGE, offset = 0): Promise<Paged<PersonResult>> {
  // Las personas no tienen rubro: si se filtra por rubro, no se listan.
  if (f.categoryId) return { items: [], hasMore: false };
  const { data, error } = await supabase.rpc("search_profile_ids", {
    p_query: f.q || null,
    p_city_id: f.cityId,
    p_situation: f.situation,
    p_limit: limit + 1,
    p_offset: offset,
  });
  if (error) throw error;
  const list = ids(data);
  const page = list.slice(0, limit);
  if (!page.length) return { items: [], hasMore: false };
  const { data: rows, error: rowsError } = await supabase
    .from("profiles")
    .select("id, username, first_name, last_name, avatar_path, headline, situation, followers_count, city:cities ( name )")
    .in("id", page);
  if (rowsError) throw rowsError;
  return { items: ordered(page, (rows ?? []) as unknown as PersonResult[]), hasMore: list.length > limit };
}

export const BUSINESS_RESULT_COLUMNS = `id, slug, name, tagline, logo_path, cover_path, verification, followers_count, posts_count,
  category:categories ( name, slug ), city:cities ( name, slug, provinces ( name, slug ) )`;

export async function searchBusinesses(
  supabase: SupabaseClient,
  f: Pick<SearchFilters, "q" | "categoryId" | "cityId"> & { subcategoryId?: number | null; provinceId?: number | null },
  limit = SEARCH_PAGE,
  offset = 0,
): Promise<Paged<BusinessResult>> {
  const { data, error } = await supabase.rpc("search_business_ids", {
    p_query: f.q || null,
    p_category_id: f.categoryId,
    p_subcategory_id: f.subcategoryId ?? null,
    p_city_id: f.cityId,
    p_province_id: f.provinceId ?? null,
    p_limit: limit + 1,
    p_offset: offset,
  });
  if (error) throw error;
  const list = ids(data);
  const page = list.slice(0, limit);
  if (!page.length) return { items: [], hasMore: false };
  const { data: rows, error: rowsError } = await supabase.from("businesses").select(BUSINESS_RESULT_COLUMNS).in("id", page);
  if (rowsError) throw rowsError;
  return { items: ordered(page, (rows ?? []) as unknown as BusinessResult[]), hasMore: list.length > limit };
}

export async function searchPosts(supabase: SupabaseClient, f: SearchFilters, limit = SEARCH_PAGE, offset = 0): Promise<Paged<PostView>> {
  // Las publicaciones no tienen "situación" propia: ese filtro es de personas.
  if (f.situation) return { items: [], hasMore: false };
  const { data, error } = await supabase.rpc("search_post_ids", {
    p_query: f.q || null,
    p_type: f.type,
    p_category_id: f.categoryId,
    p_city_id: f.cityId,
    p_limit: limit + 1,
    p_offset: offset,
  });
  if (error) throw error;
  const list = ids(data);
  return { items: await getPostsByIds(supabase, list.slice(0, limit)), hasMore: list.length > limit };
}
