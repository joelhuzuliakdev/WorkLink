import { defineMiddleware } from "astro:middleware";
import { createSupabaseServerClient } from "../lib/supabase/server";
import { getSessionUser, hasRole } from "../lib/auth/session";
import { protectedPrefixes, routes, staffPrefixes } from "../config/site";
import { contentSecurityPolicy } from "../lib/security";

const CSP = contentSecurityPolicy(import.meta.env.DEV);

const matchesPrefix = (pathname: string, prefixes: readonly string[]) =>
  prefixes.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`));

/**
 * Middleware global:
 *  1. Crea el cliente de Supabase de la request y resuelve el usuario.
 *  2. Protege /panel, /cuenta y /admin (sesión), y /admin (rol de staff).
 *  3. Aplica headers de seguridad y evita que la CDN guarde respuestas
 *     personalizadas o con cookies de sesión.
 *
 * Las páginas prerenderizadas (estáticas) no pasan por acá en producción.
 */
export const onRequest = defineMiddleware(async (context, next) => {
  if (context.isPrerendered) {
    return next();
  }

  const authHeaders = new Headers();
  const supabase = createSupabaseServerClient({
    request: context.request,
    cookies: context.cookies,
    responseHeaders: authHeaders,
  });

  context.locals.supabase = supabase;
  context.locals.user = await getSessionUser(supabase);

  const { pathname, search } = context.url;
  const isProtected = matchesPrefix(pathname, protectedPrefixes);

  if (isProtected && !context.locals.user) {
    const next = encodeURIComponent(pathname + search);
    return context.redirect(`${routes.login}?next=${next}`);
  }

  if (matchesPrefix(pathname, staffPrefixes) && !(await hasRole(supabase, "moderator"))) {
    return new Response("No tenés permiso para ver esta página.", {
      status: 403,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  // Copia mutable: las respuestas de redirección tienen headers inmutables.
  const original = await next();
  const response = new Response(original.body, original);

  // Headers que @supabase/ssr pide cuando renovó la sesión (no cachear).
  authHeaders.forEach((value, key) => response.headers.set(key, value));

  // Lo privado o personalizado nunca se guarda en caches compartidas.
  if (isProtected || context.locals.user) {
    response.headers.set("Cache-Control", "private, no-store");
  }

  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(self), payment=()");
  response.headers.set("Cross-Origin-Opener-Policy", "same-origin");
  if ((response.headers.get("Content-Type") ?? "").includes("text/html")) {
    response.headers.set("Content-Security-Policy", CSP);
  }
  if (import.meta.env.PROD) {
    // Siempre por HTTPS (2 años), también en subdominios.
    response.headers.set("Strict-Transport-Security", "max-age=63072000; includeSubDomains");
  }

  return response;
});
