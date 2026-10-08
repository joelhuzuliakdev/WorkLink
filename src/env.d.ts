/// <reference types="astro/client" />

import type { SupabaseClient } from "@supabase/supabase-js";
import type { SessionUser } from "./lib/auth/session";

declare global {
  namespace App {
    interface Locals {
      /** Cliente de Supabase con la sesión de esta request (RLS aplica). */
      supabase: SupabaseClient;
      /** Usuario autenticado, o null si es un visitante. */
      user: SessionUser | null;
    }
  }
}

export {};
