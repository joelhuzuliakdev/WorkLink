import type { SupabaseClient } from "@supabase/supabase-js";
import type { CategoryRef, SubcategoryRef } from "../types/domain";

export interface CategoryTree extends CategoryRef {
  subcategories: SubcategoryRef[];
}

/**
 * Árbol de categorías activas con sus subcategorías (una sola consulta).
 * Son pocas filas y cambian poco.
 */
export async function getCategoryTree(supabase: SupabaseClient): Promise<CategoryTree[]> {
  const { data, error } = await supabase
    .from("categories")
    .select("id, name, slug, seo_noun, sort_order, subcategories ( id, category_id, name, slug, sort_order, active )")
    .eq("active", true)
    .order("sort_order")
    .order("name");

  if (error) throw error;

  return (data ?? []).map((category) => ({
    id: category.id,
    name: category.name,
    slug: category.slug,
    seo_noun: category.seo_noun,
    subcategories: ((category.subcategories ?? []) as (SubcategoryRef & { sort_order: number; active: boolean })[])
      .filter((sub) => sub.active)
      .sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "es"))
      .map(({ id, category_id, name, slug }) => ({ id, category_id, name, slug })),
  }));
}
