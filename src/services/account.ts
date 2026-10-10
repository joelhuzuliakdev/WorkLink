import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from "astro:env/client";
import { cancelPreapproval, isMercadoPagoConfigured } from "../lib/mercadopago";

/**
 * Configuración de la cuenta: datos de acceso, bloqueos y borrado.
 * Lo que es de cada persona se lee con SU sesión (RLS). El borrado de la
 * cuenta es lo único que necesita el cliente de servicio, y solo se usa con
 * el id de la sesión verificada (nunca con un id que mande el navegador).
 */

export interface AccountInfo {
  email: string | null;
  has_password: boolean;
  pending_email: string | null;
  providers: string[];
  created_at: string;
}

export async function getAccountInfo(supabase: SupabaseClient): Promise<AccountInfo | null> {
  const { data, error } = await supabase.rpc("my_account_info");
  if (error) {
    console.error("[account] info", error.code, error.message);
    return null;
  }
  return data as AccountInfo | null;
}

export interface BlockedPerson {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  blocked_at: string;
}

export async function getBlockedPeople(supabase: SupabaseClient, userId: string): Promise<BlockedPerson[]> {
  const { data, error } = await supabase
    .from("user_blocks")
    .select("created_at, person:profiles!user_blocks_blocked_id_fkey ( id, username, first_name, last_name, avatar_path )")
    .eq("blocker_id", userId)
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) {
    console.error("[account] bloqueados", error.code, error.message);
    return [];
  }
  return (data ?? []).flatMap((row) => {
    const person = row.person as unknown as Omit<BlockedPerson, "blocked_at"> | null;
    return person ? [{ ...person, blocked_at: row.created_at }] : [];
  });
}

export async function isBlockedByMe(supabase: SupabaseClient, userId: string | undefined, profileId: string): Promise<boolean> {
  if (!userId || userId === profileId) return false;
  const { count } = await supabase
    .from("user_blocks")
    .select("blocked_id", { count: "exact", head: true })
    .eq("blocker_id", userId)
    .eq("blocked_id", profileId);
  return (count ?? 0) > 0;
}

/**
 * Comprueba la contraseña actual sin tocar la sesión del navegador: usa un
 * cliente aparte, sin cookies, y cierra enseguida la sesión que abre.
 */
export async function checkPassword(email: string, password: string): Promise<boolean> {
  const probe = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data, error } = await probe.auth.signInWithPassword({ email, password });
  if (error || !data.session) return false;
  await probe.auth.signOut({ scope: "local" });
  return true;
}

/** Motivo por el que no se puede borrar la cuenta todavía (o null si se puede). */
export async function deletionBlocker(admin: SupabaseClient, userId: string): Promise<string | null> {
  const { data: role } = await admin.from("user_roles").select("role").eq("user_id", userId).maybeSingle();
  if (role?.role === "super_admin") {
    const { count } = await admin.from("user_roles").select("user_id", { count: "exact", head: true }).eq("role", "super_admin");
    if ((count ?? 0) <= 1) {
      return "Sos la única persona con el rol principal de administración. Antes de borrar tu cuenta, dale ese rol a otra persona del equipo.";
    }
  }
  return null;
}

/**
 * Cancela en Mercado Pago los planes que se siguen cobrando, para que no se
 * le cobre nada más a una cuenta borrada. Si no se puede cancelar alguno,
 * corta (es mejor no borrar la cuenta que dejar un cobro vivo).
 */
export async function cancelLivePlans(admin: SupabaseClient, userId: string): Promise<void> {
  const { data: subs, error } = await admin
    .from("subscriptions")
    .select("id, mp_preapproval_id, status")
    .eq("user_id", userId)
    .in("status", ["pending", "authorized", "paused"]);
  if (error) throw new Error(error.message);

  for (const sub of subs ?? []) {
    if (sub.mp_preapproval_id) {
      if (!isMercadoPagoConfigured()) throw new Error("Mercado Pago no está configurado");
      await cancelPreapproval(sub.mp_preapproval_id);
    }
    const done = await admin.rpc("sub_sync", {
      p_subscription_id: sub.id,
      p_preapproval_id: sub.mp_preapproval_id,
      p_status: "cancelled",
      p_next_payment_at: null,
    });
    if (done.error) console.warn("[account] sub_sync", done.error.message);
  }
}

const BUCKETS = ["avatars", "covers", "post-media", "verification"] as const;

/**
 * Borra todos los archivos de la persona (fotos, portadas, publicaciones,
 * DNI y selfie). Todos viven en la carpeta `{user_id}/` de cada bucket.
 * Un error acá no frena el borrado de la cuenta: se registra y sigue.
 */
export async function removeUserFiles(admin: SupabaseClient, userId: string): Promise<number> {
  let removed = 0;
  for (const bucket of BUCKETS) {
    const storage = admin.storage.from(bucket);
    for (let round = 0; round < 20; round++) {
      const { data: entries, error } = await storage.list(userId, { limit: 100 });
      if (error || !entries?.length) break;
      const paths: string[] = [];
      for (const entry of entries) {
        if (entry.id) {
          paths.push(`${userId}/${entry.name}`);
          continue;
        }
        // Carpeta de una imagen o video: `{user_id}/{uuid}/{archivo}`.
        const { data: files } = await storage.list(`${userId}/${entry.name}`, { limit: 100 });
        for (const file of files ?? []) paths.push(`${userId}/${entry.name}/${file.name}`);
      }
      if (!paths.length) break;
      const { error: removeError } = await storage.remove(paths);
      if (removeError) {
        console.warn("[account] no se pudieron borrar archivos", bucket, removeError.message);
        break;
      }
      removed += paths.length;
    }
  }
  return removed;
}
