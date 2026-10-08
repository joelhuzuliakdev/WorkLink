import { createClient } from "@supabase/supabase-js";
import { PUBLIC_SUPABASE_URL } from "astro:env/client";
import { getSecret } from "astro:env/server";

/**
 * Cliente con la service role key: SALTEA todas las políticas RLS.
 * Solo para tareas del sistema (cron, webhooks). Nunca usarlo para responder
 * pedidos de usuarios ni importarlo desde código que llegue al navegador.
 */
export function createSupabaseAdminClient() {
  const key = getSecret("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) throw new Error("Falta la variable SUPABASE_SERVICE_ROLE_KEY en el servidor.");
  return createClient(PUBLIC_SUPABASE_URL, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
