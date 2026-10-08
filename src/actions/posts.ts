import { ActionError, defineAction } from "astro:actions";
import type { SupabaseClient } from "@supabase/supabase-js";
import { postRefSchema, postSchema, postStatusSchema, postUpdateSchema, type PostInput, type PostMediaInput } from "../schemas/post";
import { dbError, requireUser } from "../lib/auth/guards";
import { isOwnMediaPath } from "../lib/media";
import { mediaPresets, videoLimits } from "../config/media";

/** Verifica en Storage que los archivos nuevos existan y sean del usuario. */
async function assertUploaded(supabase: SupabaseClient, userId: string, item: PostMediaInput) {
  if (!isOwnMediaPath(item.path, userId)) {
    throw new ActionError({ code: "FORBIDDEN", message: "Hay archivos que no son tuyos." });
  }
  const { data, error } = await supabase.storage.from("post-media").list(item.path, { limit: 10 });
  const files = new Map((data ?? []).map((file) => [file.name, file]));
  const expected =
    item.kind === "image"
      ? mediaPresets.post.sizes.map((size) => `${size}.webp`)
      : [`video.${videoLimits.types[item.mime as keyof typeof videoLimits.types]}`, "poster.webp"];
  if (error || !expected.every((name) => files.has(name))) {
    throw new ActionError({ code: "BAD_REQUEST", message: "Un archivo no terminó de subirse. Quitalo y volvé a subirlo." });
  }
}

/**
 * Registra los archivos nuevos en la tabla media y devuelve la lista final de
 * ids en orden (los ya guardados conservan su id).
 */
async function resolveMediaIds(supabase: SupabaseClient, userId: string, items: PostMediaInput[]): Promise<string[]> {
  const fresh = items.filter((item) => !item.id);
  for (const item of fresh) await assertUploaded(supabase, userId, item);

  let inserted: { id: string; path: string }[] = [];
  if (fresh.length) {
    const { data, error } = await supabase
      .from("media")
      .insert(
        fresh.map((item) => ({
          bucket: "post-media",
          path: item.path,
          kind: item.kind,
          mime: item.mime,
          bytes: item.bytes,
          width: item.width,
          height: item.height,
          duration_s: item.kind === "video" ? item.duration : null,
          poster_path: item.kind === "video" ? `${item.path}/poster.webp` : null,
          variants:
            item.kind === "image"
              ? { sizes: mediaPresets.post.sizes }
              : { file: `video.${videoLimits.types[item.mime as keyof typeof videoLimits.types]}` },
        })),
      )
      .select("id, path");
    if (error) throw dbError(error, "No pudimos guardar los archivos.");
    inserted = data ?? [];
  }

  const byPath = new Map(inserted.map((row) => [row.path, row.id]));
  return items.map((item) => item.id ?? byPath.get(item.path)!).filter(Boolean);
}

async function defaultsFromBusiness(supabase: SupabaseClient, businessId: string | undefined) {
  if (!businessId) return null;
  const { data } = await supabase.from("businesses").select("category_id, city_id").eq("id", businessId).maybeSingle();
  return data;
}

function postColumns(input: PostInput, defaults: { category_id: number | null; city_id: number | null } | null) {
  return {
    business_id: input.business_id ?? null,
    type: input.type,
    title: input.title ?? null,
    body: input.body,
    price: input.price ?? null,
    category_id: input.category_id ?? (input.subcategory_id ? null : (defaults?.category_id ?? null)),
    subcategory_id: input.subcategory_id ?? null,
    city_id: input.city_id ?? defaults?.city_id ?? null,
    province_id: null, // la completa la base a partir de la ciudad
    tags: input.tags,
    status: input.status,
  };
}

export const posts = {
  create: defineAction({
    accept: "form",
    input: postSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const supabase = locals.supabase;

      const mediaIds = await resolveMediaIds(supabase, user.id, input.media);
      const defaults = await defaultsFromBusiness(supabase, input.business_id);

      const { data, error } = await supabase.from("posts").insert(postColumns(input, defaults)).select("id").single();
      if (error) throw dbError(error, "No pudimos publicar. Probá de nuevo.");

      if (mediaIds.length) {
        const { error: mediaError } = await supabase.rpc("set_post_media", { p_post_id: data.id, p_media_ids: mediaIds });
        if (mediaError) {
          await supabase.from("posts").update({ deleted_at: new Date().toISOString() }).eq("id", data.id);
          throw dbError(mediaError, "No pudimos adjuntar los archivos. Probá de nuevo.");
        }
      }
      return { id: data.id as string };
    },
  }),

  update: defineAction({
    accept: "form",
    input: postUpdateSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const supabase = locals.supabase;

      const { data: current } = await supabase
        .from("posts")
        .select("id, business_id")
        .eq("id", input.post_id)
        .is("deleted_at", null)
        .maybeSingle();
      if (!current) throw new ActionError({ code: "NOT_FOUND", message: "La publicación no existe o no tenés acceso." });

      const mediaIds = await resolveMediaIds(supabase, user.id, input.media);
      const defaults = await defaultsFromBusiness(supabase, current.business_id ?? undefined);
      // El emprendimiento de una publicación no se cambia al editar.
      const { business_id: _ignored, ...columns } = postColumns({ ...input, business_id: current.business_id ?? undefined }, defaults);

      const { data, error } = await supabase.from("posts").update(columns).eq("id", input.post_id).select("id");
      if (error) throw dbError(error, "No pudimos guardar los cambios.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para editar esta publicación." });

      const { error: mediaError } = await supabase.rpc("set_post_media", { p_post_id: input.post_id, p_media_ids: mediaIds });
      if (mediaError) throw dbError(mediaError, "No pudimos actualizar los archivos.");

      return { id: input.post_id };
    },
  }),

  setStatus: defineAction({
    accept: "form",
    input: postStatusSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from("posts")
        .update({ status: input.status })
        .eq("id", input.post_id)
        .is("deleted_at", null)
        .select("id");
      if (error) throw dbError(error, "No pudimos cambiar la visibilidad.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para editar esta publicación." });
      return { id: input.post_id };
    },
  }),

  remove: defineAction({
    accept: "form",
    input: postRefSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from("posts")
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", input.post_id)
        .is("deleted_at", null)
        .select("id");
      if (error) throw dbError(error, "No pudimos eliminar la publicación.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para eliminar esta publicación." });
      return { removed: true };
    },
  }),
};
