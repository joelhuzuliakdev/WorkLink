import type { APIRoute } from "astro";

/** robots.txt: deja indexar lo público y apunta al sitemap. */
export const GET: APIRoute = ({ site, url }) => {
  const origin = (site ?? new URL(url.origin)).toString().replace(/\/$/, "");
  const body = [
    "User-agent: *",
    "Allow: /",
    "Disallow: /panel",
    "Disallow: /cuenta",
    "Disallow: /admin",
    "Disallow: /api/",
    "Disallow: /buscar",
    "Disallow: /inicio/",
    "Disallow: /salir",
    "Disallow: /*?desde=",
    "",
    `Sitemap: ${origin}/sitemap.xml`,
    "",
  ].join("\n");
  return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=3600, s-maxage=86400" } });
};
