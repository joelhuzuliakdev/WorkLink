import type { AstroGlobal } from "astro";

/** Páginas de plata y documentos: solo administración (la base también lo exige). */
export async function requireAdmin(Astro: AstroGlobal): Promise<Response | null> {
  const { data } = await Astro.locals.supabase.rpc("has_role", { min_role: "admin" });
  if (data === true) return null;
  return new Response("Solo administración puede ver esta página.", {
    status: 403,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
