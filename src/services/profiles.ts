import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "../types/domain";
import { CITY_EMBED, toCityRef } from "./locations";

const PUBLIC_COLUMNS = `id, username, first_name, last_name, bio, avatar_path, situation, headline, intent,
  instagram, facebook, tiktok, website, followers_count, following_count, created_at, cities ( ${CITY_EMBED} )`;

/** Columnas de contacto directo: solo para usuarios logueados (RLS por columnas). */
const CONTACT_COLUMNS = "whatsapp, phone";

type ProfileRow = Omit<Profile, "city"> & { cities: Parameters<typeof toCityRef>[0] };

function toProfile(row: ProfileRow): Profile {
  const { cities, ...rest } = row;
  return { ...rest, city: toCityRef(cities) };
}

/** Perfil propio para editar (incluye contacto). */
export async function getOwnProfile(supabase: SupabaseClient, userId: string): Promise<Profile | null> {
  const { data, error } = await supabase
    .from("profiles")
    .select(`${PUBLIC_COLUMNS}, ${CONTACT_COLUMNS}`)
    .eq("id", userId)
    .maybeSingle();
  if (error) throw error;
  return data ? toProfile(data as unknown as ProfileRow) : null;
}

/** Perfil público por username. El contacto solo se pide si hay sesión. */
export async function getPublicProfile(
  supabase: SupabaseClient,
  username: string,
  { withContact }: { withContact: boolean },
): Promise<Profile | null> {
  const { data, error } = await supabase
    .from("profiles")
    .select(withContact ? `${PUBLIC_COLUMNS}, ${CONTACT_COLUMNS}` : PUBLIC_COLUMNS)
    .eq("username", username.toLowerCase())
    .eq("status", "active")
    .maybeSingle();
  if (error) throw error;
  return data ? toProfile(data as unknown as ProfileRow) : null;
}

export function displayName(profile: Pick<Profile, "first_name" | "last_name" | "username">): string {
  const full = [profile.first_name, profile.last_name].filter(Boolean).join(" ").trim();
  return full || `@${profile.username}`;
}

/** Porcentaje de perfil completo, para motivar a completarlo. */
export function profileCompleteness(profile: Profile): { percent: number; missing: string[] } {
  const checks: [boolean, string][] = [
    [Boolean(profile.avatar_path), "foto"],
    [Boolean(profile.bio), "descripción"],
    [Boolean(profile.city), "ciudad"],
    [Boolean(profile.whatsapp || profile.phone), "un teléfono"],
  ];
  const done = checks.filter(([ok]) => ok).length + 1; // nombre ya está
  return {
    percent: Math.round((done / (checks.length + 1)) * 100),
    missing: checks.filter(([ok]) => !ok).map(([, label]) => label),
  };
}
