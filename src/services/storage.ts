import type { SupabaseClient } from "@supabase/supabase-js";
import { mediaPresets, type MediaPurpose } from "../config/media";
import { mediaFiles } from "../lib/media";

/**
 * Borra de Storage todas las variantes de una imagen que ya no se usa.
 * Se ejecuta con la sesión del usuario: las políticas solo le permiten borrar
 * de su propia carpeta. Un error acá no debe cortar el guardado (el archivo
 * huérfano lo limpia el cron de mantenimiento).
 */
export async function removeMedia(supabase: SupabaseClient, purpose: MediaPurpose, basePath: string | null | undefined) {
  if (!basePath) return;
  const { error } = await supabase.storage.from(mediaPresets[purpose].bucket).remove(mediaFiles(purpose, basePath));
  if (error) console.warn("[storage] no se pudo borrar", basePath, error.message);
}

/** ¿Existe la variante principal de la imagen? (evita guardar rutas inventadas) */
export async function mediaExists(supabase: SupabaseClient, purpose: MediaPurpose, basePath: string): Promise<boolean> {
  const preset = mediaPresets[purpose];
  const { data, error } = await supabase.storage.from(preset.bucket).list(basePath, { limit: 10 });
  if (error) return false;
  const names = new Set((data ?? []).map((file) => file.name));
  return preset.sizes.every((size) => names.has(`${size}.webp`));
}
