import type { APIRoute } from "astro";
import { mediaPresets, videoLimits, type MediaPurpose } from "../../../config/media";

/**
 * Genera URLs firmadas para subir UNA imagen (todas sus variantes) o UN video
 * (archivo + portada) a Storage.
 *
 * Por qué así: la sesión vive en cookies httpOnly que el navegador no puede
 * leer. El servidor verifica al usuario y pide a Storage un permiso de subida
 * de un solo uso por archivo; Storage valida las políticas (carpeta propia,
 * tipo y tamaño del bucket) con la identidad del usuario. El navegador sube
 * directo a Storage con ese permiso: los archivos no pasan por Vercel.
 *
 * POST { purpose: "avatar" | "logo" | "cover" | "catalog" | "post" }
 * POST { purpose: "video", ext: "mp4" | "webm" }
 * → { basePath, uploads: [{ name, url }] }
 */
export const POST: APIRoute = async ({ request, locals }) => {
  const user = locals.user;
  if (!user) return json({ error: "Tenés que ingresar para subir archivos." }, 401);

  let body: { purpose?: string; ext?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "Pedido inválido." }, 400);
  }

  let bucket: string;
  let names: string[];
  if (body.purpose === "video") {
    const allowed = Object.values(videoLimits.types) as string[];
    if (!body.ext || !allowed.includes(body.ext)) return json({ error: "Formato de video no permitido (MP4 o WebM)." }, 400);
    bucket = videoLimits.bucket;
    names = [`video.${body.ext}`, "poster.webp"];
  } else if (body.purpose && body.purpose in mediaPresets) {
    const preset = mediaPresets[body.purpose as MediaPurpose];
    bucket = preset.bucket;
    names = preset.sizes.map((size) => `${size}.webp`);
  } else {
    return json({ error: "Pedido inválido." }, 400);
  }

  const basePath = `${user.id}/${crypto.randomUUID()}`;
  const storage = locals.supabase.storage.from(bucket);

  const uploads: { name: string; url: string }[] = [];
  for (const name of names) {
    const { data, error } = await storage.createSignedUploadUrl(`${basePath}/${name}`);
    if (error || !data) {
      console.error("[uploads/sign]", error);
      return json({ error: "No pudimos preparar la subida. Probá de nuevo." }, 500);
    }
    uploads.push({ name, url: data.signedUrl });
  }

  return json({ basePath, uploads });
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
