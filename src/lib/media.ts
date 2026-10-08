import { PUBLIC_SUPABASE_URL } from "astro:env/client";
import { mediaPresets, type MediaPurpose } from "../config/media";

/**
 * Único lugar que arma URLs de imágenes. Si mañana se usa un CDN de imágenes
 * o las transformaciones de Supabase, se cambia solo esta función.
 */
export function mediaUrl(purpose: MediaPurpose, basePath: string | null | undefined, width?: number): string | null {
  if (!basePath) return null;
  const preset = mediaPresets[purpose];
  const size = width
    ? (preset.sizes.find((s) => s >= width) ?? preset.sizes[preset.sizes.length - 1])
    : preset.sizes[preset.sizes.length - 1];
  return `${PUBLIC_SUPABASE_URL}/storage/v1/object/public/${preset.bucket}/${basePath}/${size}.webp`;
}

/** srcset con todas las variantes, para <img srcset sizes>. */
export function mediaSrcSet(purpose: MediaPurpose, basePath: string | null | undefined): string | undefined {
  if (!basePath) return undefined;
  const preset = mediaPresets[purpose];
  return preset.sizes
    .map((size) => `${PUBLIC_SUPABASE_URL}/storage/v1/object/public/${preset.bucket}/${basePath}/${size}.webp ${size}w`)
    .join(", ");
}

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const basePathPattern = new RegExp(`^(${UUID})/(${UUID})$`);

/**
 * ¿La carpeta de imagen tiene el formato correcto y pertenece al usuario?
 * Evita que alguien guarde en su perfil la imagen de otra persona.
 */
export function isOwnMediaPath(basePath: string, userId: string): boolean {
  const match = basePathPattern.exec(basePath);
  return Boolean(match && match[1] === userId);
}

/** Rutas de todos los archivos de una imagen (para borrarla de Storage). */
export function mediaFiles(purpose: MediaPurpose, basePath: string): string[] {
  return mediaPresets[purpose].sizes.map((size) => `${basePath}/${size}.webp`);
}

/** URL pública de un archivo cualquiera de post-media (video o portada). */
export function postFileUrl(basePath: string, fileName: string): string {
  return `${PUBLIC_SUPABASE_URL}/storage/v1/object/public/post-media/${basePath}/${fileName}`;
}
