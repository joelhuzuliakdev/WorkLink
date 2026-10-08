import { ActionError, defineAction } from "astro:actions";
import type { SupabaseClient } from "@supabase/supabase-js";
import { catalogItemRefSchema, catalogStatusSchema, productSchema, serviceSchema } from "../schemas/catalog";
import { dbError, requireUser } from "../lib/auth/guards";
import { isOwnMediaPath } from "../lib/media";
import { mediaExists, removeMedia } from "../services/storage";
import { slugify } from "../utils/slug";

type Kind = "service" | "product";
const table = (kind: Kind) => (kind === "service" ? "services" : "products");

/** Slug único dentro del emprendimiento: "torta-chocolate", "torta-chocolate-2"... */
async function uniqueItemSlug(supabase: SupabaseClient, kind: Kind, businessId: string, name: string, exceptId?: string) {
  const base = slugify(name, 70) || "item";
  const { data } = await supabase.from(table(kind)).select("id, slug").eq("business_id", businessId).like("slug", `${base}%`);
  const taken = new Set((data ?? []).filter((row) => row.id !== exceptId).map((row) => row.slug as string));
  if (!taken.has(base)) return base;
  for (let i = 2; i < 500; i++) if (!taken.has(`${base}-${i}`)) return `${base}-${i}`;
  return `${base}-${crypto.randomUUID().slice(0, 6)}`;
}

async function assertCover(supabase: SupabaseClient, userId: string, path: string | null | undefined) {
  if (path && (!isOwnMediaPath(path, userId) || !(await mediaExists(supabase, "catalog", path)))) {
    throw new ActionError({ code: "BAD_REQUEST", message: "La imagen no se subió bien. Volvé a elegirla." });
  }
}

async function saveItem(
  supabase: SupabaseClient,
  userId: string,
  kind: Kind,
  input: { business_id: string; item_id?: string; name: string; cover_path?: string | null } & Record<string, unknown>,
  columns: Record<string, unknown>,
) {
  await assertCover(supabase, userId, input.cover_path);

  if (input.item_id) {
    const { data: current } = await supabase
      .from(table(kind))
      .select("cover_path, name")
      .eq("id", input.item_id)
      .eq("business_id", input.business_id)
      .maybeSingle();
    if (!current) throw new ActionError({ code: "NOT_FOUND", message: "El ítem no existe o no tenés acceso." });

    const slug = current.name === input.name ? undefined : await uniqueItemSlug(supabase, kind, input.business_id, input.name, input.item_id);
    const { data, error } = await supabase
      .from(table(kind))
      .update({ ...columns, ...(slug ? { slug } : {}) })
      .eq("id", input.item_id)
      .eq("business_id", input.business_id)
      .select("id");
    if (error) throw dbError(error, "No pudimos guardar los cambios.");
    if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para editar este ítem." });

    if (current.cover_path && current.cover_path !== input.cover_path) await removeMedia(supabase, "catalog", current.cover_path);
    return { id: input.item_id };
  }

  const slug = await uniqueItemSlug(supabase, kind, input.business_id, input.name);
  const { data, error } = await supabase
    .from(table(kind))
    .insert({ ...columns, business_id: input.business_id, slug })
    .select("id")
    .single();
  if (error) throw dbError(error, "No pudimos guardar. Probá de nuevo.");
  return { id: data.id as string };
}

export const catalog = {
  saveService: defineAction({
    accept: "form",
    input: serviceSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      return saveItem(locals.supabase, user.id, "service", input, {
        name: input.name,
        description: input.description ?? null,
        price: input.price_type === "ask" ? null : (input.price ?? null),
        price_type: input.price_type,
        duration_min: input.duration_min ?? null,
        service_area: input.service_area ?? null,
        cover_path: input.cover_path ?? null,
      });
    },
  }),

  saveProduct: defineAction({
    accept: "form",
    input: productSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      return saveItem(locals.supabase, user.id, "product", input, {
        name: input.name,
        description: input.description ?? null,
        price: input.price_type === "ask" ? null : (input.price ?? null),
        price_type: input.price_type,
        cover_path: input.cover_path ?? null,
      });
    },
  }),

  setStatus: defineAction({
    accept: "form",
    input: catalogStatusSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from(table(input.kind))
        .update({ status: input.status })
        .eq("id", input.item_id)
        .eq("business_id", input.business_id)
        .select("id");
      if (error) throw dbError(error, "No pudimos cambiar la visibilidad.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para editar este ítem." });
      return { id: input.item_id };
    },
  }),

  remove: defineAction({
    accept: "form",
    input: catalogItemRefSchema,
    handler: async (input, { locals }) => {
      requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from(table(input.kind))
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", input.item_id)
        .eq("business_id", input.business_id)
        .is("deleted_at", null)
        .select("id, cover_path");
      if (error) throw dbError(error, "No pudimos eliminar el ítem.");
      if (!data?.length) throw new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para eliminar este ítem." });
      await removeMedia(locals.supabase, "catalog", data[0].cover_path as string | null);
      return { removed: true };
    },
  }),
};
