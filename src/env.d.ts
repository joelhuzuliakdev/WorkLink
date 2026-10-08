/// <reference types="astro/client" />

import type { SupabaseClient } from "@supabase/supabase-js";
import type { SessionUser } from "./lib/auth/session";
import type { ViewerProfile } from "./lib/viewer";

declare global {
  namespace App {
    interface Locals {
      /** Cliente de Supabase con la sesión de esta request (RLS aplica). */
      supabase: SupabaseClient;
      /** Usuario autenticado, o null si es un visitante. */
      user: SessionUser | null;
      /** Perfil del usuario actual (se carga una vez, al pedirlo). Usar getViewerProfile(). */
      viewerProfile?: Promise<ViewerProfile | null>;
    }
  }
}

export {};
