/**
 * Procesamiento de imágenes en el navegador (compartido por las islas).
 * Corrige la orientación EXIF, recorta (opcional), escala y exporta WebP.
 * Al dibujar en un canvas se descartan todos los metadatos (incluido GPS).
 */

export async function decodeImage(file: File | Blob): Promise<ImageBitmap> {
  return createImageBitmap(file, { imageOrientation: "from-image" } as ImageBitmapOptions);
}

/**
 * Genera una variante WebP de `width` píxeles de ancho como máximo (nunca agranda).
 * `aspect` = ancho/alto para recortar al centro; null = mantiene la forma original.
 */
export async function renderVariant(
  source: CanvasImageSource & { width: number; height: number },
  width: number,
  aspect: number | null,
  quality: number,
): Promise<{ blob: Blob; width: number; height: number }> {
  let sw = source.width;
  let sh = source.height;
  if (aspect) {
    const srcAspect = source.width / source.height;
    if (srcAspect > aspect) sw = Math.round(source.height * aspect);
    else sh = Math.round(source.width / aspect);
  }
  const sx = Math.round((source.width - sw) / 2);
  const sy = Math.round((source.height - sh) / 2);

  const targetWidth = Math.min(width, sw);
  const targetHeight = Math.round(targetWidth * (sh / sw));

  const canvas = document.createElement("canvas");
  canvas.width = targetWidth;
  canvas.height = targetHeight;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Tu navegador no permite procesar imágenes.");
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(source, sx, sy, sw, sh, 0, 0, targetWidth, targetHeight);

  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/webp", quality));
  if (!blob || blob.type !== "image/webp") {
    throw new Error("Tu navegador no puede generar imágenes WebP. Probá con Chrome, Edge, Firefox o Safari actualizado.");
  }
  return { blob, width: targetWidth, height: targetHeight };
}

/** Sube un archivo a una URL firmada de Supabase Storage. */
export async function uploadToSignedUrl(url: string, body: Blob, contentType: string, anonKey: string): Promise<void> {
  const res = await fetch(url, {
    method: "PUT",
    headers: {
      "Content-Type": contentType,
      "cache-control": "max-age=31536000",
      "x-upsert": "false",
      apikey: anonKey,
    },
    body,
  });
  if (!res.ok) throw new Error("La subida falló. Revisá tu conexión y probá de nuevo.");
}

/** Pide URLs firmadas al servidor para subir una imagen o un video. */
export async function requestUploadUrls(body: { purpose: string; ext?: string }) {
  const res = await fetch("/api/uploads/sign", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = (await res.json()) as {
    basePath?: string;
    uploads?: { name: string; url: string }[];
    error?: string;
  };
  if (!res.ok || !json.basePath || !json.uploads) throw new Error(json.error ?? "No pudimos preparar la subida.");
  return { basePath: json.basePath, uploads: json.uploads };
}

/** Lee duración y dimensiones de un video, y genera su imagen de portada. */
export async function inspectVideo(file: File, posterWidth: number): Promise<{
  duration: number;
  width: number;
  height: number;
  poster: Blob;
}> {
  const url = URL.createObjectURL(file);
  try {
    const video = document.createElement("video");
    video.preload = "metadata";
    video.muted = true;
    video.playsInline = true;
    video.src = url;
    await new Promise<void>((resolve, reject) => {
      video.onloadedmetadata = () => resolve();
      video.onerror = () => reject(new Error("No pudimos leer el video. Probá con un MP4."));
    });
    const duration = video.duration;
    // Un fotograma un poco después del inicio (evita pantallas negras).
    video.currentTime = Math.min(1, duration / 3);
    await new Promise<void>((resolve, reject) => {
      video.onseeked = () => resolve();
      video.onerror = () => reject(new Error("No pudimos leer el video."));
    });
    const width = video.videoWidth;
    const height = video.videoHeight;
    const { blob } = await renderVariant(
      Object.assign(video, { width, height }) as unknown as CanvasImageSource & { width: number; height: number },
      posterWidth,
      null,
      0.8,
    );
    return { duration, width, height, poster: blob };
  } finally {
    URL.revokeObjectURL(url);
  }
}
