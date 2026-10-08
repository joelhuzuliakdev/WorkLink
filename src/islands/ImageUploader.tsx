/**
 * Subida de imágenes (isla Preact).
 *
 * 1. El usuario elige una foto (o la saca con la cámara en el celular).
 * 2. En el navegador se corrige la orientación, se recorta al formato pedido
 *    (cuadrado para avatar/logo, 3:1 para portada) y se generan variantes
 *    WebP livianas. Se descartan los metadatos (incluida la ubicación GPS).
 * 3. Se piden URLs firmadas a /api/uploads/sign y se sube cada variante
 *    directo a Supabase Storage.
 * 4. La carpeta resultante queda en un <input type="hidden"> del formulario,
 *    que se guarda con el resto de los datos.
 */
import { useRef, useState } from "preact/hooks";
import { acceptedImageTypes, mediaPresets, type MediaPurpose } from "../config/media";
import { decodeImage, renderVariant, requestUploadUrls, uploadToSignedUrl } from "./lib/image";

interface Props {
  /** Nombre del campo oculto del formulario. */
  name: string;
  purpose: MediaPurpose;
  label: string;
  /** Carpeta actual (si ya hay imagen). */
  initialPath?: string | null;
  /** URL de vista previa de la imagen actual. */
  initialPreview?: string | null;
  /** Clave pública de Supabase (requerida por la API de Storage). */
  supabaseAnonKey: string;
  hint?: string;
}

type Status = "idle" | "processing" | "uploading" | "done" | "error";

export default function ImageUploader(props: Props) {
  const preset = mediaPresets[props.purpose];
  const [path, setPath] = useState(props.initialPath ?? "");
  const [preview, setPreview] = useState(props.initialPreview ?? "");
  const [status, setStatus] = useState<Status>("idle");
  const [message, setMessage] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const round = props.purpose === "avatar";
  const wide = (preset.aspect ?? 1) > 1;
  const busy = status === "processing" || status === "uploading";

  async function handleFile(file: File) {
    setMessage("");
    if (!acceptedImageTypes.includes(file.type) && !/\.(jpe?g|png|webp|heic|heif)$/i.test(file.name)) {
      setStatus("error");
      setMessage("Elegí una imagen JPG, PNG o WebP.");
      return;
    }
    if (file.size > preset.maxInputBytes) {
      setStatus("error");
      setMessage(`La imagen pesa demasiado (máximo ${Math.round(preset.maxInputBytes / 1024 / 1024)} MB).`);
      return;
    }

    try {
      setStatus("processing");
      const bitmap = await decodeImage(file);
      const variants = await Promise.all(preset.sizes.map((size) => renderVariant(bitmap, size, preset.aspect, preset.quality)));
      bitmap.close?.();
      const blobs = variants.map((variant) => variant.blob);

      setStatus("uploading");
      const signed = await requestUploadUrls({ purpose: props.purpose });
      await Promise.all(
        signed.uploads.map(({ name, url }) =>
          uploadToSignedUrl(url, blobs[preset.sizes.indexOf(Number.parseInt(name, 10))], "image/webp", props.supabaseAnonKey),
        ),
      );

      setPath(signed.basePath);
      setPreview(URL.createObjectURL(blobs[blobs.length - 1]));
      setStatus("done");
      setMessage("Imagen lista. Guardá los cambios para aplicarla.");
    } catch (error) {
      setStatus("error");
      setMessage(error instanceof Error ? error.message : "No pudimos procesar la imagen.");
    } finally {
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  return (
    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-ink">{props.label}</span>
      <input type="hidden" name={props.name} value={path} />

      <div class={wide ? "flex flex-col gap-3" : "flex items-center gap-4"}>
        <div
          class={[
            "relative shrink-0 overflow-hidden border border-line bg-surface-muted",
            round ? "h-20 w-20 rounded-full" : wide ? "aspect-[3/1] w-full rounded-wl" : "h-20 w-20 rounded-wl",
          ].join(" ")}
        >
          {preview ? (
            <img src={preview} alt="" class="h-full w-full object-cover" />
          ) : (
            <span class="absolute inset-0 grid place-items-center text-xs text-ink-muted">Sin imagen</span>
          )}
          {busy && (
            <span class="absolute inset-0 grid place-items-center bg-bg/70 text-xs font-medium text-ink">
              {status === "processing" ? "Preparando…" : "Subiendo…"}
            </span>
          )}
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <label
            class={[
              "inline-flex h-9 cursor-pointer items-center rounded-wl border border-line bg-surface px-3 text-sm font-semibold text-ink hover:bg-surface-muted",
              busy ? "pointer-events-none opacity-60" : "",
            ].join(" ")}
          >
            {path ? "Cambiar imagen" : "Elegir imagen"}
            <input
              ref={inputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              class="sr-only"
              disabled={busy}
              onChange={(event) => {
                const file = (event.currentTarget as HTMLInputElement).files?.[0];
                if (file) void handleFile(file);
              }}
            />
          </label>
          {path && !busy && (
            <button
              type="button"
              class="h-9 rounded-wl px-3 text-sm font-medium text-ink-muted hover:bg-surface-muted hover:text-ink"
              onClick={() => {
                setPath("");
                setPreview("");
                setStatus("idle");
                setMessage("Se quitará al guardar los cambios.");
              }}
            >
              Quitar
            </button>
          )}
        </div>
      </div>

      {message ? (
        <p class={status === "error" ? "text-sm text-danger" : "text-xs text-ink-muted"} role={status === "error" ? "alert" : "status"}>
          {message}
        </p>
      ) : (
        props.hint && <p class="text-xs text-ink-muted">{props.hint}</p>
      )}
    </div>
  );
}
