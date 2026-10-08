import { createServerClient, parseCookieHeader } from "@supabase/ssr";
import type { AstroCookies } from "astro";
import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from "astro:env/client";

/**
 * Crea un cliente de Supabase para UNA request del servidor.
 *
 * - Lee la sesión desde las cookies httpOnly de la request.
 * - Cuando Supabase renueva el token, escribe las cookies nuevas en la
 *   respuesta y guarda los headers anti-caché en `responseHeaders` para que el
 *   middleware los aplique (una respuesta con cookies de sesión nunca debe
 *   quedar en la CDN).
 *
 * Usa la clave pública: todas las consultas pasan por RLS con la identidad
 * del usuario. Nunca reutilizar un cliente entre requests.
 */
export function createSupabaseServerClient(options: {
  request: Request;
  cookies: AstroCookies;
  responseHeaders?: Headers;
}) {
  const { request, cookies, responseHeaders } = options;

  return createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return parseCookieHeader(request.headers.get("Cookie") ?? "").map(({ name, value }) => ({
          name,
          value: value ?? "",
        }));
      },
      setAll(cookiesToSet, headers) {
        for (const { name, value, options: cookieOptions } of cookiesToSet) {
          cookies.set(name, value, {
            ...cookieOptions,
            path: cookieOptions?.path ?? "/",
            httpOnly: true,
            secure: import.meta.env.PROD,
            sameSite: "lax",
          });
        }
        if (responseHeaders) {
          for (const [key, value] of Object.entries(headers ?? {})) {
            responseHeaders.set(key, value);
          }
        }
      },
    },
    auth: {
      flowType: "pkce",
    },
  });
}
