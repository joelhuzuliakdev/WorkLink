import { PUBLIC_SUPABASE_URL } from "astro:env/client";

/**
 * Política de seguridad de contenido (CSP): le dice al navegador de dónde
 * puede cargar cosas cada página. Si alguien lograra meter código en una
 * página, el navegador no lo dejaría mandar datos a otro sitio ni cargar
 * scripts de afuera.
 *
 *  - Scripts y estilos: solo de WorkLink ('unsafe-inline' hace falta para los
 *    scripts chiquitos que Astro escribe dentro de la página).
 *  - Imágenes y videos: WorkLink y el almacenamiento de Supabase.
 *  - Conexiones: WorkLink y Supabase (subida de fotos, sesión).
 *  - Formularios: WorkLink, y las redirecciones a Google (ingresar) y a
 *    Mercado Pago (pagar).
 *  - Ningún sitio puede mostrar WorkLink dentro de un marco (clickjacking).
 */
export function contentSecurityPolicy(dev = false): string {
  const supabase = new URL(PUBLIC_SUPABASE_URL).origin;
  const supabaseWs = supabase.replace(/^http/, "ws");
  const formTargets = [
    "'self'",
    supabase,
    "https://accounts.google.com",
    "https://*.mercadopago.com",
    "https://*.mercadopago.com.ar",
    "https://*.mercadolibre.com",
    ...(dev ? ["http://127.0.0.1:*", "http://localhost:*"] : []),
  ];
  const directives: Record<string, string[]> = {
    "default-src": ["'self'"],
    "script-src": ["'self'", "'unsafe-inline'"],
    "style-src": ["'self'", "'unsafe-inline'"],
    "img-src": ["'self'", "data:", "blob:", supabase],
    "media-src": ["'self'", "blob:", supabase],
    "font-src": ["'self'", "data:"],
    "connect-src": ["'self'", supabase, supabaseWs, ...(dev ? ["ws:"] : [])],
    "worker-src": ["'self'", "blob:"],
    "frame-src": ["'none'"],
    "frame-ancestors": ["'none'"],
    "object-src": ["'none'"],
    "base-uri": ["'self'"],
    "form-action": formTargets,
    ...(dev ? {} : { "upgrade-insecure-requests": [] }),
  };
  return Object.entries(directives)
    .map(([key, values]) => [key, ...values].join(" "))
    .join("; ");
}
