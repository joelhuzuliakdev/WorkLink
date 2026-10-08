import type { APIRoute } from "astro";
import { getSecret } from "astro:env/server";
import { createSupabaseAdminClient } from "../../../lib/supabase/admin";

/**
 * Limpieza diaria de archivos sin usar (la ejecuta Vercel Cron, ver vercel.json).
 *
 * Borra de Storage y de la tabla media los archivos de publicaciones que:
 *  - se subieron pero nunca se publicaron (pending) hace más de 24 h, o
 *  - quedaron desvinculados (orphan) hace más de 24 h (editados o eliminados).
 *
 * Vercel envía "Authorization: Bearer <CRON_SECRET>": sin ese secreto, 401.
 * Procesa en lotes para no exceder el tiempo de una función.
 */
const BATCH = 200;

export const GET: APIRoute = async ({ request }) => {
  const secret = getSecret("CRON_SECRET");
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response("No autorizado", { status: 401 });
  }

  const supabase = createSupabaseAdminClient();
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const { data: rows, error } = await supabase
    .from("media")
    .select("id, bucket, path")
    .in("status", ["pending", "orphan"])
    .lt("created_at", cutoff)
    .order("created_at")
    .limit(BATCH);
  if (error) {
    console.error("[cron/limpiar-archivos]", error.message);
    return Response.json({ ok: false }, { status: 500 });
  }

  let removedFiles = 0;
  const removedRows: string[] = [];
  for (const row of rows ?? []) {
    const { data: files } = await supabase.storage.from(row.bucket).list(row.path, { limit: 20 });
    const paths = (files ?? []).map((file) => `${row.path}/${file.name}`);
    if (paths.length) {
      const { error: removeError } = await supabase.storage.from(row.bucket).remove(paths);
      if (removeError) {
        console.warn("[cron/limpiar-archivos] no se pudo borrar", row.path, removeError.message);
        continue;
      }
      removedFiles += paths.length;
    }
    removedRows.push(row.id);
  }

  if (removedRows.length) {
    const { error: deleteError } = await supabase.from("media").delete().in("id", removedRows);
    if (deleteError) console.error("[cron/limpiar-archivos]", deleteError.message);
  }

  return Response.json({ ok: true, media: removedRows.length, files: removedFiles, more: (rows?.length ?? 0) === BATCH });
};
