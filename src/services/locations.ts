import type { SupabaseClient } from "@supabase/supabase-js";
import type { CityRef } from "../types/domain";

/** Columnas para embeber una ciudad con su provincia en otras consultas. */
export const CITY_EMBED = "id, name, slug, provinces ( name, slug )";

interface CityRow {
  id: number;
  name: string;
  slug: string;
  provinces: { name: string; slug: string } | null;
}

export function toCityRef(row: CityRow | null | undefined): CityRef | null {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    slug: row.slug,
    province_name: row.provinces?.name ?? "",
    province_slug: row.provinces?.slug ?? "",
  };
}

export async function getCity(supabase: SupabaseClient, id: number): Promise<CityRef | null> {
  const { data } = await supabase.from("cities").select(CITY_EMBED).eq("id", id).maybeSingle();
  return toCityRef(data as CityRow | null);
}
