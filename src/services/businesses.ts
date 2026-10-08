import type { SupabaseClient } from "@supabase/supabase-js";
import type { Business, CatalogItem } from "../types/domain";
import { CITY_EMBED, toCityRef } from "./locations";

const BASE_COLUMNS = `id, owner_id, slug, name, tagline, description, logo_path, cover_path, status, verification,
  instagram, facebook, tiktok, website, hours, availability, followers_count, rating_sum, rating_count,
  created_at, updated_at,
  categories ( id, name, slug, seo_noun ),
  cities ( ${CITY_EMBED} ),
  business_subcategories ( subcategories ( id, category_id, name, slug ) )`;

/** Contacto directo: solo usuarios logueados (privilegios por columna). */
const CONTACT_COLUMNS = "whatsapp, phone, email";

const CATALOG_COLUMNS = "id, name, slug, description, price, currency, price_type, cover_path, status, sort_order";

type Row = Record<string, unknown> & {
  categories: Business["category"];
  cities: Parameters<typeof toCityRef>[0];
  business_subcategories: { subcategories: Business["subcategories"][number] | null }[];
};

function toBusiness(row: Row): Business {
  const { categories, cities, business_subcategories, ...rest } = row;
  return {
    ...(rest as unknown as Business),
    category: categories ?? null,
    city: toCityRef(cities),
    subcategories: (business_subcategories ?? [])
      .map((link) => link.subcategories)
      .filter((sub): sub is NonNullable<typeof sub> => Boolean(sub))
      .sort((a, b) => a.name.localeCompare(b.name, "es")),
  };
}

/** Página pública /e/[slug]. Devuelve null si no existe o no es visible. */
export async function getBusinessBySlug(
  supabase: SupabaseClient,
  slug: string,
  { withContact }: { withContact: boolean },
): Promise<Business | null> {
  const { data, error } = await supabase
    .from("businesses")
    .select(withContact ? `${BASE_COLUMNS}, ${CONTACT_COLUMNS}` : BASE_COLUMNS)
    .eq("slug", slug.toLowerCase())
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw error;
  return data ? toBusiness(data as unknown as Row) : null;
}

/** Para editar desde el panel (el usuario tiene que ser miembro: lo garantiza RLS). */
export async function getBusinessForEdit(supabase: SupabaseClient, id: string): Promise<Business | null> {
  const { data, error } = await supabase
    .from("businesses")
    .select(`${BASE_COLUMNS}, ${CONTACT_COLUMNS}`)
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw error;
  return data ? toBusiness(data as unknown as Row) : null;
}

export interface MyBusiness {
  id: string;
  slug: string;
  name: string;
  logo_path: string | null;
  status: Business["status"];
  verification: Business["verification"];
  role: "owner" | "editor";
  category_name: string | null;
}

/** Emprendimientos donde el usuario es miembro. */
export async function getMyBusinesses(supabase: SupabaseClient, userId: string): Promise<MyBusiness[]> {
  const { data, error } = await supabase
    .from("business_members")
    .select("role, businesses!inner ( id, slug, name, logo_path, status, verification, deleted_at, categories ( name ) )")
    .eq("user_id", userId)
    .is("businesses.deleted_at", null);
  if (error) throw error;

  type LinkRow = {
    role: "owner" | "editor";
    businesses: Omit<MyBusiness, "role" | "category_name"> & { categories: { name: string } | null };
  };

  return ((data ?? []) as unknown as LinkRow[])
    .map(({ role, businesses: b }) => ({
      id: b.id,
      slug: b.slug,
      name: b.name,
      logo_path: b.logo_path,
      status: b.status,
      verification: b.verification,
      role,
      category_name: b.categories?.name ?? null,
    }))
    .sort((a, b) => a.name.localeCompare(b.name, "es"));
}

/** Emprendimientos activos de un usuario (perfil público). */
export async function getPublicBusinessesByOwner(supabase: SupabaseClient, ownerId: string) {
  const { data, error } = await supabase
    .from("businesses")
    .select("id, slug, name, tagline, logo_path, verification, categories ( name ), cities ( name )")
    .eq("owner_id", ownerId)
    .eq("status", "active")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(20);
  if (error) throw error;
  return (data ?? []) as unknown as {
    id: string;
    slug: string;
    name: string;
    tagline: string | null;
    logo_path: string | null;
    verification: Business["verification"];
    categories: { name: string } | null;
    cities: { name: string } | null;
  }[];
}

/**
 * Servicios y productos de un emprendimiento.
 * `onlyPublic`: solo los activos (página pública); si no, todos (panel).
 */
export async function getCatalog(
  supabase: SupabaseClient,
  businessId: string,
  { onlyPublic }: { onlyPublic: boolean },
): Promise<{ services: CatalogItem[]; products: CatalogItem[] }> {
  let services = supabase
    .from("services")
    .select(`${CATALOG_COLUMNS}, duration_min, service_area`)
    .eq("business_id", businessId)
    .is("deleted_at", null)
    .order("sort_order")
    .order("created_at")
    .limit(100);
  let products = supabase
    .from("products")
    .select(CATALOG_COLUMNS)
    .eq("business_id", businessId)
    .is("deleted_at", null)
    .order("sort_order")
    .order("created_at")
    .limit(100);

  if (onlyPublic) {
    services = services.eq("status", "active");
    products = products.eq("status", "active");
  }

  const [s, p] = await Promise.all([services, products]);
  if (s.error) throw s.error;
  if (p.error) throw p.error;
  return { services: (s.data ?? []) as CatalogItem[], products: (p.data ?? []) as CatalogItem[] };
}

/**
 * Elige un slug libre a partir del pedido (o del nombre): "pasteleria-ana",
 * "pasteleria-ana-2", ... Usa una función de la base que ve también
 * borradores y eliminados.
 */
export async function findAvailableSlug(supabase: SupabaseClient, base: string): Promise<string | null> {
  const clean = base.replace(/^-+|-+$/g, "").slice(0, 72) || "emprendimiento";
  const candidates = [clean.length >= 3 ? clean : `${clean}-ar`];
  for (let i = 2; i <= 6; i++) candidates.push(`${candidates[0]}-${i}`);
  for (const candidate of candidates) {
    const { data, error } = await supabase.rpc("is_business_slug_available", { p_slug: candidate });
    if (error) throw error;
    if (data === true) return candidate;
  }
  return null;
}
