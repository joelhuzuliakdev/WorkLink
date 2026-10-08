import { ActionError, defineAction } from "astro:actions";
import type { SupabaseClient } from "@supabase/supabase-js";
import { businessSchema, deleteBusinessSchema, type BusinessInput } from "../schemas/business";
import { z } from "astro/zod";
import { dbError, requireUser } from "../lib/auth/guards";
import { isOwnMediaPath } from "../lib/media";
import { findAvailableSlug } from "../services/businesses";
import { mediaExists, removeMedia } from "../services/storage";
import { slugify } from "../utils/slug";

/** Valida que las imágenes elegidas sean del usuario y estén subidas. */
async function assertImages(supabase: SupabaseClient, userId: string, input: BusinessInput) {
  for (const [purpose, path] of [
    ["logo", input.logo_path],
    ["cover", input.cover_path],
  ] as const) {
    if (path && (!isOwnMediaPath(path, userId) || !(await mediaExists(supabase, purpose, path)))) {
      throw new ActionError({
        code: "BAD_REQUEST",
        message: purpose === "logo" ? "El logo no se subió bien. Volvé a elegirlo." : "La portada no se subió bien. Volvé a elegirla.",
      });
    }
  }
}

/** Solo subcategorías que pertenecen a la categoría elegida. */
async function validSubcategories(supabase: SupabaseClient, categoryId: number, ids: number[]): Promise<number[]> {
  if (ids.length === 0) return [];
  const { data, error } = await supabase
    .from("subcategories")
    .select("id")
    .eq("category_id", categoryId)
    .in("id", [...new Set(ids)]);
  if (error) throw dbError(error, "No pudimos validar las especialidades.");
  return (data ?? []).map((row) => row.id as number);
}

function businessColumns(input: BusinessInput) {
  return {
    name: input.name,
    tagline: input.tagline ?? null,
    description: input.description ?? null,
    category_id: input.category_id,
    city_id: input.city_id ?? null,
    province_id: null, // la completa la base a partir de la ciudad
    logo_path: input.logo_path ?? null,
    cover_path: input.cover_path ?? null,
    whatsapp: input.whatsapp ?? null,
    phone: input.phone ?? null,
    email: input.email ?? null,
    instagram: input.instagram ?? null,
    facebook: input.facebook ?? null,
    tiktok: input.tiktok ?? null,
    website: input.website ?? null,
    availability: input.availability ?? null,
    hours: input.hours ?? null,
    status: input.status,
  };
}

async function syncSubcategories(supabase: SupabaseClient, businessId: string, ids: number[]) {
  const { data: existing, error } = await supabase
    .from("business_subcategories")
    .select("subcategory_id")
    .eq("business_id", businessId);
  if (error) throw dbError(error, "No pudimos guardar las especialidades.");

  const current = new Set((existing ?? []).map((row) => row.subcategory_id as number));
  const wanted = new Set(ids);
  const toRemove = [...current].filter((id) => !wanted.has(id));
  const toAdd = [...wanted].filter((id) => !current.has(id));

  if (toRemove.length) {
    const { error: delError } = await supabase
      .from("business_subcategories")
      .delete()
      .eq("business_id", businessId)
      .in("subcategory_id", toRemove);
    if (delError) throw dbError(delError, "No pudimos guardar las especialidades.");
  }
  if (toAdd.length) {
    const { error: insError } = await supabase
      .from("business_subcategories")
      .insert(toAdd.map((subcategory_id) => ({ business_id: businessId, subcategory_id })));
    if (insError) throw dbError(insError, "No pudimos guardar las especialidades.");
  }
}

export const business = {
  create: defineAction({
    accept: "form",
    input: businessSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const supabase = locals.supabase;
      await assertImages(supabase, user.id, input);

      // Si la dirección es la autocompletada a partir del nombre, se busca una
      // libre automáticamente ("mi-negocio-2"); si la eligió la persona, se respeta.
      const autoSlug = slugify(input.name);
      let slug: string | null;
      if (input.slug && input.slug !== autoSlug) {
        const { data: free } = await supabase.rpc("is_business_slug_available", { p_slug: input.slug });
        if (!free) {
          throw new ActionError({ code: "CONFLICT", message: `La dirección /e/${input.slug} ya está en uso. Elegí otra.` });
        }
        slug = input.slug;
      } else {
        slug = await findAvailableSlug(supabase, autoSlug);
      }
      if (!slug) throw new ActionError({ code: "CONFLICT", message: "Elegí una dirección para tu emprendimiento." });

      const { data, error } = await supabase
        .from("businesses")
        .insert({ ...businessColumns(input), slug })
        .select("id")
        .single();
      if (error) throw dbError(error, "No pudimos crear el emprendimiento. Probá de nuevo.");

      await syncSubcategories(supabase, data.id, await validSubcategories(supabase, input.category_id, input.subcategory_ids));
      return { id: data.id as string };
    },
  }),

  update: defineAction({
    accept: "form",
    input: businessSchema.extend({ business_id: z.uuid() }),
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const supabase = locals.supabase;
      await assertImages(supabase, user.id, input);

      const { data: current, error: currentError } = await supabase
        .from("businesses")
        .select("slug, logo_path, cover_path, status")
        .eq("id", input.business_id)
        .is("deleted_at", null)
        .maybeSingle();
      if (currentError) throw dbError(currentError, "No pudimos cargar el emprendimiento.");
      if (!current) throw new ActionError({ code: "NOT_FOUND", message: "El emprendimiento no existe o no tenés acceso." });

      const slug = input.slug || current.slug;
      if (slug !== current.slug) {
        const { data: free } = await supabase.rpc("is_business_slug_available", { p_slug: slug });
        if (!free) throw new ActionError({ code: "CONFLICT", message: `La dirección /e/${slug} ya está en uso. Elegí otra.` });
      }

      const columns = businessColumns(input);
      // Un emprendimiento suspendido por moderación no puede cambiar su estado.
      const { status, ...rest } = columns;
      const payload = current.status === "suspended" ? rest : { ...rest, status };

      const { data: updated, error } = await supabase
        .from("businesses")
        .update({ ...payload, slug })
        .eq("id", input.business_id)
        .select("id");
      if (error) throw dbError(error, "No pudimos guardar los cambios. Probá de nuevo.");
      if (!updated?.length) throw new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para editar este emprendimiento." });

      await syncSubcategories(supabase, input.business_id, await validSubcategories(supabase, input.category_id, input.subcategory_ids));

      if (current.logo_path && current.logo_path !== input.logo_path) await removeMedia(supabase, "logo", current.logo_path);
      if (current.cover_path && current.cover_path !== input.cover_path) await removeMedia(supabase, "cover", current.cover_path);

      return { id: input.business_id, slug };
    },
  }),

  remove: defineAction({
    accept: "form",
    input: deleteBusinessSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      if (input.confirm.toUpperCase() !== "ELIMINAR") {
        throw new ActionError({ code: "BAD_REQUEST", message: "Escribí ELIMINAR para confirmar." });
      }
      const { data, error } = await locals.supabase
        .from("businesses")
        .update({ deleted_at: new Date().toISOString(), status: "inactive" })
        .eq("id", input.business_id)
        .select("id");
      if (error) throw dbError(error, "No pudimos eliminar el emprendimiento.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "Solo el titular puede eliminar el emprendimiento." });
      return { removed: true };
    },
  }),
};
