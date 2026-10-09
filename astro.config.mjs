// @ts-check
import { defineConfig, envField } from "astro/config";
import { loadEnv } from "vite";
import tailwindcss from "@tailwindcss/vite";
import vercel from "@astrojs/vercel";
import preact from "@astrojs/preact";

// Lee .env también al cargar la configuración (Vercel inyecta las variables).
const { PUBLIC_SITE_URL } = loadEnv(process.env.NODE_ENV ?? "development", process.cwd(), "");

// https://docs.astro.build/en/reference/configuration-reference/
export default defineConfig({
  // URL pública del sitio: canonical, sitemap y links de emails.
  site: PUBLIC_SITE_URL || "http://localhost:4321",

  // Todas las rutas se renderizan en el servidor salvo las que declaren
  // `export const prerender = true` (páginas estáticas).
  output: "server",

  adapter: vercel({
    // Analíticas de rendimiento (Core Web Vitals) del panel de Vercel.
    webAnalytics: { enabled: false },
  }),

  integrations: [preact()],

  vite: {
    plugins: [tailwindcss()],
  },

  // Variables de entorno tipadas y validadas al arrancar (astro:env).
  env: {
    schema: {
      PUBLIC_SUPABASE_URL: envField.string({ context: "client", access: "public", url: true }),
      PUBLIC_SUPABASE_ANON_KEY: envField.string({ context: "client", access: "public" }),
      PUBLIC_SITE_URL: envField.string({
        context: "client",
        access: "public",
        url: true,
        default: "http://localhost:4321",
      }),
      // Solo servidor. Opcional hasta que se use (webhooks, cron, admin).
      SUPABASE_SERVICE_ROLE_KEY: envField.string({ context: "server", access: "secret", optional: true }),
      // Secreto que Vercel Cron envía para autorizar las tareas programadas.
      CRON_SECRET: envField.string({ context: "server", access: "secret", optional: true }),
      // Mercado Pago (suscripciones). Access token de producción (APP_USR-...)
      // o de prueba (TEST-...). Nunca con prefijo PUBLIC_.
      MP_ACCESS_TOKEN: envField.string({ context: "server", access: "secret", optional: true }),
      // Clave secreta de los avisos (webhooks) de Mercado Pago, para validar la firma.
      MP_WEBHOOK_SECRET: envField.string({ context: "server", access: "secret", optional: true }),
      // Solo para pruebas locales: dirección de la API (por defecto la oficial).
      MP_API_URL: envField.string({ context: "server", access: "secret", optional: true }),
    },
    validateSecrets: true,
  },

  security: {
    // Rechaza envíos de formularios desde otros dominios (CSRF).
    checkOrigin: true,
  },

  prefetch: {
    prefetchAll: false,
    defaultStrategy: "hover",
  },
});
