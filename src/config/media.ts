/**
 * Configuración de imágenes y videos por uso. Cada imagen se guarda como una
 * carpeta `{user_id}/{uuid}` con una variante WebP por tamaño: `{size}.webp`.
 * En la base se guarda solo la carpeta (ej. avatar_path = "uuid-usuario/uuid-imagen").
 */
export type MediaPurpose = "avatar" | "logo" | "cover" | "catalog" | "post";

export interface MediaPreset {
  bucket: "avatars" | "covers" | "post-media";
  /** Anchos generados, de menor a mayor. */
  sizes: readonly number[];
  /** Relación ancho / alto del recorte; null = sin recorte (se mantiene la forma original). */
  aspect: number | null;
  /** Tamaño máximo del archivo original que elige el usuario. */
  maxInputBytes: number;
  quality: number;
}

export const mediaPresets: Record<MediaPurpose, MediaPreset> = {
  avatar: { bucket: "avatars", sizes: [96, 256, 512], aspect: 1, maxInputBytes: 15 * 1024 * 1024, quality: 0.85 },
  logo: { bucket: "avatars", sizes: [96, 256, 512], aspect: 1, maxInputBytes: 15 * 1024 * 1024, quality: 0.85 },
  cover: { bucket: "covers", sizes: [800, 1600], aspect: 3, maxInputBytes: 20 * 1024 * 1024, quality: 0.8 },
  catalog: { bucket: "post-media", sizes: [320, 800], aspect: 1, maxInputBytes: 15 * 1024 * 1024, quality: 0.82 },
  post: { bucket: "post-media", sizes: [480, 960, 1600], aspect: null, maxInputBytes: 20 * 1024 * 1024, quality: 0.8 },
};

export const acceptedImageTypes = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"];

/**
 * Video en publicaciones (v1): se sube el archivo tal cual, con límites
 * estrictos, más una imagen de portada generada en el navegador.
 * Cuando el video pese en el producto, se pasa a un proveedor con streaming.
 */
export const videoLimits = {
  bucket: "post-media" as const,
  maxBytes: 50 * 1024 * 1024,
  maxSeconds: 60,
  types: { "video/mp4": "mp4", "video/webm": "webm" } as const,
  posterWidth: 960,
};

export type VideoExt = (typeof videoLimits.types)[keyof typeof videoLimits.types];

/** Máximo de archivos por publicación. */
export const POST_MAX_IMAGES = 10;
