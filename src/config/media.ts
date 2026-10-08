/**
 * Configuración de imágenes por uso. Cada imagen se guarda como una carpeta
 * `{user_id}/{uuid}` con una variante WebP por tamaño: `{size}.webp`.
 * En la base se guarda solo la carpeta (ej. avatar_path = "uuid-usuario/uuid-imagen").
 */
export type MediaPurpose = "avatar" | "logo" | "cover" | "catalog";

export interface MediaPreset {
  bucket: "avatars" | "covers" | "post-media";
  /** Anchos generados, de menor a mayor. */
  sizes: readonly number[];
  /** Relación ancho / alto del recorte. */
  aspect: number;
  /** Tamaño máximo del archivo original que elige el usuario. */
  maxInputBytes: number;
  quality: number;
}

export const mediaPresets: Record<MediaPurpose, MediaPreset> = {
  avatar: { bucket: "avatars", sizes: [96, 256, 512], aspect: 1, maxInputBytes: 15 * 1024 * 1024, quality: 0.85 },
  logo: { bucket: "avatars", sizes: [96, 256, 512], aspect: 1, maxInputBytes: 15 * 1024 * 1024, quality: 0.85 },
  cover: { bucket: "covers", sizes: [800, 1600], aspect: 3, maxInputBytes: 20 * 1024 * 1024, quality: 0.8 },
  catalog: { bucket: "post-media", sizes: [320, 800], aspect: 1, maxInputBytes: 15 * 1024 * 1024, quality: 0.82 },
};

export const acceptedImageTypes = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"];
