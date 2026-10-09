import type { SupabaseClient } from "@supabase/supabase-js";

/** Sugerencias de "A quién seguir" (la base elige y ordena; acá se traen los datos). */
export interface SuggestedPerson {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  headline: string | null;
  verified_at: string | null;
  followers_count: number;
  city: { name: string } | null;
}

export interface SuggestedBusiness {
  id: string;
  slug: string;
  name: string;
  logo_path: string | null;
  verification: string;
  plan_tier: string;
  followers_count: number;
  category: { name: string } | null;
  city: { name: string } | null;
}

const ordered = <T extends { id: string }>(ids: string[], rows: T[]) => {
  const byId = new Map(rows.map((r) => [r.id, r]));
  return ids.map((id) => byId.get(id)).filter((r): r is T => Boolean(r));
};

export async function getSuggestions(supabase: SupabaseClient, limit = 5): Promise<{ people: SuggestedPerson[]; businesses: SuggestedBusiness[] }> {
  const [p, b] = await Promise.all([
    supabase.rpc("suggested_profile_ids", { p_limit: limit }),
    supabase.rpc("suggested_business_ids", { p_limit: limit }),
  ]);
  const personIds = ((p.data ?? []) as { id: string }[]).map((r) => r.id);
  const businessIds = ((b.data ?? []) as { id: string }[]).map((r) => r.id);
  const [people, businesses] = await Promise.all([
    personIds.length
      ? supabase
          .from("profiles")
          .select("id, username, first_name, last_name, avatar_path, headline, verified_at, followers_count, city:cities ( name )")
          .in("id", personIds)
      : Promise.resolve({ data: [] }),
    businessIds.length
      ? supabase
          .from("businesses")
          .select("id, slug, name, logo_path, verification, plan_tier, followers_count, category:categories ( name ), city:cities ( name )")
          .in("id", businessIds)
      : Promise.resolve({ data: [] }),
  ]);
  return {
    people: ordered(personIds, (people.data ?? []) as unknown as SuggestedPerson[]),
    businesses: ordered(businessIds, (businesses.data ?? []) as unknown as SuggestedBusiness[]),
  };
}
