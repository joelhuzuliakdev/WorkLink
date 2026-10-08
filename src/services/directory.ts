import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Directorio por rubro y ciudad (páginas /rubros/...). Decide también si una
 * página se indexa en buscadores: solo si tiene contenido suficiente, para no
 * llenar Google de páginas vacías (umbrales editables en settings, seo.*).
 */

export interface DirectoryCategory {
  id: number;
  name: string;
  slug: string;
  seo_noun: string | null;
  description: string | null;
  businesses: number;
}

export interface CategoryCity {
  city_id: number;
  city_name: string;
  city_slug: string;
  province_id: number;
  province_name: string;
  province_slug: string;
  businesses: number;
}

export interface SeoThresholds {
  minBusinesses: number;
  minBusinessesAlt: number;
  minRecentPosts: number;
}

const DEFAULT_THRESHOLDS: SeoThresholds = { minBusinesses: 5, minBusinessesAlt: 3, minRecentPosts: 10 };

export async function getSeoThresholds(supabase: SupabaseClient): Promise<SeoThresholds> {
  const { data } = await supabase.from("settings").select("key, value").like("key", "seo.%");
  const get = (key: string, fallback: number) => {
    const raw = data?.find((row) => row.key === key)?.value;
    const n = Number(raw);
    return Number.isFinite(n) && n > 0 ? n : fallback;
  };
  return {
    minBusinesses: get("seo.landing_min_businesses", DEFAULT_THRESHOLDS.minBusinesses),
    minBusinessesAlt: get("seo.landing_min_businesses_alt", DEFAULT_THRESHOLDS.minBusinessesAlt),
    minRecentPosts: get("seo.landing_min_recent_posts", DEFAULT_THRESHOLDS.minRecentPosts),
  };
}

/** ¿La página rubro + ciudad tiene contenido suficiente para indexarse? */
export function isIndexableLanding(t: SeoThresholds, businesses: number, recentPosts: number): boolean {
  return businesses >= t.minBusinesses || (businesses >= t.minBusinessesAlt && recentPosts >= t.minRecentPosts);
}

export async function getDirectoryCategories(supabase: SupabaseClient): Promise<DirectoryCategory[]> {
  const { data, error } = await supabase.rpc("directory_categories");
  if (error) throw error;
  return ((data ?? []) as DirectoryCategory[]).map((c) => ({ ...c, businesses: Number(c.businesses) }));
}

export async function getCategoryCities(supabase: SupabaseClient, categoryId: number, limit = 40): Promise<CategoryCity[]> {
  const { data, error } = await supabase.rpc("directory_category_cities", { p_category_id: categoryId, p_limit: limit });
  if (error) throw error;
  return ((data ?? []) as CategoryCity[]).map((c) => ({ ...c, businesses: Number(c.businesses) }));
}

export async function getCityCategories(supabase: SupabaseClient, cityId: number) {
  const { data, error } = await supabase.rpc("directory_city_categories", { p_city_id: cityId });
  if (error) throw error;
  return ((data ?? []) as { id: number; name: string; slug: string; businesses: number }[]).map((c) => ({ ...c, businesses: Number(c.businesses) }));
}

export interface CategoryDetail {
  id: number;
  name: string;
  slug: string;
  seo_noun: string | null;
  description: string | null;
  subcategories: { id: number; name: string; slug: string }[];
}

export async function getCategoryBySlug(supabase: SupabaseClient, slug: string): Promise<CategoryDetail | null> {
  const { data, error } = await supabase
    .from("categories")
    .select("id, name, slug, seo_noun, description, subcategories ( id, name, slug, sort_order, active )")
    .eq("slug", slug)
    .eq("active", true)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  type SubRow = { id: number; name: string; slug: string; sort_order: number; active: boolean };
  const row = data as unknown as Omit<CategoryDetail, "subcategories"> & { subcategories: SubRow[] };
  return {
    ...row,
    subcategories: (row.subcategories ?? [])
      .filter((s) => s.active)
      .sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "es"))
      .map(({ id, name, slug }) => ({ id, name, slug })),
  };
}

export interface CityDetail {
  id: number;
  name: string;
  slug: string;
  province: { id: number; name: string; slug: string };
}

export async function getCityBySlugs(supabase: SupabaseClient, provinceSlug: string, citySlug: string): Promise<CityDetail | null> {
  const { data, error } = await supabase
    .from("cities")
    .select("id, name, slug, province:provinces!inner ( id, name, slug )")
    .eq("slug", citySlug)
    .eq("province.slug", provinceSlug)
    .maybeSingle();
  if (error) throw error;
  return (data as unknown as CityDetail | null) ?? null;
}

/** Cantidad de emprendimientos activos de un rubro (y opcionalmente una ciudad). */
export async function countBusinesses(supabase: SupabaseClient, categoryId: number, cityId?: number | null): Promise<number> {
  let query = supabase
    .from("businesses")
    .select("id", { count: "exact", head: true })
    .eq("category_id", categoryId)
    .eq("status", "active")
    .is("deleted_at", null);
  if (cityId) query = query.eq("city_id", cityId);
  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

/** Publicaciones de los últimos 90 días de un rubro en una ciudad. */
export async function countRecentPosts(supabase: SupabaseClient, categoryId: number, cityId: number): Promise<number> {
  const since = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .from("posts")
    .select("id", { count: "exact", head: true })
    .eq("category_id", categoryId)
    .eq("city_id", cityId)
    .eq("status", "published")
    .is("deleted_at", null)
    .gte("published_at", since);
  if (error) throw error;
  return count ?? 0;
}

/** "Fotógrafos" a partir de seo_noun ("fotógrafos") o del nombre del rubro. */
export function categoryNoun(category: { name: string; seo_noun: string | null }): string {
  const noun = category.seo_noun?.trim() || category.name;
  return noun.charAt(0).toLocaleUpperCase("es-AR") + noun.slice(1);
}

export const directoryPath = {
  index: "/rubros",
  category: (slug: string) => `/rubros/${slug}`,
  landing: (categorySlug: string, provinceSlug: string, citySlug: string) => `/rubros/${categorySlug}/${provinceSlug}/${citySlug}`,
};
