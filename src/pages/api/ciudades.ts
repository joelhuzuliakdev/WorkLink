import type { APIRoute } from "astro";

/**
 * Autocompletado de ciudades: GET /api/ciudades?q=villa%20ma&provincia=14
 * Responde como máximo 10 resultados. Es información pública y cambia poco:
 * se cachea en la CDN.
 */
export const GET: APIRoute = async ({ url, locals }) => {
  const q = (url.searchParams.get("q") ?? "").trim().slice(0, 60);
  const province = Number(url.searchParams.get("provincia"));

  const { data, error } = await locals.supabase.rpc("search_cities", {
    q,
    p_province_id: Number.isInteger(province) && province > 0 ? province : null,
    max_results: 10,
  });

  if (error) {
    console.error("[api/ciudades]", error.message);
    return Response.json({ results: [] }, { status: 500 });
  }

  return Response.json(
    { results: data ?? [] },
    { headers: { "Cache-Control": "public, max-age=300, s-maxage=3600, stale-while-revalidate=86400" } },
  );
};
