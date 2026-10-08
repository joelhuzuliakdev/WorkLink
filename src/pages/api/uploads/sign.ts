import type { APIRoute } from "astro";
import { mediaPresets, type MediaPurpose } from "../../../config/media";

/**
 * Genera URLs firmadas para subir UNA imagen (todas sus variantes) a Storage.
 *
 * Por qué así: la sesión vive en cookies httpOnly que el navegador no puede
 * leer. El servidor verifica al usuario y pide a Storage un permiso de subida
 * de un solo uso por archivo; Storage valida las políticas (carpeta propia,
 * tipo y tamaño del bucket) con la identidad del usuario. El navegador sube
 * directo a Storage con ese permiso: los archivos no pasan por Vercel.
 *
 * POST { purpose: "avatar" | "logo" | "cover" | "catalog" }
 * → { basePath, uploads: [{ size, url }] }
 */
export const POST: APIRoute = async ({ request, locals }) => {
  const user = locals.user;
  if (!user) return json({ error: "Tenés que ingresar para subir imágenes." }, 401);

  let purpose: MediaPurpose;
  try {
    const body = (await request.json()) as { purpose?: string };
    if (!body.purpose || !(body.purpose in mediaPresets)) throw new Error("purpose");
    purpose = body.purpose as MediaPurpose;
  } catch {
    return json({ error: "Pedido inválido." }, 400);
  }

  const preset = mediaPresets[purpose];
  const basePath = `${user.id}/${crypto.randomUUID()}`;
  const storage = locals.supabase.storage.from(preset.bucket);

  const uploads: { size: number; url: string }[] = [];
  for (const size of preset.sizes) {
    const { data, error } = await storage.createSignedUploadUrl(`${basePath}/${size}.webp`);
    if (error || !data) {
      console.error("[uploads/sign]", error);
      return json({ error: "No pudimos preparar la subida. Probá de nuevo." }, 500);
    }
    uploads.push({ size, url: data.signedUrl });
  }

  return json({ basePath, uploads });
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
