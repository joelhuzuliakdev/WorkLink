/**
 * Fotos y video de una publicación (isla Preact).
 *
 * - Hasta 10 fotos, o un video (no se mezclan).
 * - Las fotos se procesan en el navegador (sin recorte, WebP en 3 tamaños,
 *   sin metadatos GPS) y se suben con URLs firmadas.
 * - El video se valida (formato, peso y duración) y se sube tal cual, con una
 *   imagen de portada generada en el navegador.
 * - Se pueden reordenar y quitar. La lista final viaja al servidor en un campo
 *   oculto "media" (JSON); el servidor verifica cada archivo antes de guardar.
 */
import { useRef, useState } from "preact/hooks";
import { acceptedImageTypes, mediaPresets, POST_MAX_IMAGES, videoLimits } from "../config/media";
import { decodeImage, inspectVideo, renderVariant, requestUploadUrls, uploadToSignedUrl } from "./lib/image";
import { icons } from "../config/icons";

/** Ícono de línea (los mismos dibujos que el resto del sitio). */
function MiniIcon({ d }: { d: string }) {
  return (
    <svg viewBox="0 0 24 24" class="h-5 w-5 shrink-0 fill-none stroke-current" stroke-width={2} aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" d={d} />
    </svg>
  );
}

export interface PostMediaItem {
  /** id de media si ya estaba guardado en la publicación. */
  id?: string;
  path: string;
  kind: "image" | "video";
  mime: string;
  bytes: number;
  width: number;
  height: number;
  duration?: number;
  /** URL para la vista previa (local o pública). */
  preview: string;
}

interface Props {
  name?: string;
  initial?: PostMediaItem[];
  supabaseAnonKey: string;
}

export default function PostMediaUploader({ name = "media", initial = [], supabaseAnonKey }: Props) {
  const [items, setItems] = useState<PostMediaItem[]>(initial);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const imageInput = useRef<HTMLInputElement>(null);
  const videoInput = useRef<HTMLInputElement>(null);

  const hasVideo = items.some((item) => item.kind === "video");
  const imageSlots = POST_MAX_IMAGES - items.length;
  const preset = mediaPresets.post;

  const serialized = JSON.stringify(
    items.map(({ preview: _preview, ...rest }) => rest),
  );

  async function addImages(files: FileList) {
    setError("");
    const list = [...files].slice(0, imageSlots);
    if (files.length > imageSlots) setError(`Podés subir hasta ${POST_MAX_IMAGES} fotos por publicación.`);

    for (const [index, file] of list.entries()) {
      if (!acceptedImageTypes.includes(file.type) && !/\.(jpe?g|png|webp|heic|heif)$/i.test(file.name)) {
        setError(`"${file.name}" no es una imagen JPG, PNG o WebP.`);
        continue;
      }
      if (file.size > preset.maxInputBytes) {
        setError(`"${file.name}" pesa demasiado (máximo ${Math.round(preset.maxInputBytes / 1024 / 1024)} MB).`);
        continue;
      }
      try {
        setBusy(`Preparando foto ${index + 1} de ${list.length}…`);
        const bitmap = await decodeImage(file);
        const variants: Awaited<ReturnType<typeof renderVariant>>[] = [];
        for (const size of preset.sizes) variants.push(await renderVariant(bitmap, size, null, preset.quality));
        bitmap.close?.();

        setBusy(`Subiendo foto ${index + 1} de ${list.length}…`);
        const signed = await requestUploadUrls({ purpose: "post" });
        await Promise.all(
          signed.uploads.map(({ name: fileName, url }) => {
            const variant = variants[preset.sizes.indexOf(Number.parseInt(fileName, 10))];
            return uploadToSignedUrl(url, variant.blob, "image/webp", supabaseAnonKey);
          }),
        );
        const largest = variants[variants.length - 1];
        setItems((current) => [
          ...current,
          {
            path: signed.basePath,
            kind: "image",
            mime: "image/webp",
            bytes: largest.blob.size,
            width: largest.width,
            height: largest.height,
            preview: URL.createObjectURL(variants[0].blob),
          },
        ]);
      } catch (err) {
        setError(err instanceof Error ? err.message : "No pudimos subir la foto.");
      }
    }
    setBusy("");
  }

  async function addVideo(file: File) {
    setError("");
    const ext = videoLimits.types[file.type as keyof typeof videoLimits.types];
    if (!ext) {
      setError("El video tiene que ser MP4 o WebM.");
      return;
    }
    if (file.size > videoLimits.maxBytes) {
      setError(`El video pesa demasiado (máximo ${videoLimits.maxBytes / 1024 / 1024} MB).`);
      return;
    }
    try {
      setBusy("Revisando el video…");
      const info = await inspectVideo(file, videoLimits.posterWidth);
      if (!Number.isFinite(info.duration) || info.duration > videoLimits.maxSeconds) {
        throw new Error(`El video puede durar hasta ${videoLimits.maxSeconds} segundos.`);
      }
      setBusy("Subiendo el video…");
      const signed = await requestUploadUrls({ purpose: "video", ext });
      await Promise.all(
        signed.uploads.map(({ name: fileName, url }) =>
          fileName === "poster.webp"
            ? uploadToSignedUrl(url, info.poster, "image/webp", supabaseAnonKey)
            : uploadToSignedUrl(url, file, file.type, supabaseAnonKey),
        ),
      );
      setItems([
        {
          path: signed.basePath,
          kind: "video",
          mime: file.type,
          bytes: file.size,
          width: info.width,
          height: info.height,
          duration: Math.round(info.duration * 100) / 100,
          preview: URL.createObjectURL(info.poster),
        },
      ]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "No pudimos subir el video.");
    } finally {
      setBusy("");
    }
  }

  function move(index: number, delta: number) {
    setItems((current) => {
      const next = [...current];
      const target = index + delta;
      if (target < 0 || target >= next.length) return current;
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  }

  const buttonClass =
    "inline-flex h-10 cursor-pointer items-center gap-2 rounded-wl border border-line bg-surface px-3 text-sm font-semibold text-ink hover:bg-surface-muted";

  return (
    <div class="flex flex-col gap-3">
      <input type="hidden" name={name} value={serialized} />

      {items.length > 0 && (
        <ul class="grid grid-cols-3 gap-2 sm:grid-cols-5" aria-label="Archivos de la publicación">
          {items.map((item, index) => (
            <li key={item.path} class="relative overflow-hidden rounded-wl border border-line bg-surface-muted">
              <img src={item.preview} alt="" class="aspect-square w-full object-cover" />
              {item.kind === "video" && (
                <span class="absolute left-1.5 top-1.5 rounded bg-black/70 px-1.5 py-0.5 text-xs font-semibold text-white">
                  ▶ {Math.round(item.duration ?? 0)} s
                </span>
              )}
              {index === 0 && items.length > 1 && (
                <span class="absolute left-1.5 top-1.5 rounded bg-black/70 px-1.5 py-0.5 text-xs font-semibold text-white">Portada</span>
              )}
              <div class="absolute inset-x-0 bottom-0 flex justify-between gap-1 bg-gradient-to-t from-black/70 to-transparent p-1.5">
                <span class="flex gap-1">
                  {items.length > 1 && (
                    <>
                      <button type="button" aria-label="Mover a la izquierda" disabled={index === 0} onClick={() => move(index, -1)} class="grid h-7 w-7 place-items-center rounded bg-white/90 text-sm text-black disabled:opacity-40">←</button>
                      <button type="button" aria-label="Mover a la derecha" disabled={index === items.length - 1} onClick={() => move(index, 1)} class="grid h-7 w-7 place-items-center rounded bg-white/90 text-sm text-black disabled:opacity-40">→</button>
                    </>
                  )}
                </span>
                <button
                  type="button"
                  aria-label="Quitar"
                  onClick={() => setItems((current) => current.filter((_, i) => i !== index))}
                  class="grid h-7 w-7 place-items-center rounded bg-white/90 text-sm font-bold text-danger"
                >
                  ✕
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <div class="flex flex-wrap items-center gap-2">
        {!hasVideo && imageSlots > 0 && (
          <label class={[buttonClass, busy ? "pointer-events-none opacity-60" : ""].join(" ")}>
            <MiniIcon d={icons.camera} />
            {items.length ? "Agregar fotos" : "Subir fotos"}
            <input
              ref={imageInput}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              multiple
              class="sr-only"
              disabled={Boolean(busy)}
              onChange={(event) => {
                const files = (event.currentTarget as HTMLInputElement).files;
                if (files?.length) void addImages(files).finally(() => imageInput.current && (imageInput.current.value = ""));
              }}
            />
          </label>
        )}
        {items.length === 0 && (
          <label class={[buttonClass, busy ? "pointer-events-none opacity-60" : ""].join(" ")}>
            <MiniIcon d={icons.video} />
            Subir un video
            <input
              ref={videoInput}
              type="file"
              accept="video/mp4,video/webm"
              class="sr-only"
              disabled={Boolean(busy)}
              onChange={(event) => {
                const file = (event.currentTarget as HTMLInputElement).files?.[0];
                if (file) void addVideo(file).finally(() => videoInput.current && (videoInput.current.value = ""));
              }}
            />
          </label>
        )}
        {busy && <span class="text-sm text-ink-muted" role="status">{busy}</span>}
      </div>

      {error ? (
        <p class="text-sm text-danger" role="alert">{error}</p>
      ) : (
        <p class="text-xs text-ink-muted">
          Hasta {POST_MAX_IMAGES} fotos, o un video de hasta {videoLimits.maxSeconds} segundos y {videoLimits.maxBytes / 1024 / 1024} MB (MP4).
          La primera foto es la portada.
        </p>
      )}
    </div>
  );
}
