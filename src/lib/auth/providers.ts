import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from "astro:env/client";

/**
 * ¿Está activado "Ingresar con Google" en Supabase? Se consulta la
 * configuración pública de Auth (no es secreta) y se guarda 5 minutos.
 * Así el botón no aparece hasta que se configure en Supabase.
 */
let cache: { at: number; google: boolean } | null = null;

export async function isGoogleEnabled(): Promise<boolean> {
  if (cache && Date.now() - cache.at < 5 * 60 * 1000) return cache.google;
  try {
    const res = await fetch(`${PUBLIC_SUPABASE_URL}/auth/v1/settings`, {
      headers: { apikey: PUBLIC_SUPABASE_ANON_KEY },
      signal: AbortSignal.timeout(3000),
    });
    const data = (await res.json()) as { external?: { google?: boolean } };
    cache = { at: Date.now(), google: Boolean(data.external?.google) };
  } catch {
    cache = { at: Date.now(), google: false };
  }
  return cache.google;
}
