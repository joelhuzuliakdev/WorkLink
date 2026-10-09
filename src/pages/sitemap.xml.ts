import type { APIRoute } from "astro";
import { directoryPath, getDirectoryCategories, getSeoThresholds } from "../services/directory";
import { needPath, postPath } from "../lib/urls";

/**
 * Mapa del sitio para buscadores: páginas públicas indexables.
 *  - inicio, publicaciones y directorio de rubros
 *  - rubros con suficientes emprendimientos y pares rubro + ciudad
 *  - emprendimientos activos, publicaciones públicas recientes y necesidades abiertas
 * Se genera en cada pedido y la CDN lo guarda una hora. Máximo 50.000 URLs
 * (límite del protocolo); cuando se acerque, se divide en un índice.
 */
const MAX_POSTS = 10000;
const MAX_BUSINESSES = 30000;
const MAX_NEEDS = 5000;

const escape = (value: string) => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export const GET: APIRoute = async ({ locals, site, url }) => {
  const { supabase } = locals;
  const origin = site ?? new URL(url.origin);
  const abs = (path: string) => new URL(path, origin).toString();

  const thresholds = await getSeoThresholds(supabase);
  const [categories, pairs, businesses, posts, needs] = await Promise.all([
    getDirectoryCategories(supabase),
    supabase.rpc("directory_landing_pairs", { p_min: thresholds.minBusinesses }),
    supabase
      .from("businesses")
      .select("slug, updated_at")
      .eq("status", "active")
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(MAX_BUSINESSES),
    supabase
      .from("posts")
      .select("id, title, body, updated_at")
      .eq("status", "published")
      .is("deleted_at", null)
      .order("published_at", { ascending: false })
      .limit(MAX_POSTS),
    supabase
      .from("needs")
      .select("id, slug, updated_at")
      .in("status", ["open", "in_review"])
      .is("deleted_at", null)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(MAX_NEEDS),
  ]);

  const entries: { loc: string; lastmod?: string }[] = [
    { loc: abs("/") },
    { loc: abs("/publicaciones") },
    { loc: abs("/necesidades") },
    { loc: abs("/como-funciona") },
    { loc: abs("/planes") },
    { loc: abs(directoryPath.index) },
    ...categories.filter((c) => c.businesses >= thresholds.minBusinessesAlt).map((c) => ({ loc: abs(directoryPath.category(c.slug)) })),
    ...((pairs.data ?? []) as { category_slug: string; province_slug: string; city_slug: string; last_updated: string }[]).map((p) => ({
      loc: abs(directoryPath.landing(p.category_slug, p.province_slug, p.city_slug)),
      lastmod: p.last_updated,
    })),
    ...((businesses.data ?? []) as { slug: string; updated_at: string }[]).map((b) => ({ loc: abs(`/e/${b.slug}`), lastmod: b.updated_at })),
    ...((posts.data ?? []) as { id: string; title: string | null; body: string; updated_at: string }[]).map((p) => ({
      loc: abs(postPath(p)),
      lastmod: p.updated_at,
    })),
    ...((needs.data ?? []) as { id: string; slug: string; updated_at: string }[]).map((n) => ({ loc: abs(needPath(n)), lastmod: n.updated_at })),
  ];

  const xml = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...entries.map(
      (e) => `  <url><loc>${escape(e.loc)}</loc>${e.lastmod ? `<lastmod>${new Date(e.lastmod).toISOString()}</lastmod>` : ""}</url>`,
    ),
    "</urlset>",
    "",
  ].join("\n");

  return new Response(xml, {
    headers: {
      "Content-Type": "application/xml; charset=utf-8",
      "Cache-Control": "public, max-age=0, s-maxage=3600, stale-while-revalidate=86400",
    },
  });
};
