#!/usr/bin/env bash
# =============================================================================
# WorkLink · instalador de la Etapa 6 (me gusta, comentarios, guardados y seguir)
# =============================================================================
# Uso, en Git Bash, desde la carpeta raíz del proyecto (donde está package.json):
#     bash instalar-etapa6.sh
#
# Crea o reemplaza los archivos de src/ y public/, astro.config.mjs, vercel.json
# y .env.example, y agrega la migración 0012. NO toca tu .env, node_modules ni
# las migraciones anteriores.
# =============================================================================
set -euo pipefail

if [ ! -f package.json ] || [ ! -d src ] || [ ! -d supabase/migrations ]; then
  echo "ERROR: ejecutá este script desde la carpeta raíz de WorkLink (donde está package.json)."
  exit 1
fi

escribir() {
  mkdir -p "$(dirname "$1")"
  cat > "$1"
  echo "  ✓ $1"
}

echo ""
echo "Instalando archivos de la Etapa 6..."

escribir 'public/brand/logo.svg' << '__WORKLINK_FIN_DEL_ARCHIVO__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 168 32" width="168" height="32" role="img" aria-label="WorkLink">
  <title>WorkLink</title>
  <g fill="none" stroke-width="3.6" stroke-linecap="round">
    <circle cx="20" cy="16" r="7" stroke="#e8572e"/>
    <circle cx="12" cy="16" r="7" stroke="#2f4fd8"/>
    <path d="M18.19 9.24 A7 7 0 0 0 13.42 13.61" stroke="#e8572e" stroke-linecap="butt"/>
  </g>
  <text x="36" y="23" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif" font-size="21" font-weight="700" letter-spacing="-0.5" fill="#14161f">Work<tspan fill="#2f4fd8">Link</tspan></text>
</svg>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'public/brand/mark.svg' << '__WORKLINK_FIN_DEL_ARCHIVO__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32" role="img" aria-label="WorkLink">
  <title>WorkLink</title>
  <g fill="none" stroke-width="3.6" stroke-linecap="round">
    <circle cx="20" cy="16" r="7" stroke="#e8572e"/>
    <circle cx="12" cy="16" r="7" stroke="#2f4fd8"/>
    <path d="M18.19 9.24 A7 7 0 0 0 13.42 13.61" stroke="#e8572e" stroke-linecap="butt"/>
  </g>
</svg>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'public/favicon.svg' << '__WORKLINK_FIN_DEL_ARCHIVO__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32" role="img" aria-label="WorkLink">
  <title>WorkLink</title>
  <g fill="none" stroke-width="3.6" stroke-linecap="round">
    <circle cx="20" cy="16" r="7" stroke="#e8572e"/>
    <circle cx="12" cy="16" r="7" stroke="#2f4fd8"/>
    <path d="M18.19 9.24 A7 7 0 0 0 13.42 13.61" stroke="#e8572e" stroke-linecap="butt"/>
  </g>
</svg>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/actions/auth.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { ActionError, defineAction } from "astro:actions";
import { PUBLIC_SITE_URL } from "astro:env/client";
import { forgotPasswordSchema, resetPasswordSchema, signInSchema, signUpSchema } from "../schemas/auth";
import { toActionError } from "../lib/auth/errors";
import { routes, safeNextPath } from "../config/site";

/** URL absoluta para los links de los emails de Supabase. */
const confirmUrl = (next: string) =>
  new URL(`${routes.authConfirm}?next=${encodeURIComponent(next)}`, PUBLIC_SITE_URL).toString();

/**
 * Acciones de autenticación. Se ejecutan SIEMPRE en el servidor, validan con
 * Zod y usan el cliente de Supabase de la request (locals.supabase), que
 * escribe la sesión en cookies httpOnly.
 */
export const auth = {
  signUp: defineAction({
    accept: "form",
    input: signUpSchema,
    handler: async (input, { locals }) => {
      const { data, error } = await locals.supabase.auth.signUp({
        email: input.email,
        password: input.password,
        options: {
          // Metadata leída por el trigger handle_new_user para crear el perfil.
          data: {
            first_name: input.first_name,
            last_name: input.last_name,
            intent: input.intent,
          },
          emailRedirectTo: confirmUrl(routes.dashboard),
        },
      });

      if (error) throw toActionError(error, "No pudimos crear tu cuenta. Probá de nuevo.");

      // Con confirmación de email activada no hay sesión hasta confirmar.
      // Si el email ya existía, Supabase responde igual (no se revela).
      return { needsConfirmation: !data.session, email: input.email };
    },
  }),

  signIn: defineAction({
    accept: "form",
    input: signInSchema,
    handler: async (input, { locals }) => {
      const { error } = await locals.supabase.auth.signInWithPassword({
        email: input.email,
        password: input.password,
      });

      if (error) throw toActionError(error);

      return { redirectTo: safeNextPath(input.next, routes.dashboard) };
    },
  }),

  signOut: defineAction({
    accept: "form",
    handler: async (_input, { locals }) => {
      // scope "local": cierra solo este dispositivo.
      const { error } = await locals.supabase.auth.signOut({ scope: "local" });
      if (error) throw toActionError(error);
      return { redirectTo: routes.home };
    },
  }),

  requestPasswordReset: defineAction({
    accept: "form",
    input: forgotPasswordSchema,
    handler: async (input, { locals }) => {
      const { error } = await locals.supabase.auth.resetPasswordForEmail(input.email, {
        redirectTo: confirmUrl(routes.resetPassword),
      });

      // Ante errores de límite avisamos; ante cualquier otro, respondemos
      // igual que si hubiera funcionado para no revelar qué emails existen.
      if (error && error.code?.startsWith("over_")) throw toActionError(error);
      if (error) console.error("[auth] reset", error.code, error.message);

      return { sent: true };
    },
  }),

  updatePassword: defineAction({
    accept: "form",
    input: resetPasswordSchema,
    handler: async (input, { locals }) => {
      if (!locals.user) {
        throw new ActionError({
          code: "UNAUTHORIZED",
          message: "El enlace venció. Pedí uno nuevo para cambiar tu contraseña.",
        });
      }

      const { error } = await locals.supabase.auth.updateUser({ password: input.password });
      if (error) throw toActionError(error, "No pudimos cambiar tu contraseña. Probá de nuevo.");

      return { redirectTo: routes.dashboard };
    },
  }),
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/actions/business.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/actions/catalog.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/actions/index.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { auth } from "./auth";
import { profile } from "./profile";
import { business } from "./business";
import { catalog } from "./catalog";
import { posts } from "./posts";
import { social } from "./social";

/**
 * Registro central de Astro Actions. Cada dominio agrega su grupo:
 *   actions.auth.signIn, actions.profile.update, actions.business.create...
 */
export const server = {
  auth,
  profile,
  business,
  catalog,
  posts,
  social,
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/actions/posts.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/actions/profile.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { ActionError, defineAction } from "astro:actions";
import { profileSchema } from "../schemas/profile";
import { dbError, requireUser } from "../lib/auth/guards";
import { isOwnMediaPath } from "../lib/media";
import { mediaExists, removeMedia } from "../services/storage";

export const profile = {
  update: defineAction({
    accept: "form",
    input: profileSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const supabase = locals.supabase;

      if (input.avatar_path) {
        if (!isOwnMediaPath(input.avatar_path, user.id) || !(await mediaExists(supabase, "avatar", input.avatar_path))) {
          throw new ActionError({ code: "BAD_REQUEST", message: "La foto no se subió correctamente. Volvé a elegirla." });
        }
      }

      const { data: current } = await supabase.from("profiles").select("avatar_path").eq("id", user.id).single();

      const { error } = await supabase
        .from("profiles")
        .update({
          username: input.username,
          first_name: input.first_name,
          last_name: input.last_name,
          bio: input.bio ?? null,
          city_id: input.city_id ?? null,
          // La provincia la completa la base a partir de la ciudad.
          province_id: null,
          avatar_path: input.avatar_path ?? null,
          whatsapp: input.whatsapp ?? null,
          phone: input.phone ?? null,
          instagram: input.instagram ?? null,
          facebook: input.facebook ?? null,
          tiktok: input.tiktok ?? null,
          website: input.website ?? null,
        })
        .eq("id", user.id);

      if (error) {
        if (error.code === "23505") {
          throw new ActionError({ code: "CONFLICT", message: `El usuario @${input.username} ya está en uso. Elegí otro.` });
        }
        throw dbError(error, "No pudimos guardar tu perfil. Probá de nuevo.");
      }

      if (current?.avatar_path && current.avatar_path !== input.avatar_path) {
        await removeMedia(supabase, "avatar", current.avatar_path);
      }

      return { saved: true };
    },
  }),
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/actions/social.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { ActionError, defineAction } from "astro:actions";
import type { SupabaseClient } from "@supabase/supabase-js";
import { commentRefSchema, commentSchema, followSchema, reactionSchema } from "../schemas/social";
import { dbError, requireUser } from "../lib/auth/guards";

/**
 * Interacción social. Me gusta, guardar y seguir reciben el estado deseado
 * (active: true/false) en vez de "alternar": si el pedido se repite por una
 * red lenta o un doble toque, el resultado es el mismo.
 *
 * Los permisos (publicación visible, bloqueos, cuenta activa) y los
 * contadores los resuelve la base con RLS y triggers.
 */

const isDuplicate = (error: { code?: string }) => error.code === "23505";

async function setRow(
  supabase: SupabaseClient,
  table: string,
  row: Record<string, string>,
  active: boolean,
  messages: { forbidden: string; fallback: string },
) {
  if (active) {
    const { error } = await supabase.from(table).insert(row);
    if (error && !isDuplicate(error)) {
      if (error.code === "42501") throw new ActionError({ code: "FORBIDDEN", message: messages.forbidden });
      throw dbError(error, messages.fallback);
    }
  } else {
    let query = supabase.from(table).delete();
    for (const [column, value] of Object.entries(row)) query = query.eq(column, value);
    const { error } = await query;
    if (error) throw dbError(error, messages.fallback);
  }
}

async function postCounters(supabase: SupabaseClient, postId: string) {
  const { data } = await supabase.from("posts").select("likes_count, saves_count").eq("id", postId).maybeSingle();
  return data ?? { likes_count: 0, saves_count: 0 };
}

export const social = {
  like: defineAction({
    input: reactionSchema,
    handler: async ({ post_id, active }, context) => {
      const user = requireUser(context.locals.user);
      await setRow(context.locals.supabase, "post_likes", { post_id, user_id: user.id }, active, {
        forbidden: "No podés reaccionar a esta publicación.",
        fallback: "No pudimos guardar tu me gusta.",
      });
      const counters = await postCounters(context.locals.supabase, post_id);
      return { active, count: counters.likes_count };
    },
  }),

  save: defineAction({
    input: reactionSchema,
    handler: async ({ post_id, active }, context) => {
      const user = requireUser(context.locals.user);
      await setRow(context.locals.supabase, "post_saves", { post_id, user_id: user.id }, active, {
        forbidden: "No podés guardar esta publicación.",
        fallback: "No pudimos guardar la publicación.",
      });
      const counters = await postCounters(context.locals.supabase, post_id);
      return { active, count: counters.saves_count };
    },
  }),

  follow: defineAction({
    input: followSchema,
    handler: async ({ kind, id, active }, context) => {
      const user = requireUser(context.locals.user);
      const { supabase } = context.locals;
      if (kind === "profile" && id === user.id) {
        throw new ActionError({ code: "BAD_REQUEST", message: "No podés seguirte a vos." });
      }

      const table = kind === "profile" ? "profile_follows" : "business_follows";
      const row: Record<string, string> =
        kind === "profile" ? { follower_id: user.id, followed_id: id } : { follower_id: user.id, business_id: id };
      await setRow(supabase, table, row, active, {
        forbidden: "No podés seguir a esta cuenta.",
        fallback: "No pudimos actualizar a quién seguís.",
      });

      const { data } = await supabase
        .from(kind === "profile" ? "profiles" : "businesses")
        .select("followers_count")
        .eq("id", id)
        .maybeSingle();
      return { active, count: (data?.followers_count as number | undefined) ?? 0 };
    },
  }),

  comment: defineAction({
    accept: "form",
    input: commentSchema,
    handler: async ({ post_id, body }, context) => {
      const user = requireUser(context.locals.user);
      const { data, error } = await context.locals.supabase
        .from("post_comments")
        .insert({ post_id, author_id: user.id, body })
        .select("id")
        .single();
      if (error) {
        if (error.code === "42501") {
          throw new ActionError({ code: "FORBIDDEN", message: "No podés comentar en esta publicación." });
        }
        throw dbError(error, "No pudimos publicar tu comentario.");
      }
      return { id: data.id as string };
    },
  }),

  removeComment: defineAction({
    accept: "form",
    input: commentRefSchema,
    handler: async ({ comment_id }, context) => {
      requireUser(context.locals.user);
      const { data, error } = await context.locals.supabase
        .from("post_comments")
        .delete()
        .eq("id", comment_id)
        .select("id");
      if (error) throw dbError(error, "No pudimos borrar el comentario.");
      if (!data?.length) {
        throw new ActionError({ code: "FORBIDDEN", message: "No podés borrar este comentario." });
      }
      return { ok: true };
    },
  }),
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/brand/Logo.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Logo provisional de WorkLink en SVG inline: usa las variables de color de
 * la marca, así se adapta solo al modo oscuro. Para cambiar el logo, editá
 * este archivo y /public/brand/*.svg.
 */
import { brand } from "../../config/brand";

interface Props {
  /** "full" = símbolo + nombre; "mark" = solo el símbolo. */
  variant?: "full" | "mark";
  class?: string;
}

const { variant = "full", class: className = "" } = Astro.props;
---

<span class:list={["inline-flex items-center gap-2", className]}>
  <svg viewBox="0 0 32 32" class="h-8 w-8 shrink-0" aria-hidden="true" focusable="false">
    <g fill="none" stroke-width="3.6" stroke-linecap="round">
      <circle cx="20" cy="16" r="7" stroke="var(--wl-offer)"></circle>
      <circle cx="12" cy="16" r="7" stroke="var(--wl-seek)"></circle>
      <path d="M18.19 9.24 A7 7 0 0 0 13.42 13.61" stroke="var(--wl-offer)" stroke-linecap="butt"></path>
    </g>
  </svg>
  {
    variant === "full" ? (
      <span class="font-display text-xl font-bold tracking-tight text-ink">
        Work<span class="text-brand">Link</span>
      </span>
    ) : (
      <span class="sr-only">{brand.name}</span>
    )
  }
</span>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/business/BusinessForm.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Formulario de emprendimiento (crear y editar). Funciona sin JavaScript;
 * un script pequeño agrega dos comodidades: dirección automática a partir del
 * nombre y mostrar solo las especialidades de la categoría elegida.
 */
import Field from "../ui/Field.astro";
import TextArea from "../ui/TextArea.astro";
import SelectField from "../ui/SelectField.astro";
import Button from "../ui/Button.astro";
import HoursEditor from "./HoursEditor.astro";
import ImageUploader from "../../islands/ImageUploader.tsx";
import CityPicker from "../../islands/CityPicker.tsx";
import { PUBLIC_SUPABASE_ANON_KEY } from "astro:env/client";
import type { Business } from "../../types/domain";
import type { CategoryTree } from "../../services/categories";
import type { BusinessHours } from "../../schemas/business";
import { mediaUrl } from "../../lib/media";
import type { CityRef } from "../../types/domain";

interface Props {
  action: string;
  business?: Business | null;
  categories: CategoryTree[];
  /** Datos enviados si hubo un error (para no perder lo escrito). */
  submitted?: FormData | null;
  fieldErrors?: Record<string, string[] | undefined>;
  submitLabel: string;
  /** Ciudad a mostrar (la enviada si hubo error, o la guardada). */
  city?: CityRef | null;
}

const { action, business = null, categories, submitted = null, fieldErrors = {}, submitLabel, city = business?.city ?? null } = Astro.props;

const v = (name: string, fallback: unknown = ""): string => {
  if (submitted) return String(submitted.get(name) ?? "");
  return fallback === null || fallback === undefined ? "" : String(fallback);
};

const categoryId = Number(v("category_id", business?.category?.id ?? "")) || null;
const selectedSubs = new Set(
  (submitted ? submitted.getAll("subcategory_ids") : (business?.subcategories ?? []).map((s) => s.id)).map(Number),
);
const err = (name: string) => fieldErrors[name]?.[0];

const host = (Astro.site ?? Astro.url).host;
const status = v("status", business?.status ?? "active");
const isSuspended = business?.status === "suspended";

// Horarios: los enviados (si hubo error) o los guardados.
let hours: BusinessHours | null = business?.hours ?? null;
if (submitted) {
  hours = {};
  for (const day of ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const) {
    if (!submitted.get(`hours.${day}.open`)) continue;
    const ranges: [string, string][] = [];
    for (const n of [1, 2]) {
      const from = String(submitted.get(`hours.${day}.from${n}`) ?? "");
      const to = String(submitted.get(`hours.${day}.to${n}`) ?? "");
      if (from || to) ranges.push([from, to]);
    }
    hours[day] = ranges.length ? ranges : [["", ""]];
  }
}

const instagramValue = v("instagram", business?.instagram ? `@${business.instagram}` : "");
---

<form method="POST" action={action} class="flex flex-col gap-8" novalidate data-business-form>
  {business && <input type="hidden" name="business_id" value={business.id} />}

  <section class="flex flex-col gap-4">
    <h2 class="text-lg font-semibold">Lo básico</h2>
    <Field name="name" label="Nombre del emprendimiento" required maxlength={80} value={v("name", business?.name)} error={err("name")} data-name-input />
    <div class="flex flex-col gap-1.5">
      <label for="slug" class="text-sm font-medium text-ink">Dirección de tu página</label>
      <div class:list={["flex items-stretch overflow-hidden rounded-wl border bg-surface focus-within:border-brand focus-within:ring-2 focus-within:ring-brand/25", err("slug") ? "border-danger" : "border-line"]}>
        <span class="flex items-center border-r border-line bg-surface-muted px-3 text-sm text-ink-muted">{host}/e/</span>
        <input
          id="slug"
          name="slug"
          value={v("slug", business?.slug)}
          maxlength="80"
          pattern="[a-z0-9]+(-[a-z0-9]+)*"
          autocomplete="off"
          placeholder="se-completa-con-el-nombre"
          class="h-11 min-w-0 flex-1 bg-transparent px-3 text-base text-ink focus:outline-none"
          data-slug-input
          data-touched={business ? "true" : undefined}
        />
      </div>
      {err("slug") ? <p class="text-sm text-danger" role="alert">{err("slug")}</p> : <p class="text-xs text-ink-muted">Letras sin tilde, números y guiones. {business && "Si la cambiás, los enlaces viejos dejan de funcionar."}</p>}
    </div>
    <Field name="tagline" label="Frase corta (opcional)" maxlength={140} placeholder="Ej.: Tortas personalizadas para tus eventos" value={v("tagline", business?.tagline)} error={err("tagline")} />
    <TextArea name="description" label="Descripción" rows={5} maxlength={3000} placeholder="Contá qué hacés, cómo trabajás y qué te diferencia." value={v("description", business?.description)} error={err("description")} />
  </section>

  <section class="flex flex-col gap-4">
    <h2 class="text-lg font-semibold">Categoría</h2>
    <SelectField
      name="category_id"
      label="Categoría principal"
      placeholder="Elegí una categoría"
      options={categories.map((c) => ({ value: c.id, label: c.name }))}
      value={categoryId}
      required
      error={err("category_id")}
      data-category-select
    />
    <fieldset class="flex flex-col gap-2">
      <legend class="mb-1 text-sm font-medium text-ink">Especialidades (opcional)</legend>
      {
        categories.map((category) => (
          <div data-subcategories-for={category.id} hidden={categoryId !== null && categoryId !== category.id}>
            {categoryId === null && <p class="mb-1 text-xs font-semibold uppercase tracking-wide text-ink-muted">{category.name}</p>}
            <div class="flex flex-wrap gap-2">
              {category.subcategories.map((sub) => (
                <label class="inline-flex cursor-pointer items-center gap-2 rounded-full border border-line bg-surface px-3 py-1.5 text-sm has-[:checked]:border-brand has-[:checked]:bg-seek-soft">
                  <input type="checkbox" name="subcategory_ids" value={sub.id} checked={selectedSubs.has(sub.id)} class="h-3.5 w-3.5 accent-[var(--wl-brand)]" />
                  {sub.name}
                </label>
              ))}
            </div>
          </div>
        ))
      }
      {err("subcategory_ids") && <p class="text-sm text-danger" role="alert">{err("subcategory_ids")}</p>}
      <p class="text-xs text-ink-muted">¿No encontrás tu rubro? Pronto vas a poder proponer una categoría nueva.</p>
    </fieldset>
  </section>

  <section class="flex flex-col gap-4">
    <h2 class="text-lg font-semibold">Imágenes</h2>
    <ImageUploader
      client:load
      name="logo_path"
      purpose="logo"
      label="Logo"
      initialPath={v("logo_path", business?.logo_path) || null}
      initialPreview={mediaUrl("logo", v("logo_path", business?.logo_path) || null, 256)}
      supabaseAnonKey={PUBLIC_SUPABASE_ANON_KEY}
      hint="Cuadrado, se ve en las búsquedas. JPG, PNG o WebP."
    />
    <ImageUploader
      client:load
      name="cover_path"
      purpose="cover"
      label="Portada"
      initialPath={v("cover_path", business?.cover_path) || null}
      initialPreview={mediaUrl("cover", v("cover_path", business?.cover_path) || null, 800)}
      supabaseAnonKey={PUBLIC_SUPABASE_ANON_KEY}
      hint="Horizontal (3:1). Una foto de tus trabajos o tu local."
    />
  </section>

  <section class="flex flex-col gap-4">
    <h2 class="text-lg font-semibold">Ubicación y contacto</h2>
    <CityPicker
      client:load
      name="city_id"
      label="Ciudad"
      initialCity={city ? { id: city.id, name: city.name, province_name: city.province_name } : null}
      error={err("city_id")}
      hint="Dónde trabajás o desde dónde atendés."
    />
    <div class="grid gap-4 sm:grid-cols-2">
      <Field name="whatsapp" label="WhatsApp" inputmode="tel" autocomplete="tel" placeholder="351 555-1234" value={v("whatsapp", business?.whatsapp)} error={err("whatsapp")} />
      <Field name="phone" label="Teléfono fijo (opcional)" inputmode="tel" placeholder="0351 422-1234" value={v("phone", business?.phone)} error={err("phone")} />
      <Field name="email" label="Email de contacto (opcional)" type="email" inputmode="email" value={v("email", business?.email)} error={err("email")} />
      <Field name="website" label="Sitio web (opcional)" inputmode="url" placeholder="minegocio.com.ar" value={v("website", business?.website)} error={err("website")} />
      <Field name="instagram" label="Instagram (opcional)" placeholder="@minegocio" value={instagramValue} error={err("instagram")} />
      <Field name="facebook" label="Facebook (opcional)" placeholder="facebook.com/minegocio" value={v("facebook", business?.facebook)} error={err("facebook")} />
      <Field name="tiktok" label="TikTok (opcional)" placeholder="@minegocio" value={v("tiktok", business?.tiktok ? `@${business.tiktok}` : "")} error={err("tiktok")} />
    </div>
    <p class="-mt-2 text-xs text-ink-muted">WhatsApp, teléfono y email solo los ven personas con cuenta en WorkLink.</p>
  </section>

  <section class="flex flex-col gap-4">
    <h2 class="text-lg font-semibold">Disponibilidad</h2>
    <HoursEditor hours={hours} error={err("hours")} />
    <Field name="availability" label="Aclaración (opcional)" maxlength={200} placeholder="Ej.: Con turno previo. Hago envíos a todo Córdoba." value={v("availability", business?.availability)} error={err("availability")} />
  </section>

  <section class="flex flex-col gap-4">
    <h2 class="text-lg font-semibold">Visibilidad</h2>
    {
      isSuspended ? (
        <p class="rounded-wl border border-danger/30 bg-danger-soft px-4 py-3 text-sm">Este emprendimiento fue suspendido por moderación y no es visible.</p>
      ) : (
        <div class="grid gap-2 sm:grid-cols-3">
          {[
            { value: "active", title: "Publicado", text: "Visible para todos." },
            { value: "draft", title: "Borrador", text: "Solo lo ve tu equipo." },
            { value: "inactive", title: "Pausado", text: "Oculto temporalmente." },
          ].map((option) => (
            <label class="flex cursor-pointer flex-col gap-0.5 rounded-wl border border-line bg-surface p-3 has-[:checked]:border-brand has-[:checked]:bg-seek-soft">
              <span class="flex items-center gap-2 font-semibold">
                <input type="radio" name="status" value={option.value} checked={status === option.value} class="accent-[var(--wl-brand)]" />
                {option.title}
              </span>
              <span class="text-sm text-ink-muted">{option.text}</span>
            </label>
          ))}
        </div>
      )
    }
  </section>

  <div class="sticky bottom-0 -mx-4 border-t border-line bg-bg/95 px-4 py-3 backdrop-blur sm:static sm:mx-0 sm:border-0 sm:bg-transparent sm:p-0">
    <Button type="submit" size="lg" class="w-full sm:w-auto">{submitLabel}</Button>
  </div>
</form>

<script>
  import { slugify } from "../../utils/slug";

  for (const form of document.querySelectorAll<HTMLFormElement>("[data-business-form]")) {
    const name = form.querySelector<HTMLInputElement>("[data-name-input]");
    const slug = form.querySelector<HTMLInputElement>("[data-slug-input]");
    if (name && slug) {
      if (slug.value) slug.dataset.touched = "true";
      slug.addEventListener("input", () => (slug.dataset.touched = "true"));
      name.addEventListener("input", () => {
        if (slug.dataset.touched !== "true") slug.value = slugify(name.value);
      });
    }

    const select = form.querySelector<HTMLSelectElement>("[data-category-select]");
    const groups = form.querySelectorAll<HTMLElement>("[data-subcategories-for]");
    const sync = () => {
      for (const group of groups) {
        const visible = group.dataset.subcategoriesFor === select?.value;
        group.hidden = !visible;
        const label = group.querySelector("p");
        if (label) label.hidden = true;
        if (!visible) group.querySelectorAll<HTMLInputElement>("input").forEach((input) => (input.checked = false));
      }
    };
    if (select) {
      select.addEventListener("change", sync);
      if (select.value) sync();
      else groups.forEach((group) => (group.hidden = true));
    }
  }
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/business/CatalogItemCard.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Tarjeta de producto o servicio en la página pública del emprendimiento. */
import type { CatalogItem } from "../../types/domain";
import { formatPrice } from "../../lib/format";
import { mediaSrcSet, mediaUrl } from "../../lib/media";

interface Props {
  item: CatalogItem;
}

const { item } = Astro.props;
const image = mediaUrl("catalog", item.cover_path, 320);
const duration =
  item.duration_min && item.duration_min >= 60
    ? `${Math.floor(item.duration_min / 60)} h${item.duration_min % 60 ? ` ${item.duration_min % 60} min` : ""}`
    : item.duration_min
      ? `${item.duration_min} min`
      : null;
---

<article class="flex gap-4 rounded-wl-lg border border-line bg-surface p-4">
  {
    image && (
      <img
        src={image}
        srcset={mediaSrcSet("catalog", item.cover_path)}
        sizes="96px"
        width="96"
        height="96"
        alt={item.name}
        loading="lazy"
        decoding="async"
        class="h-24 w-24 shrink-0 rounded-wl bg-surface-muted object-cover"
      />
    )
  }
  <div class="flex min-w-0 flex-1 flex-col gap-1">
    <h3 class="font-semibold leading-snug">{item.name}</h3>
    {item.description && <p class="line-clamp-3 text-sm text-ink-muted">{item.description}</p>}
    <div class="mt-auto flex flex-wrap items-center gap-x-3 gap-y-1 pt-1 text-sm">
      <span class="font-semibold text-ink">{formatPrice(item.price, item.price_type)}</span>
      {duration && <span class="text-ink-muted">· {duration}</span>}
      {item.service_area && <span class="text-ink-muted">· {item.service_area}</span>}
    </div>
  </div>
</article>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/business/CatalogItemForm.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Formulario de servicio o producto (alta y edición). */
import { PUBLIC_SUPABASE_ANON_KEY } from "astro:env/client";
import Field from "../ui/Field.astro";
import TextArea from "../ui/TextArea.astro";
import Button from "../ui/Button.astro";
import ImageUploader from "../../islands/ImageUploader.tsx";
import type { CatalogItem } from "../../types/domain";
import { mediaUrl } from "../../lib/media";

interface Props {
  kind: "service" | "product";
  action: string;
  businessId: string;
  item?: CatalogItem | null;
  submitted?: FormData | null;
  fieldErrors?: Record<string, string[] | undefined>;
}

const { kind, action, businessId, item = null, submitted = null, fieldErrors = {} } = Astro.props;
const prefix = item ? `item-${item.id}` : `new-${kind}`;
const v = (name: string, saved: unknown) =>
  submitted ? String(submitted.get(name) ?? "") : saved === null || saved === undefined ? "" : String(saved);
const err = (name: string) => fieldErrors[name]?.[0];
const priceType = v("price_type", item?.price_type ?? (kind === "service" ? "from" : "fixed"));
const price = v("price", item?.price !== null && item?.price !== undefined ? String(item.price).replace(".", ",") : "");
const coverPath = v("cover_path", item?.cover_path) || null;
---

<form method="POST" action={action} class="flex flex-col gap-4" novalidate>
  <input type="hidden" name="business_id" value={businessId} />
  {item && <input type="hidden" name="item_id" value={item.id} />}

  <Field
    id={`${prefix}-name`}
    name="name"
    label={kind === "service" ? "Nombre del servicio" : "Nombre del producto"}
    required
    maxlength={120}
    placeholder={kind === "service" ? "Ej.: Cobertura fotográfica de casamiento" : "Ej.: Torta personalizada de 2 pisos"}
    value={v("name", item?.name)}
    error={err("name")}
  />
  <TextArea id={`${prefix}-description`} name="description" label="Descripción (opcional)" rows={3} maxlength={3000} value={v("description", item?.description)} error={err("description")} />

  <div class="grid gap-4 sm:grid-cols-2">
    <div class="flex flex-col gap-1.5">
      <label for={`${prefix}-price_type`} class="text-sm font-medium text-ink">Precio</label>
      <select id={`${prefix}-price_type`} name="price_type" class="h-11 rounded-wl border border-line bg-surface px-3 text-base">
        <option value="fixed" selected={priceType === "fixed"}>Precio fijo</option>
        <option value="from" selected={priceType === "from"}>Desde (precio mínimo)</option>
        <option value="ask" selected={priceType === "ask"}>Consultar precio</option>
      </select>
    </div>
    <Field id={`${prefix}-price`} name="price" label="Importe en pesos" inputmode="decimal" placeholder="Ej.: 25.000" value={price} error={err("price")} hint="Dejalo vacío si elegiste “Consultar precio”." />
  </div>

  {
    kind === "service" && (
      <div class="grid gap-4 sm:grid-cols-2">
        <Field id={`${prefix}-duration`} name="duration_min" label="Duración en minutos (opcional)" type="number" min={5} inputmode="numeric" value={v("duration_min", item?.duration_min)} error={err("duration_min")} />
        <Field id={`${prefix}-area`} name="service_area" label="Zona de trabajo (opcional)" maxlength={200} placeholder="Ej.: Córdoba capital y alrededores" value={v("service_area", item?.service_area)} error={err("service_area")} />
      </div>
    )
  }

  <ImageUploader
    client:visible
    name="cover_path"
    purpose="catalog"
    label="Foto (opcional)"
    initialPath={coverPath}
    initialPreview={mediaUrl("catalog", coverPath, 320)}
    supabaseAnonKey={PUBLIC_SUPABASE_ANON_KEY}
  />

  <div>
    <Button type="submit">{item ? "Guardar cambios" : kind === "service" ? "Agregar servicio" : "Agregar producto"}</Button>
  </div>
</form>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/business/HoursEditor.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Editor de horarios semanal, sin JavaScript: por día, una casilla "Abierto"
 * y hasta dos franjas (ej. 9 a 13 y 17 a 21, habitual en Argentina).
 * Campos: hours.mon.open, hours.mon.from1, hours.mon.to1, hours.mon.from2...
 */
import { WEEK_DAYS, type BusinessHours } from "../../schemas/business";

interface Props {
  hours: BusinessHours | null;
  error?: string;
}

const { hours, error } = Astro.props;
const timeClass =
  "h-10 w-[6.5rem] rounded-wl border border-line bg-surface px-2 text-sm text-ink focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25";
---

<fieldset class="flex flex-col gap-2">
  <legend class="mb-1 text-sm font-medium text-ink">Horarios de atención</legend>
  <p class="text-xs text-ink-muted">Marcá los días que atendés. La segunda franja es opcional (por ejemplo, de tarde).</p>
  <div class="divide-y divide-line rounded-wl border border-line bg-surface">
    {
      WEEK_DAYS.map(({ key, label }) => {
        const ranges = hours?.[key] ?? [];
        const open = ranges.length > 0;
        return (
          <div class="flex flex-col gap-2 px-3 py-2.5 sm:flex-row sm:items-center sm:gap-4">
            <label class="flex w-32 items-center gap-2 text-sm font-medium">
              <input type="checkbox" name={`hours.${key}.open`} checked={open} class="h-4 w-4 accent-[var(--wl-brand)]" />
              {label}
            </label>
            <div class="flex flex-wrap items-center gap-2 text-sm text-ink-muted">
              <input type="time" name={`hours.${key}.from1`} value={ranges[0]?.[0] ?? ""} aria-label={`${label}: abre`} class={timeClass} />
              a
              <input type="time" name={`hours.${key}.to1`} value={ranges[0]?.[1] ?? ""} aria-label={`${label}: cierra`} class={timeClass} />
              <span class="px-1">y</span>
              <input type="time" name={`hours.${key}.from2`} value={ranges[1]?.[0] ?? ""} aria-label={`${label}: abre (segunda franja)`} class={timeClass} />
              a
              <input type="time" name={`hours.${key}.to2`} value={ranges[1]?.[1] ?? ""} aria-label={`${label}: cierra (segunda franja)`} class={timeClass} />
            </div>
          </div>
        );
      })
    }
  </div>
  {error && <p class="text-sm text-danger" role="alert">{error}</p>}
</fieldset>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/business/HoursTable.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Horarios en la página pública: "Lunes 9:00 a 13:00 y 17:00 a 21:00". Resalta el día de hoy. */
import { WEEK_DAYS, type BusinessHours } from "../../schemas/business";

interface Props {
  hours: BusinessHours;
}

const { hours } = Astro.props;
const todayKey = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: "America/Argentina/Cordoba" })
  .format(new Date())
  .toLowerCase()
  .slice(0, 3);
const fmt = (t: string) => t.replace(/^0/, "");
---

<dl class="divide-y divide-line text-sm">
  {
    WEEK_DAYS.map(({ key, label }) => {
      const ranges = hours[key] ?? [];
      const isToday = key === todayKey;
      return (
        <div class:list={["flex justify-between gap-4 py-2", isToday && "font-semibold"]}>
          <dt>{label}{isToday && <span class="ml-1 text-xs font-medium text-brand">(hoy)</span>}</dt>
          <dd class:list={[ranges.length ? "text-ink" : "text-ink-muted"]}>
            {ranges.length ? ranges.map(([from, to]) => `${fmt(from)} a ${fmt(to)}`).join(" y ") : "Cerrado"}
          </dd>
        </div>
      );
    })
  }
</dl>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/layout/Footer.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import Logo from "../brand/Logo.astro";
import { brand } from "../../config/brand";

const year = new Date().getFullYear();
---

<footer class="mt-auto border-t border-line">
  <div class="mx-auto flex max-w-6xl flex-col gap-4 px-4 py-8 text-sm text-ink-muted sm:flex-row sm:items-center sm:justify-between">
    <div class="flex items-center gap-3">
      <Logo variant="mark" />
      <p>{brand.tagline}.</p>
    </div>
    <p>© {year} {brand.name} · Hecho en Córdoba, Argentina</p>
  </div>
</footer>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/layout/Header.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import Logo from "../brand/Logo.astro";
import Button from "../ui/Button.astro";
import { actions } from "astro:actions";
import { routes } from "../../config/site";

const user = Astro.locals.user;
const logoutAction = `/salir${actions.auth.signOut}`;
---

<header class="sticky top-0 z-30 border-b border-line bg-bg/85 backdrop-blur supports-[backdrop-filter]:bg-bg/70">
  <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4">
    <a href={routes.home} class="rounded-wl" aria-label="WorkLink, ir al inicio">
      <Logo />
    </a>

    <nav aria-label="Cuenta" class="flex items-center gap-2">
      <a href="/publicaciones" class="hidden rounded-wl px-3 py-2 text-sm font-medium text-ink-muted hover:text-ink sm:inline-block">Publicaciones</a>
      {
        user ? (
          <>
            <Button href={routes.dashboard} variant="ghost" size="sm">
              Mi panel
            </Button>
            <form method="POST" action={logoutAction}>
              <Button type="submit" variant="secondary" size="sm">
                Salir
              </Button>
            </form>
          </>
        ) : (
          <>
            <Button href={routes.login} variant="ghost" size="sm">
              Ingresar
            </Button>
            <Button href={routes.signup} size="sm">
              Crear cuenta
            </Button>
          </>
        )
      }
    </nav>
  </div>
</header>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/posts/FeedPage.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Una página del feed: tarjetas + enlace "Cargar más". Se usa en la página
 * completa y en el fragmento que se agrega con JavaScript (/publicaciones/mas).
 */
import PostCard from "./PostCard.astro";
import type { PostView } from "../../services/posts";
import type { ViewerReactions } from "../../services/social";

interface Props {
  posts: PostView[];
  nextHref: string | null;
  nextFragmentHref: string | null;
  priorityCount?: number;
  reactions?: ViewerReactions;
}

const { posts, nextHref, nextFragmentHref, priorityCount = 0, reactions } = Astro.props;
---

{
  posts.map((post, index) => (
    <PostCard post={post} priority={index < priorityCount} liked={reactions?.liked.has(post.id)} saved={reactions?.saved.has(post.id)} />
  ))
}
{
  nextHref && (
    <div class="col-span-full flex justify-center pt-2" data-load-more-wrapper>
      <a
        href={nextHref}
        data-load-more={nextFragmentHref}
        class="inline-flex h-11 items-center rounded-wl border border-line bg-surface px-5 font-semibold text-ink hover:bg-surface-muted"
      >
        Cargar más
      </a>
    </div>
  )
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/posts/PostCard.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Tarjeta de publicación para el feed: quién publica, tipo, texto, primera
 * foto (o portada del video), precio y ciudad. Toda la tarjeta lleva a /p/...
 */
import Avatar from "../ui/Avatar.astro";
import PostActions from "../social/PostActions.astro";
import type { PostView } from "../../services/posts";
import { POST_TYPE_LABELS, postHeadline } from "../../services/posts";
import { postFileUrl, mediaSrcSet, mediaUrl } from "../../lib/media";
import { formatMoney, formatRelative } from "../../lib/format";
import { businessPath, postPath, profilePath } from "../../lib/urls";
import { displayName } from "../../services/profiles";

interface Props {
  post: PostView;
  /** true para las primeras tarjetas visibles (carga prioritaria de la imagen). */
  priority?: boolean;
  /** Estado del usuario actual (me gusta / guardada). */
  liked?: boolean;
  saved?: boolean;
}

const { post, priority = false, liked = false, saved = false } = Astro.props;
const href = postPath(post);
const type = POST_TYPE_LABELS[post.type];
const cover = post.media[0];
const authorName = post.business?.name ?? (post.author ? displayName(post.author) : "");
const authorHref = post.business ? businessPath(post.business.slug) : post.author ? profilePath(post.author.username) : null;
const extraMedia = post.media.length - 1;
const ratio = cover?.width && cover?.height ? Math.min(Math.max(cover.width / cover.height, 0.8), 1.91) : 4 / 3;
---

<article class="flex flex-col overflow-hidden rounded-wl-lg border border-line bg-surface">
  <header class="flex items-center gap-3 px-4 pt-4">
    {
      authorHref ? (
        <a href={authorHref} class="flex min-w-0 flex-1 items-center gap-3">
          <Avatar
            name={authorName}
            path={post.business?.logo_path ?? post.author?.avatar_path}
            purpose={post.business ? "logo" : "avatar"}
            shape={post.business ? "rounded" : "circle"}
            size={40}
          />
          <span class="min-w-0">
            <span class="block truncate font-semibold">
              {authorName}
              {post.business?.verification === "verified" && <span class="text-seek" title="Verificado"> ✓</span>}
            </span>
            <span class="block truncate text-xs text-ink-muted">
              {formatRelative(post.published_at)}{post.city && ` · ${post.city.name}`}
            </span>
          </span>
        </a>
      ) : null
    }
    <span class:list={["shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold", type.class]}>{type.label}</span>
  </header>

  <a href={href} class="mt-3 flex flex-1 flex-col">
    <div class="px-4">
      {post.title && <h2 class="font-semibold leading-snug">{post.title}</h2>}
      <p class:list={["whitespace-pre-line text-sm", post.title ? "mt-1 line-clamp-3 text-ink-muted" : "line-clamp-4 text-ink"]}>{post.body}</p>
    </div>

    {
      cover && (
        <div class="relative mt-3 w-full overflow-hidden bg-surface-muted" style={{ aspectRatio: String(ratio) }}>
          {cover.kind === "image" ? (
            <img
              src={mediaUrl("post", cover.path, 960)}
              srcset={mediaSrcSet("post", cover.path)}
              sizes="(min-width: 768px) 600px, 100vw"
              width={cover.width ?? undefined}
              height={cover.height ?? undefined}
              alt={postHeadline(post, 120)}
              loading={priority ? "eager" : "lazy"}
              fetchpriority={priority ? "high" : undefined}
              decoding="async"
              class="h-full w-full object-cover"
            />
          ) : (
            <>
              <img
                src={postFileUrl(cover.path, "poster.webp")}
                alt={postHeadline(post, 120)}
                loading={priority ? "eager" : "lazy"}
                decoding="async"
                class="h-full w-full object-cover"
              />
              <span class="absolute inset-0 grid place-items-center">
                <span class="grid h-14 w-14 place-items-center rounded-full bg-black/60 text-2xl text-white" aria-hidden="true">▶</span>
              </span>
              <span class="sr-only">Video</span>
            </>
          )}
          {extraMedia > 0 && (
            <span class="absolute right-2 top-2 rounded-full bg-black/65 px-2 py-0.5 text-xs font-semibold text-white">+{extraMedia} {extraMedia === 1 ? "foto" : "fotos"}</span>
          )}
        </div>
      )
    }

    {
      (post.price !== null || post.category) && (
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 pt-3 text-sm">
          {post.price !== null && <span class="font-semibold">{formatMoney(post.price)}</span>}
          {post.category && <span class="text-ink-muted">{post.subcategory?.name ?? post.category.name}</span>}
        </div>
      )
    }
    <span class="sr-only">Ver publicación</span>
  </a>

  <PostActions post={post} liked={liked} saved={saved} commentsHref={`${href}#comentarios`} class="mt-2 border-t border-line px-2 py-1.5" />
</article>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/posts/PostForm.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Formulario de publicación (crear y editar). Funciona sin JavaScript salvo
 * las islas de fotos y ciudad; un script pequeño habilita los tipos que
 * requieren emprendimiento y filtra las subcategorías.
 */
import { PUBLIC_SUPABASE_ANON_KEY } from "astro:env/client";
import Field from "../ui/Field.astro";
import TextArea from "../ui/TextArea.astro";
import Button from "../ui/Button.astro";
import CityPicker from "../../islands/CityPicker.tsx";
import PostMediaUploader, { type PostMediaItem } from "../../islands/PostMediaUploader.tsx";
import type { CategoryTree } from "../../services/categories";
import type { PostView } from "../../services/posts";
import type { MyBusiness } from "../../services/businesses";
import type { CityRef } from "../../types/domain";
import { POST_TYPES } from "../../schemas/post";

interface Props {
  action: string;
  post?: PostView | null;
  businesses: MyBusiness[];
  categories: CategoryTree[];
  submitted?: FormData | null;
  fieldErrors?: Record<string, string[] | undefined>;
  city?: CityRef | null;
  media: PostMediaItem[];
  submitLabel: string;
  /** Emprendimiento preseleccionado (?emprendimiento=...). */
  defaultBusinessId?: string | null;
}

const { action, post = null, businesses, categories, submitted = null, fieldErrors = {}, city = null, media, submitLabel, defaultBusinessId = null } = Astro.props;

const v = (name: string, saved: unknown) =>
  submitted ? String(submitted.get(name) ?? "") : saved === null || saved === undefined ? "" : String(saved);
const err = (name: string) => fieldErrors[name]?.[0];

const businessId = v("business_id", post ? post.business_id : (defaultBusinessId ?? (businesses.length ? businesses[0].id : "")));
const type = v("type", post?.type ?? (businessId ? "offer" : "offer"));
const categoryId = Number(v("category_id", post?.category_id)) || null;
const subcategoryId = Number(v("subcategory_id", post?.subcategory_id)) || null;
const price = v("price", post?.price !== null && post?.price !== undefined ? String(post.price).replace(".", ",") : "");
const tags = v("tags", post?.tags.join(", "));
const status = v("status", post?.status === "hidden" ? "hidden" : "published");
const activeBusinesses = businesses.filter((b) => b.status !== "suspended");
const selectClass = "h-11 w-full rounded-wl border border-line bg-surface px-3 text-base text-ink focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25";
---

<form method="POST" action={action} class="flex flex-col gap-7" novalidate data-post-form>
  {post && <input type="hidden" name="post_id" value={post.id} />}

  <section class="flex flex-col gap-4">
    {
      post ? (
        post.business_id && <input type="hidden" name="business_id" value={post.business_id} />
      ) : (
        <div class="flex flex-col gap-1.5">
          <label for="business_id" class="text-sm font-medium text-ink">Publicar como</label>
          <select id="business_id" name="business_id" class={selectClass} data-business-select>
            {activeBusinesses.map((b) => (
              <option value={b.id} selected={businessId === b.id}>{b.name}</option>
            ))}
            <option value="" selected={businessId === ""}>Yo, a título personal</option>
          </select>
        </div>
      )
    }

    <fieldset class="flex flex-col gap-2">
      <legend class="mb-1 text-sm font-medium text-ink">¿Qué querés publicar?</legend>
      <div class="flex flex-wrap gap-2">
        {
          POST_TYPES.map((option) => (
            <label
              class="inline-flex cursor-pointer items-center gap-2 rounded-full border border-line bg-surface px-3.5 py-2 text-sm font-medium has-[:checked]:border-brand has-[:checked]:bg-seek-soft has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-45"
              data-needs-business={option.needsBusiness ? "true" : undefined}
            >
              <input type="radio" name="type" value={option.value} checked={type === option.value} class="accent-[var(--wl-brand)]" />
              {option.label}
            </label>
          ))
        }
      </div>
      {err("type") ? <p class="text-sm text-danger" role="alert">{err("type")}</p> : <p class="text-xs text-ink-muted">Producto, Servicio y Promoción se publican desde un emprendimiento.</p>}
    </fieldset>

    <Field name="title" label="Título (opcional)" maxlength={140} placeholder="Ej.: Tortas temáticas para cumpleaños" value={v("title", post?.title)} error={err("title")} />
    <TextArea name="body" label="Texto" rows={5} maxlength={5000} required placeholder="Contá qué ofrecés o qué estás buscando: detalles, zona, plazos…" value={v("body", post?.body)} error={err("body")} />
  </section>

  <section class="flex flex-col gap-2">
    <h2 class="text-sm font-medium text-ink">Fotos o video</h2>
    <PostMediaUploader client:load initial={media} supabaseAnonKey={PUBLIC_SUPABASE_ANON_KEY} />
    {err("media") && <p class="text-sm text-danger" role="alert">{err("media")}</p>}
  </section>

  <section class="grid gap-4 sm:grid-cols-2">
    <Field name="price" label="Precio en pesos (opcional)" inputmode="decimal" placeholder="Ej.: 25.000" value={price} error={err("price")} />
    <div class="flex flex-col gap-1.5">
      <label for="category_id" class="text-sm font-medium text-ink">Categoría</label>
      <select id="category_id" name="category_id" class={selectClass} data-category-select>
        <option value="">{businessId ? "La de mi emprendimiento" : "Elegí una categoría"}</option>
        {categories.map((c) => <option value={c.id} selected={categoryId === c.id}>{c.name}</option>)}
      </select>
    </div>
    <div class="flex flex-col gap-1.5">
      <label for="subcategory_id" class="text-sm font-medium text-ink">Especialidad (opcional)</label>
      <select id="subcategory_id" name="subcategory_id" class={selectClass} data-subcategory-select>
        <option value="">Ninguna</option>
        {categories.map((c) => (
          <optgroup label={c.name} data-category={c.id}>
            {c.subcategories.map((s) => <option value={s.id} selected={subcategoryId === s.id}>{s.name}</option>)}
          </optgroup>
        ))}
      </select>
    </div>
    <CityPicker
      client:load
      name="city_id"
      label="Ciudad"
      initialCity={city ? { id: city.id, name: city.name, province_name: city.province_name } : null}
      error={err("city_id")}
      hint={businessId ? "Si la dejás vacía, se usa la de tu emprendimiento." : undefined}
    />
    <Field name="tags" label="Etiquetas (opcional)" placeholder="bodas, eventos, fotografía" value={tags} hint="Separadas por coma. Hasta 10." error={err("tags")} class="sm:col-span-2" />
  </section>

  <section class="flex flex-col gap-2">
    <span class="text-sm font-medium text-ink">Visibilidad</span>
    <div class="flex flex-wrap gap-2">
      <label class="inline-flex cursor-pointer items-center gap-2 rounded-wl border border-line bg-surface px-3 py-2 text-sm has-[:checked]:border-brand has-[:checked]:bg-seek-soft">
        <input type="radio" name="status" value="published" checked={status === "published"} class="accent-[var(--wl-brand)]" /> Publicada
      </label>
      <label class="inline-flex cursor-pointer items-center gap-2 rounded-wl border border-line bg-surface px-3 py-2 text-sm has-[:checked]:border-brand has-[:checked]:bg-seek-soft">
        <input type="radio" name="status" value="hidden" checked={status === "hidden"} class="accent-[var(--wl-brand)]" /> Oculta (solo vos la ves)
      </label>
    </div>
  </section>

  <div class="sticky bottom-0 -mx-4 border-t border-line bg-bg/95 px-4 py-3 backdrop-blur sm:static sm:mx-0 sm:border-0 sm:bg-transparent sm:p-0">
    <Button type="submit" size="lg" class="w-full sm:w-auto">{submitLabel}</Button>
  </div>
</form>

<script>
  for (const form of document.querySelectorAll<HTMLFormElement>("[data-post-form]")) {
    // Tipos que requieren emprendimiento: deshabilitados si se publica a título personal.
    const businessSelect = form.querySelector<HTMLSelectElement>("[data-business-select]");
    const syncTypes = () => {
      const personal = businessSelect ? businessSelect.value === "" : !form.querySelector('input[name="business_id"]');
      for (const label of form.querySelectorAll<HTMLElement>("[data-needs-business]")) {
        const input = label.querySelector("input");
        if (!input) continue;
        input.disabled = personal;
        if (personal && input.checked) {
          input.checked = false;
          form.querySelector<HTMLInputElement>('input[name="type"][value="offer"]')!.checked = true;
        }
      }
    };
    businessSelect?.addEventListener("change", syncTypes);
    syncTypes();

    // Especialidades: solo las de la categoría elegida.
    const category = form.querySelector<HTMLSelectElement>("[data-category-select]");
    const sub = form.querySelector<HTMLSelectElement>("[data-subcategory-select]");
    const syncSubs = () => {
      if (!category || !sub) return;
      for (const group of sub.querySelectorAll<HTMLOptGroupElement>("optgroup")) {
        const visible = !category.value || group.dataset.category === category.value;
        group.hidden = !visible;
        group.disabled = !visible;
      }
      const selected = sub.selectedOptions[0];
      if (selected?.parentElement instanceof HTMLOptGroupElement && selected.parentElement.disabled) sub.value = "";
    };
    category?.addEventListener("change", syncSubs);
    syncSubs();
  }
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/social/CommentsSection.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Comentarios de una publicación: lista (del más viejo al más nuevo) y
 * formulario para comentar. Funciona sin JavaScript (formularios comunes).
 *
 * Borrar: quien escribió el comentario, o quien gestiona la publicación
 * (para moderar su propia conversación). Lo verifica la base.
 */
import { actions } from "astro:actions";
import Avatar from "../ui/Avatar.astro";
import Alert from "../ui/Alert.astro";
import Button from "../ui/Button.astro";
import TextArea from "../ui/TextArea.astro";
import type { CommentView } from "../../services/social";
import { COMMENT_MAX } from "../../schemas/social";
import { displayName } from "../../services/profiles";
import { formatDate, formatRelative } from "../../lib/format";
import { profilePath } from "../../lib/urls";
import { routes } from "../../config/site";

interface Props {
  postId: string;
  total: number;
  comments: CommentView[];
  /** Enlace a los comentarios anteriores, si hay. */
  olderHref: string | null;
  /** El usuario gestiona la publicación (puede borrar cualquier comentario). */
  canModerate: boolean;
  /** La publicación admite comentarios nuevos (está publicada). */
  open: boolean;
  returnTo: string;
  error?: { message: string; fields?: Record<string, string[] | undefined> } | null;
  draft?: string;
}

const { postId, total, comments, olderHref, canModerate, open, returnTo, error, draft } = Astro.props;
const { user } = Astro.locals;
const bodyError = error?.fields?.body?.[0];
const generalError = error && !bodyError ? error.message : null;
---

<section id="comentarios" class="scroll-mt-20">
  <h2 class="text-lg font-semibold">
    Comentarios {total > 0 && <span class="font-normal text-ink-muted">({total.toLocaleString("es-AR")})</span>}
  </h2>

  {generalError && <Alert tone="danger" class="mt-4">{generalError}</Alert>}

  {
    olderHref && (
      <a href={olderHref} class="mt-4 inline-block text-sm font-semibold text-brand">
        Ver comentarios anteriores
      </a>
    )
  }

  {
    comments.length > 0 ? (
      <ol class="mt-4 flex flex-col gap-4">
        {comments.map((comment) => {
          const name = comment.author ? displayName(comment.author) : "Usuario";
          const canDelete = Boolean(user) && (comment.author_id === user!.id || canModerate);
          return (
            <li id={`c-${comment.id}`} class="flex scroll-mt-24 gap-3">
              <a href={comment.author ? profilePath(comment.author.username) : undefined} class="shrink-0">
                <Avatar name={name} path={comment.author?.avatar_path} size={36} />
              </a>
              <div class="min-w-0 flex-1">
                <div class="rounded-wl-lg bg-surface-muted px-3 py-2">
                  <p class="flex flex-wrap items-baseline gap-x-2 text-sm">
                    {comment.author ? (
                      <a href={profilePath(comment.author.username)} class="font-semibold hover:underline">{name}</a>
                    ) : (
                      <span class="font-semibold">{name}</span>
                    )}
                    <time
                      datetime={comment.created_at}
                      title={formatDate(comment.created_at, { dateStyle: "long", timeStyle: "short" })}
                      class="text-xs text-ink-muted"
                    >
                      {formatRelative(comment.created_at)}
                    </time>
                  </p>
                  <p class="mt-0.5 whitespace-pre-line break-words">{comment.body}</p>
                </div>
                {canDelete && (
                  <form method="POST" action={actions.social.removeComment} data-confirm="¿Borrar este comentario?" class="mt-1">
                    <input type="hidden" name="comment_id" value={comment.id} />
                    <button type="submit" class="px-3 text-xs font-semibold text-ink-muted hover:text-danger">Borrar</button>
                  </form>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    ) : (
      open && <p class="mt-3 text-ink-muted">Todavía no hay comentarios. ¿Querés preguntar algo?</p>
    )
  }

  {
    open &&
      (user ? (
        <form method="POST" action={actions.social.comment} class="mt-6 flex flex-col gap-3" data-comment-form>
          <input type="hidden" name="post_id" value={postId} />
          <TextArea
            name="body"
            label="Escribí un comentario"
            rows={3}
            maxlength={COMMENT_MAX}
            required
            value={draft}
            error={bodyError}
            placeholder="Preguntá por precio, disponibilidad, zona…"
            hint="Para datos personales (teléfono, dirección), mejor usá el contacto directo."
          />
          <div>
            <Button type="submit">Comentar</Button>
          </div>
        </form>
      ) : (
        <p class="mt-6 rounded-wl border border-line bg-surface px-4 py-3 text-sm">
          <a href={`${routes.login}?next=${encodeURIComponent(`${returnTo}#comentarios`)}`} class="font-semibold text-brand">Ingresá</a>
          {" "}o{" "}
          <a href={routes.signup} class="font-semibold text-brand">creá tu cuenta</a> para comentar.
        </p>
      ))
  }
</section>

<script>
  // Confirmación antes de borrar y evitar el doble envío del comentario.
  for (const form of document.querySelectorAll<HTMLFormElement>("#comentarios form[data-confirm]")) {
    form.addEventListener("submit", (event) => {
      if (!window.confirm(form.dataset.confirm ?? "¿Confirmás?")) event.preventDefault();
    });
  }
  for (const form of document.querySelectorAll<HTMLFormElement>("form[data-comment-form]")) {
    form.addEventListener("submit", () => {
      const button = form.querySelector<HTMLButtonElement>("button[type=submit]");
      if (button) setTimeout(() => (button.disabled = true), 0);
    });
  }
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/social/FollowButton.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Botón Seguir / Siguiendo para una persona o un emprendimiento.
 * El contador de seguidores se muestra aparte con FollowersCount (mismo id),
 * y el script lo actualiza al tocar el botón.
 */
import { routes } from "../../config/site";

interface Props {
  kind: "profile" | "business";
  id: string;
  following: boolean;
  /** Página a la que vuelve después de ingresar. */
  returnTo: string;
  class?: string;
}

const { kind, id, following, returnTo, class: className = "" } = Astro.props;
const loggedIn = Boolean(Astro.locals.user);
const loginHref = `${routes.login}?next=${encodeURIComponent(returnTo)}`;

const base =
  "inline-flex h-10 items-center justify-center gap-1.5 rounded-wl px-4 text-sm font-semibold transition-colors";
---

{
  loggedIn ? (
    <button
      type="button"
      data-social="follow"
      data-kind={kind}
      data-id={id}
      data-label-on="Siguiendo"
      data-label-off="Seguir"
      aria-pressed={following ? "true" : "false"}
      class:list={[
        base,
        "bg-brand text-brand-contrast hover:bg-brand-hover",
        "aria-pressed:border aria-pressed:border-line aria-pressed:bg-surface aria-pressed:text-ink aria-pressed:hover:bg-surface-muted",
        className,
      ]}
    >
      <span data-label>{following ? "Siguiendo" : "Seguir"}</span>
    </button>
  ) : (
    <a href={loginHref} class:list={[base, "bg-brand text-brand-contrast hover:bg-brand-hover", className]}>
      Seguir
    </a>
  )
}

<script>
  import "../../scripts/social";
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/social/PostActions.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Barra de acciones de una publicación: me gusta (con cantidad), comentarios
 * (con cantidad, lleva a la sección de comentarios) y guardar.
 * Con sesión son botones (los maneja scripts/social.ts); sin sesión, enlaces
 * a /ingresar que vuelven a esta página.
 */
import { routes } from "../../config/site";

interface Props {
  post: { id: string; likes_count: number; comments_count: number };
  liked?: boolean;
  saved?: boolean;
  /** Enlace a los comentarios (en el feed, la página de la publicación). */
  commentsHref: string;
  size?: "sm" | "lg";
  class?: string;
}

const { post, liked = false, saved = false, commentsHref, size = "sm", class: className = "" } = Astro.props;
const loggedIn = Boolean(Astro.locals.user);
// Sin sesión: ingresar y volver a la publicación.
const loginHref = `${routes.login}?next=${encodeURIComponent(commentsHref.split("#")[0])}`;
const fmt = (n: number) => (n > 0 ? n.toLocaleString("es-AR") : "");

const base = [
  "group inline-flex items-center gap-1.5 rounded-full font-semibold text-ink-muted transition-colors hover:bg-surface-muted hover:text-ink",
  size === "lg" ? "h-11 px-4 text-base" : "h-9 px-3 text-sm",
].join(" ");
const icon = size === "lg" ? "h-6 w-6" : "h-5 w-5";
---

<div class:list={["flex items-center gap-1", className]}>
  {
    loggedIn ? (
      <button
        type="button"
        class:list={[base, "aria-pressed:text-danger"]}
        data-social="like"
        data-id={post.id}
        aria-pressed={liked ? "true" : "false"}
        aria-label="Me gusta"
      >
        <svg viewBox="0 0 24 24" class:list={[icon, "fill-none stroke-current stroke-2 group-aria-pressed:fill-current"]} aria-hidden="true">
          <path stroke-linejoin="round" d="M12 20.5s-7.5-4.6-9.2-9.3C1.6 7.8 3.9 4.5 7.3 4.5c2 0 3.6 1.1 4.7 2.8 1.1-1.7 2.7-2.8 4.7-2.8 3.4 0 5.7 3.3 4.5 6.7-1.7 4.7-9.2 9.3-9.2 9.3Z" />
        </svg>
        <span data-count>{fmt(post.likes_count)}</span>
      </button>
    ) : (
      <a href={loginHref} class={base} aria-label="Me gusta (ingresá para reaccionar)">
        <svg viewBox="0 0 24 24" class:list={[icon, "fill-none stroke-current stroke-2"]} aria-hidden="true">
          <path stroke-linejoin="round" d="M12 20.5s-7.5-4.6-9.2-9.3C1.6 7.8 3.9 4.5 7.3 4.5c2 0 3.6 1.1 4.7 2.8 1.1-1.7 2.7-2.8 4.7-2.8 3.4 0 5.7 3.3 4.5 6.7-1.7 4.7-9.2 9.3-9.2 9.3Z" />
        </svg>
        <span>{fmt(post.likes_count)}</span>
      </a>
    )
  }

  <a href={commentsHref} class={base} aria-label={`Comentarios (${post.comments_count})`}>
    <svg viewBox="0 0 24 24" class:list={[icon, "fill-none stroke-current stroke-2"]} aria-hidden="true">
      <path stroke-linejoin="round" d="M20 12.5c0 4-3.6 7-8 7-1.2 0-2.3-.2-3.3-.6L4 20l1.2-3.6C4.4 15.3 4 14 4 12.5c0-4 3.6-7 8-7s8 3 8 7Z" />
    </svg>
    <span>{fmt(post.comments_count)}</span>
  </a>

  {
    loggedIn ? (
      <button
        type="button"
        class:list={[base, "ml-auto aria-pressed:text-brand"]}
        data-social="save"
        data-id={post.id}
        aria-pressed={saved ? "true" : "false"}
        aria-label="Guardar"
        data-label-on="Guardada"
        data-label-off="Guardar"
      >
        <svg viewBox="0 0 24 24" class:list={[icon, "fill-none stroke-current stroke-2 group-aria-pressed:fill-current"]} aria-hidden="true">
          <path stroke-linejoin="round" d="M6.5 3.5h11a1 1 0 0 1 1 1v16l-6.5-4.2-6.5 4.2v-16a1 1 0 0 1 1-1Z" />
        </svg>
        {size === "lg" && <span data-label>{saved ? "Guardada" : "Guardar"}</span>}
      </button>
    ) : (
      <a href={loginHref} class:list={[base, "ml-auto"]} aria-label="Guardar (ingresá para guardar)">
        <svg viewBox="0 0 24 24" class:list={[icon, "fill-none stroke-current stroke-2"]} aria-hidden="true">
          <path stroke-linejoin="round" d="M6.5 3.5h11a1 1 0 0 1 1 1v16l-6.5-4.2-6.5 4.2v-16a1 1 0 0 1 1-1Z" />
        </svg>
        {size === "lg" && <span>Guardar</span>}
      </a>
    )
  }
</div>

<script>
  import "../../scripts/social";
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/ui/Alert.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Mensaje destacado (error, éxito, aviso, información). */
interface Props {
  tone?: "info" | "success" | "warning" | "danger";
  title?: string;
  class?: string;
}

const { tone = "info", title, class: className = "" } = Astro.props;

const tones = {
  info: "border-seek/30 bg-seek-soft text-ink",
  success: "border-success/30 bg-success-soft text-ink",
  warning: "border-warning/30 bg-warning-soft text-ink",
  danger: "border-danger/30 bg-danger-soft text-ink",
} as const;
---

<div
  class:list={["rounded-wl border px-4 py-3 text-sm", tones[tone], className]}
  role={tone === "danger" ? "alert" : "status"}
>
  {title && <p class="mb-0.5 font-semibold">{title}</p>}
  <div class="leading-relaxed"><slot /></div>
</div>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/ui/Avatar.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Avatar o logo: muestra la imagen (variante del tamaño justo) o, si no hay,
 * las iniciales sobre un color estable derivado del nombre.
 */
import { mediaUrl, mediaSrcSet } from "../../lib/media";

interface Props {
  name: string;
  path?: string | null;
  purpose?: "avatar" | "logo";
  /** Tamaño en píxeles CSS. */
  size?: number;
  shape?: "circle" | "rounded";
  class?: string;
  /** true para la imagen principal de la página (LCP). */
  priority?: boolean;
}

const { name, path, purpose = "avatar", size = 48, shape = "circle", class: className = "", priority = false } = Astro.props;

const initials =
  name
    .replace(/^@/, "")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? "")
    .join("") || "?";

const palette = ["bg-seek-soft text-seek", "bg-offer-soft text-offer", "bg-success-soft text-success", "bg-warning-soft text-warning"];
const color = palette[[...name].reduce((acc, ch) => acc + ch.charCodeAt(0), 0) % palette.length];
const radius = shape === "circle" ? "rounded-full" : "rounded-wl";
const src = mediaUrl(purpose, path, size * 2);
---

{
  src ? (
    <img
      src={src}
      srcset={mediaSrcSet(purpose, path)}
      sizes={`${size}px`}
      width={size}
      height={size}
      alt={name}
      loading={priority ? "eager" : "lazy"}
      fetchpriority={priority ? "high" : undefined}
      decoding="async"
      class:list={["shrink-0 bg-surface-muted object-cover", radius, className]}
      style={{ width: `${size}px`, height: `${size}px` }}
    />
  ) : (
    <span
      aria-hidden="true"
      class:list={["inline-grid shrink-0 place-items-center font-bold", radius, color, className]}
      style={{ width: `${size}px`, height: `${size}px`, fontSize: `${Math.round(size * 0.38)}px` }}
    >
      {initials}
    </span>
  )
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/ui/Button.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Botón reutilizable. Con `href` se renderiza como enlace; sin `href`, como
 * <button> (por defecto type="button"; usá type="submit" en formularios).
 * Variantes: primary, secondary, ghost, seek, offer.
 */
import type { HTMLAttributes } from "astro/types";

type Variant = "primary" | "secondary" | "ghost" | "seek" | "offer";
type Size = "sm" | "md" | "lg";

type Props = {
  variant?: Variant;
  size?: Size;
  href?: string;
  block?: boolean;
  class?: string;
} & Omit<HTMLAttributes<"button">, "class"> &
  Omit<HTMLAttributes<"a">, "class" | "type">;

const {
  variant = "primary",
  size = "md",
  href,
  block = false,
  type = "button",
  class: className = "",
  ...rest
} = Astro.props;

const variants: Record<Variant, string> = {
  primary: "bg-brand text-brand-contrast hover:bg-brand-hover",
  secondary: "border border-line bg-surface text-ink hover:bg-surface-muted",
  ghost: "text-ink hover:bg-surface-muted",
  seek: "bg-seek text-white hover:opacity-90",
  offer: "bg-offer text-white hover:opacity-90",
};

const sizes: Record<Size, string> = {
  sm: "h-9 px-3 text-sm",
  md: "h-11 px-4 text-[0.95rem]",
  lg: "h-12 px-6 text-base",
};

const classes = [
  "inline-flex items-center justify-center gap-2 rounded-wl font-semibold transition-colors",
  "disabled:cursor-not-allowed disabled:opacity-60",
  variants[variant],
  sizes[size],
  block ? "w-full" : "",
  className,
];
---

{
  href ? (
    <a href={href} class:list={classes} {...rest}>
      <slot />
    </a>
  ) : (
    <button type={type} class:list={classes} {...rest}>
      <slot />
    </button>
  )
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/ui/Field.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Campo de formulario accesible: etiqueta, input, ayuda y error vinculados
 * por aria-describedby. Acepta cualquier atributo nativo de <input>.
 */
import type { HTMLAttributes } from "astro/types";

type Props = {
  name: string;
  label: string;
  error?: string | undefined;
  hint?: string;
  class?: string;
} & Omit<HTMLAttributes<"input">, "name" | "class">;

const { name, label, error, hint, class: className = "", id = name, ...inputProps } = Astro.props;

const hintId = hint ? `${id}-hint` : undefined;
const errorId = error ? `${id}-error` : undefined;
const describedBy = [hintId, errorId].filter(Boolean).join(" ") || undefined;
---

<div class:list={["flex flex-col gap-1.5", className]}>
  <label for={id} class="text-sm font-medium text-ink">{label}</label>
  <input
    id={id}
    name={name}
    aria-invalid={error ? "true" : undefined}
    aria-describedby={describedBy}
    class:list={[
      "h-11 w-full rounded-wl border bg-surface px-3 text-base text-ink placeholder:text-ink-muted/70",
      "transition-colors focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25",
      error ? "border-danger" : "border-line",
    ]}
    {...inputProps}
  />
  {hint && !error && <p id={hintId} class="text-xs text-ink-muted">{hint}</p>}
  {error && <p id={errorId} class="text-sm text-danger" role="alert">{error}</p>}
</div>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/ui/SelectField.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Select nativo accesible (funciona sin JavaScript y es cómodo en celulares). */
import type { HTMLAttributes } from "astro/types";

interface Option {
  value: string | number;
  label: string;
}

type Props = {
  name: string;
  label: string;
  options: Option[];
  value?: string | number | null;
  placeholder?: string;
  error?: string | undefined;
  hint?: string;
  class?: string;
} & Omit<HTMLAttributes<"select">, "name" | "class" | "value">;

const { name, label, options, value, placeholder, error, hint, class: className = "", id = name, ...rest } = Astro.props;
const current = value === null || value === undefined ? "" : String(value);
---

<div class:list={["flex flex-col gap-1.5", className]}>
  <label for={id} class="text-sm font-medium text-ink">{label}</label>
  <select
    id={id}
    name={name}
    aria-invalid={error ? "true" : undefined}
    class:list={[
      "h-11 w-full rounded-wl border bg-surface px-3 text-base text-ink",
      "focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25",
      error ? "border-danger" : "border-line",
    ]}
    {...rest}
  >
    {placeholder && <option value="" selected={current === ""}>{placeholder}</option>}
    {options.map((option) => (
      <option value={option.value} selected={String(option.value) === current}>{option.label}</option>
    ))}
  </select>
  {hint && !error && <p class="text-xs text-ink-muted">{hint}</p>}
  {error && <p class="text-sm text-danger" role="alert">{error}</p>}
</div>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/ui/TextArea.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Área de texto accesible, con contador opcional de caracteres máximos. */
import type { HTMLAttributes } from "astro/types";

type Props = {
  name: string;
  label: string;
  value?: string | null;
  error?: string | undefined;
  hint?: string;
  class?: string;
} & Omit<HTMLAttributes<"textarea">, "name" | "class" | "value">;

const { name, label, value, error, hint, class: className = "", id = name, rows = 4, ...rest } = Astro.props;
const hintId = hint ? `${id}-hint` : undefined;
const errorId = error ? `${id}-error` : undefined;
const describedBy = [hintId, errorId].filter(Boolean).join(" ") || undefined;
---

<div class:list={["flex flex-col gap-1.5", className]}>
  <label for={id} class="text-sm font-medium text-ink">{label}</label>
  <textarea
    id={id}
    name={name}
    rows={rows}
    aria-invalid={error ? "true" : undefined}
    aria-describedby={describedBy}
    class:list={[
      "w-full rounded-wl border bg-surface px-3 py-2.5 text-base text-ink placeholder:text-ink-muted/70",
      "focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25",
      error ? "border-danger" : "border-line",
    ]}
    {...rest}>{value ?? ""}</textarea>
  {hint && !error && <p id={hintId} class="text-xs text-ink-muted">{hint}</p>}
  {error && <p id={errorId} class="text-sm text-danger" role="alert">{error}</p>}
</div>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/config/brand.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Identidad de marca de WorkLink (provisional).
 *
 * Nombre, textos y rutas del logo viven SOLO acá y en /public/brand.
 * Los colores y la tipografía están en src/styles/global.css (variables --wl-*).
 */
export const brand = {
  name: "WorkLink",
  shortName: "WorkLink",
  tagline: "Conectamos lo que necesitás con quien lo ofrece",
  description:
    "Encontrá emprendedores, profesionales, productos y servicios cerca tuyo, o publicá lo que necesitás y recibí propuestas. Empezamos en Córdoba.",
  logo: {
    /** Logo con texto (cabeceras). */
    full: "/brand/logo.svg",
    /** Solo el símbolo (favicon, avatares de la plataforma). */
    mark: "/brand/mark.svg",
  },
  /** Color principal para la barra del navegador en móviles. */
  themeColor: "#2f4fd8",
  locale: "es_AR",
  social: {
    instagram: null as string | null,
  },
} as const;

export type Brand = typeof brand;
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/config/media.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/config/site.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Configuración de rutas y navegación del sitio.
 */
export const routes = {
  home: "/",
  login: "/ingresar",
  signup: "/registrarse",
  forgotPassword: "/recuperar",
  resetPassword: "/cuenta/nueva-contrasena",
  authConfirm: "/auth/confirm",
  dashboard: "/panel",
  admin: "/admin",
} as const;

/**
 * Prefijos que requieren sesión. El middleware redirige al login si no hay
 * usuario, y vuelve a la página pedida después de ingresar.
 */
export const protectedPrefixes = ["/panel", "/cuenta", "/admin"] as const;

/** Prefijos que además requieren rol de staff (moderator o superior). */
export const staffPrefixes = ["/admin"] as const;

/**
 * Valida una ruta interna de redirección (?next=...). Evita redirecciones
 * abiertas a otros dominios ("//evil.com", "https://...").
 */
export function safeNextPath(value: string | null | undefined, fallback: string = routes.dashboard): string {
  if (!value) return fallback;
  if (!value.startsWith("/") || value.startsWith("//") || value.startsWith("/\\")) return fallback;
  return value;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/env.d.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/// <reference types="astro/client" />

import type { SupabaseClient } from "@supabase/supabase-js";
import type { SessionUser } from "./lib/auth/session";

declare global {
  namespace App {
    interface Locals {
      /** Cliente de Supabase con la sesión de esta request (RLS aplica). */
      supabase: SupabaseClient;
      /** Usuario autenticado, o null si es un visitante. */
      user: SessionUser | null;
    }
  }
}

export {};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/islands/CityPicker.tsx' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Selector de ciudad con autocompletado (isla Preact, combobox accesible).
 * Escribe en un <input type="hidden" name={name}> el id de la ciudad.
 * Busca sin importar tildes: "villa maria", "rio cuarto"...
 */
import { useEffect, useId, useRef, useState } from "preact/hooks";

interface City {
  id: number;
  name: string;
  province_name: string;
}

interface Props {
  name: string;
  label: string;
  initialCity?: City | null;
  error?: string;
  hint?: string;
  required?: boolean;
}

export default function CityPicker({ name, label, initialCity = null, error, hint, required }: Props) {
  const id = useId();
  const listId = `${id}-list`;
  const [selected, setSelected] = useState<City | null>(initialCity);
  const [query, setQuery] = useState(initialCity ? display(initialCity) : "");
  const [results, setResults] = useState<City[]>([]);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const [loading, setLoading] = useState(false);
  const timer = useRef<number>();
  const controller = useRef<AbortController>();

  useEffect(() => () => window.clearTimeout(timer.current), []);

  function search(text: string) {
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(async () => {
      controller.current?.abort();
      controller.current = new AbortController();
      setLoading(true);
      try {
        const res = await fetch(`/api/ciudades?q=${encodeURIComponent(text)}`, { signal: controller.current.signal });
        const json = (await res.json()) as { results: City[] };
        setResults(json.results);
        setActive(json.results.length ? 0 : -1);
        setOpen(true);
      } catch {
        /* búsqueda cancelada o sin conexión */
      } finally {
        setLoading(false);
      }
    }, 200);
  }

  function choose(city: City) {
    setSelected(city);
    setQuery(display(city));
    setOpen(false);
  }

  return (
    <div class="relative flex flex-col gap-1.5">
      <label for={id} class="text-sm font-medium text-ink">
        {label}
      </label>
      <input type="hidden" name={name} value={selected ? String(selected.id) : ""} />
      <input
        id={id}
        type="text"
        role="combobox"
        autocomplete="off"
        aria-autocomplete="list"
        aria-expanded={open}
        aria-controls={listId}
        aria-activedescendant={open && active >= 0 ? `${listId}-${active}` : undefined}
        aria-invalid={error ? "true" : undefined}
        required={required}
        placeholder="Escribí tu ciudad, por ejemplo Villa María"
        value={query}
        class={[
          "h-11 w-full rounded-wl border bg-surface px-3 text-base text-ink placeholder:text-ink-muted/70",
          "focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25",
          error ? "border-danger" : "border-line",
        ].join(" ")}
        onFocus={() => search(selected ? "" : query)}
        onInput={(event) => {
          const text = (event.currentTarget as HTMLInputElement).value;
          setQuery(text);
          setSelected(null);
          search(text);
        }}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown") {
            event.preventDefault();
            setOpen(true);
            setActive((i) => Math.min(i + 1, results.length - 1));
          } else if (event.key === "ArrowUp") {
            event.preventDefault();
            setActive((i) => Math.max(i - 1, 0));
          } else if (event.key === "Enter" && open && active >= 0 && results[active]) {
            event.preventDefault();
            choose(results[active]);
          } else if (event.key === "Escape") {
            setOpen(false);
          }
        }}
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
      />

      {open && (
        <ul
          id={listId}
          role="listbox"
          class="absolute top-full z-20 mt-1 max-h-64 w-full overflow-auto rounded-wl border border-line bg-surface py-1 shadow-lg"
        >
          {results.length === 0 ? (
            <li class="px-3 py-2 text-sm text-ink-muted">{loading ? "Buscando…" : "No encontramos esa ciudad."}</li>
          ) : (
            results.map((city, index) => (
              <li
                id={`${listId}-${index}`}
                key={city.id}
                role="option"
                aria-selected={index === active}
                class={[
                  "cursor-pointer px-3 py-2 text-sm",
                  index === active ? "bg-seek-soft text-ink" : "text-ink hover:bg-surface-muted",
                ].join(" ")}
                onMouseDown={(event) => {
                  event.preventDefault();
                  choose(city);
                }}
              >
                <span class="font-medium">{city.name}</span>
                <span class="text-ink-muted">, {city.province_name}</span>
              </li>
            ))
          )}
        </ul>
      )}

      {hint && !error && <p class="text-xs text-ink-muted">{hint}</p>}
      {error && (
        <p class="text-sm text-danger" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

function display(city: City) {
  return `${city.name}, ${city.province_name}`;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/islands/ImageUploader.tsx' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/islands/PostMediaUploader.tsx' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
            📷 {items.length ? "Agregar fotos" : "Subir fotos"}
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
            🎬 Subir un video
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/islands/lib/image.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/layouts/AuthLayout.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Layout de las pantallas de cuenta (ingresar, registrarse, recuperar):
 * tarjeta centrada, sin distracciones, y siempre noindex.
 */
import BaseLayout from "./BaseLayout.astro";

interface Props {
  title: string;
  heading: string;
  subheading?: string;
}

const { title, heading, subheading } = Astro.props;
---

<BaseLayout title={title} noindex>
  <section class="mx-auto flex w-full max-w-md flex-col px-4 py-10 sm:py-16">
    <div class="rounded-wl-lg border border-line bg-surface p-6 shadow-sm sm:p-8">
      <h1 class="text-2xl font-bold">{heading}</h1>
      {subheading && <p class="mt-1.5 text-ink-muted">{subheading}</p>}
      <div class="mt-6">
        <slot />
      </div>
    </div>
    <div class="mt-6 text-center text-sm text-ink-muted">
      <slot name="footer" />
    </div>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/layouts/BaseLayout.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Layout base de todas las páginas: <head> con SEO (title, description,
 * canonical, Open Graph, Twitter), favicon, color de tema y estructura
 * Header / contenido / Footer.
 */
import "../styles/global.css";
import Header from "../components/layout/Header.astro";
import Footer from "../components/layout/Footer.astro";
import { brand } from "../config/brand";

export interface Props {
  /** Título de la página, sin el nombre de la marca. */
  title?: string;
  description?: string;
  /** Ruta canónica si difiere de la URL actual (sin query string). */
  canonicalPath?: string;
  /** Páginas privadas o sin valor para buscadores. */
  noindex?: boolean;
  /** Imagen para compartir (URL absoluta o ruta pública). */
  image?: string;
  /** Oculta Header y Footer (pantallas enfocadas). */
  bare?: boolean;
}

const { title, description = brand.description, canonicalPath, noindex = false, image, bare = false } = Astro.props;

const fullTitle = title ? `${title} · ${brand.name}` : `${brand.name} · ${brand.tagline}`;
const site = Astro.site ?? new URL(Astro.url.origin);
const canonical = new URL(canonicalPath ?? Astro.url.pathname, site).toString();
const ogImage = image ? new URL(image, site).toString() : undefined;
---

<!doctype html>
<html lang="es-AR">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <title>{fullTitle}</title>
    <meta name="description" content={description} />
    <link rel="canonical" href={canonical} />
    {noindex && <meta name="robots" content="noindex, nofollow" />}

    <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
    <meta name="theme-color" content={brand.themeColor} />
    <meta name="generator" content={Astro.generator} />

    <meta property="og:type" content="website" />
    <meta property="og:site_name" content={brand.name} />
    <meta property="og:locale" content={brand.locale} />
    <meta property="og:title" content={fullTitle} />
    <meta property="og:description" content={description} />
    <meta property="og:url" content={canonical} />
    {ogImage && <meta property="og:image" content={ogImage} />}
    <meta name="twitter:card" content={ogImage ? "summary_large_image" : "summary"} />
    <meta name="twitter:title" content={fullTitle} />
    <meta name="twitter:description" content={description} />

    <slot name="head" />
  </head>
  <body class="flex min-h-dvh flex-col">
    <a
      href="#contenido"
      class="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:rounded-wl focus:bg-surface focus:px-4 focus:py-2"
    >
      Saltar al contenido
    </a>
    {!bare && <Header />}
    <main id="contenido" class="flex-1">
      <slot />
    </main>
    {!bare && <Footer />}
  </body>
</html>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/layouts/PanelLayout.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Layout del área privada: navegación del panel + contenido. Siempre noindex. */
import BaseLayout from "./BaseLayout.astro";

interface Props {
  title: string;
  heading?: string;
  description?: string;
  /** Enlace "volver" opcional sobre el título. */
  back?: { href: string; label: string };
}

const { title, heading = title, description, back } = Astro.props;
const path = Astro.url.pathname;

const links = [
  { href: "/panel", label: "Inicio", active: path === "/panel" },
  { href: "/panel/perfil", label: "Mi perfil", active: path.startsWith("/panel/perfil") },
  { href: "/panel/publicaciones", label: "Publicaciones", active: path.startsWith("/panel/publicaciones") },
  { href: "/panel/guardados", label: "Guardados", active: path.startsWith("/panel/guardados") },
  { href: "/panel/emprendimientos", label: "Emprendimientos", active: path.startsWith("/panel/emprendimientos") },
];
---

<BaseLayout title={title} noindex>
  <div class="border-b border-line bg-surface">
    <nav aria-label="Panel" class="mx-auto flex max-w-5xl gap-1 overflow-x-auto px-4">
      {
        links.map((link) => (
          <a
            href={link.href}
            aria-current={link.active ? "page" : undefined}
            class:list={[
              "whitespace-nowrap border-b-2 px-3 py-3 text-sm font-medium transition-colors",
              link.active ? "border-brand text-ink" : "border-transparent text-ink-muted hover:text-ink",
            ]}
          >
            {link.label}
          </a>
        ))
      }
    </nav>
  </div>

  <section class="mx-auto max-w-5xl px-4 py-8">
    {back && <a href={back.href} class="mb-3 inline-block text-sm font-medium text-ink-muted hover:text-ink">← {back.label}</a>}
    <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold sm:text-3xl">{heading}</h1>
        {description && <p class="mt-1 text-ink-muted">{description}</p>}
      </div>
      <slot name="actions" />
    </div>
    <slot />
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/auth/errors.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { ActionError } from "astro:actions";
import type { AuthError } from "@supabase/supabase-js";

/**
 * Traduce errores de Supabase Auth a mensajes en español y a códigos de
 * Astro Actions. No revela si un email existe o no (evita enumerar cuentas).
 */
export function toActionError(error: AuthError, fallback = "No pudimos completar la operación. Probá de nuevo."): ActionError {
  switch (error.code) {
    case "invalid_credentials":
      return new ActionError({ code: "UNAUTHORIZED", message: "Email o contraseña incorrectos." });
    case "email_not_confirmed":
      return new ActionError({
        code: "FORBIDDEN",
        message: "Tenés que confirmar tu email. Revisá tu bandeja de entrada (y la carpeta de spam).",
      });
    case "weak_password":
      return new ActionError({
        code: "BAD_REQUEST",
        message: "La contraseña es muy débil o aparece en filtraciones conocidas. Elegí otra.",
      });
    case "same_password":
      return new ActionError({ code: "BAD_REQUEST", message: "La nueva contraseña tiene que ser distinta de la anterior." });
    case "over_email_send_rate_limit":
    case "over_request_rate_limit":
    case "over_sms_send_rate_limit":
      return new ActionError({
        code: "TOO_MANY_REQUESTS",
        message: "Hiciste demasiados intentos. Esperá unos minutos y volvé a probar.",
      });
    case "user_already_exists":
    case "email_exists":
      return new ActionError({
        code: "CONFLICT",
        message: "Ya hay una cuenta con ese email. Ingresá o recuperá tu contraseña.",
      });
    case "signup_disabled":
      return new ActionError({ code: "FORBIDDEN", message: "El registro está deshabilitado temporalmente." });
    case "user_banned":
      return new ActionError({ code: "FORBIDDEN", message: "Esta cuenta está suspendida." });
    case "session_not_found":
    case "session_expired":
      return new ActionError({ code: "UNAUTHORIZED", message: "Tu sesión venció. Ingresá de nuevo." });
    default:
      console.error("[auth]", error.code, error.message);
      return new ActionError({ code: "INTERNAL_SERVER_ERROR", message: fallback });
  }
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/auth/guards.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { ActionError } from "astro:actions";
import type { SessionUser } from "./session";

/** Exige sesión dentro de una Astro Action. */
export function requireUser(user: SessionUser | null): SessionUser {
  if (!user) {
    throw new ActionError({ code: "UNAUTHORIZED", message: "Tu sesión venció. Ingresá de nuevo." });
  }
  return user;
}

/** Traduce errores de PostgreSQL / PostgREST a mensajes para el usuario. */
export function dbError(error: { code?: string; message?: string; hint?: string | null }, fallback: string): ActionError {
  if (error.hint === "rate_limited" || error.hint === "quota_exceeded") {
    return new ActionError({ code: "TOO_MANY_REQUESTS", message: error.message ?? fallback });
  }
  switch (error.code) {
    case "42501": // permiso denegado (RLS o trigger de protección)
      return new ActionError({ code: "FORBIDDEN", message: "No tenés permiso para hacer este cambio." });
    case "23514": // check constraint / validación de trigger
      return new ActionError({ code: "BAD_REQUEST", message: error.message?.startsWith("new row") ? fallback : (error.message ?? fallback) });
    default:
      console.error("[db]", error.code, error.message);
      return new ActionError({ code: "INTERNAL_SERVER_ERROR", message: fallback });
  }
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/auth/session.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";

/** Datos mínimos del usuario autenticado disponibles en cada request. */
export interface SessionUser {
  id: string;
  email: string | null;
}

/**
 * Obtiene el usuario de la sesión verificando el JWT.
 *
 * `getClaims()` valida la firma del token (localmente si el proyecto usa
 * claves asimétricas, o contra Auth si no) y no confía en datos de cookies
 * sin verificar. Nunca usar `getSession()` para decidir permisos en el servidor.
 */
export async function getSessionUser(supabase: SupabaseClient): Promise<SessionUser | null> {
  const { data, error } = await supabase.auth.getClaims();
  if (error || !data?.claims?.sub) return null;

  return {
    id: data.claims.sub,
    email: typeof data.claims.email === "string" ? data.claims.email : null,
  };
}

/** Nivel mínimo de staff. El orden coincide con el enum staff_role de la base. */
export type StaffRole = "moderator" | "admin" | "super_admin";

/**
 * ¿El usuario actual tiene al menos el rol indicado?
 * Consulta la base (función has_role), no el frontend: la fuente de verdad
 * es user_roles, protegida por RLS.
 */
export async function hasRole(supabase: SupabaseClient, minRole: StaffRole): Promise<boolean> {
  const { data, error } = await supabase.rpc("has_role", { min_role: minRole });
  if (error) return false;
  return data === true;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/contact.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Normalización de datos de contacto: la gente escribe "351 15-555-1234",
 * "@mi.negocio" o "instagram.com/mi.negocio/". Acá se guardan en un formato
 * único y se arman los enlaces.
 */

/**
 * Teléfonos argentinos a formato internacional "+549XXXXXXXXXX" (móvil).
 * Acepta: "+54 9 351 555-1234", "0351 15 555-1234", "3515551234".
 * Devuelve null si no se puede interpretar.
 */
export function normalizeArgentinePhone(input: string, { mobile = true } = {}): string | null {
  let digits = input.replace(/\D/g, "");
  if (!digits) return null;
  if (digits.startsWith("00")) digits = digits.slice(2);

  if (digits.startsWith("54")) {
    digits = digits.slice(2);
    if (digits.startsWith("9")) digits = digits.slice(1);
  }
  if (digits.startsWith("0")) digits = digits.slice(1);

  // "351 15 5551234" -> "351 5551234": el 15 va después de la característica.
  const withFifteen = /^(\d{2,4})15(\d{6,8})$/.exec(digits);
  if (withFifteen && withFifteen[1].length + withFifteen[2].length === 10) {
    digits = withFifteen[1] + withFifteen[2];
  }

  if (digits.length !== 10) return null;
  return mobile ? `+549${digits}` : `+54${digits}`;
}

/** Enlace de WhatsApp a partir del número normalizado. */
export function whatsappUrl(phone: string, message?: string): string {
  const base = `https://wa.me/${phone.replace(/\D/g, "")}`;
  return message ? `${base}?text=${encodeURIComponent(message)}` : base;
}

/** "@mi.negocio", "instagram.com/mi.negocio" -> "mi.negocio" */
export function normalizeHandle(input: string, host: "instagram.com" | "tiktok.com"): string | null {
  let value = input.trim();
  if (!value) return null;
  value = value.replace(/^https?:\/\//i, "").replace(/^www\./i, "");
  if (value.toLowerCase().startsWith(host)) value = value.slice(host.length);
  value = value.replace(/^\/+/, "").replace(/^@/, "").split(/[/?#]/)[0] ?? "";
  return /^[A-Za-z0-9._]{1,40}$/.test(value) ? value : null;
}

/** Facebook: acepta usuario o URL de página. Devuelve la URL completa. */
export function normalizeFacebook(input: string): string | null {
  const value = input.trim();
  if (!value) return null;
  if (/^https?:\/\/(www\.|m\.)?facebook\.com\/.+/i.test(value)) return value.slice(0, 120);
  if (/^(www\.|m\.)?facebook\.com\/.+/i.test(value)) return `https://${value}`.slice(0, 120);
  if (/^[A-Za-z0-9.]{3,60}$/.test(value)) return `https://facebook.com/${value}`;
  return null;
}

/** Sitio web: agrega https:// si falta y valida que sea una URL. */
export function normalizeWebsite(input: string): string | null {
  const value = input.trim();
  if (!value) return null;
  const withProtocol = /^https?:\/\//i.test(value) ? value : `https://${value}`;
  try {
    const url = new URL(withProtocol);
    if (!url.hostname.includes(".")) return null;
    return url.toString().slice(0, 200);
  } catch {
    return null;
  }
}

export const instagramUrl = (handle: string) => `https://instagram.com/${handle}`;
export const tiktokUrl = (handle: string) => `https://www.tiktok.com/@${handle}`;
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/feed-params.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { PostType } from "../schemas/post";
import { decodeCursor, type Cursor } from "../services/posts";

/**
 * Parámetros del feed /publicaciones, compartidos por la página completa y el
 * fragmento de "Cargar más":
 *   ?tipo=busco      filtra por tipo
 *   ?ver=siguiendo   solo cuentas que sigue el usuario (requiere sesión)
 *   ?desde=...       cursor de la página siguiente
 */
export const TYPE_SLUGS: Record<string, PostType> = {
  ofrezco: "offer",
  busco: "seeking",
  productos: "product",
  servicios: "service",
  promociones: "promotion",
};

export interface FeedParams {
  tipo: string;
  type: PostType | null;
  following: boolean;
  cursor: Cursor | null;
  /** Arma el query string conservando los filtros actuales ("" o "?..."). */
  query: (extra?: Record<string, string>) => string;
}

export function parseFeedParams(url: URL): FeedParams {
  const following = url.searchParams.get("ver") === "siguiendo";
  const rawTipo = url.searchParams.get("tipo") ?? "";
  const type = following ? null : (TYPE_SLUGS[rawTipo] ?? null);
  const tipo = type ? rawTipo : "";
  const cursor = decodeCursor(url.searchParams.get("desde"));

  const query = (extra: Record<string, string> = {}) => {
    const params = new URLSearchParams({
      ...(following ? { ver: "siguiendo" } : {}),
      ...(type ? { tipo } : {}),
      ...extra,
    }).toString();
    return params ? `?${params}` : "";
  };

  return { tipo, type, following, cursor, query };
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/format.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Formatos para Argentina: pesos, números y fechas en es-AR, mostrados en la
 * zona horaria de Córdoba (la base guarda todo en UTC).
 */
const TIME_ZONE = "America/Argentina/Cordoba";

const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 2 });
const moneyRound = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 });
const number = new Intl.NumberFormat("es-AR");

export function formatMoney(amount: number | string | null | undefined): string {
  if (amount === null || amount === undefined || amount === "") return "";
  const value = typeof amount === "string" ? Number(amount) : amount;
  if (!Number.isFinite(value)) return "";
  return Number.isInteger(value) ? moneyRound.format(value) : money.format(value);
}

export type PriceType = "fixed" | "from" | "ask";

/** "$ 12.500" · "Desde $ 350.000" · "Consultar precio" */
export function formatPrice(amount: number | string | null | undefined, priceType: PriceType): string {
  if (priceType === "ask" || amount === null || amount === undefined) return "Consultar precio";
  const formatted = formatMoney(amount);
  return priceType === "from" ? `Desde ${formatted}` : formatted;
}

export function formatNumber(value: number): string {
  return number.format(value);
}

export function formatDate(value: string | Date, options: Intl.DateTimeFormatOptions = { dateStyle: "long" }): string {
  return new Intl.DateTimeFormat("es-AR", { timeZone: TIME_ZONE, ...options }).format(new Date(value));
}

/** "Miembro desde octubre de 2026" */
export function formatMonthYear(value: string | Date): string {
  return new Intl.DateTimeFormat("es-AR", { timeZone: TIME_ZONE, month: "long", year: "numeric" }).format(new Date(value));
}

/** Convierte "12.500,50" o "12500.5" en 12500.5. Devuelve null si no es un número válido. */
export function parseArgentineAmount(input: string): number | null {
  const raw = input.replace(/[$\s]/g, "").trim();
  if (!raw) return null;
  let normalized = raw;
  if (raw.includes(",")) {
    normalized = raw.replace(/\./g, "").replace(",", ".");
  } else if (/^\d{1,3}(\.\d{3})+$/.test(raw)) {
    normalized = raw.replace(/\./g, "");
  }
  if (!/^\d+(\.\d{1,2})?$/.test(normalized)) return null;
  const value = Number(normalized);
  return Number.isFinite(value) ? value : null;
}

/**
 * "Villa María, Córdoba" · "Córdoba capital" (cuando la ciudad se llama igual
 * que la provincia, para no repetir "Córdoba, Córdoba").
 */
export function formatLocation(city: { name: string; province_name: string } | null | undefined): string | null {
  if (!city) return null;
  if (city.name === city.province_name) return `${city.name} capital`;
  return city.province_name ? `${city.name}, ${city.province_name}` : city.name;
}

const relative = new Intl.RelativeTimeFormat("es-AR", { numeric: "auto" });

/** "hace 5 minutos", "ayer", "hace 3 días"; más de 30 días: fecha corta. */
export function formatRelative(value: string | Date, now: Date = new Date()): string {
  const date = new Date(value);
  const seconds = Math.round((date.getTime() - now.getTime()) / 1000);
  const abs = Math.abs(seconds);
  if (abs < 60) return "recién";
  if (abs < 3600) return relative.format(Math.round(seconds / 60), "minute");
  if (abs < 86400) return relative.format(Math.round(seconds / 3600), "hour");
  if (abs < 86400 * 30) return relative.format(Math.round(seconds / 86400), "day");
  return formatDate(date, { day: "numeric", month: "short", year: date.getFullYear() === now.getFullYear() ? undefined : "numeric" });
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/media.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { PUBLIC_SUPABASE_URL } from "astro:env/client";
import { mediaPresets, type MediaPurpose } from "../config/media";

/**
 * Único lugar que arma URLs de imágenes. Si mañana se usa un CDN de imágenes
 * o las transformaciones de Supabase, se cambia solo esta función.
 */
export function mediaUrl(purpose: MediaPurpose, basePath: string | null | undefined, width?: number): string | null {
  if (!basePath) return null;
  const preset = mediaPresets[purpose];
  const size = width
    ? (preset.sizes.find((s) => s >= width) ?? preset.sizes[preset.sizes.length - 1])
    : preset.sizes[preset.sizes.length - 1];
  return `${PUBLIC_SUPABASE_URL}/storage/v1/object/public/${preset.bucket}/${basePath}/${size}.webp`;
}

/** srcset con todas las variantes, para <img srcset sizes>. */
export function mediaSrcSet(purpose: MediaPurpose, basePath: string | null | undefined): string | undefined {
  if (!basePath) return undefined;
  const preset = mediaPresets[purpose];
  return preset.sizes
    .map((size) => `${PUBLIC_SUPABASE_URL}/storage/v1/object/public/${preset.bucket}/${basePath}/${size}.webp ${size}w`)
    .join(", ");
}

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const basePathPattern = new RegExp(`^(${UUID})/(${UUID})$`);

/**
 * ¿La carpeta de imagen tiene el formato correcto y pertenece al usuario?
 * Evita que alguien guarde en su perfil la imagen de otra persona.
 */
export function isOwnMediaPath(basePath: string, userId: string): boolean {
  const match = basePathPattern.exec(basePath);
  return Boolean(match && match[1] === userId);
}

/** Rutas de todos los archivos de una imagen (para borrarla de Storage). */
export function mediaFiles(purpose: MediaPurpose, basePath: string): string[] {
  return mediaPresets[purpose].sizes.map((size) => `${basePath}/${size}.webp`);
}

/** URL pública de un archivo cualquiera de post-media (video o portada). */
export function postFileUrl(basePath: string, fileName: string): string {
  return `${PUBLIC_SUPABASE_URL}/storage/v1/object/public/post-media/${basePath}/${fileName}`;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/post-media.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { PostMediaItem } from "../islands/PostMediaUploader";
import type { PostView } from "../services/posts";
import { mediaUrl, postFileUrl } from "./media";

/** Archivos guardados de una publicación, en el formato del componente de subida. */
export function mediaItemsFromPost(post: PostView): PostMediaItem[] {
  return post.media.map((m) => ({
    id: m.id,
    path: m.path,
    kind: m.kind,
    mime: m.mime,
    bytes: m.bytes,
    width: m.width ?? 1,
    height: m.height ?? 1,
    duration: m.duration_s ?? undefined,
    preview: m.kind === "image" ? (mediaUrl("post", m.path, 480) ?? "") : postFileUrl(m.path, "poster.webp"),
  }));
}

/** Archivos enviados en un formulario con error (para no perder lo subido). */
export function mediaItemsFromSubmitted(raw: FormDataEntryValue | null): PostMediaItem[] {
  if (typeof raw !== "string" || !raw) return [];
  try {
    const list = JSON.parse(raw) as Omit<PostMediaItem, "preview">[];
    if (!Array.isArray(list)) return [];
    return list.slice(0, 10).map((item) => ({
      ...item,
      preview: item.kind === "image" ? (mediaUrl("post", item.path, 480) ?? "") : postFileUrl(item.path, "poster.webp"),
    }));
  } catch {
    return [];
  }
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/seo/business.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { Business, CatalogItem } from "../../types/domain";
import { WEEK_DAYS } from "../../schemas/business";
import { mediaUrl } from "../media";
import { instagramUrl, tiktokUrl } from "../contact";

const SCHEMA_DAYS: Record<string, string> = {
  mon: "Monday",
  tue: "Tuesday",
  wed: "Wednesday",
  thu: "Thursday",
  fri: "Friday",
  sat: "Saturday",
  sun: "Sunday",
};

/**
 * Datos estructurados schema.org (LocalBusiness) para la página pública.
 * No incluye teléfono ni WhatsApp (son privados para visitantes).
 * AggregateRating solo cuando haya reseñas reales (Etapa 11).
 */
export function businessJsonLd(business: Business, url: string, catalog: { services: CatalogItem[]; products: CatalogItem[] }) {
  const sameAs = [
    business.instagram && instagramUrl(business.instagram),
    business.tiktok && tiktokUrl(business.tiktok),
    business.facebook,
    business.website,
  ].filter(Boolean);

  const openingHours = WEEK_DAYS.flatMap(({ key }) =>
    (business.hours?.[key] ?? []).map(([opens, closes]) => ({
      "@type": "OpeningHoursSpecification",
      dayOfWeek: SCHEMA_DAYS[key],
      opens,
      closes,
    })),
  );

  const offers = [...catalog.services, ...catalog.products]
    .filter((item) => item.price !== null && item.price_type !== "ask")
    .slice(0, 20)
    .map((item) => ({
      "@type": "Offer",
      name: item.name,
      price: Number(item.price),
      priceCurrency: item.currency,
    }));

  return {
    "@context": "https://schema.org",
    "@type": "LocalBusiness",
    "@id": `${url}#business`,
    name: business.name,
    url,
    description: business.tagline ?? business.description?.slice(0, 300) ?? undefined,
    image: mediaUrl("cover", business.cover_path) ?? mediaUrl("logo", business.logo_path) ?? undefined,
    logo: mediaUrl("logo", business.logo_path) ?? undefined,
    address: business.city
      ? {
          "@type": "PostalAddress",
          addressLocality: business.city.name,
          addressRegion: business.city.province_name,
          addressCountry: "AR",
        }
      : undefined,
    sameAs: sameAs.length ? sameAs : undefined,
    openingHoursSpecification: openingHours.length ? openingHours : undefined,
    makesOffer: offers.length ? offers : undefined,
    aggregateRating:
      business.rating_count > 0
        ? {
            "@type": "AggregateRating",
            ratingValue: (business.rating_sum / business.rating_count).toFixed(1),
            reviewCount: business.rating_count,
          }
        : undefined,
  };
}

export function breadcrumbJsonLd(items: { name: string; url: string }[]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: item.url,
    })),
  };
}

/** Serializa JSON-LD de forma segura dentro de <script> (evita cerrar la etiqueta). */
export function jsonLdScript(data: unknown): string {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/supabase/admin.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { createClient } from "@supabase/supabase-js";
import { PUBLIC_SUPABASE_URL } from "astro:env/client";
import { getSecret } from "astro:env/server";

/**
 * Cliente con la service role key: SALTEA todas las políticas RLS.
 * Solo para tareas del sistema (cron, webhooks). Nunca usarlo para responder
 * pedidos de usuarios ni importarlo desde código que llegue al navegador.
 */
export function createSupabaseAdminClient() {
  const key = getSecret("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) throw new Error("Falta la variable SUPABASE_SERVICE_ROLE_KEY en el servidor.");
  return createClient(PUBLIC_SUPABASE_URL, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/supabase/server.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { createServerClient, parseCookieHeader } from "@supabase/ssr";
import type { AstroCookies } from "astro";
import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from "astro:env/client";

/**
 * Crea un cliente de Supabase para UNA request del servidor.
 *
 * - Lee la sesión desde las cookies httpOnly de la request.
 * - Cuando Supabase renueva el token, escribe las cookies nuevas en la
 *   respuesta y guarda los headers anti-caché en `responseHeaders` para que el
 *   middleware los aplique (una respuesta con cookies de sesión nunca debe
 *   quedar en la CDN).
 *
 * Usa la clave pública: todas las consultas pasan por RLS con la identidad
 * del usuario. Nunca reutilizar un cliente entre requests.
 */
export function createSupabaseServerClient(options: {
  request: Request;
  cookies: AstroCookies;
  responseHeaders?: Headers;
}) {
  const { request, cookies, responseHeaders } = options;

  return createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return parseCookieHeader(request.headers.get("Cookie") ?? "").map(({ name, value }) => ({
          name,
          value: value ?? "",
        }));
      },
      setAll(cookiesToSet, headers) {
        for (const { name, value, options: cookieOptions } of cookiesToSet) {
          cookies.set(name, value, {
            ...cookieOptions,
            path: cookieOptions?.path ?? "/",
            httpOnly: true,
            secure: import.meta.env.PROD,
            sameSite: "lax",
          });
        }
        if (responseHeaders) {
          for (const [key, value] of Object.entries(headers ?? {})) {
            responseHeaders.set(key, value);
          }
        }
      },
    },
    auth: {
      flowType: "pkce",
    },
  });
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/lib/urls.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { slugify } from "../utils/slug";

/**
 * URLs públicas. La de una publicación lleva un texto legible y el id al final:
 * /p/busco-fotografo-para-casamiento-6f1c...  (lo único que importa es el id).
 */
export function postPath(post: { id: string; title: string | null; body: string }): string {
  const words = slugify((post.title || post.body).slice(0, 80), 60);
  return `/p/${words ? `${words}-` : ""}${post.id}`;
}

/** Extrae el id del final de /p/[ref]. */
export function postIdFromRef(ref: string | undefined): string | null {
  const match = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/.exec(ref ?? "");
  return match ? match[1] : null;
}

export const businessPath = (slug: string) => `/e/${slug}`;
export const profilePath = (username: string) => `/u/${username}`;
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/middleware/index.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { defineMiddleware } from "astro:middleware";
import { createSupabaseServerClient } from "../lib/supabase/server";
import { getSessionUser, hasRole } from "../lib/auth/session";
import { protectedPrefixes, routes, staffPrefixes } from "../config/site";

const matchesPrefix = (pathname: string, prefixes: readonly string[]) =>
  prefixes.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`));

/**
 * Middleware global:
 *  1. Crea el cliente de Supabase de la request y resuelve el usuario.
 *  2. Protege /panel, /cuenta y /admin (sesión), y /admin (rol de staff).
 *  3. Aplica headers de seguridad y evita que la CDN guarde respuestas
 *     personalizadas o con cookies de sesión.
 *
 * Las páginas prerenderizadas (estáticas) no pasan por acá en producción.
 */
export const onRequest = defineMiddleware(async (context, next) => {
  if (context.isPrerendered) {
    return next();
  }

  const authHeaders = new Headers();
  const supabase = createSupabaseServerClient({
    request: context.request,
    cookies: context.cookies,
    responseHeaders: authHeaders,
  });

  context.locals.supabase = supabase;
  context.locals.user = await getSessionUser(supabase);

  const { pathname, search } = context.url;
  const isProtected = matchesPrefix(pathname, protectedPrefixes);

  if (isProtected && !context.locals.user) {
    const next = encodeURIComponent(pathname + search);
    return context.redirect(`${routes.login}?next=${next}`);
  }

  if (matchesPrefix(pathname, staffPrefixes) && !(await hasRole(supabase, "moderator"))) {
    return new Response("No tenés permiso para ver esta página.", {
      status: 403,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  // Copia mutable: las respuestas de redirección tienen headers inmutables.
  const original = await next();
  const response = new Response(original.body, original);

  // Headers que @supabase/ssr pide cuando renovó la sesión (no cachear).
  authHeaders.forEach((value, key) => response.headers.set(key, value));

  // Lo privado o personalizado nunca se guarda en caches compartidas.
  if (isProtected || context.locals.user) {
    response.headers.set("Cache-Control", "private, no-store");
  }

  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(self)");

  return response;
});
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/404.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import BaseLayout from "../layouts/BaseLayout.astro";
import Button from "../components/ui/Button.astro";

// Se renderiza en el servidor (no prerender) para que las páginas dinámicas
// puedan mostrarla con Astro.rewrite("/404") cuando algo no existe.
Astro.response.status = 404;
---

<BaseLayout title="Página no encontrada" noindex>
  <section class="mx-auto max-w-xl px-4 py-20 text-center">
    <p class="text-sm font-semibold text-ink-muted">Error 404</p>
    <h1 class="mt-2 text-3xl font-bold">No encontramos esta página</h1>
    <p class="mt-3 text-ink-muted">Puede que el enlace esté mal escrito o que el contenido ya no exista.</p>
    <div class="mt-8">
      <Button href="/">Volver al inicio</Button>
    </div>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/admin/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Panel administrativo (Etapa 12). El middleware ya verificó sesión y rol
 * de staff contra la base; acá solo se muestra el rol actual.
 */
import BaseLayout from "../../layouts/BaseLayout.astro";

const { supabase, user } = Astro.locals;
const { data: role } = await supabase.from("user_roles").select("role").eq("user_id", user!.id).maybeSingle();

const roleLabel: Record<string, string> = {
  moderator: "Moderación",
  admin: "Administración",
  super_admin: "Super administración",
};
---

<BaseLayout title="Administración" noindex>
  <section class="mx-auto max-w-6xl px-4 py-10">
    <p class="text-sm font-semibold uppercase tracking-wider text-ink-muted">
      {role ? roleLabel[role.role] ?? role.role : "Staff"}
    </p>
    <h1 class="mt-2 text-3xl font-bold">Panel administrativo</h1>
    <p class="mt-2 max-w-2xl text-ink-muted">
      Acá van a estar el dashboard, la moderación, las categorías propuestas y las métricas. Se construye en la Etapa 12.
    </p>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/api/ciudades.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { APIRoute } from "astro";

/**
 * Autocompletado de ciudades: GET /api/ciudades?q=villa%20ma&provincia=14
 * Responde como máximo 10 resultados. Es información pública y cambia poco:
 * se cachea en la CDN.
 */
export const GET: APIRoute = async ({ url, locals }) => {
  const q = (url.searchParams.get("q") ?? "").trim().slice(0, 60);
  const province = Number(url.searchParams.get("provincia"));

  const { data, error } = await locals.supabase.rpc("search_cities", {
    q,
    p_province_id: Number.isInteger(province) && province > 0 ? province : null,
    max_results: 10,
  });

  if (error) {
    console.error("[api/ciudades]", error.message);
    return Response.json({ results: [] }, { status: 500 });
  }

  return Response.json(
    { results: data ?? [] },
    { headers: { "Cache-Control": "public, max-age=300, s-maxage=3600, stale-while-revalidate=86400" } },
  );
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/api/cron/limpiar-archivos.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/api/uploads/sign.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
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
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/auth/confirm.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { APIRoute } from "astro";
import type { EmailOtpType } from "@supabase/supabase-js";
import { routes, safeNextPath } from "../../config/site";

const OTP_TYPES: EmailOtpType[] = ["signup", "email", "recovery", "invite", "magiclink", "email_change"];

/**
 * Destino de los enlaces de los emails de Supabase (confirmar cuenta,
 * recuperar contraseña). Abre la sesión y redirige a `next`.
 *
 * Acepta dos formatos:
 *  - ?token_hash=...&type=...  (plantillas de email personalizadas; funciona
 *    aunque el enlace se abra en otro dispositivo o navegador)
 *  - ?code=...                 (flujo PKCE por defecto de Supabase; requiere
 *    abrir el enlace en el mismo navegador donde se pidió)
 */
export const GET: APIRoute = async ({ url, locals, redirect }) => {
  const next = safeNextPath(url.searchParams.get("next"));
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type") as EmailOtpType | null;
  const code = url.searchParams.get("code");

  if (tokenHash && type && OTP_TYPES.includes(type)) {
    const { error } = await locals.supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) return redirect(type === "recovery" ? routes.resetPassword : next);
    console.error("[auth/confirm] verifyOtp", error.code, error.message);
  } else if (code) {
    const { error } = await locals.supabase.auth.exchangeCodeForSession(code);
    if (!error) return redirect(next);
    console.error("[auth/confirm] exchangeCode", error.code, error.message);
  }

  return redirect(`${routes.login}?error=link`);
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/buscar.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Buscador (provisional). El buscador real con Full Text Search, filtros y
 * paginación llega en la Etapa 7. Las búsquedas nunca se indexan.
 */
import BaseLayout from "../layouts/BaseLayout.astro";
import Button from "../components/ui/Button.astro";
import { routes } from "../config/site";

const q = (Astro.url.searchParams.get("q") ?? "").trim().slice(0, 120);
---

<BaseLayout title={q ? `Buscar “${q}”` : "Buscar"} noindex canonicalPath="/buscar">
  <section class="mx-auto max-w-3xl px-4 py-16 text-center">
    <h1 class="text-3xl font-bold">Estamos preparando el buscador</h1>
    <p class="mt-3 text-ink-muted">
      {q ? <>Muy pronto vas a poder encontrar resultados para <strong class="text-ink">“{q}”</strong>.</> : "Muy pronto vas a poder buscar emprendedores, productos, servicios y necesidades."}
      Mientras tanto, creá tu cuenta para ser de los primeros.
    </p>
    <div class="mt-8 flex justify-center gap-3">
      <Button href={routes.signup}>Crear cuenta</Button>
      <Button href={routes.home} variant="secondary">Volver al inicio</Button>
    </div>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/cuenta/nueva-contrasena.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Elegir nueva contraseña. Se llega desde el email de recuperación: el enlace
 * pasa por /auth/confirm, que abre la sesión y redirige acá. Ruta protegida
 * por el middleware (/cuenta/*).
 */
import { actions, isInputError } from "astro:actions";
import AuthLayout from "../../layouts/AuthLayout.astro";
import Field from "../../components/ui/Field.astro";
import Button from "../../components/ui/Button.astro";
import Alert from "../../components/ui/Alert.astro";
import { routes } from "../../config/site";

const result = Astro.getActionResult(actions.auth.updatePassword);
if (result && !result.error) {
  return Astro.redirect(`${routes.dashboard}?password=updated`);
}

const fieldErrors = result?.error && isInputError(result.error) ? result.error.fields : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;
---

<AuthLayout title="Nueva contraseña" heading="Elegí una nueva contraseña">
  {formError && <Alert tone="danger" class="mb-5">{formError}</Alert>}

  <form method="POST" action={actions.auth.updatePassword} class="flex flex-col gap-4" novalidate>
    <Field
      name="password"
      label="Nueva contraseña"
      type="password"
      autocomplete="new-password"
      required
      minlength={8}
      maxlength={72}
      hint="Mínimo 8 caracteres, con al menos una letra y un número."
      error={fieldErrors.password?.[0]}
    />
    <Field
      name="password_confirm"
      label="Repetí la contraseña"
      type="password"
      autocomplete="new-password"
      required
      error={fieldErrors.password_confirm?.[0]}
    />
    <Button type="submit" block size="lg">Guardar contraseña</Button>
  </form>
</AuthLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/e/[slug].astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Página pública de un emprendimiento: /e/[slug]
 * Indexable si está publicado. Los datos de contacto directo solo se cargan
 * para usuarios logueados (la base ni siquiera los entrega a visitantes).
 */
import BaseLayout from "../../layouts/BaseLayout.astro";
import Avatar from "../../components/ui/Avatar.astro";
import Button from "../../components/ui/Button.astro";
import HoursTable from "../../components/business/HoursTable.astro";
import CatalogItemCard from "../../components/business/CatalogItemCard.astro";
import PostCard from "../../components/posts/PostCard.astro";
import FollowButton from "../../components/social/FollowButton.astro";
import { followersLabel, getViewerReactions, isFollowing } from "../../services/social";
import { getFeed } from "../../services/posts";
import { getBusinessBySlug, getCatalog } from "../../services/businesses";
import { mediaSrcSet, mediaUrl } from "../../lib/media";
import { instagramUrl, tiktokUrl, whatsappUrl } from "../../lib/contact";
import { formatLocation, formatMonthYear } from "../../lib/format";
import { breadcrumbJsonLd, businessJsonLd, jsonLdScript } from "../../lib/seo/business";
import { routes } from "../../config/site";

const { supabase, user } = Astro.locals;
const slug = (Astro.params.slug ?? "").toLowerCase();
if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) return Astro.rewrite("/404");

const business = await getBusinessBySlug(supabase, slug, { withContact: Boolean(user) });
if (!business) return Astro.rewrite("/404");

const { data: membership } = user
  ? await supabase.from("business_members").select("role").eq("business_id", business.id).eq("user_id", user.id).maybeSingle()
  : { data: null };
const canEdit = Boolean(membership);

const [catalog, { posts: businessPosts }, following] = await Promise.all([
  getCatalog(supabase, business.id, { onlyPublic: true }),
  getFeed(supabase, { businessId: business.id, limit: 6 }),
  isFollowing(supabase, user?.id, "business", business.id),
]);
const reactions = await getViewerReactions(supabase, user?.id, businessPosts.map((p) => p.id));
const isPublic = business.status === "active";

const site = Astro.site ?? new URL(Astro.url.origin);
const url = new URL(`/e/${business.slug}`, site).toString();
const location = formatLocation(business.city);
const title = [business.name, business.category?.name, business.city?.name].filter(Boolean).join(" · ");
const description =
  business.tagline ??
  business.description?.slice(0, 155) ??
  `${business.name}: ${business.category?.name ?? "emprendimiento"}${location ? ` en ${location}` : ""}. Contactalo en WorkLink.`;

const hasHours = business.hours && Object.keys(business.hours).length > 0;
const cover = mediaUrl("cover", business.cover_path, 1600);
const waMessage = `Hola ${business.name}, te encontré en WorkLink.`;
const loginToContact = `${routes.login}?next=${encodeURIComponent(`/e/${business.slug}`)}`;

const jsonLd = [
  businessJsonLd(business, url, catalog),
  breadcrumbJsonLd([
    // Las páginas de categoría se suman al breadcrumb en la Etapa 7.
    { name: "Inicio", url: new URL("/", site).toString() },
    { name: business.name, url },
  ]),
];
---

<BaseLayout title={title} description={description} canonicalPath={`/e/${business.slug}`} noindex={!isPublic} image={cover ?? undefined}>
  {isPublic && jsonLd.map((data) => <script slot="head" type="application/ld+json" set:html={jsonLdScript(data)} />)}

  {
    !isPublic && (
      <div class="border-b border-warning/30 bg-warning-soft">
        <p class="mx-auto max-w-5xl px-4 py-2 text-sm">
          {business.status === "draft" && "Borrador: solo lo ve tu equipo."}
          {business.status === "inactive" && "Pausado: no es visible para el público."}
          {business.status === "suspended" && "Suspendido por moderación."}
        </p>
      </div>
    )
  }

  <article>
    <div class="mx-auto max-w-5xl px-0 sm:px-4 sm:pt-6">
      <div class="aspect-[3/1] w-full overflow-hidden bg-gradient-to-br from-seek-soft to-offer-soft sm:rounded-wl-lg">
        {cover && (
          <img
            src={cover}
            srcset={mediaSrcSet("cover", business.cover_path)}
            sizes="(min-width: 1024px) 992px, 100vw"
            width="1600"
            height="533"
            alt=""
            fetchpriority="high"
            class="h-full w-full object-cover"
          />
        )}
      </div>
    </div>

    <div class="mx-auto max-w-5xl px-4">
      <header class="flex flex-col gap-3 sm:flex-row sm:items-end sm:gap-5">
        <Avatar name={business.name} path={business.logo_path} purpose="logo" shape="rounded" size={96} priority class="-mt-12 border-4 border-bg sm:-mt-14 sm:ml-6" />
        <div class="min-w-0 flex-1">
          <h1 class="flex flex-wrap items-center gap-2 text-2xl font-bold sm:text-3xl">
            {business.name}
            {business.verification === "verified" && (
              <span class="inline-flex items-center gap-1 rounded-full bg-seek-soft px-2 py-0.5 text-xs font-semibold text-seek" title="Emprendedor verificado por WorkLink">
                ✓ Verificado
              </span>
            )}
          </h1>
          <p class="mt-1 text-ink-muted">
            {[business.category?.name, location].filter(Boolean).join(" · ")}
          </p>
          <p class="mt-1 text-sm text-ink-muted">
            <span data-followers={business.id}>{followersLabel(business.followers_count)}</span>
            {business.posts_count > 0 && <span> · {business.posts_count} {business.posts_count === 1 ? "publicación" : "publicaciones"}</span>}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          {!canEdit && isPublic && <FollowButton kind="business" id={business.id} following={following} returnTo={`/e/${business.slug}`} />}
          <Button href="#contacto" class="lg:hidden">Contactar</Button>
          {canEdit && <Button href={`/panel/emprendimientos/${business.id}`} variant="secondary">Editar</Button>}
        </div>
      </header>

      <div class="mt-8 grid gap-8 lg:grid-cols-[1fr_320px]">
        <div class="flex min-w-0 flex-col gap-10">
          {(business.tagline || business.description) && (
            <section>
              {business.tagline && <p class="text-lg font-medium">{business.tagline}</p>}
              {business.description && <p class="mt-3 whitespace-pre-line text-ink-muted">{business.description}</p>}
            </section>
          )}

          {business.subcategories.length > 0 && (
            <section aria-label="Especialidades">
              <ul class="flex flex-wrap gap-2">
                {business.subcategories.map((sub) => (
                  <li class="rounded-full border border-line bg-surface px-3 py-1 text-sm">{sub.name}</li>
                ))}
              </ul>
            </section>
          )}

          {catalog.services.length > 0 && (
            <section>
              <h2 class="mb-4 text-xl font-semibold">Servicios</h2>
              <div class="grid gap-3">
                {catalog.services.map((item) => <CatalogItemCard item={item} />)}
              </div>
            </section>
          )}

          {catalog.products.length > 0 && (
            <section>
              <h2 class="mb-4 text-xl font-semibold">Productos</h2>
              <div class="grid gap-3 sm:grid-cols-2">
                {catalog.products.map((item) => <CatalogItemCard item={item} />)}
              </div>
            </section>
          )}

          {(businessPosts.length > 0 || canEdit) && (
            <section>
              <div class="mb-4 flex items-center justify-between gap-4">
                <h2 class="text-xl font-semibold">Publicaciones</h2>
                {canEdit && <Button href={`/panel/publicaciones/nueva?emprendimiento=${business.id}`} variant="secondary" size="sm">Publicar</Button>}
              </div>
              {businessPosts.length > 0 ? (
                <div class="grid items-start gap-4 sm:grid-cols-2">
                  {businessPosts.map((post) => <PostCard post={post} liked={reactions.liked.has(post.id)} saved={reactions.saved.has(post.id)} />)}
                </div>
              ) : (
                <p class="text-ink-muted">Todavía no hay publicaciones.</p>
              )}
            </section>
          )}

          {catalog.services.length === 0 && catalog.products.length === 0 && !business.description && businessPosts.length === 0 && (
            <p class="text-ink-muted">Este emprendimiento todavía está armando su página.</p>
          )}
        </div>

        <aside class="flex flex-col gap-6 lg:sticky lg:top-24 lg:self-start">
          <section id="contacto" class="scroll-mt-20 rounded-wl-lg border border-line bg-surface p-5">
            <h2 class="font-semibold">Contacto</h2>
            {user ? (
              <div class="mt-4 flex flex-col gap-2">
                {business.whatsapp && (
                  <Button href={whatsappUrl(business.whatsapp, waMessage)} variant="primary" block target="_blank" rel="noopener nofollow">
                    Escribir por WhatsApp
                  </Button>
                )}
                {business.phone && (
                  <Button href={`tel:${business.phone}`} variant="secondary" block>Llamar</Button>
                )}
                {business.email && (
                  <Button href={`mailto:${business.email}`} variant="secondary" block>Enviar email</Button>
                )}
                {!business.whatsapp && !business.phone && !business.email && (
                  <p class="text-sm text-ink-muted">Todavía no cargó datos de contacto.</p>
                )}
              </div>
            ) : (
              <div class="mt-3 flex flex-col gap-3">
                <p class="text-sm text-ink-muted">Ingresá para ver el WhatsApp y el teléfono.</p>
                <Button href={loginToContact} block>Ingresar para contactar</Button>
                <a href={routes.signup} class="text-center text-sm font-medium text-brand hover:underline">Crear cuenta gratis</a>
              </div>
            )}

            {(business.instagram || business.facebook || business.tiktok || business.website) && (
              <ul class="mt-5 flex flex-col gap-2 border-t border-line pt-4 text-sm">
                {business.instagram && <li><a href={instagramUrl(business.instagram)} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">Instagram: @{business.instagram}</a></li>}
                {business.facebook && <li><a href={business.facebook} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">Facebook</a></li>}
                {business.tiktok && <li><a href={tiktokUrl(business.tiktok)} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">TikTok: @{business.tiktok}</a></li>}
                {business.website && <li><a href={business.website} target="_blank" rel="noopener nofollow" class="break-all text-brand hover:underline">{business.website.replace(/^https?:\/\//, "").replace(/\/$/, "")}</a></li>}
              </ul>
            )}
          </section>

          {(hasHours || business.availability) && (
            <section class="rounded-wl-lg border border-line bg-surface p-5">
              <h2 class="mb-2 font-semibold">Horarios</h2>
              {hasHours && <HoursTable hours={business.hours!} />}
              {business.availability && <p class="mt-3 text-sm text-ink-muted">{business.availability}</p>}
            </section>
          )}

          <p class="px-1 text-xs text-ink-muted">En WorkLink desde {formatMonthYear(business.created_at)}.</p>
        </aside>
      </div>
    </div>
  </article>
  <div class="h-16"></div>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Home provisional de WorkLink: explica el concepto (necesito / ofrezco) y
 * lleva al buscador o al registro. El buscador real llega en la Etapa 7.
 */
import BaseLayout from "../layouts/BaseLayout.astro";
import Button from "../components/ui/Button.astro";
import { routes } from "../config/site";
import PostCard from "../components/posts/PostCard.astro";
import { getFeed } from "../services/posts";
import { getViewerReactions } from "../services/social";

const user = Astro.locals.user;
const { posts: latest } = await getFeed(Astro.locals.supabase, { limit: 6 });
const reactions = await getViewerReactions(Astro.locals.supabase, Astro.locals.user?.id, latest.map((p) => p.id));

const seekExamples = ["Fotógrafo para un casamiento", "Electricista", "Tortas personalizadas", "Diseño de logo"];
const offerExamples = ["Desarrollo web", "Pastelería", "Ropa personalizada", "Clases particulares"];
---

<BaseLayout>
  <section class="mx-auto max-w-6xl px-4 pb-12 pt-10 sm:pt-16">
    <p class="text-sm font-semibold uppercase tracking-wider text-ink-muted">Córdoba, Argentina</p>
    <h1 class="mt-3 max-w-3xl text-4xl font-extrabold leading-[1.05] sm:text-6xl">
      Lo que <span class="text-seek">necesitás</span>, con quien lo <span class="text-offer">ofrece</span>.
    </h1>
    <p class="mt-5 max-w-2xl text-lg text-ink-muted">
      Encontrá emprendedores, profesionales, productos y servicios cerca tuyo. O publicá lo que buscás y recibí
      propuestas.
    </p>

    <form action="/buscar" method="GET" role="search" class="mt-8 flex max-w-2xl flex-col gap-2 sm:flex-row">
      <label for="q" class="sr-only">¿Qué estás buscando?</label>
      <input
        id="q"
        name="q"
        type="search"
        placeholder="¿Qué estás buscando? Ej.: fotógrafo en Córdoba"
        autocomplete="off"
        enterkeyhint="search"
        class="h-13 w-full rounded-wl border border-line bg-surface px-4 text-base shadow-sm focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25"
      />
      <Button type="submit" size="lg" class="h-13 shrink-0">Buscar</Button>
    </form>
  </section>

  <section class="mx-auto grid max-w-6xl gap-4 px-4 pb-16 md:grid-cols-2" aria-label="Cómo usar WorkLink">
    <article class="flex flex-col rounded-wl-lg border border-line bg-seek-soft p-6 sm:p-8">
      <h2 class="text-2xl font-bold">¿Qué estás buscando?</h2>
      <p class="mt-2 text-ink-muted">
        Buscá entre emprendedores de tu zona o publicá tu necesidad y dejá que te lleguen las propuestas.
      </p>
      <ul class="mt-5 flex flex-wrap gap-2" aria-label="Ejemplos">
        {seekExamples.map((example) => (
          <li>
            <a
              href={`/buscar?q=${encodeURIComponent(example)}`}
              class="inline-block rounded-full border border-seek/25 bg-surface px-3 py-1.5 text-sm hover:border-seek"
            >
              Busco {example.toLowerCase()}
            </a>
          </li>
        ))}
      </ul>
      <div class="mt-auto pt-6">
        <Button href={user ? routes.dashboard : `${routes.signup}?intent=seeker`} variant="seek">
          Publicar una necesidad
        </Button>
      </div>
    </article>

    <article class="flex flex-col rounded-wl-lg border border-line bg-offer-soft p-6 sm:p-8">
      <h2 class="text-2xl font-bold">¿Qué ofrecés?</h2>
      <p class="mt-2 text-ink-muted">
        Creá el perfil de tu emprendimiento, mostrá tus trabajos y encontrá personas que necesitan lo que hacés.
      </p>
      <ul class="mt-5 flex flex-wrap gap-2" aria-label="Ejemplos">
        {offerExamples.map((example) => (
          <li class="rounded-full border border-offer/25 bg-surface px-3 py-1.5 text-sm">Ofrezco {example.toLowerCase()}</li>
        ))}
      </ul>
      <div class="mt-auto pt-6">
        <Button href={user ? routes.dashboard : `${routes.signup}?intent=provider`} variant="offer">
          Crear mi emprendimiento
        </Button>
      </div>
    </article>
  </section>

  {
    latest.length > 0 && (
      <section class="mx-auto max-w-6xl px-4 pb-20" aria-labelledby="ultimas">
        <div class="mb-5 flex items-end justify-between gap-4">
          <h2 id="ultimas" class="text-2xl font-bold">Últimas publicaciones</h2>
          <a href="/publicaciones" class="text-sm font-semibold text-brand hover:underline">Ver todas →</a>
        </div>
        <div class="grid items-start gap-4 md:grid-cols-2 lg:grid-cols-3">
          {latest.map((post) => <PostCard post={post} liked={reactions.liked.has(post.id)} saved={reactions.saved.has(post.id)} />)}
        </div>
      </section>
    )
  }
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/ingresar.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import { actions, isInputError } from "astro:actions";
import AuthLayout from "../layouts/AuthLayout.astro";
import Field from "../components/ui/Field.astro";
import Button from "../components/ui/Button.astro";
import Alert from "../components/ui/Alert.astro";
import { routes, safeNextPath } from "../config/site";
import { getSubmittedValues } from "../utils/form";

const next = safeNextPath(Astro.url.searchParams.get("next"));

// Si ya hay sesión, no tiene sentido mostrar el login.
if (Astro.locals.user) {
  return Astro.redirect(next);
}

const result = Astro.getActionResult(actions.auth.signIn);
if (result && !result.error) {
  return Astro.redirect(result.data.redirectTo);
}

const fieldErrors = result?.error && isInputError(result.error) ? result.error.fields : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;

const values = result?.error ? await getSubmittedValues(Astro.request) : {};
const linkError = Astro.url.searchParams.get("error") === "link";
const passwordChanged = Astro.url.searchParams.get("password") === "updated";
---

<AuthLayout title="Ingresar" heading="Ingresá a WorkLink" subheading="Qué bueno verte de nuevo.">
  {linkError && (
    <Alert tone="warning" class="mb-5">
      El enlace venció o ya se usó. Ingresá con tu contraseña o pedí uno nuevo.
    </Alert>
  )}
  {passwordChanged && (
    <Alert tone="success" class="mb-5">Listo, cambiaste tu contraseña.</Alert>
  )}
  {formError && <Alert tone="danger" class="mb-5">{formError}</Alert>}

  <form method="POST" action={actions.auth.signIn} class="flex flex-col gap-4" novalidate>
    <input type="hidden" name="next" value={next} />
    <Field
      name="email"
      value={values.email}
      label="Email"
      type="email"
      autocomplete="email"
      inputmode="email"
      required
      error={fieldErrors.email?.[0]}
    />
    <Field
      name="password"
      label="Contraseña"
      type="password"
      autocomplete="current-password"
      required
      error={fieldErrors.password?.[0]}
    />
    <div class="-mt-1 text-right text-sm">
      <a href={routes.forgotPassword} class="font-medium text-brand hover:underline">¿Olvidaste tu contraseña?</a>
    </div>
    <Button type="submit" block size="lg">Ingresar</Button>
  </form>

  <Fragment slot="footer">
    ¿Todavía no tenés cuenta?
    <a href={routes.signup} class="font-semibold text-brand hover:underline">Creala gratis</a>
  </Fragment>
</AuthLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/p/[ref].astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Página pública de una publicación: /p/texto-legible-<id>
 * Si el texto de la URL no coincide con el actual, redirige (301) a la URL
 * canónica: así los enlaces viejos siguen funcionando y Google ve una sola.
 */
import { actions, isInputError } from "astro:actions";
import BaseLayout from "../../layouts/BaseLayout.astro";
import Avatar from "../../components/ui/Avatar.astro";
import Button from "../../components/ui/Button.astro";
import PostCard from "../../components/posts/PostCard.astro";
import PostActions from "../../components/social/PostActions.astro";
import FollowButton from "../../components/social/FollowButton.astro";
import CommentsSection from "../../components/social/CommentsSection.astro";
import { getComments, getViewerReactions, isFollowing } from "../../services/social";
import { getFeed, getPost, POST_TYPE_LABELS, postHeadline } from "../../services/posts";
import { displayName } from "../../services/profiles";
import { mediaSrcSet, mediaUrl, postFileUrl } from "../../lib/media";
import { formatDate, formatMoney, formatRelative } from "../../lib/format";
import { businessPath, postIdFromRef, postPath, profilePath } from "../../lib/urls";
import { jsonLdScript } from "../../lib/seo/business";

const { supabase, user } = Astro.locals;
const id = postIdFromRef(Astro.params.ref);
if (!id) return Astro.rewrite("/404");

const post = await getPost(supabase, id);
if (!post) return Astro.rewrite("/404");

const canonical = postPath(post);
if (Astro.url.pathname !== canonical) return Astro.redirect(canonical, 301);

// Comentar / borrar comentario (formularios): si salió bien, volver a la
// publicación con GET (así recargar no reenvía el formulario).
const commentResult = Astro.getActionResult(actions.social.comment);
const removeResult = Astro.getActionResult(actions.social.removeComment);
if (commentResult && !commentResult.error) return Astro.redirect(`${canonical}#c-${commentResult.data.id}`, 303);
if (removeResult && !removeResult.error) return Astro.redirect(`${canonical}#comentarios`, 303);
const commentError = commentResult?.error
  ? { message: commentResult.error.message, fields: isInputError(commentResult.error) ? commentResult.error.fields : undefined }
  : removeResult?.error
    ? { message: removeResult.error.message }
    : null;
let draft: string | undefined;
if (commentResult?.error) {
  try {
    draft = String((await Astro.request.clone().formData()).get("body") ?? "");
  } catch {
    draft = undefined;
  }
}

const isPublic = post.status === "published";
const isOwner = user?.id === post.author_id;
const type = POST_TYPE_LABELS[post.type];
const headline = postHeadline(post, 70);
const authorName = post.business?.name ?? (post.author ? displayName(post.author) : "");
const authorHref = post.business ? businessPath(post.business.slug) : post.author ? profilePath(post.author.username) : null;
const site = Astro.site ?? new URL(Astro.url.origin);
const absoluteUrl = new URL(canonical, site).toString();

const cover = post.media[0];
const ogImage = cover ? (cover.kind === "image" ? mediaUrl("post", cover.path, 1600) : postFileUrl(cover.path, "poster.webp")) : null;
const description = post.body.replace(/\s+/g, " ").slice(0, 155);

const before = Astro.url.searchParams.get("comentarios_antes");
const [more, { comments, hasOlder }, following, canModerateComments] = await Promise.all([
  post.business_id
    ? getFeed(supabase, { businessId: post.business_id, limit: 4 }).then((r) => r.posts.filter((p) => p.id !== post.id).slice(0, 3))
    : Promise.resolve([]),
  getComments(supabase, post.id, { before }),
  user
    ? post.business_id
      ? isFollowing(supabase, user.id, "business", post.business_id)
      : isFollowing(supabase, user.id, "profile", post.author_id)
    : Promise.resolve(false),
  user ? supabase.rpc("can_edit_post", { p_post_id: post.id }).then((r) => Boolean(r.data)) : Promise.resolve(false),
]);
const reactions = await getViewerReactions(supabase, user?.id, [post.id, ...more.map((p) => p.id)]);
const olderHref = hasOlder && comments[0] ? `${canonical}?comentarios_antes=${encodeURIComponent(comments[0].created_at)}#comentarios` : null;
const showFollow = isPublic && !canModerateComments && user?.id !== post.author_id;

const shareText = `${headline} — en WorkLink`;
const whatsappShare = `https://wa.me/?text=${encodeURIComponent(`${shareText} ${absoluteUrl}`)}`;

const jsonLd =
  isPublic && post.type === "product" && post.price !== null
    ? {
        "@context": "https://schema.org",
        "@type": "Product",
        name: headline,
        description,
        image: ogImage ?? undefined,
        url: absoluteUrl,
        brand: post.business ? { "@type": "Brand", name: post.business.name } : undefined,
        offers: { "@type": "Offer", price: post.price, priceCurrency: post.currency, availability: "https://schema.org/InStock", url: absoluteUrl },
      }
    : null;
---

<BaseLayout title={headline} description={description} canonicalPath={canonical} noindex={!isPublic} image={ogImage ?? undefined}>
  {jsonLd && <script slot="head" type="application/ld+json" set:html={jsonLdScript(jsonLd)} />}

  <article class="mx-auto max-w-3xl px-4 py-6 sm:py-10">
    {!isPublic && (
      <p class="mb-4 rounded-wl border border-warning/30 bg-warning-soft px-4 py-2 text-sm">
        {post.status === "hidden" ? "Publicación oculta: solo la ven vos y tu equipo." : "Esta publicación fue removida por moderación."}
      </p>
    )}

    <header class="flex flex-wrap items-center gap-3">
      {authorHref && (
        <a href={authorHref} class="flex min-w-0 flex-1 basis-full items-center gap-3 sm:basis-0">
          <Avatar
            name={authorName}
            path={post.business?.logo_path ?? post.author?.avatar_path}
            purpose={post.business ? "logo" : "avatar"}
            shape={post.business ? "rounded" : "circle"}
            size={48}
          />
          <span class="min-w-0">
            <span class="block truncate font-semibold">{authorName}{post.business?.verification === "verified" && <span class="text-seek"> ✓</span>}</span>
            <span class="block text-sm text-ink-muted">
              <time datetime={post.published_at} title={formatDate(post.published_at, { dateStyle: "long", timeStyle: "short" })}>{formatRelative(post.published_at)}</time>
              {post.city && ` · ${post.city.name}`}
            </span>
          </span>
        </a>
      )}
      <span class:list={["rounded-full px-3 py-1 text-sm font-semibold", type.class]}>{type.label}</span>
      {showFollow && (
        <FollowButton
          kind={post.business_id ? "business" : "profile"}
          id={post.business_id ?? post.author_id}
          following={following}
          returnTo={canonical}
        />
      )}
    </header>

    {post.title && <h1 class="mt-6 text-2xl font-bold sm:text-3xl">{post.title}</h1>}
    {!post.title && <h1 class="sr-only">{headline}</h1>}

    {post.price !== null && <p class="mt-3 text-2xl font-bold">{formatMoney(post.price)}</p>}

    {
      post.media.length > 0 && (
        <div class="-mx-4 mt-6 sm:mx-0">
          {cover.kind === "video" ? (
            <video
              controls
              playsinline
              preload="none"
              poster={postFileUrl(cover.path, "poster.webp")}
              width={cover.width ?? undefined}
              height={cover.height ?? undefined}
              class="max-h-[80vh] w-full bg-black sm:rounded-wl-lg"
            >
              <source src={postFileUrl(cover.path, `video.${cover.mime === "video/webm" ? "webm" : "mp4"}`)} type={cover.mime} />
              Tu navegador no puede reproducir este video.
            </video>
          ) : (
            <div class="flex snap-x snap-mandatory gap-2 overflow-x-auto px-4 sm:px-0" aria-label={`${post.media.length} fotos`}>
              {post.media.map((m, index) => (
                <img
                  src={mediaUrl("post", m.path, 960)}
                  srcset={mediaSrcSet("post", m.path)}
                  sizes="(min-width: 768px) 720px, 92vw"
                  width={m.width ?? undefined}
                  height={m.height ?? undefined}
                  alt={`${headline} (foto ${index + 1} de ${post.media.length})`}
                  loading={index === 0 ? "eager" : "lazy"}
                  fetchpriority={index === 0 ? "high" : undefined}
                  decoding="async"
                  class:list={[
                    "max-h-[75vh] snap-center rounded-wl-lg bg-surface-muted object-contain",
                    post.media.length > 1 ? "w-[88%] shrink-0 sm:w-[85%]" : "w-full",
                  ]}
                />
              ))}
            </div>
          )}
          {post.media.length > 1 && <p class="mt-2 px-4 text-center text-xs text-ink-muted sm:px-0">Deslizá para ver las {post.media.length} fotos</p>}
        </div>
      )
    }

    <div class="mt-6 whitespace-pre-line text-lg leading-relaxed">{post.body}</div>

    {
      (post.category || post.tags.length > 0) && (
        <ul class="mt-6 flex flex-wrap gap-2 text-sm">
          {post.category && <li class="rounded-full border border-line bg-surface px-3 py-1">{post.subcategory?.name ?? post.category.name}</li>}
          {post.tags.map((tag) => <li class="rounded-full bg-surface-muted px-3 py-1 text-ink-muted">#{tag}</li>)}
        </ul>
      )
    }

    {isPublic && (
      <PostActions
        post={post}
        liked={reactions.liked.has(post.id)}
        saved={reactions.saved.has(post.id)}
        commentsHref="#comentarios"
        size="lg"
        class="mt-6 border-y border-line py-1"
      />
    )}

    <div class="mt-6 flex flex-wrap gap-2">
      {post.business ? (
        <Button href={`${businessPath(post.business.slug)}#contacto`} size="lg">Contactar a {post.business.name}</Button>
      ) : post.author ? (
        <Button href={profilePath(post.author.username)} size="lg">Ver perfil de {displayName(post.author)}</Button>
      ) : null}
      <Button href={whatsappShare} variant="secondary" size="lg" target="_blank" rel="noopener">Compartir por WhatsApp</Button>
      <Button variant="ghost" size="lg" data-share={absoluteUrl} data-share-title={shareText}>Copiar enlace</Button>
      {isOwner && <Button href={`/panel/publicaciones/${post.id}`} variant="ghost" size="lg">Editar</Button>}
    </div>

    <div class="mt-10">
      <CommentsSection
        postId={post.id}
        total={post.comments_count}
        comments={comments}
        olderHref={olderHref}
        canModerate={canModerateComments}
        open={isPublic}
        returnTo={canonical}
        error={commentError}
        draft={draft}
      />
    </div>
  </article>

  {
    more.length > 0 && post.business && (
      <section class="mx-auto max-w-5xl px-4 pb-16">
        <h2 class="mb-4 text-lg font-semibold">Más de {post.business.name}</h2>
        <div class="grid gap-4 md:grid-cols-3">
          {more.map((item) => <PostCard post={item} liked={reactions.liked.has(item.id)} saved={reactions.saved.has(item.id)} />)}
        </div>
      </section>
    )
  }
</BaseLayout>

<script>
  // Compartir: menú nativo del celular si existe; si no, copia el enlace.
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-share]")) {
    button.addEventListener("click", async () => {
      const url = button.dataset.share!;
      const title = button.dataset.shareTitle ?? document.title;
      try {
        if (navigator.share) {
          await navigator.share({ title, url });
          return;
        }
        await navigator.clipboard.writeText(url);
        const original = button.textContent;
        button.textContent = "¡Enlace copiado!";
        setTimeout(() => (button.textContent = original), 2000);
      } catch {
        /* el usuario canceló */
      }
    });
  }
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/emprendimientos/[id]/catalogo.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Servicios y productos de un emprendimiento. Cada acción vuelve a esta
 * página con un mensaje (?ok=...) para evitar reenvíos al recargar.
 */
import { actions, isInputError } from "astro:actions";
import PanelLayout from "../../../../layouts/PanelLayout.astro";
import Alert from "../../../../components/ui/Alert.astro";
import Button from "../../../../components/ui/Button.astro";
import CatalogItemForm from "../../../../components/business/CatalogItemForm.astro";
import { getBusinessForEdit, getCatalog } from "../../../../services/businesses";
import { formatPrice } from "../../../../lib/format";
import { getSubmittedForm } from "../../../../utils/form";
import type { CatalogItem } from "../../../../types/domain";

const { supabase } = Astro.locals;
const id = Astro.params.id ?? "";
if (!/^[0-9a-f-]{36}$/.test(id)) return Astro.rewrite("/404");

const base = `/panel/emprendimientos/${id}/catalogo`;
const results = {
  saveService: Astro.getActionResult(actions.catalog.saveService),
  saveProduct: Astro.getActionResult(actions.catalog.saveProduct),
  setStatus: Astro.getActionResult(actions.catalog.setStatus),
  remove: Astro.getActionResult(actions.catalog.remove),
};
const okMessages = { saveService: "servicio", saveProduct: "producto", setStatus: "visibilidad", remove: "eliminado" } as const;
for (const [key, res] of Object.entries(results)) {
  if (res && !res.error) return Astro.redirect(`${base}?ok=${okMessages[key as keyof typeof okMessages]}`);
}

const business = await getBusinessForEdit(supabase, id);
if (!business) return Astro.rewrite("/404");
const { services, products } = await getCatalog(supabase, id, { onlyPublic: false });

// Errores de formulario: a qué formulario pertenecen.
const failed = Object.entries(results).find(([, res]) => res?.error);
const failedKey = failed?.[0];
const failedError = failed?.[1]?.error;
const submitted = failedError ? await getSubmittedForm(Astro.request) : null;
const failedItemId = submitted ? String(submitted.get("item_id") ?? "") : "";
const fieldErrors = failedError && isInputError(failedError) ? (failedError.fields as Record<string, string[] | undefined>) : {};
const formError = failedError && !isInputError(failedError) ? failedError.message : null;

const formStateFor = (kind: "service" | "product", item?: CatalogItem) => {
  const key = kind === "service" ? "saveService" : "saveProduct";
  const matches = failedKey === key && (item ? failedItemId === item.id : !failedItemId);
  return matches ? { submitted, fieldErrors } : { submitted: null, fieldErrors: {} };
};

const ok = Astro.url.searchParams.get("ok");
const okText: Record<string, string> = {
  servicio: "Guardamos el servicio.",
  producto: "Guardamos el producto.",
  visibilidad: "Actualizamos la visibilidad.",
  eliminado: "Eliminamos el ítem.",
};
const created = Astro.url.searchParams.get("creado") === "1";

const sections = [
  { kind: "service" as const, title: "Servicios", items: services, action: actions.catalog.saveService, empty: "Todavía no cargaste servicios." },
  { kind: "product" as const, title: "Productos", items: products, action: actions.catalog.saveProduct, empty: "Todavía no cargaste productos." },
];
---

<PanelLayout
  title={`Catálogo · ${business.name}`}
  heading="Servicios y productos"
  description={business.name}
  back={{ href: `/panel/emprendimientos/${id}`, label: "Datos del emprendimiento" }}
>
  <Button slot="actions" href={`/e/${business.slug}`} variant="secondary" size="sm">Ver página pública</Button>

  {created && (
    <Alert tone="success" title="¡Tu emprendimiento ya está creado!" class="mb-6">
      Sumá tus servicios o productos con precio: es lo primero que mira la gente.
    </Alert>
  )}
  {ok && okText[ok] && <Alert tone="success" class="mb-6">{okText[ok]}</Alert>}
  {formError && <Alert tone="danger" class="mb-6">{formError}</Alert>}
  {Object.keys(fieldErrors).length > 0 && <Alert tone="danger" class="mb-6">Revisá los campos marcados en el formulario.</Alert>}

  <div class="grid gap-10">
    {
      sections.map((section) => {
        const newState = formStateFor(section.kind);
        return (
          <section class="flex flex-col gap-4">
            <h2 class="text-xl font-semibold">{section.title}</h2>

            {section.items.length === 0 ? (
              <p class="text-ink-muted">{section.empty}</p>
            ) : (
              <ul class="grid gap-3">
                {section.items.map((item) => {
                  const state = formStateFor(section.kind, item);
                  return (
                    <li class="rounded-wl-lg border border-line bg-surface">
                      <div class="flex flex-wrap items-center gap-3 p-4">
                        <div class="min-w-0 flex-1">
                          <p class="flex flex-wrap items-center gap-2 font-semibold">
                            {item.name}
                            {item.status === "hidden" && (
                              <span class="rounded-full bg-surface-muted px-2 py-0.5 text-xs font-medium text-ink-muted">Oculto</span>
                            )}
                          </p>
                          <p class="text-sm text-ink-muted">{formatPrice(item.price, item.price_type)}</p>
                        </div>
                        <form method="POST" action={actions.catalog.setStatus}>
                          <input type="hidden" name="business_id" value={id} />
                          <input type="hidden" name="item_id" value={item.id} />
                          <input type="hidden" name="kind" value={section.kind} />
                          <input type="hidden" name="status" value={item.status === "active" ? "hidden" : "active"} />
                          <Button type="submit" variant="ghost" size="sm">{item.status === "active" ? "Ocultar" : "Mostrar"}</Button>
                        </form>
                        <form method="POST" action={actions.catalog.remove} data-confirm={`¿Eliminar “${item.name}”?`}>
                          <input type="hidden" name="business_id" value={id} />
                          <input type="hidden" name="item_id" value={item.id} />
                          <input type="hidden" name="kind" value={section.kind} />
                          <Button type="submit" variant="ghost" size="sm" class="text-danger">Eliminar</Button>
                        </form>
                      </div>
                      <details class="border-t border-line px-4 py-3" open={Boolean(state.submitted)}>
                        <summary class="cursor-pointer text-sm font-semibold text-brand">Editar</summary>
                        <div class="pt-4">
                          <CatalogItemForm
                            kind={section.kind}
                            action={section.action}
                            businessId={id}
                            item={item}
                            submitted={state.submitted}
                            fieldErrors={state.fieldErrors}
                          />
                        </div>
                      </details>
                    </li>
                  );
                })}
              </ul>
            )}

            <details class="rounded-wl-lg border border-dashed border-line bg-surface p-4" open={section.items.length === 0 || Boolean(newState.submitted)}>
              <summary class="cursor-pointer font-semibold text-brand">
                {section.kind === "service" ? "+ Agregar servicio" : "+ Agregar producto"}
              </summary>
              <div class="pt-4">
                <CatalogItemForm
                  kind={section.kind}
                  action={section.action}
                  businessId={id}
                  submitted={newState.submitted}
                  fieldErrors={newState.fieldErrors}
                />
              </div>
            </details>
          </section>
        );
      })
    }
  </div>
</PanelLayout>

<script>
  // Confirmación antes de eliminar (sin JS, se elimina directamente).
  for (const form of document.querySelectorAll<HTMLFormElement>("form[data-confirm]")) {
    form.addEventListener("submit", (event) => {
      if (!window.confirm(form.dataset.confirm ?? "¿Confirmás?")) event.preventDefault();
    });
  }
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/emprendimientos/[id]/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import { actions, isInputError } from "astro:actions";
import PanelLayout from "../../../../layouts/PanelLayout.astro";
import Alert from "../../../../components/ui/Alert.astro";
import Button from "../../../../components/ui/Button.astro";
import Field from "../../../../components/ui/Field.astro";
import BusinessForm from "../../../../components/business/BusinessForm.astro";
import { getBusinessForEdit } from "../../../../services/businesses";
import { getCategoryTree } from "../../../../services/categories";
import { getCity } from "../../../../services/locations";
import { getSubmittedForm } from "../../../../utils/form";

const { supabase, user } = Astro.locals;
const id = Astro.params.id ?? "";
if (!/^[0-9a-f-]{36}$/.test(id)) return Astro.rewrite("/404");

const removeResult = Astro.getActionResult(actions.business.remove);
if (removeResult && !removeResult.error) return Astro.redirect("/panel/emprendimientos?eliminado=1");

const result = Astro.getActionResult(actions.business.update);
if (result && !result.error) return Astro.redirect(`/panel/emprendimientos/${id}?guardado=1`);

const business = await getBusinessForEdit(supabase, id);
if (!business) return Astro.rewrite("/404");

const { data: membership } = await supabase
  .from("business_members")
  .select("role")
  .eq("business_id", id)
  .eq("user_id", user!.id)
  .maybeSingle();
const isOwner = membership?.role === "owner";

const categories = await getCategoryTree(supabase);
const submitted = result?.error ? await getSubmittedForm(Astro.request) : null;
const fieldErrors = result?.error && isInputError(result.error) ? result.error.fields : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;
const submittedCityId = submitted ? Number(submitted.get("city_id")) : 0;
const city = submitted ? (submittedCityId ? await getCity(supabase, submittedCityId) : null) : business.city;
const removeError = removeResult?.error?.message;
---

<PanelLayout
  title={`Editar ${business.name}`}
  heading={business.name}
  description="Datos del emprendimiento"
  back={{ href: "/panel/emprendimientos", label: "Mis emprendimientos" }}
>
  <div slot="actions" class="flex gap-2">
    <Button href={`/e/${business.slug}`} variant="ghost" size="sm">Ver página</Button>
    <Button href={`/panel/emprendimientos/${id}/catalogo`} variant="secondary" size="sm">Servicios y productos</Button>
  </div>

  {Astro.url.searchParams.get("guardado") === "1" && <Alert tone="success" class="mb-6">Guardamos los cambios.</Alert>}
  {formError && <Alert tone="danger" class="mb-6">{formError}</Alert>}
  {Object.keys(fieldErrors).length > 0 && <Alert tone="danger" class="mb-6">Revisá los campos marcados.</Alert>}

  <div class="max-w-3xl">
    <BusinessForm
      action={actions.business.update}
      business={business}
      categories={categories}
      submitted={submitted}
      fieldErrors={fieldErrors as Record<string, string[] | undefined>}
      city={city}
      submitLabel="Guardar cambios"
    />

    {
      isOwner && (
        <details class="mt-12 rounded-wl-lg border border-danger/30 bg-surface p-5">
          <summary class="cursor-pointer font-semibold text-danger">Eliminar emprendimiento</summary>
          <p class="mt-3 text-sm text-ink-muted">
            Se quita de WorkLink junto con su catálogo. Esta acción no se puede deshacer desde el panel.
          </p>
          {removeError && <Alert tone="danger" class="mt-3">{removeError}</Alert>}
          <form method="POST" action={actions.business.remove} class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end">
            <input type="hidden" name="business_id" value={business.id} />
            <Field name="confirm" label="Escribí ELIMINAR para confirmar" autocomplete="off" class="sm:w-72" />
            <Button type="submit" variant="secondary" class="border-danger text-danger">Eliminar definitivamente</Button>
          </form>
        </details>
      )
    }
  </div>
</PanelLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/emprendimientos/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import PanelLayout from "../../../layouts/PanelLayout.astro";
import Button from "../../../components/ui/Button.astro";
import Alert from "../../../components/ui/Alert.astro";
import Avatar from "../../../components/ui/Avatar.astro";
import { getMyBusinesses } from "../../../services/businesses";

const { supabase, user } = Astro.locals;
const businesses = await getMyBusinesses(supabase, user!.id);
const removed = Astro.url.searchParams.get("eliminado") === "1";

const statusLabel = {
  active: { text: "Publicado", class: "bg-success-soft text-success" },
  draft: { text: "Borrador", class: "bg-surface-muted text-ink-muted" },
  inactive: { text: "Pausado", class: "bg-warning-soft text-warning" },
  suspended: { text: "Suspendido", class: "bg-danger-soft text-danger" },
} as const;
---

<PanelLayout title="Mis emprendimientos" description="Tus vidrieras en WorkLink.">
  <Button slot="actions" href="/panel/emprendimientos/nuevo" variant="offer">Crear emprendimiento</Button>

  {removed && <Alert tone="success" class="mb-6">Eliminamos el emprendimiento.</Alert>}

  {
    businesses.length === 0 ? (
      <div class="rounded-wl-lg border border-dashed border-line bg-surface p-8 text-center">
        <h2 class="text-lg font-semibold">Todavía no tenés emprendimientos</h2>
        <p class="mx-auto mt-1 max-w-md text-ink-muted">
          Creá la página de tu emprendimiento: servicios, productos, horarios y contacto, todo en un lugar.
        </p>
        <div class="mt-5">
          <Button href="/panel/emprendimientos/nuevo" variant="offer">Crear mi primer emprendimiento</Button>
        </div>
      </div>
    ) : (
      <ul class="grid gap-3">
        {businesses.map((b) => (
          <li class="flex flex-wrap items-center gap-4 rounded-wl-lg border border-line bg-surface p-4">
            <Avatar name={b.name} path={b.logo_path} purpose="logo" shape="rounded" size={56} />
            <div class="min-w-0 flex-1">
              <p class="flex flex-wrap items-center gap-2">
                <span class="font-semibold">{b.name}</span>
                <span class:list={["rounded-full px-2 py-0.5 text-xs font-medium", statusLabel[b.status].class]}>
                  {statusLabel[b.status].text}
                </span>
                {b.role === "editor" && <span class="text-xs text-ink-muted">Editor</span>}
              </p>
              <p class="truncate text-sm text-ink-muted">{b.category_name} · /e/{b.slug}</p>
            </div>
            <div class="flex gap-2">
              <Button href={`/e/${b.slug}`} variant="ghost" size="sm">Ver</Button>
              <Button href={`/panel/emprendimientos/${b.id}/catalogo`} variant="secondary" size="sm">Catálogo</Button>
              <Button href={`/panel/emprendimientos/${b.id}`} variant="secondary" size="sm">Editar</Button>
            </div>
          </li>
        ))}
      </ul>
    )
  }
</PanelLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/emprendimientos/nuevo.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import { actions, isInputError } from "astro:actions";
import PanelLayout from "../../../layouts/PanelLayout.astro";
import Alert from "../../../components/ui/Alert.astro";
import BusinessForm from "../../../components/business/BusinessForm.astro";
import { getCategoryTree } from "../../../services/categories";
import { getCity } from "../../../services/locations";
import { getSubmittedForm } from "../../../utils/form";

const { supabase } = Astro.locals;

const result = Astro.getActionResult(actions.business.create);
if (result && !result.error) {
  return Astro.redirect(`/panel/emprendimientos/${result.data.id}/catalogo?creado=1`);
}

const categories = await getCategoryTree(supabase);
const submitted = result?.error ? await getSubmittedForm(Astro.request) : null;
const fieldErrors = result?.error && isInputError(result.error) ? result.error.fields : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;
const submittedCityId = submitted ? Number(submitted.get("city_id")) : 0;
const city = submittedCityId ? await getCity(supabase, submittedCityId) : null;
---

<PanelLayout
  title="Crear emprendimiento"
  description="Completá lo principal ahora; el resto lo podés sumar después."
  back={{ href: "/panel/emprendimientos", label: "Mis emprendimientos" }}
>
  {formError && <Alert tone="danger" class="mb-6">{formError}</Alert>}
  {Object.keys(fieldErrors).length > 0 && <Alert tone="danger" class="mb-6">Revisá los campos marcados.</Alert>}
  <div class="max-w-3xl">
    <BusinessForm
      action={actions.business.create}
      categories={categories}
      submitted={submitted}
      fieldErrors={fieldErrors as Record<string, string[] | undefined>}
      city={city}
      submitLabel="Crear emprendimiento"
    />
  </div>
</PanelLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/guardados.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Publicaciones guardadas por el usuario, de la más reciente a la más vieja.
 * Solo las ve él (RLS). Las que se ocultaron o eliminaron no aparecen.
 */
import PanelLayout from "../../layouts/PanelLayout.astro";
import Button from "../../components/ui/Button.astro";
import PostCard from "../../components/posts/PostCard.astro";
import { getPostsByIds } from "../../services/posts";
import { getSavedPostIds, getViewerReactions } from "../../services/social";

const { supabase, user } = Astro.locals;
const page = Math.max(1, Math.min(500, Number.parseInt(Astro.url.searchParams.get("pagina") ?? "1", 10) || 1));
const { ids, hasMore } = await getSavedPostIds(supabase, user!.id, page);
const posts = await getPostsByIds(supabase, ids);
const reactions = await getViewerReactions(supabase, user!.id, posts.map((p) => p.id));
---

<PanelLayout title="Guardados" description="Las publicaciones que guardaste para ver después. Solo vos ves esta lista.">
  {
    posts.length === 0 && page === 1 ? (
      <div class="rounded-wl-lg border border-dashed border-line bg-surface p-10 text-center">
        <h2 class="text-lg font-semibold">Todavía no guardaste publicaciones</h2>
        <p class="mt-1 text-ink-muted">Tocá el ícono de guardar en cualquier publicación y la vas a encontrar acá.</p>
        <div class="mt-4">
          <Button href="/publicaciones" variant="secondary">Ver publicaciones</Button>
        </div>
      </div>
    ) : (
      <>
        <div class="grid items-start gap-4 md:grid-cols-2">
          {posts.map((post) => (
            <PostCard post={post} liked={reactions.liked.has(post.id)} saved={reactions.saved.has(post.id)} />
          ))}
        </div>
        {posts.length < ids.length && (
          <p class="mt-4 text-sm text-ink-muted">Algunas publicaciones guardadas ya no están disponibles.</p>
        )}
        <nav class="mt-6 flex justify-between gap-4" aria-label="Páginas">
          {page > 1 ? <Button href={`/panel/guardados?pagina=${page - 1}`} variant="secondary">← Anteriores</Button> : <span />}
          {hasMore && <Button href={`/panel/guardados?pagina=${page + 1}`} variant="secondary">Más guardados →</Button>}
        </nav>
      </>
    )
  }
</PanelLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Inicio del panel: saludo, perfil completo y accesos a emprendimientos.
 * Ruta protegida por el middleware.
 */
import PanelLayout from "../../layouts/PanelLayout.astro";
import Alert from "../../components/ui/Alert.astro";
import Button from "../../components/ui/Button.astro";
import Avatar from "../../components/ui/Avatar.astro";
import { hasRole } from "../../lib/auth/session";
import { displayName, getOwnProfile, profileCompleteness } from "../../services/profiles";
import { getMyBusinesses } from "../../services/businesses";
import { routes } from "../../config/site";

const { supabase, user } = Astro.locals;

const [profile, businesses, isStaff] = await Promise.all([
  getOwnProfile(supabase, user!.id),
  getMyBusinesses(supabase, user!.id),
  hasRole(supabase, "moderator"),
]);

const name = profile?.first_name ?? profile?.username ?? "";
const completeness = profile ? profileCompleteness(profile) : { percent: 0, missing: [] };
const isProvider = profile?.intent === "provider";
const passwordUpdated = Astro.url.searchParams.get("password") === "updated";
---

<PanelLayout title="Mi panel" heading={`Hola${name ? `, ${name}` : ""} 👋`} description={profile ? `@${profile.username}` : undefined}>
  {passwordUpdated && <Alert tone="success" class="mb-6">Listo, cambiaste tu contraseña.</Alert>}

  <div class="grid gap-4 md:grid-cols-2">
    <section class="flex flex-col rounded-wl-lg border border-line bg-surface p-5">
      <div class="flex items-center gap-4">
        {profile && <Avatar name={displayName(profile)} path={profile.avatar_path} size={56} />}
        <div class="min-w-0 flex-1">
          <h2 class="font-semibold">Tu perfil</h2>
          <p class="text-sm text-ink-muted">Completo al {completeness.percent}%</p>
        </div>
      </div>
      <div class="mt-4 h-2 overflow-hidden rounded-full bg-surface-muted" role="progressbar" aria-valuenow={completeness.percent} aria-valuemin="0" aria-valuemax="100" aria-label="Perfil completo">
        <div class="h-full rounded-full bg-brand" style={{ width: `${completeness.percent}%` }}></div>
      </div>
      {completeness.missing.length > 0 && (
        <p class="mt-3 text-sm text-ink-muted">Te falta: {completeness.missing.join(", ")}.</p>
      )}
      <div class="mt-auto pt-4">
        <Button href="/panel/perfil" variant="secondary" size="sm">{completeness.percent < 100 ? "Completar perfil" : "Editar perfil"}</Button>
      </div>
    </section>

    <section class="flex flex-col rounded-wl-lg border border-line bg-surface p-5">
      <h2 class="font-semibold">Tus emprendimientos</h2>
      {
        businesses.length === 0 ? (
          <p class="mt-1 text-sm text-ink-muted">
            {isProvider
              ? "Creá la página de tu emprendimiento con tus servicios, productos y horarios."
              : "¿Tenés algo para ofrecer? Podés crear un emprendimiento cuando quieras."}
          </p>
        ) : (
          <ul class="mt-3 flex flex-col gap-2">
            {businesses.slice(0, 4).map((b) => (
              <li>
                <a href={`/panel/emprendimientos/${b.id}`} class="flex items-center gap-3 rounded-wl p-1 hover:bg-surface-muted">
                  <Avatar name={b.name} path={b.logo_path} purpose="logo" shape="rounded" size={36} />
                  <span class="truncate font-medium">{b.name}</span>
                </a>
              </li>
            ))}
          </ul>
        )
      }
      <div class="mt-auto flex flex-wrap gap-2 pt-4">
        <Button href="/panel/emprendimientos/nuevo" variant={businesses.length ? "secondary" : "offer"} size="sm">Crear emprendimiento</Button>
        {businesses.length > 0 && <Button href="/panel/emprendimientos" variant="ghost" size="sm">Ver todos</Button>}
      </div>
    </section>
  </div>

  <h2 class="mt-10 text-lg font-semibold">Más para hacer</h2>
  <ul class="mt-3 grid gap-3 md:grid-cols-3">
    <li class="rounded-wl-lg border border-line bg-surface p-4 text-sm"><strong>Publicaciones</strong><p class="text-ink-muted">Mostrá trabajos y promociones.</p><a href="/panel/publicaciones/nueva" class="mt-2 inline-block font-semibold text-brand hover:underline">Publicar ahora →</a></li>
    <li class="rounded-wl-lg border border-dashed border-line p-4 text-sm"><strong>Buscador</strong><p class="text-ink-muted">Encontrá por categoría y ciudad.</p></li>
    <li class="rounded-wl-lg border border-dashed border-line p-4 text-sm"><strong>Necesidades</strong><p class="text-ink-muted">Publicá lo que buscás y recibí propuestas.</p></li>
  </ul>

  {isStaff && (
    <div class="mt-10">
      <Button href={routes.admin} variant="secondary">Ir al panel administrativo</Button>
    </div>
  )}
</PanelLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/perfil.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import { actions, isInputError } from "astro:actions";
import { PUBLIC_SUPABASE_ANON_KEY } from "astro:env/client";
import PanelLayout from "../../layouts/PanelLayout.astro";
import Field from "../../components/ui/Field.astro";
import TextArea from "../../components/ui/TextArea.astro";
import Button from "../../components/ui/Button.astro";
import Alert from "../../components/ui/Alert.astro";
import ImageUploader from "../../islands/ImageUploader.tsx";
import CityPicker from "../../islands/CityPicker.tsx";
import { getOwnProfile } from "../../services/profiles";
import { getCity } from "../../services/locations";
import { mediaUrl } from "../../lib/media";
import { getSubmittedForm } from "../../utils/form";

const { supabase, user } = Astro.locals;

const result = Astro.getActionResult(actions.profile.update);
if (result && !result.error) {
  return Astro.redirect("/panel/perfil?guardado=1");
}

const profile = await getOwnProfile(supabase, user!.id);
if (!profile) return Astro.redirect("/panel");

const submitted = result?.error ? await getSubmittedForm(Astro.request) : null;
const fieldErrors = result?.error && isInputError(result.error) ? result.error.fields : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;
const err = (name: string) => (fieldErrors as Record<string, string[] | undefined>)[name]?.[0];
const v = (name: string, saved: unknown) =>
  submitted ? String(submitted.get(name) ?? "") : saved === null || saved === undefined ? "" : String(saved);

const submittedCityId = submitted ? Number(submitted.get("city_id")) : null;
const city = submittedCityId ? await getCity(supabase, submittedCityId) : profile.city;
const avatarPath = v("avatar_path", profile.avatar_path) || null;
const saved = Astro.url.searchParams.get("guardado") === "1";
---

<PanelLayout title="Mi perfil" description="Así te ven las personas en WorkLink.">
  <a slot="actions" href={`/u/${profile.username}`} class="text-sm font-semibold text-brand hover:underline">Ver mi perfil público →</a>

  {saved && <Alert tone="success" class="mb-6">Guardamos tu perfil.</Alert>}
  {formError && <Alert tone="danger" class="mb-6">{formError}</Alert>}

  <form method="POST" action={actions.profile.update} class="flex max-w-2xl flex-col gap-8" novalidate>
    <section class="flex flex-col gap-4">
      <ImageUploader
        client:load
        name="avatar_path"
        purpose="avatar"
        label="Foto de perfil"
        initialPath={avatarPath}
        initialPreview={mediaUrl("avatar", avatarPath, 256)}
        supabaseAnonKey={PUBLIC_SUPABASE_ANON_KEY}
        hint="Una foto tuya donde se te vea bien la cara."
      />
      <div class="grid gap-4 sm:grid-cols-2">
        <Field name="first_name" label="Nombre" required maxlength={60} autocomplete="given-name" value={v("first_name", profile.first_name)} error={err("first_name")} />
        <Field name="last_name" label="Apellido" required maxlength={60} autocomplete="family-name" value={v("last_name", profile.last_name)} error={err("last_name")} />
      </div>
      <Field
        name="username"
        label="Nombre de usuario"
        required
        maxlength={30}
        autocomplete="username"
        value={v("username", profile.username)}
        hint="Es tu dirección pública: worklink/u/tu-usuario"
        error={err("username")}
      />
      <TextArea name="bio" label="Sobre vos (opcional)" rows={4} maxlength={500} placeholder="Contá en pocas palabras a qué te dedicás o qué estás buscando." value={v("bio", profile.bio)} error={err("bio")} />
      <CityPicker
        client:load
        name="city_id"
        label="Ciudad"
        initialCity={city ? { id: city.id, name: city.name, province_name: city.province_name } : null}
        error={err("city_id")}
      />
    </section>

    <section class="flex flex-col gap-4">
      <div>
        <h2 class="text-lg font-semibold">Contacto</h2>
        <p class="text-sm text-ink-muted">WhatsApp y teléfono solo los ven personas con cuenta en WorkLink.</p>
      </div>
      <div class="grid gap-4 sm:grid-cols-2">
        <Field name="whatsapp" label="WhatsApp" inputmode="tel" autocomplete="tel" placeholder="351 555-1234" value={v("whatsapp", profile.whatsapp)} error={err("whatsapp")} />
        <Field name="phone" label="Otro teléfono (opcional)" inputmode="tel" placeholder="0351 422-1234" value={v("phone", profile.phone)} error={err("phone")} />
        <Field name="instagram" label="Instagram" placeholder="@usuario" value={v("instagram", profile.instagram ? `@${profile.instagram}` : "")} error={err("instagram")} />
        <Field name="facebook" label="Facebook" placeholder="facebook.com/usuario" value={v("facebook", profile.facebook)} error={err("facebook")} />
        <Field name="tiktok" label="TikTok" placeholder="@usuario" value={v("tiktok", profile.tiktok ? `@${profile.tiktok}` : "")} error={err("tiktok")} />
        <Field name="website" label="Sitio web" inputmode="url" placeholder="misitio.com.ar" value={v("website", profile.website)} error={err("website")} />
      </div>
    </section>

    <div>
      <Button type="submit" size="lg">Guardar perfil</Button>
    </div>
  </form>
</PanelLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/publicaciones/[id].astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import { actions, isInputError } from "astro:actions";
import PanelLayout from "../../../layouts/PanelLayout.astro";
import Alert from "../../../components/ui/Alert.astro";
import Button from "../../../components/ui/Button.astro";
import PostForm from "../../../components/posts/PostForm.astro";
import { getPost } from "../../../services/posts";
import { getMyBusinesses } from "../../../services/businesses";
import { getCategoryTree } from "../../../services/categories";
import { getCity } from "../../../services/locations";
import { getSubmittedForm } from "../../../utils/form";
import { mediaItemsFromPost, mediaItemsFromSubmitted } from "../../../lib/post-media";
import { postPath } from "../../../lib/urls";

const { supabase, user } = Astro.locals;
const id = Astro.params.id ?? "";
if (!/^[0-9a-f-]{36}$/.test(id)) return Astro.rewrite("/404");

const result = Astro.getActionResult(actions.posts.update);
if (result && !result.error) return Astro.redirect("/panel/publicaciones?ok=guardada");

const [post, businesses, categories] = await Promise.all([
  getPost(supabase, id),
  getMyBusinesses(supabase, user!.id),
  getCategoryTree(supabase),
]);

// Solo el autor o el equipo del emprendimiento pueden editar.
const canEdit = post && (post.author_id === user!.id || (post.business_id && businesses.some((b) => b.id === post.business_id)));
if (!post || !canEdit) return Astro.rewrite("/404");

const submitted = result?.error ? await getSubmittedForm(Astro.request) : null;
const fieldErrors = result?.error && isInputError(result.error) ? (result.error.fields as Record<string, string[] | undefined>) : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;

const cityId = submitted ? Number(submitted.get("city_id")) : post.city_id;
const city = cityId ? await getCity(supabase, cityId) : null;
const media = submitted ? mediaItemsFromSubmitted(submitted.get("media")) : mediaItemsFromPost(post);
---

<PanelLayout title="Editar publicación" back={{ href: "/panel/publicaciones", label: "Mis publicaciones" }}>
  <Button slot="actions" href={postPath(post)} variant="ghost" size="sm">Ver publicación</Button>
  {post.status === "removed" && <Alert tone="danger" class="mb-6">Esta publicación fue removida por moderación y no se puede editar.</Alert>}
  {formError && <Alert tone="danger" class="mb-6">{formError}</Alert>}
  {Object.keys(fieldErrors).length > 0 && <Alert tone="danger" class="mb-6">Revisá los campos marcados.</Alert>}
  {
    post.status !== "removed" && (
      <div class="max-w-3xl">
        <PostForm
          action={actions.posts.update}
          post={post}
          businesses={businesses}
          categories={categories}
          submitted={submitted}
          fieldErrors={fieldErrors}
          city={city}
          media={media}
          submitLabel="Guardar cambios"
        />
      </div>
    )
  }
</PanelLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/publicaciones/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Mis publicaciones (propias y de mis emprendimientos), con acciones rápidas. */
import { actions } from "astro:actions";
import PanelLayout from "../../../layouts/PanelLayout.astro";
import Button from "../../../components/ui/Button.astro";
import Alert from "../../../components/ui/Alert.astro";
import { getManageablePosts, decodeCursor, POST_TYPE_LABELS, postHeadline } from "../../../services/posts";
import { getMyBusinesses } from "../../../services/businesses";
import { mediaUrl, postFileUrl } from "../../../lib/media";
import { formatMoney, formatRelative } from "../../../lib/format";
import { postPath } from "../../../lib/urls";

const { supabase, user } = Astro.locals;

const statusResult = Astro.getActionResult(actions.posts.setStatus);
const removeResult = Astro.getActionResult(actions.posts.remove);
if (statusResult && !statusResult.error) return Astro.redirect("/panel/publicaciones?ok=visibilidad");
if (removeResult && !removeResult.error) return Astro.redirect("/panel/publicaciones?ok=eliminada");
const actionError = statusResult?.error?.message ?? removeResult?.error?.message;

const businesses = await getMyBusinesses(supabase, user!.id);
const cursor = decodeCursor(Astro.url.searchParams.get("desde"));
const { posts, nextCursor } = await getManageablePosts(supabase, user!.id, businesses.map((b) => b.id), { cursor });

const ok = Astro.url.searchParams.get("ok");
const okText: Record<string, string> = {
  publicada: "¡Listo! Tu publicación ya está en WorkLink.",
  guardada: "Guardamos los cambios.",
  visibilidad: "Actualizamos la visibilidad.",
  eliminada: "Eliminamos la publicación.",
};
---

<PanelLayout title="Mis publicaciones" description="Lo que publicaste vos y tus emprendimientos.">
  <Button slot="actions" href="/panel/publicaciones/nueva">Nueva publicación</Button>

  {ok && okText[ok] && <Alert tone="success" class="mb-6">{okText[ok]}</Alert>}
  {actionError && <Alert tone="danger" class="mb-6">{actionError}</Alert>}

  {
    posts.length === 0 && !cursor ? (
      <div class="rounded-wl-lg border border-dashed border-line bg-surface p-8 text-center">
        <h2 class="text-lg font-semibold">Todavía no publicaste nada</h2>
        <p class="mx-auto mt-1 max-w-md text-ink-muted">Mostrá tus trabajos, promociones o contá qué estás buscando.</p>
        <div class="mt-5"><Button href="/panel/publicaciones/nueva">Crear mi primera publicación</Button></div>
      </div>
    ) : (
      <ul class="grid gap-3">
        {posts.map((post) => {
          const cover = post.media[0];
          const thumb = cover ? (cover.kind === "image" ? mediaUrl("post", cover.path, 480) : postFileUrl(cover.path, "poster.webp")) : null;
          const type = POST_TYPE_LABELS[post.type];
          return (
            <li class="flex flex-wrap items-center gap-4 rounded-wl-lg border border-line bg-surface p-3 sm:flex-nowrap">
              {thumb ? (
                <img src={thumb} alt="" width="64" height="64" loading="lazy" class="h-16 w-16 shrink-0 rounded-wl object-cover" />
              ) : (
                <span class="grid h-16 w-16 shrink-0 place-items-center rounded-wl bg-surface-muted text-xs text-ink-muted">Sin foto</span>
              )}
              <div class="min-w-0 flex-1">
                <p class="flex flex-wrap items-center gap-2 text-xs">
                  <span class:list={["rounded-full px-2 py-0.5 font-semibold", type.class]}>{type.label}</span>
                  {post.status === "hidden" && <span class="rounded-full bg-surface-muted px-2 py-0.5 font-medium text-ink-muted">Oculta</span>}
                  {post.status === "removed" && <span class="rounded-full bg-danger-soft px-2 py-0.5 font-medium text-danger">Removida por moderación</span>}
                  <span class="text-ink-muted">{post.business?.name ?? "Personal"} · {formatRelative(post.published_at)}</span>
                </p>
                <p class="mt-1 truncate font-medium">{postHeadline(post, 90)}</p>
                {post.price !== null && <p class="text-sm text-ink-muted">{formatMoney(post.price)}</p>}
                <p class="text-xs text-ink-muted">
                  {post.likes_count} me gusta · {post.comments_count} {post.comments_count === 1 ? "comentario" : "comentarios"} · {post.saves_count} {post.saves_count === 1 ? "guardado" : "guardados"}
                </p>
              </div>
              <div class="flex flex-wrap gap-1">
                <Button href={postPath(post)} variant="ghost" size="sm">Ver</Button>
                {post.status !== "removed" && (
                  <>
                    <Button href={`/panel/publicaciones/${post.id}`} variant="secondary" size="sm">Editar</Button>
                    <form method="POST" action={actions.posts.setStatus}>
                      <input type="hidden" name="post_id" value={post.id} />
                      <input type="hidden" name="status" value={post.status === "published" ? "hidden" : "published"} />
                      <Button type="submit" variant="ghost" size="sm">{post.status === "published" ? "Ocultar" : "Publicar"}</Button>
                    </form>
                  </>
                )}
                <form method="POST" action={actions.posts.remove} data-confirm="¿Eliminar esta publicación?">
                  <input type="hidden" name="post_id" value={post.id} />
                  <Button type="submit" variant="ghost" size="sm" class="text-danger">Eliminar</Button>
                </form>
              </div>
            </li>
          );
        })}
      </ul>
    )
  }

  {nextCursor && (
    <div class="mt-6 text-center">
      <Button href={`/panel/publicaciones?desde=${nextCursor}`} variant="secondary">Ver más antiguas</Button>
    </div>
  )}
</PanelLayout>

<script>
  for (const form of document.querySelectorAll<HTMLFormElement>("form[data-confirm]")) {
    form.addEventListener("submit", (event) => {
      if (!window.confirm(form.dataset.confirm ?? "¿Confirmás?")) event.preventDefault();
    });
  }
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/panel/publicaciones/nueva.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import { actions, isInputError } from "astro:actions";
import PanelLayout from "../../../layouts/PanelLayout.astro";
import Alert from "../../../components/ui/Alert.astro";
import PostForm from "../../../components/posts/PostForm.astro";
import { getMyBusinesses } from "../../../services/businesses";
import { getCategoryTree } from "../../../services/categories";
import { getCity } from "../../../services/locations";
import { getOwnProfile } from "../../../services/profiles";
import { getSubmittedForm } from "../../../utils/form";
import { mediaItemsFromSubmitted } from "../../../lib/post-media";

const { supabase, user } = Astro.locals;

const result = Astro.getActionResult(actions.posts.create);
if (result && !result.error) return Astro.redirect("/panel/publicaciones?ok=publicada");

const [businesses, categories, profile] = await Promise.all([
  getMyBusinesses(supabase, user!.id),
  getCategoryTree(supabase),
  getOwnProfile(supabase, user!.id),
]);

const submitted = result?.error ? await getSubmittedForm(Astro.request) : null;
const fieldErrors = result?.error && isInputError(result.error) ? (result.error.fields as Record<string, string[] | undefined>) : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;

const submittedCity = submitted ? Number(submitted.get("city_id")) : 0;
const city = submitted ? (submittedCity ? await getCity(supabase, submittedCity) : null) : null;
const defaultBusinessId = Astro.url.searchParams.get("emprendimiento");
const personalCity = !businesses.length ? profile?.city ?? null : null;
---

<PanelLayout title="Nueva publicación" back={{ href: "/panel/publicaciones", label: "Mis publicaciones" }}>
  {formError && <Alert tone="danger" class="mb-6">{formError}</Alert>}
  {Object.keys(fieldErrors).length > 0 && <Alert tone="danger" class="mb-6">Revisá los campos marcados.</Alert>}
  <div class="max-w-3xl">
    <PostForm
      action={actions.posts.create}
      businesses={businesses}
      categories={categories}
      submitted={submitted}
      fieldErrors={fieldErrors}
      city={city ?? personalCity}
      media={submitted ? mediaItemsFromSubmitted(submitted.get("media")) : []}
      submitLabel="Publicar"
      defaultBusinessId={defaultBusinessId}
    />
  </div>
</PanelLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/privacidad.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Página legal provisional. Reemplazar por el texto definitivo antes del lanzamiento. */
import BaseLayout from "../layouts/BaseLayout.astro";

export const prerender = true;
---

<BaseLayout title="Política de privacidad" noindex>
  <section class="mx-auto max-w-3xl px-4 py-12">
    <h1 class="text-3xl font-bold">Política de privacidad</h1>
    <p class="mt-4 text-ink-muted">
      Este texto está en preparación y se publicará antes del lanzamiento de WorkLink.
    </p>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/publicaciones/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Feed de publicaciones, del más nuevo al más viejo, 20 por página.
 * Filtros: por tipo (?tipo=busco) o "Siguiendo" (?ver=siguiendo, con sesión).
 * La primera página pública se indexa; las siguientes (?desde=...) y
 * "Siguiendo" no, para no duplicar contenido en buscadores.
 */
import BaseLayout from "../../layouts/BaseLayout.astro";
import Button from "../../components/ui/Button.astro";
import FeedPage from "../../components/posts/FeedPage.astro";
import { getFeed } from "../../services/posts";
import { getViewerReactions } from "../../services/social";
import { parseFeedParams, TYPE_SLUGS } from "../../lib/feed-params";
import { POST_TYPES } from "../../schemas/post";
import { routes } from "../../config/site";

const { supabase, user } = Astro.locals;
const { tipo, type, following, cursor, query } = parseFeedParams(Astro.url);
if (following && !user) return Astro.redirect(`${routes.login}?next=${encodeURIComponent("/publicaciones?ver=siguiendo")}`);

const { posts, nextCursor } = await getFeed(supabase, { type, following, cursor });
const reactions = await getViewerReactions(supabase, user?.id, posts.map((p) => p.id));

const nextHref = nextCursor ? `/publicaciones${query({ desde: nextCursor })}` : null;
const nextFragmentHref = nextCursor ? `/publicaciones/mas${query({ desde: nextCursor })}` : null;

const filters = [
  { href: "/publicaciones", label: "Todo", active: !type && !following },
  ...(user ? [{ href: "/publicaciones?ver=siguiendo", label: "Siguiendo", active: following }] : []),
  ...Object.entries(TYPE_SLUGS).map(([slug, value]) => ({
    href: `/publicaciones?tipo=${slug}`,
    label: POST_TYPES.find((t) => t.value === value)!.label,
    active: type === value,
  })),
];
const currentLabel = filters.find((f) => f.active)?.label ?? "Todo";
---

<BaseLayout
  title={type || following ? `Publicaciones: ${currentLabel}` : "Publicaciones"}
  description="Lo último que publicaron emprendedores y personas en WorkLink: servicios, productos, promociones y pedidos."
  canonicalPath={`/publicaciones${type ? `?tipo=${tipo}` : ""}`}
  noindex={Boolean(cursor) || following}
>
  <section class="mx-auto max-w-6xl px-4 py-8">
    <div class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-3xl font-bold">Publicaciones</h1>
        <p class="mt-1 text-ink-muted">Lo último que se publicó en WorkLink.</p>
      </div>
      <Button href={user ? "/panel/publicaciones/nueva" : "/registrarse"}>Publicar</Button>
    </div>

    <nav aria-label="Filtrar por tipo" class="mt-6 flex gap-2 overflow-x-auto pb-1">
      {
        filters.map((filter) => (
          <a
            href={filter.href}
            aria-current={filter.active ? "page" : undefined}
            class:list={[
              "whitespace-nowrap rounded-full border px-4 py-2 text-sm font-medium",
              filter.active ? "border-brand bg-brand text-brand-contrast" : "border-line bg-surface text-ink hover:bg-surface-muted",
            ]}
          >
            {filter.label}
          </a>
        ))
      }
    </nav>

    {
      posts.length === 0 ? (
        <div class="mt-10 rounded-wl-lg border border-dashed border-line bg-surface p-10 text-center">
          {following ? (
            <>
              <h2 class="text-lg font-semibold">Todavía no hay publicaciones de las cuentas que seguís</h2>
              <p class="mt-1 text-ink-muted">Tocá “Seguir” en los emprendimientos y personas que te interesan y vas a ver acá lo que publiquen.</p>
              <a href="/publicaciones" class="mt-4 inline-block font-semibold text-brand">Ver todas las publicaciones →</a>
            </>
          ) : (
            <>
              <h2 class="text-lg font-semibold">Todavía no hay publicaciones {type && `de tipo “${currentLabel}”`}</h2>
              <p class="mt-1 text-ink-muted">¡Podés ser la primera persona en publicar!</p>
            </>
          )}
        </div>
      ) : (
        <div class="mt-6 grid items-start gap-4 md:grid-cols-2 lg:grid-cols-3" data-feed>
          <FeedPage posts={posts} reactions={reactions} nextHref={nextHref} nextFragmentHref={nextFragmentHref} priorityCount={cursor ? 0 : 2} />
        </div>
      )
    }
  </section>
</BaseLayout>

<script>
  // "Cargar más" sin recargar: pide el fragmento HTML y lo agrega al feed.
  document.addEventListener("click", async (event) => {
    const link = (event.target as HTMLElement).closest<HTMLAnchorElement>("a[data-load-more]");
    if (!link || event.metaKey || event.ctrlKey) return;
    event.preventDefault();
    const wrapper = link.closest("[data-load-more-wrapper]");
    link.textContent = "Cargando…";
    link.setAttribute("aria-busy", "true");
    try {
      const res = await fetch(link.dataset.loadMore!, { headers: { Accept: "text/html" } });
      if (!res.ok) throw new Error();
      const html = await res.text();
      wrapper?.insertAdjacentHTML("afterend", html);
      wrapper?.remove();
    } catch {
      window.location.href = link.href;
    }
  });
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/publicaciones/mas.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Fragmento HTML con la página siguiente del feed (sin <html> ni layout).
 * Lo pide el botón "Cargar más" de /publicaciones. No se indexa.
 */
import FeedPage from "../../components/posts/FeedPage.astro";
import { getFeed } from "../../services/posts";
import { getViewerReactions } from "../../services/social";
import { parseFeedParams } from "../../lib/feed-params";

export const partial = true;

const { supabase, user } = Astro.locals;
const { type, following, cursor, query } = parseFeedParams(Astro.url);
if (!cursor || (following && !user)) return new Response(null, { status: 400 });

const { posts, nextCursor } = await getFeed(supabase, { type, following, cursor });
const reactions = await getViewerReactions(supabase, user?.id, posts.map((p) => p.id));

Astro.response.headers.set("X-Robots-Tag", "noindex");
---

<FeedPage
  posts={posts}
  reactions={reactions}
  nextHref={nextCursor ? `/publicaciones${query({ desde: nextCursor })}` : null}
  nextFragmentHref={nextCursor ? `/publicaciones/mas${query({ desde: nextCursor })}` : null}
/>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/recuperar.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import { actions, isInputError } from "astro:actions";
import AuthLayout from "../layouts/AuthLayout.astro";
import Field from "../components/ui/Field.astro";
import Button from "../components/ui/Button.astro";
import Alert from "../components/ui/Alert.astro";
import { routes } from "../config/site";
import { getSubmittedValues } from "../utils/form";

const result = Astro.getActionResult(actions.auth.requestPasswordReset);
const sent = result && !result.error;
const fieldErrors = result?.error && isInputError(result.error) ? result.error.fields : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;
const values = result?.error ? await getSubmittedValues(Astro.request) : {};
---

<AuthLayout
  title="Recuperar contraseña"
  heading="Recuperá tu contraseña"
  subheading="Te mandamos un enlace para elegir una nueva."
>
  {
    sent ? (
      <Alert tone="success" title="Revisá tu email">
        Si hay una cuenta con ese email, en unos minutos vas a recibir un enlace para cambiar la contraseña. Revisá
        también la carpeta de spam.
      </Alert>
    ) : (
      <>
        {formError && <Alert tone="danger" class="mb-5">{formError}</Alert>}
        <form method="POST" action={actions.auth.requestPasswordReset} class="flex flex-col gap-4" novalidate>
          <Field
            name="email"
            value={values.email}
            label="Email de tu cuenta"
            type="email"
            autocomplete="email"
            inputmode="email"
            required
            error={fieldErrors.email?.[0]}
          />
          <Button type="submit" block size="lg">Enviar enlace</Button>
        </form>
      </>
    )
  }

  <Fragment slot="footer">
    <a href={routes.login} class="font-semibold text-brand hover:underline">Volver a ingresar</a>
  </Fragment>
</AuthLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/registrarse.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import { actions, isInputError } from "astro:actions";
import AuthLayout from "../layouts/AuthLayout.astro";
import Field from "../components/ui/Field.astro";
import Button from "../components/ui/Button.astro";
import Alert from "../components/ui/Alert.astro";
import { routes } from "../config/site";
import { getSubmittedValues } from "../utils/form";

if (Astro.locals.user) {
  return Astro.redirect(routes.dashboard);
}

const result = Astro.getActionResult(actions.auth.signUp);

// Sin confirmación de email (desarrollo): la sesión ya existe.
if (result && !result.error && !result.data.needsConfirmation) {
  return Astro.redirect(routes.dashboard);
}

const sentTo = result && !result.error ? result.data.email : null;
const fieldErrors = result?.error && isInputError(result.error) ? result.error.fields : {};
const formError = result?.error && !isInputError(result.error) ? result.error.message : null;

const values = result?.error ? await getSubmittedValues(Astro.request) : {};
const preselected = (values.intent ?? Astro.url.searchParams.get("intent")) === "provider" ? "provider" : "seeker";

const intents = [
  {
    value: "seeker",
    title: "Necesito algo",
    text: "Busco servicios, productos o profesionales.",
    ring: "has-[:checked]:border-seek has-[:checked]:bg-seek-soft",
    dot: "bg-seek",
  },
  {
    value: "provider",
    title: "Tengo algo para ofrecer",
    text: "Tengo un emprendimiento o doy un servicio.",
    ring: "has-[:checked]:border-offer has-[:checked]:bg-offer-soft",
    dot: "bg-offer",
  },
] as const;
---

<AuthLayout
  title="Crear cuenta"
  heading={sentTo ? "Revisá tu email" : "Creá tu cuenta"}
  subheading={sentTo ? undefined : "Es gratis. Podés buscar y ofrecer con la misma cuenta."}
>
  {
    sentTo ? (
      <div class="flex flex-col gap-4">
        <Alert tone="success" title="Te enviamos un enlace de confirmación">
          Abrí el email que mandamos a <strong>{sentTo}</strong> y tocá el enlace para activar tu cuenta.
          Si no aparece en unos minutos, revisá la carpeta de spam.
        </Alert>
        <Button href={routes.login} variant="secondary" block>
          Ya la confirmé, ingresar
        </Button>
      </div>
    ) : (
      <>
        {formError && <Alert tone="danger" class="mb-5">{formError}</Alert>}

        <form method="POST" action={actions.auth.signUp} class="flex flex-col gap-4" novalidate>
          <fieldset class="flex flex-col gap-2">
            <legend class="mb-2 text-sm font-medium text-ink">¿Qué venís a hacer?</legend>
            <div class="grid gap-2 sm:grid-cols-2">
              {intents.map((option) => (
                <label
                  class:list={[
                    "flex cursor-pointer flex-col gap-1 rounded-wl border border-line bg-surface p-3 transition-colors",
                    "hover:bg-surface-muted has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-brand/40",
                    option.ring,
                  ]}
                >
                  <span class="flex items-center gap-2 font-semibold">
                    <input
                      type="radio"
                      name="intent"
                      value={option.value}
                      checked={preselected === option.value}
                      class="sr-only"
                    />
                    <span class:list={["h-2.5 w-2.5 rounded-full", option.dot]} aria-hidden="true" />
                    {option.title}
                  </span>
                  <span class="text-sm text-ink-muted">{option.text}</span>
                </label>
              ))}
            </div>
            <p class="text-xs text-ink-muted">Después podés hacer las dos cosas.</p>
            {fieldErrors.intent?.[0] && <p class="text-sm text-danger">{fieldErrors.intent[0]}</p>}
          </fieldset>

          <div class="grid gap-4 sm:grid-cols-2">
            <Field
              name="first_name"
              value={values.first_name}
              label="Nombre"
              autocomplete="given-name"
              required
              maxlength={60}
              error={fieldErrors.first_name?.[0]}
            />
            <Field
              name="last_name"
              value={values.last_name}
              label="Apellido"
              autocomplete="family-name"
              required
              maxlength={60}
              error={fieldErrors.last_name?.[0]}
            />
          </div>
          <Field
            name="email"
              value={values.email}
            label="Email"
            type="email"
            autocomplete="email"
            inputmode="email"
            required
            error={fieldErrors.email?.[0]}
          />
          <Field
            name="password"
            label="Contraseña"
            type="password"
            autocomplete="new-password"
            required
            minlength={8}
            maxlength={72}
            hint="Mínimo 8 caracteres, con al menos una letra y un número."
            error={fieldErrors.password?.[0]}
          />

          <div class="flex flex-col gap-1">
            <label class="flex items-start gap-2.5 text-sm text-ink-muted">
              <input type="checkbox" name="accept_terms" class="mt-0.5 h-4 w-4 accent-[var(--wl-brand)]" required />
              <span>
                Acepto los <a href="/terminos" class="font-medium text-brand hover:underline">términos y condiciones</a> y la{" "}
                <a href="/privacidad" class="font-medium text-brand hover:underline">política de privacidad</a>.
              </span>
            </label>
            {fieldErrors.accept_terms?.[0] && <p class="text-sm text-danger">{fieldErrors.accept_terms[0]}</p>}
          </div>

          <Button type="submit" block size="lg">Crear cuenta</Button>
        </form>
      </>
    )
  }

  <Fragment slot="footer">
    ¿Ya tenés cuenta?
    <a href={routes.login} class="font-semibold text-brand hover:underline">Ingresá</a>
  </Fragment>
</AuthLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/salir.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Cierre de sesión. El botón "Salir" envía un POST a /salir con la acción
 * auth.signOut; esta página solo redirige. Un GET (link directo) no cierra
 * la sesión, para que nadie pueda desloguearte con un enlace.
 */
import { actions } from "astro:actions";
import { routes } from "../config/site";

const result = Astro.getActionResult(actions.auth.signOut);
return Astro.redirect(result && !result.error ? result.data.redirectTo : routes.home);
---
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/terminos.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Página legal provisional. Reemplazar por el texto definitivo antes del lanzamiento. */
import BaseLayout from "../layouts/BaseLayout.astro";

export const prerender = true;
---

<BaseLayout title="Términos y condiciones" noindex>
  <section class="mx-auto max-w-3xl px-4 py-12">
    <h1 class="text-3xl font-bold">Términos y condiciones</h1>
    <p class="mt-4 text-ink-muted">
      Este texto está en preparación y se publicará antes del lanzamiento de WorkLink.
    </p>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/u/[username].astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Perfil público de una persona: /u/[username]. No se indexa en buscadores
 * (privacidad): lo indexable son los emprendimientos.
 */
import BaseLayout from "../../layouts/BaseLayout.astro";
import Avatar from "../../components/ui/Avatar.astro";
import Button from "../../components/ui/Button.astro";
import PostCard from "../../components/posts/PostCard.astro";
import FollowButton from "../../components/social/FollowButton.astro";
import { getFeed } from "../../services/posts";
import { followersLabel, getViewerReactions, isFollowing } from "../../services/social";
import { displayName, getPublicProfile } from "../../services/profiles";
import { getPublicBusinessesByOwner } from "../../services/businesses";
import { instagramUrl, tiktokUrl } from "../../lib/contact";
import { formatLocation, formatMonthYear } from "../../lib/format";

const { supabase, user } = Astro.locals;
const username = (Astro.params.username ?? "").toLowerCase();
if (!/^[a-z0-9_.]{3,30}$/.test(username)) return Astro.rewrite("/404");

const profile = await getPublicProfile(supabase, username, { withContact: false });
if (!profile) return Astro.rewrite("/404");

const isMe = user?.id === profile.id;
const [businesses, { posts }, following] = await Promise.all([
  getPublicBusinessesByOwner(supabase, profile.id),
  getFeed(supabase, { authorId: profile.id, personalOnly: true, limit: 6 }),
  isMe ? Promise.resolve(false) : isFollowing(supabase, user?.id, "profile", profile.id),
]);
const reactions = await getViewerReactions(supabase, user?.id, posts.map((p) => p.id));
const name = displayName(profile);
---

<BaseLayout title={name} description={profile.bio ?? `Perfil de ${name} en WorkLink.`} noindex>
  <section class="mx-auto max-w-3xl px-4 py-10">
    <header class="flex flex-wrap items-center gap-5">
      <Avatar name={name} path={profile.avatar_path} size={96} priority />
      <div class="min-w-0 flex-1">
        <h1 class="text-2xl font-bold">{name}</h1>
        <p class="text-ink-muted">
          @{profile.username}{profile.city && ` · ${formatLocation(profile.city)}`}
        </p>
        <p class="mt-1 text-sm text-ink-muted">
          <span data-followers={profile.id}>{followersLabel(profile.followers_count)}</span>
          {" · "}{profile.following_count.toLocaleString("es-AR")} seguidos
          {" · "}En WorkLink desde {formatMonthYear(profile.created_at)}
        </p>
      </div>
      {isMe ? (
        <Button href="/panel/perfil" variant="secondary" size="sm">Editar perfil</Button>
      ) : (
        <FollowButton kind="profile" id={profile.id} following={following} returnTo={`/u/${profile.username}`} />
      )}
    </header>

    {profile.bio && <p class="mt-6 whitespace-pre-line">{profile.bio}</p>}

    {
      (profile.instagram || profile.tiktok || profile.website) && (
        <ul class="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-sm">
          {profile.instagram && <li><a href={instagramUrl(profile.instagram)} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">Instagram</a></li>}
          {profile.tiktok && <li><a href={tiktokUrl(profile.tiktok)} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">TikTok</a></li>}
          {profile.website && <li><a href={profile.website} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">Sitio web</a></li>}
        </ul>
      )
    }

    {
      businesses.length > 0 && (
        <section class="mt-10">
          <h2 class="mb-4 text-lg font-semibold">Emprendimientos</h2>
          <ul class="grid gap-3">
            {businesses.map((b) => (
              <li>
                <a href={`/e/${b.slug}`} class="flex items-center gap-4 rounded-wl-lg border border-line bg-surface p-4 hover:border-brand">
                  <Avatar name={b.name} path={b.logo_path} purpose="logo" shape="rounded" size={56} />
                  <div class="min-w-0">
                    <p class="font-semibold">{b.name}{b.verification === "verified" && <span class="ml-1 text-seek">✓</span>}</p>
                    <p class="truncate text-sm text-ink-muted">{[b.categories?.name, b.cities?.name].filter(Boolean).join(" · ")}</p>
                    {b.tagline && <p class="truncate text-sm">{b.tagline}</p>}
                  </div>
                </a>
              </li>
            ))}
          </ul>
        </section>
      )
    }

    {
      posts.length > 0 && (
        <section class="mt-10">
          <h2 class="mb-4 text-lg font-semibold">Publicaciones</h2>
          <div class="grid items-start gap-4 sm:grid-cols-2">
            {posts.map((post) => <PostCard post={post} liked={reactions.liked.has(post.id)} saved={reactions.saved.has(post.id)} />)}
          </div>
        </section>
      )
    }
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/schemas/auth.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { z } from "astro/zod";

/**
 * Validaciones de autenticación. Se usan en el servidor (Astro Actions) y
 * sus mensajes se muestran en los formularios.
 */

const email = z
  .string({ error: "Ingresá tu email" })
  .trim()
  .toLowerCase()
  .pipe(z.email({ error: "Ingresá un email válido" }).max(254, { error: "El email es demasiado largo" }));

/** 8 a 72 caracteres (límite de bcrypt), con al menos una letra y un número. */
export const passwordSchema = z
  .string({ error: "Ingresá una contraseña" })
  .min(8, { error: "La contraseña debe tener al menos 8 caracteres" })
  .max(72, { error: "La contraseña puede tener hasta 72 caracteres" })
  .regex(/[A-Za-zÁÉÍÓÚáéíóúÑñ]/, { error: "La contraseña debe incluir al menos una letra" })
  .regex(/[0-9]/, { error: "La contraseña debe incluir al menos un número" });

const personName = (label: string) =>
  z
    .string({ error: `Ingresá tu ${label}` })
    .trim()
    .min(2, { error: `Tu ${label} debe tener al menos 2 letras` })
    .max(60, { error: `Tu ${label} puede tener hasta 60 caracteres` })
    .regex(/^[\p{L}][\p{L}\s'.-]*$/u, { error: `Tu ${label} solo puede tener letras` });

export const signUpSchema = z.object({
  first_name: personName("nombre"),
  last_name: personName("apellido"),
  email,
  password: passwordSchema,
  intent: z.enum(["seeker", "provider"], { error: "Elegí qué venís a hacer" }),
  accept_terms: z.boolean().refine((value) => value, {
    error: "Tenés que aceptar los términos para crear la cuenta",
  }),
});

export const signInSchema = z.object({
  email,
  password: z.string({ error: "Ingresá tu contraseña" }).min(1, { error: "Ingresá tu contraseña" }).max(72),
  next: z.string().max(500).optional(),
});

export const forgotPasswordSchema = z.object({
  email,
});

export const resetPasswordSchema = z
  .object({
    password: passwordSchema,
    password_confirm: z.string(),
  })
  .refine((data) => data.password === data.password_confirm, {
    error: "Las contraseñas no coinciden",
    path: ["password_confirm"],
  });

export type SignUpInput = z.infer<typeof signUpSchema>;
export type SignInInput = z.infer<typeof signInSchema>;
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/schemas/business.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { z } from "astro/zod";
import {
  optionalFacebook,
  optionalId,
  optionalInstagram,
  optionalMediaPath,
  optionalPhone,
  optionalText,
  optionalTiktok,
  optionalWebsite,
  optionalWhatsapp,
} from "./common";

export const WEEK_DAYS = [
  { key: "mon", label: "Lunes" },
  { key: "tue", label: "Martes" },
  { key: "wed", label: "Miércoles" },
  { key: "thu", label: "Jueves" },
  { key: "fri", label: "Viernes" },
  { key: "sat", label: "Sábado" },
  { key: "sun", label: "Domingo" },
] as const;

export type DayKey = (typeof WEEK_DAYS)[number]["key"];
/** {"mon": [["09:00","13:00"], ["17:00","21:00"]], ...} — un día ausente = cerrado. */
export type BusinessHours = Partial<Record<DayKey, [string, string][]>>;

const time = z.preprocess(
  (value) => (typeof value === "string" && value.trim() === "" ? null : value),
  z
    .string()
    .regex(/^([01]\d|2[0-3]):[0-5]\d$/, { error: "Hora inválida" })
    .nullable()
    .optional(),
);

const daySchema = z.object({
  open: z.boolean().default(false),
  from1: time,
  to1: time,
  from2: time,
  to2: time,
});

/** Campos del formulario: hours.mon.open, hours.mon.from1, hours.mon.to1... */
// Nota: .optional() va al final para que Astro reconozca el objeto anidado.
const hoursSchema = z
  .object(Object.fromEntries(WEEK_DAYS.map((day) => [day.key, daySchema.optional()])) as Record<DayKey, z.ZodOptional<typeof daySchema>>)
  .transform((input, ctx) => {
    const result: BusinessHours = {};
    for (const { key, label } of WEEK_DAYS) {
      const day = input[key];
      if (!day?.open) continue;
      const ranges: [string, string][] = [];
      for (const [from, to] of [
        [day.from1, day.to1],
        [day.from2, day.to2],
      ] as const) {
        if (!from && !to) continue;
        if (!from || !to || from >= to) {
          ctx.addIssue({ code: "custom", path: [key], message: `Revisá el horario del ${label.toLowerCase()}` });
          return z.NEVER;
        }
        ranges.push([from, to]);
      }
      if (ranges.length === 0) {
        ctx.addIssue({ code: "custom", path: [key], message: `Indicá el horario del ${label.toLowerCase()}` });
        return z.NEVER;
      }
      result[key] = ranges;
    }
    return Object.keys(result).length ? result : null;
  })
  .optional();

export const businessSchema = z.object({
  name: z
    .string({ error: "Escribí el nombre del emprendimiento" })
    .trim()
    .min(2, { error: "El nombre debe tener al menos 2 caracteres" })
    .max(80, { error: "El nombre puede tener hasta 80 caracteres" }),
  slug: z.preprocess(
    // Astro entrega los campos vacíos como null.
    (value) => (typeof value === "string" ? value.trim().toLowerCase() || undefined : (value ?? undefined)),
    z
      .string()
      .max(80)
      .regex(/^([a-z0-9]+(-[a-z0-9]+)*)?$/, { error: "Solo letras sin tilde, números y guiones" })
      .optional(),
  ),
  tagline: optionalText(140, "La frase"),
  description: optionalText(3000, "La descripción"),
  category_id: z.coerce.number({ error: "Elegí una categoría" }).int().positive({ error: "Elegí una categoría" }),
  subcategory_ids: z.array(z.coerce.number().int().positive()).max(10, { error: "Elegí hasta 10 especialidades" }).default([]),
  city_id: optionalId,
  logo_path: optionalMediaPath,
  cover_path: optionalMediaPath,
  whatsapp: optionalWhatsapp,
  phone: optionalPhone,
  email: z.preprocess(
    (value) => (typeof value === "string" && value.trim() === "" ? null : value),
    z.email({ error: "Email inválido" }).max(254).nullable().optional(),
  ),
  instagram: optionalInstagram,
  facebook: optionalFacebook,
  tiktok: optionalTiktok,
  website: optionalWebsite,
  availability: optionalText(200, "La disponibilidad"),
  hours: hoursSchema,
  /** "active" = publicado; "draft" = borrador (solo lo ve el equipo). */
  status: z.enum(["active", "draft", "inactive"]).default("active"),
});

export type BusinessInput = z.infer<typeof businessSchema>;

export const businessIdSchema = z.object({ business_id: z.uuid() });

export const deleteBusinessSchema = z.object({
  business_id: z.uuid(),
  confirm: z.string({ error: "Escribí ELIMINAR para confirmar" }).trim(),
});
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/schemas/catalog.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { z } from "astro/zod";
import { optionalAmount, optionalMediaPath, optionalText } from "./common";

const base = {
  business_id: z.uuid(),
  item_id: z.preprocess((v) => (v === "" || v === null ? undefined : v), z.uuid().optional()),
  name: z
    .string({ error: "Escribí un nombre" })
    .trim()
    .min(2, { error: "El nombre debe tener al menos 2 caracteres" })
    .max(120, { error: "El nombre puede tener hasta 120 caracteres" }),
  description: optionalText(3000, "La descripción"),
  price: optionalAmount,
  price_type: z.enum(["fixed", "from", "ask"]).default("fixed"),
  cover_path: optionalMediaPath,
};

const priceRule = <T extends { price: number | null | undefined; price_type: string }>(data: T) =>
  data.price_type === "ask" || (data.price !== null && data.price !== undefined);

export const serviceSchema = z
  .object({
    ...base,
    duration_min: z.preprocess(
      (v) => (v === "" || v === null ? null : v),
      z.coerce.number().int().min(5, { error: "Mínimo 5 minutos" }).max(100000).nullable().optional(),
    ),
    service_area: optionalText(200, "La zona"),
  })
  .refine(priceRule, { error: "Indicá el precio o elegí “Consultar precio”", path: ["price"] });

export const productSchema = z
  .object(base)
  .refine(priceRule, { error: "Indicá el precio o elegí “Consultar precio”", path: ["price"] });

export const catalogItemRefSchema = z.object({
  business_id: z.uuid(),
  item_id: z.uuid(),
  kind: z.enum(["service", "product"]),
});

export const catalogStatusSchema = catalogItemRefSchema.extend({
  status: z.enum(["active", "hidden"]),
});

export type ServiceInput = z.infer<typeof serviceSchema>;
export type ProductInput = z.infer<typeof productSchema>;
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/schemas/common.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { z } from "astro/zod";
import { normalizeArgentinePhone, normalizeFacebook, normalizeHandle, normalizeWebsite } from "../lib/contact";
import { parseArgentineAmount } from "../lib/format";

/**
 * Piezas de validación reutilizables. Los campos vacíos de un formulario
 * llegan como "" o null: se convierten a null para guardar NULL en la base.
 */

const emptyToNull = (value: unknown) => (typeof value === "string" && value.trim() === "" ? null : value);

/** Texto opcional con largo máximo. */
export const optionalText = (max: number, label = "Este campo") =>
  z.preprocess(
    emptyToNull,
    z
      .string()
      .trim()
      .max(max, { error: `${label} puede tener hasta ${max} caracteres` })
      .nullable()
      .optional(),
  );

/** Entero positivo opcional (ids de select / ciudad). */
export const optionalId = z.preprocess(emptyToNull, z.coerce.number().int().positive().nullable().optional());

export const optionalWhatsapp = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const phone = normalizeArgentinePhone(value, { mobile: true });
      if (!phone) {
        ctx.addIssue({ code: "custom", message: "Escribí el número con característica, por ejemplo 351 555-1234" });
        return z.NEVER;
      }
      return phone;
    }),
);

export const optionalPhone = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const phone = normalizeArgentinePhone(value, { mobile: false });
      if (!phone) {
        ctx.addIssue({ code: "custom", message: "Escribí el número con característica, por ejemplo 0351 422-1234" });
        return z.NEVER;
      }
      return phone;
    }),
);

const socialHandle = (host: "instagram.com" | "tiktok.com", label: string) =>
  z.preprocess(
    emptyToNull,
    z
      .string()
      .nullable()
      .optional()
      .transform((value, ctx) => {
        if (!value) return null;
        const handle = normalizeHandle(value, host);
        if (!handle) {
          ctx.addIssue({ code: "custom", message: `Escribí tu usuario de ${label}, por ejemplo @mi.negocio` });
          return z.NEVER;
        }
        return handle;
      }),
  );

export const optionalInstagram = socialHandle("instagram.com", "Instagram");
export const optionalTiktok = socialHandle("tiktok.com", "TikTok");

export const optionalFacebook = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const url = normalizeFacebook(value);
      if (!url) {
        ctx.addIssue({ code: "custom", message: "Escribí el enlace de tu página o tu usuario de Facebook" });
        return z.NEVER;
      }
      return url;
    }),
);

export const optionalWebsite = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const url = normalizeWebsite(value);
      if (!url) {
        ctx.addIssue({ code: "custom", message: "Escribí una dirección web válida, por ejemplo minegocio.com.ar" });
        return z.NEVER;
      }
      return url;
    }),
);

/** Importe en pesos ("12.500,50"). Opcional. */
export const optionalAmount = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const amount = parseArgentineAmount(value);
      if (amount === null || amount > 999_999_999) {
        ctx.addIssue({ code: "custom", message: "Escribí un importe válido, por ejemplo 12.500" });
        return z.NEVER;
      }
      return amount;
    }),
);

/** Carpeta de imagen subida ("uuid/uuid") o vacío para quitarla. */
export const optionalMediaPath = z.preprocess(
  emptyToNull,
  z
    .string()
    .regex(/^[0-9a-f-]{36}\/[0-9a-f-]{36}$/, { error: "Imagen inválida" })
    .nullable()
    .optional(),
);
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/schemas/post.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { z } from "astro/zod";
import { optionalAmount, optionalId, optionalText } from "./common";
import { POST_MAX_IMAGES } from "../config/media";

export const POST_TYPES = [
  { value: "offer", label: "Ofrezco", needsBusiness: false },
  { value: "seeking", label: "Busco", needsBusiness: false },
  { value: "product", label: "Producto", needsBusiness: true },
  { value: "service", label: "Servicio", needsBusiness: true },
  { value: "promotion", label: "Promoción", needsBusiness: true },
] as const;

export type PostType = (typeof POST_TYPES)[number]["value"];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const mediaItem = z.object({
  id: z.string().regex(UUID).optional(),
  path: z.string().regex(/^[0-9a-f-]{36}\/[0-9a-f-]{36}$/),
  kind: z.enum(["image", "video"]),
  mime: z.enum(["image/webp", "video/mp4", "video/webm"]),
  bytes: z.number().int().positive().max(50 * 1024 * 1024),
  width: z.number().int().positive().max(10000),
  height: z.number().int().positive().max(10000),
  duration: z.number().positive().max(180).optional(),
});

export type PostMediaInput = z.infer<typeof mediaItem>;

/** Campo oculto "media": JSON con la lista ordenada de archivos. */
const mediaField = z
  .preprocess((value) => (value === null || value === undefined || value === "" ? "[]" : value), z.string().max(20000))
  .transform((raw, ctx) => {
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      ctx.addIssue({ code: "custom", message: "No pudimos leer los archivos. Volvé a subirlos." });
      return z.NEVER;
    }
    const result = z.array(mediaItem).max(POST_MAX_IMAGES).safeParse(parsed);
    if (!result.success) {
      ctx.addIssue({ code: "custom", message: "Hay archivos inválidos. Volvé a subirlos." });
      return z.NEVER;
    }
    const videos = result.data.filter((item) => item.kind === "video").length;
    if (videos > 1 || (videos === 1 && result.data.length > 1)) {
      ctx.addIssue({ code: "custom", message: "Una publicación puede tener hasta 10 fotos o un video." });
      return z.NEVER;
    }
    return result.data;
  });

/** "bodas, fotografía , eventos" -> ["bodas", "fotografía", "eventos"] (la base las normaliza). */
const tagsField = z
  .preprocess((value) => (typeof value === "string" ? value : ""), z.string().max(400))
  .transform((raw, ctx) => {
    const tags = [...new Set(raw.split(/[,#\n]/).map((tag) => tag.trim()).filter(Boolean))];
    if (tags.length > 10) {
      ctx.addIssue({ code: "custom", message: "Hasta 10 etiquetas" });
      return z.NEVER;
    }
    return tags.map((tag) => tag.slice(0, 40));
  });

const postFields = z
  .object({
    business_id: z.preprocess((value) => (value === "" || value === null ? undefined : value), z.string().regex(UUID).optional()),
    type: z.enum(["offer", "seeking", "product", "service", "promotion"], { error: "Elegí el tipo de publicación" }),
    title: optionalText(140, "El título"),
    body: z
      .string({ error: "Escribí el texto de la publicación" })
      .trim()
      .min(3, { error: "Escribí el texto de la publicación" })
      .max(5000, { error: "El texto puede tener hasta 5000 caracteres" }),
    price: optionalAmount,
    category_id: optionalId,
    subcategory_id: optionalId,
    city_id: optionalId,
    tags: tagsField,
    media: mediaField,
    status: z.enum(["published", "hidden"]).default("published"),
  });

const needsBusinessCheck = (data: { business_id?: string; type: string }) =>
  Boolean(data.business_id) || !POST_TYPES.find((t) => t.value === data.type)?.needsBusiness;
const needsBusinessMessage = {
  error: "Productos, servicios y promociones se publican desde un emprendimiento",
  path: ["type"],
};

// Astro necesita un z.object (con .refine) para leer el formulario: por eso
// el esquema de edición se arma con .extend() y no con .and().
export const postSchema = postFields.refine(needsBusinessCheck, needsBusinessMessage);
export const postUpdateSchema = postFields
  .extend({ post_id: z.string().regex(UUID) })
  .refine(needsBusinessCheck, needsBusinessMessage);

export type PostInput = z.infer<typeof postSchema>;

export const postRefSchema = z.object({ post_id: z.string().regex(UUID) });

export const postStatusSchema = z.object({
  post_id: z.string().regex(UUID),
  status: z.enum(["published", "hidden"]),
});
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/schemas/profile.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { z } from "astro/zod";
import {
  optionalFacebook,
  optionalId,
  optionalInstagram,
  optionalMediaPath,
  optionalText,
  optionalTiktok,
  optionalWebsite,
  optionalWhatsapp,
  optionalPhone,
} from "./common";

const personName = (label: string) =>
  z
    .string({ error: `Ingresá tu ${label}` })
    .trim()
    .min(2, { error: `Tu ${label} debe tener al menos 2 letras` })
    .max(60, { error: `Tu ${label} puede tener hasta 60 caracteres` })
    .regex(/^[\p{L}][\p{L}\s'.-]*$/u, { error: `Tu ${label} solo puede tener letras` });

export const profileSchema = z.object({
  username: z
    .string({ error: "Elegí un nombre de usuario" })
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9_.]{3,30}$/, {
      error: "Entre 3 y 30 caracteres: letras sin tilde, números, punto o guion bajo",
    }),
  first_name: personName("nombre"),
  last_name: personName("apellido"),
  bio: optionalText(500, "La descripción"),
  city_id: optionalId,
  avatar_path: optionalMediaPath,
  whatsapp: optionalWhatsapp,
  phone: optionalPhone,
  instagram: optionalInstagram,
  facebook: optionalFacebook,
  tiktok: optionalTiktok,
  website: optionalWebsite,
});

export type ProfileInput = z.infer<typeof profileSchema>;
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/schemas/social.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { z } from "astro/zod";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const uuid = (message = "Dato inválido") => z.string().regex(UUID, { error: message });

export const COMMENT_MAX = 1000;

/** Me gusta / guardar: estado deseado (idempotente, sirve aunque se repita). */
export const reactionSchema = z.object({
  post_id: uuid(),
  active: z.boolean(),
});

/** Seguir o dejar de seguir a una persona o a un emprendimiento. */
export const followSchema = z.object({
  kind: z.enum(["profile", "business"]),
  id: uuid(),
  active: z.boolean(),
});

export const commentSchema = z.object({
  post_id: uuid(),
  body: z
    .string({ error: "Escribí un comentario" })
    .trim()
    .min(1, { error: "Escribí un comentario" })
    .max(COMMENT_MAX, { error: `El comentario puede tener hasta ${COMMENT_MAX} caracteres` }),
});

export const commentRefSchema = z.object({
  comment_id: uuid(),
});
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/scripts/social.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Botones de me gusta, guardar y seguir (un solo manejador para toda la
 * página, así también funcionan en las tarjetas que agrega "Cargar más").
 *
 * - Cambia el botón al instante y después confirma con el servidor; si falla,
 *   vuelve al estado anterior y avisa.
 * - Mantiene sincronizados todos los botones de la misma publicación o cuenta
 *   que haya en la página.
 * - Sin sesión, los botones son enlaces a /ingresar (no pasan por acá).
 */
import { actions } from "astro:actions";

type Kind = "like" | "save" | "follow";

const numberFormat = new Intl.NumberFormat("es-AR");

function selectorFor(button: HTMLElement): string {
  const kind = button.dataset.social as Kind;
  return `button[data-social="${kind}"][data-id="${button.dataset.id}"]`;
}

function render(id: string, kind: Kind, active: boolean, count: number | null) {
  for (const button of document.querySelectorAll<HTMLButtonElement>(`button[data-social="${kind}"][data-id="${id}"]`)) {
    button.setAttribute("aria-pressed", String(active));
    const label = button.querySelector<HTMLElement>("[data-label]");
    if (label) label.textContent = active ? (button.dataset.labelOn ?? "") : (button.dataset.labelOff ?? "");
    const counter = button.querySelector<HTMLElement>("[data-count]");
    if (counter && count !== null) counter.textContent = count > 0 ? numberFormat.format(count) : "";
  }
  if (kind === "follow" && count !== null) {
    for (const el of document.querySelectorAll<HTMLElement>(`[data-followers="${id}"]`)) {
      el.textContent = `${numberFormat.format(count)} ${count === 1 ? "seguidor" : "seguidores"}`;
    }
  }
}

function currentCount(button: HTMLElement, kind: Kind): number | null {
  if (kind === "follow") {
    const el = document.querySelector<HTMLElement>(`[data-followers="${button.dataset.id}"]`);
    return el ? Number.parseInt(el.textContent!.replace(/\D/g, ""), 10) || 0 : null;
  }
  const counter = button.querySelector<HTMLElement>("[data-count]");
  return counter ? Number.parseInt(counter.textContent!.replace(/\D/g, ""), 10) || 0 : null;
}

let toastTimer: number | undefined;
function toast(message: string) {
  let el = document.getElementById("wl-toast");
  if (!el) {
    el = document.createElement("div");
    el.id = "wl-toast";
    el.setAttribute("role", "status");
    el.className =
      "fixed inset-x-4 bottom-4 z-50 mx-auto max-w-sm rounded-wl bg-ink px-4 py-3 text-center text-sm font-medium text-white shadow-lg";
    document.body.append(el);
  }
  el.textContent = message;
  el.hidden = false;
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => (el!.hidden = true), 3500);
}

document.addEventListener("click", async (event) => {
  const button = (event.target as HTMLElement).closest<HTMLButtonElement>("button[data-social]");
  if (!button) return;
  event.preventDefault();
  if (button.dataset.busy) return;

  const kind = button.dataset.social as Kind;
  const id = button.dataset.id!;
  const wasActive = button.getAttribute("aria-pressed") === "true";
  const active = !wasActive;
  const before = currentCount(button, kind);

  render(id, kind, active, before === null ? null : Math.max(before + (active ? 1 : -1), 0));
  for (const b of document.querySelectorAll<HTMLElement>(selectorFor(button))) b.dataset.busy = "1";

  try {
    const result =
      kind === "like"
        ? await actions.social.like({ post_id: id, active })
        : kind === "save"
          ? await actions.social.save({ post_id: id, active })
          : await actions.social.follow({ kind: button.dataset.kind as "profile" | "business", id, active });

    if (result.error) {
      render(id, kind, wasActive, before);
      if (result.error.code === "UNAUTHORIZED") {
        window.location.href = `/ingresar?next=${encodeURIComponent(location.pathname + location.search)}`;
        return;
      }
      toast(result.error.message || "No pudimos guardar el cambio. Probá de nuevo.");
      return;
    }

    render(id, kind, result.data.active, result.data.count);
    if (kind === "save") toast(result.data.active ? "Guardada en tu panel → Guardados" : "Quitada de Guardados");
  } catch {
    render(id, kind, wasActive, before);
    toast("Sin conexión. Probá de nuevo.");
  } finally {
    for (const b of document.querySelectorAll<HTMLElement>(selectorFor(button))) delete b.dataset.busy;
  }
});
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/businesses.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Business, CatalogItem } from "../types/domain";
import { CITY_EMBED, toCityRef } from "./locations";

const BASE_COLUMNS = `id, owner_id, slug, name, tagline, description, logo_path, cover_path, status, verification,
  instagram, facebook, tiktok, website, hours, availability, followers_count, posts_count, rating_sum, rating_count,
  created_at, updated_at,
  categories ( id, name, slug, seo_noun ),
  cities ( ${CITY_EMBED} ),
  business_subcategories ( subcategories ( id, category_id, name, slug ) )`;

/** Contacto directo: solo usuarios logueados (privilegios por columna). */
const CONTACT_COLUMNS = "whatsapp, phone, email";

const CATALOG_COLUMNS = "id, name, slug, description, price, currency, price_type, cover_path, status, sort_order";

type Row = Record<string, unknown> & {
  categories: Business["category"];
  cities: Parameters<typeof toCityRef>[0];
  business_subcategories: { subcategories: Business["subcategories"][number] | null }[];
};

function toBusiness(row: Row): Business {
  const { categories, cities, business_subcategories, ...rest } = row;
  return {
    ...(rest as unknown as Business),
    category: categories ?? null,
    city: toCityRef(cities),
    subcategories: (business_subcategories ?? [])
      .map((link) => link.subcategories)
      .filter((sub): sub is NonNullable<typeof sub> => Boolean(sub))
      .sort((a, b) => a.name.localeCompare(b.name, "es")),
  };
}

/** Página pública /e/[slug]. Devuelve null si no existe o no es visible. */
export async function getBusinessBySlug(
  supabase: SupabaseClient,
  slug: string,
  { withContact }: { withContact: boolean },
): Promise<Business | null> {
  const { data, error } = await supabase
    .from("businesses")
    .select(withContact ? `${BASE_COLUMNS}, ${CONTACT_COLUMNS}` : BASE_COLUMNS)
    .eq("slug", slug.toLowerCase())
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw error;
  return data ? toBusiness(data as unknown as Row) : null;
}

/** Para editar desde el panel (el usuario tiene que ser miembro: lo garantiza RLS). */
export async function getBusinessForEdit(supabase: SupabaseClient, id: string): Promise<Business | null> {
  const { data, error } = await supabase
    .from("businesses")
    .select(`${BASE_COLUMNS}, ${CONTACT_COLUMNS}`)
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw error;
  return data ? toBusiness(data as unknown as Row) : null;
}

export interface MyBusiness {
  id: string;
  slug: string;
  name: string;
  logo_path: string | null;
  status: Business["status"];
  verification: Business["verification"];
  role: "owner" | "editor";
  category_name: string | null;
}

/** Emprendimientos donde el usuario es miembro. */
export async function getMyBusinesses(supabase: SupabaseClient, userId: string): Promise<MyBusiness[]> {
  const { data, error } = await supabase
    .from("business_members")
    .select("role, businesses!inner ( id, slug, name, logo_path, status, verification, deleted_at, categories ( name ) )")
    .eq("user_id", userId)
    .is("businesses.deleted_at", null);
  if (error) throw error;

  type LinkRow = {
    role: "owner" | "editor";
    businesses: Omit<MyBusiness, "role" | "category_name"> & { categories: { name: string } | null };
  };

  return ((data ?? []) as unknown as LinkRow[])
    .map(({ role, businesses: b }) => ({
      id: b.id,
      slug: b.slug,
      name: b.name,
      logo_path: b.logo_path,
      status: b.status,
      verification: b.verification,
      role,
      category_name: b.categories?.name ?? null,
    }))
    .sort((a, b) => a.name.localeCompare(b.name, "es"));
}

/** Emprendimientos activos de un usuario (perfil público). */
export async function getPublicBusinessesByOwner(supabase: SupabaseClient, ownerId: string) {
  const { data, error } = await supabase
    .from("businesses")
    .select("id, slug, name, tagline, logo_path, verification, categories ( name ), cities ( name )")
    .eq("owner_id", ownerId)
    .eq("status", "active")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(20);
  if (error) throw error;
  return (data ?? []) as unknown as {
    id: string;
    slug: string;
    name: string;
    tagline: string | null;
    logo_path: string | null;
    verification: Business["verification"];
    categories: { name: string } | null;
    cities: { name: string } | null;
  }[];
}

/**
 * Servicios y productos de un emprendimiento.
 * `onlyPublic`: solo los activos (página pública); si no, todos (panel).
 */
export async function getCatalog(
  supabase: SupabaseClient,
  businessId: string,
  { onlyPublic }: { onlyPublic: boolean },
): Promise<{ services: CatalogItem[]; products: CatalogItem[] }> {
  let services = supabase
    .from("services")
    .select(`${CATALOG_COLUMNS}, duration_min, service_area`)
    .eq("business_id", businessId)
    .is("deleted_at", null)
    .order("sort_order")
    .order("created_at")
    .limit(100);
  let products = supabase
    .from("products")
    .select(CATALOG_COLUMNS)
    .eq("business_id", businessId)
    .is("deleted_at", null)
    .order("sort_order")
    .order("created_at")
    .limit(100);

  if (onlyPublic) {
    services = services.eq("status", "active");
    products = products.eq("status", "active");
  }

  const [s, p] = await Promise.all([services, products]);
  if (s.error) throw s.error;
  if (p.error) throw p.error;
  return { services: (s.data ?? []) as CatalogItem[], products: (p.data ?? []) as CatalogItem[] };
}

/**
 * Elige un slug libre a partir del pedido (o del nombre): "pasteleria-ana",
 * "pasteleria-ana-2", ... Usa una función de la base que ve también
 * borradores y eliminados.
 */
export async function findAvailableSlug(supabase: SupabaseClient, base: string): Promise<string | null> {
  const clean = base.replace(/^-+|-+$/g, "").slice(0, 72) || "emprendimiento";
  const candidates = [clean.length >= 3 ? clean : `${clean}-ar`];
  for (let i = 2; i <= 6; i++) candidates.push(`${candidates[0]}-${i}`);
  for (const candidate of candidates) {
    const { data, error } = await supabase.rpc("is_business_slug_available", { p_slug: candidate });
    if (error) throw error;
    if (data === true) return candidate;
  }
  return null;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/categories.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import type { CategoryRef, SubcategoryRef } from "../types/domain";

export interface CategoryTree extends CategoryRef {
  subcategories: SubcategoryRef[];
}

/**
 * Árbol de categorías activas con sus subcategorías (una sola consulta).
 * Son pocas filas y cambian poco.
 */
export async function getCategoryTree(supabase: SupabaseClient): Promise<CategoryTree[]> {
  const { data, error } = await supabase
    .from("categories")
    .select("id, name, slug, seo_noun, sort_order, subcategories ( id, category_id, name, slug, sort_order, active )")
    .eq("active", true)
    .order("sort_order")
    .order("name");

  if (error) throw error;

  return (data ?? []).map((category) => ({
    id: category.id,
    name: category.name,
    slug: category.slug,
    seo_noun: category.seo_noun,
    subcategories: ((category.subcategories ?? []) as (SubcategoryRef & { sort_order: number; active: boolean })[])
      .filter((sub) => sub.active)
      .sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "es"))
      .map(({ id, category_id, name, slug }) => ({ id, category_id, name, slug })),
  }));
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/locations.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import type { CityRef } from "../types/domain";

/** Columnas para embeber una ciudad con su provincia en otras consultas. */
export const CITY_EMBED = "id, name, slug, provinces ( name, slug )";

interface CityRow {
  id: number;
  name: string;
  slug: string;
  provinces: { name: string; slug: string } | null;
}

export function toCityRef(row: CityRow | null | undefined): CityRef | null {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    slug: row.slug,
    province_name: row.provinces?.name ?? "",
    province_slug: row.provinces?.slug ?? "",
  };
}

export async function getCity(supabase: SupabaseClient, id: number): Promise<CityRef | null> {
  const { data } = await supabase.from("cities").select(CITY_EMBED).eq("id", id).maybeSingle();
  return toCityRef(data as CityRow | null);
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/posts.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import type { PostType } from "../schemas/post";

/**
 * Consultas de publicaciones. Paginación por cursor (published_at, id): cada
 * página pide las siguientes N a partir de la última vista, sin OFFSET, así
 * el costo es el mismo en la página 1 que en la 1000.
 */

export const FEED_PAGE_SIZE = 20;

export interface PostMediaView {
  id: string;
  path: string;
  kind: "image" | "video";
  mime: string;
  width: number | null;
  height: number | null;
  duration_s: number | null;
  bytes: number;
}

export interface PostView {
  id: string;
  type: PostType;
  title: string | null;
  body: string;
  price: number | null;
  currency: string;
  tags: string[];
  status: "published" | "hidden" | "removed";
  published_at: string;
  author_id: string;
  business_id: string | null;
  category_id: number | null;
  subcategory_id: number | null;
  city_id: number | null;
  likes_count: number;
  comments_count: number;
  saves_count: number;
  author: { username: string; first_name: string | null; last_name: string | null; avatar_path: string | null } | null;
  business: { slug: string; name: string; logo_path: string | null; verification: string } | null;
  city: { name: string; slug: string; provinces: { name: string } | null } | null;
  category: { name: string; slug: string } | null;
  subcategory: { name: string } | null;
  media: PostMediaView[];
}

const POST_COLUMNS = `id, type, title, body, price, currency, tags, status, published_at, author_id, business_id,
  category_id, subcategory_id, city_id, likes_count, comments_count, saves_count,
  author:profiles!posts_author_id_fkey ( username, first_name, last_name, avatar_path ),
  business:businesses ( slug, name, logo_path, verification ),
  city:cities ( name, slug, provinces ( name ) ),
  category:categories ( name, slug ),
  subcategory:subcategories ( name ),
  post_media ( position, media ( id, path, kind, mime, width, height, duration_s, bytes ) )`;

type Row = Omit<PostView, "media"> & {
  post_media: { position: number; media: PostMediaView | null }[] | null;
};

function toPost(row: Row): PostView {
  const { post_media, ...rest } = row;
  return {
    ...rest,
    price: rest.price === null ? null : Number(rest.price),
    media: (post_media ?? [])
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((pm) => pm.media)
      .filter((m): m is PostMediaView => Boolean(m)),
  };
}

/**
 * Una publicación es visible si su autor y (si tiene) su emprendimiento lo
 * son: RLS devuelve null en esos campos cuando están suspendidos o inactivos.
 */
const isVisible = (post: PostView) => Boolean(post.author) && (!post.business_id || Boolean(post.business));

export interface Cursor {
  publishedAt: string;
  id: string;
}

export function encodeCursor(post: { published_at: string; id: string }): string {
  return Buffer.from(`${post.published_at}|${post.id}`).toString("base64url");
}

export function decodeCursor(value: string | null | undefined): Cursor | null {
  if (!value) return null;
  try {
    const [publishedAt, id] = Buffer.from(value, "base64url").toString("utf8").split("|");
    if (!publishedAt || !id || Number.isNaN(Date.parse(publishedAt)) || !/^[0-9a-f-]{36}$/.test(id)) return null;
    return { publishedAt, id };
  } catch {
    return null;
  }
}

export interface FeedFilters {
  type?: PostType | null;
  businessId?: string | null;
  authorId?: string | null;
  /** Solo publicaciones personales (sin emprendimiento). */
  personalOnly?: boolean;
  /** Solo de personas y emprendimientos que sigue el usuario actual (pestaña "Siguiendo"). */
  following?: boolean;
  cursor?: Cursor | null;
  limit?: number;
}

export async function getFeed(
  supabase: SupabaseClient,
  { type, businessId, authorId, personalOnly, following, cursor, limit = FEED_PAGE_SIZE }: FeedFilters = {},
): Promise<{ posts: PostView[]; nextCursor: string | null }> {
  // "Siguiendo": la base devuelve los ids de la página (ya filtrados por los
  // seguimientos del usuario) y después se traen esas publicaciones.
  let followingIds: string[] | null = null;
  if (following) {
    const { data, error } = await supabase.rpc("following_feed_ids", {
      p_type: type ?? null,
      p_before_at: cursor?.publishedAt ?? null,
      p_before_id: cursor?.id ?? null,
      p_limit: limit + 1,
    });
    if (error) throw error;
    followingIds = ((data ?? []) as { id: string }[]).map((row) => row.id);
    if (!followingIds.length) return { posts: [], nextCursor: null };
  }

  let query = supabase
    .from("posts")
    .select(POST_COLUMNS)
    .eq("status", "published")
    .is("deleted_at", null)
    .order("published_at", { ascending: false })
    .order("id", { ascending: false })
    .order("position", { referencedTable: "post_media" })
    .limit(limit + 1);

  if (followingIds) query = query.in("id", followingIds);
  if (type) query = query.eq("type", type);
  if (businessId) query = query.eq("business_id", businessId);
  if (authorId) query = query.eq("author_id", authorId);
  if (personalOnly) query = query.is("business_id", null);
  if (cursor && !followingIds) {
    query = query.or(
      `published_at.lt."${cursor.publishedAt}",and(published_at.eq."${cursor.publishedAt}",id.lt.${cursor.id})`,
    );
  }

  const { data, error } = await query;
  if (error) throw error;

  const rows = (data ?? []) as unknown as Row[];
  const hasMore = followingIds ? followingIds.length > limit : rows.length > limit;
  const page = rows.slice(0, limit);
  const last = page[page.length - 1];
  return {
    posts: page.map(toPost).filter(isVisible),
    nextCursor: hasMore && last ? encodeCursor(last) : null,
  };
}

/** Publicación individual (pública, o del autor/equipo aunque esté oculta). */
export async function getPost(supabase: SupabaseClient, id: string): Promise<PostView | null> {
  const { data, error } = await supabase
    .from("posts")
    .select(POST_COLUMNS)
    .eq("id", id)
    .is("deleted_at", null)
    .order("position", { referencedTable: "post_media" })
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  const post = toPost(data as unknown as Row);
  return isVisible(post) || post.status !== "published" ? post : null;
}

/**
 * Varias publicaciones por id, en el mismo orden pedido (para "Guardados").
 * Las que ya no son visibles (ocultas, eliminadas) se omiten.
 */
export async function getPostsByIds(supabase: SupabaseClient, ids: string[]): Promise<PostView[]> {
  if (!ids.length) return [];
  const { data, error } = await supabase
    .from("posts")
    .select(POST_COLUMNS)
    .in("id", ids)
    .eq("status", "published")
    .is("deleted_at", null)
    .order("position", { referencedTable: "post_media" });
  if (error) throw error;
  const byId = new Map(((data ?? []) as unknown as Row[]).map((row) => [row.id, toPost(row)]));
  return ids.map((id) => byId.get(id)).filter((post): post is PostView => Boolean(post) && isVisible(post!));
}

/** Publicaciones que el usuario puede gestionar: propias o de sus emprendimientos. */
export async function getManageablePosts(
  supabase: SupabaseClient,
  userId: string,
  businessIds: string[],
  { cursor, limit = 30 }: { cursor?: Cursor | null; limit?: number } = {},
): Promise<{ posts: PostView[]; nextCursor: string | null }> {
  const owners = [`author_id.eq.${userId}`];
  if (businessIds.length) owners.push(`business_id.in.(${businessIds.join(",")})`);

  let query = supabase
    .from("posts")
    .select(POST_COLUMNS)
    .is("deleted_at", null)
    .or(owners.join(","))
    .order("published_at", { ascending: false })
    .order("id", { ascending: false })
    .order("position", { referencedTable: "post_media" })
    .limit(limit + 1);

  if (cursor) {
    query = query.or(
      `published_at.lt."${cursor.publishedAt}",and(published_at.eq."${cursor.publishedAt}",id.lt.${cursor.id})`,
    );
  }

  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as Row[];
  const page = rows.slice(0, limit);
  const last = page[page.length - 1];
  return { posts: page.map(toPost), nextCursor: rows.length > limit && last ? encodeCursor(last) : null };
}

/** Texto corto para URL y títulos: el título, o el comienzo del texto. */
export function postHeadline(post: Pick<PostView, "title" | "body">, max = 70): string {
  const text = (post.title || post.body).replace(/\s+/g, " ").trim();
  return text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;
}

export const POST_TYPE_LABELS: Record<PostType, { label: string; class: string }> = {
  offer: { label: "Ofrezco", class: "bg-offer-soft text-offer" },
  seeking: { label: "Busco", class: "bg-seek-soft text-seek" },
  product: { label: "Producto", class: "bg-success-soft text-success" },
  service: { label: "Servicio", class: "bg-surface-muted text-ink" },
  promotion: { label: "Promoción", class: "bg-warning-soft text-warning" },
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/profiles.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "../types/domain";
import { CITY_EMBED, toCityRef } from "./locations";

const PUBLIC_COLUMNS = `id, username, first_name, last_name, bio, avatar_path, intent,
  instagram, facebook, tiktok, website, followers_count, following_count, created_at, cities ( ${CITY_EMBED} )`;

/** Columnas de contacto directo: solo para usuarios logueados (RLS por columnas). */
const CONTACT_COLUMNS = "whatsapp, phone";

type ProfileRow = Omit<Profile, "city"> & { cities: Parameters<typeof toCityRef>[0] };

function toProfile(row: ProfileRow): Profile {
  const { cities, ...rest } = row;
  return { ...rest, city: toCityRef(cities) };
}

/** Perfil propio para editar (incluye contacto). */
export async function getOwnProfile(supabase: SupabaseClient, userId: string): Promise<Profile | null> {
  const { data, error } = await supabase
    .from("profiles")
    .select(`${PUBLIC_COLUMNS}, ${CONTACT_COLUMNS}`)
    .eq("id", userId)
    .maybeSingle();
  if (error) throw error;
  return data ? toProfile(data as unknown as ProfileRow) : null;
}

/** Perfil público por username. El contacto solo se pide si hay sesión. */
export async function getPublicProfile(
  supabase: SupabaseClient,
  username: string,
  { withContact }: { withContact: boolean },
): Promise<Profile | null> {
  const { data, error } = await supabase
    .from("profiles")
    .select(withContact ? `${PUBLIC_COLUMNS}, ${CONTACT_COLUMNS}` : PUBLIC_COLUMNS)
    .eq("username", username.toLowerCase())
    .eq("status", "active")
    .maybeSingle();
  if (error) throw error;
  return data ? toProfile(data as unknown as ProfileRow) : null;
}

export function displayName(profile: Pick<Profile, "first_name" | "last_name" | "username">): string {
  const full = [profile.first_name, profile.last_name].filter(Boolean).join(" ").trim();
  return full || `@${profile.username}`;
}

/** Porcentaje de perfil completo, para motivar a completarlo. */
export function profileCompleteness(profile: Profile): { percent: number; missing: string[] } {
  const checks: [boolean, string][] = [
    [Boolean(profile.avatar_path), "foto"],
    [Boolean(profile.bio), "descripción"],
    [Boolean(profile.city), "ciudad"],
    [Boolean(profile.whatsapp || profile.phone), "un teléfono"],
  ];
  const done = checks.filter(([ok]) => ok).length + 1; // nombre ya está
  return {
    percent: Math.round((done / (checks.length + 1)) * 100),
    missing: checks.filter(([ok]) => !ok).map(([, label]) => label),
  };
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/social.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Consultas de interacción social: me gusta, guardados, comentarios y
 * seguimientos. Las tablas son privadas por RLS (cada uno ve lo suyo); los
 * contadores públicos están en posts, profiles y businesses.
 */

export interface ViewerReactions {
  liked: Set<string>;
  saved: Set<string>;
}

const EMPTY: ViewerReactions = { liked: new Set(), saved: new Set() };

/** ¿Cuáles de estas publicaciones le gustan / tiene guardadas el usuario? */
export async function getViewerReactions(
  supabase: SupabaseClient,
  userId: string | null | undefined,
  postIds: string[],
): Promise<ViewerReactions> {
  if (!userId || !postIds.length) return EMPTY;
  const ids = [...new Set(postIds)];
  const [likes, saves] = await Promise.all([
    supabase.from("post_likes").select("post_id").eq("user_id", userId).in("post_id", ids),
    supabase.from("post_saves").select("post_id").eq("user_id", userId).in("post_id", ids),
  ]);
  if (likes.error) throw likes.error;
  if (saves.error) throw saves.error;
  return {
    liked: new Set((likes.data ?? []).map((row) => row.post_id as string)),
    saved: new Set((saves.data ?? []).map((row) => row.post_id as string)),
  };
}

/** ¿El usuario sigue a esta persona o emprendimiento? */
export async function isFollowing(
  supabase: SupabaseClient,
  userId: string | null | undefined,
  kind: "profile" | "business",
  id: string,
): Promise<boolean> {
  if (!userId) return false;
  const query =
    kind === "profile"
      ? supabase.from("profile_follows").select("followed_id").eq("follower_id", userId).eq("followed_id", id)
      : supabase.from("business_follows").select("business_id").eq("follower_id", userId).eq("business_id", id);
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  return Boolean(data);
}

/** ¿Sigue a alguien? (para mostrar u ocultar la pestaña "Siguiendo" vacía). */
export async function followsAnyone(supabase: SupabaseClient, userId: string): Promise<boolean> {
  const { data, error } = await supabase.from("profiles").select("following_count").eq("id", userId).maybeSingle();
  if (error) throw error;
  return (data?.following_count ?? 0) > 0;
}

export interface CommentView {
  id: string;
  post_id: string;
  author_id: string;
  body: string;
  created_at: string;
  author: { username: string; first_name: string | null; last_name: string | null; avatar_path: string | null } | null;
}

export const COMMENTS_PAGE_SIZE = 50;

/**
 * Comentarios de una publicación, del más viejo al más nuevo (como una
 * conversación). Trae los últimos `limit`; `before` pagina hacia atrás.
 */
export async function getComments(
  supabase: SupabaseClient,
  postId: string,
  { limit = COMMENTS_PAGE_SIZE, before }: { limit?: number; before?: string | null } = {},
): Promise<{ comments: CommentView[]; hasOlder: boolean }> {
  let query = supabase
    .from("post_comments")
    .select("id, post_id, author_id, body, created_at, author:profiles!post_comments_author_id_fkey ( username, first_name, last_name, avatar_path )")
    .eq("post_id", postId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(limit + 1);
  if (before && !Number.isNaN(Date.parse(before))) query = query.lt("created_at", before);

  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as CommentView[];
  return {
    // Se omiten comentarios de cuentas suspendidas (RLS devuelve author null).
    comments: rows.slice(0, limit).filter((c) => c.author).reverse(),
    hasOlder: rows.length > limit,
  };
}

export const SAVED_PAGE_SIZE = 20;

/** Ids de publicaciones guardadas por el usuario, de la más reciente a la más vieja. */
export async function getSavedPostIds(
  supabase: SupabaseClient,
  userId: string,
  page: number,
): Promise<{ ids: string[]; hasMore: boolean }> {
  const from = (page - 1) * SAVED_PAGE_SIZE;
  const { data, error } = await supabase
    .from("post_saves")
    .select("post_id")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .range(from, from + SAVED_PAGE_SIZE);
  if (error) throw error;
  const ids = (data ?? []).map((row) => row.post_id as string);
  return { ids: ids.slice(0, SAVED_PAGE_SIZE), hasMore: ids.length > SAVED_PAGE_SIZE };
}

/** "1 seguidor" / "1.234 seguidores". */
export function followersLabel(count: number): string {
  return `${count.toLocaleString("es-AR")} ${count === 1 ? "seguidor" : "seguidores"}`;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/storage.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import { mediaPresets, type MediaPurpose } from "../config/media";
import { mediaFiles } from "../lib/media";

/**
 * Borra de Storage todas las variantes de una imagen que ya no se usa.
 * Se ejecuta con la sesión del usuario: las políticas solo le permiten borrar
 * de su propia carpeta. Un error acá no debe cortar el guardado (el archivo
 * huérfano lo limpia el cron de mantenimiento).
 */
export async function removeMedia(supabase: SupabaseClient, purpose: MediaPurpose, basePath: string | null | undefined) {
  if (!basePath) return;
  const { error } = await supabase.storage.from(mediaPresets[purpose].bucket).remove(mediaFiles(purpose, basePath));
  if (error) console.warn("[storage] no se pudo borrar", basePath, error.message);
}

/** ¿Existe la variante principal de la imagen? (evita guardar rutas inventadas) */
export async function mediaExists(supabase: SupabaseClient, purpose: MediaPurpose, basePath: string): Promise<boolean> {
  const preset = mediaPresets[purpose];
  const { data, error } = await supabase.storage.from(preset.bucket).list(basePath, { limit: 10 });
  if (error) return false;
  const names = new Set((data ?? []).map((file) => file.name));
  return preset.sizes.every((size) => names.has(`${size}.webp`));
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/styles/global.css' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/* =============================================================================
   WorkLink · estilos globales y tokens de diseño (identidad provisional)
   =============================================================================
   Toda la marca vive en las variables --wl-* de abajo. Para cambiar colores,
   radios o tipografía se tocan SOLO estas variables: los componentes usan
   las clases de Tailwind generadas a partir de ellas (bg-brand, text-ink...).

   Concepto: dos lados que se encuentran.
     --wl-seek  (azul)    → "Necesito / Busco"
     --wl-offer (naranja) → "Ofrezco / Vendo"
   ========================================================================== */

@import "tailwindcss";

/* Modo oscuro por clase/atributo además de la preferencia del sistema. */
@custom-variant dark (&:where([data-theme="dark"], [data-theme="dark"] *));

:root {
  /* Marca */
  --wl-brand: #2f4fd8;
  --wl-brand-hover: #2440b8;
  --wl-brand-contrast: #ffffff;
  --wl-seek: #2f4fd8;
  --wl-seek-soft: #e8ecfd;
  --wl-offer: #e8572e;
  --wl-offer-soft: #fdece6;

  /* Superficies y texto */
  --wl-bg: #f7f7f4;
  --wl-surface: #ffffff;
  --wl-surface-muted: #efefea;
  --wl-ink: #14161f;
  --wl-ink-muted: #5b5f6e;
  --wl-line: #e2e2dc;

  /* Estados */
  --wl-success: #16794a;
  --wl-success-soft: #e3f4ea;
  --wl-danger: #c0362c;
  --wl-danger-soft: #fbe9e7;
  --wl-warning: #9a6200;
  --wl-warning-soft: #fdf3dc;

  /* Forma y tipografía */
  --wl-radius: 0.75rem;
  --wl-radius-lg: 1.25rem;
  --wl-font-sans: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial,
    "Noto Sans", sans-serif;
  --wl-font-display: var(--wl-font-sans);

  color-scheme: light;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --wl-brand: #7d93ff;
    --wl-brand-hover: #9aaaff;
    --wl-brand-contrast: #0d1020;
    --wl-seek: #7d93ff;
    --wl-seek-soft: #1c2240;
    --wl-offer: #ff8a63;
    --wl-offer-soft: #3a1f17;
    --wl-bg: #0f1016;
    --wl-surface: #171922;
    --wl-surface-muted: #20222d;
    --wl-ink: #eceef5;
    --wl-ink-muted: #a3a7b7;
    --wl-line: #2b2e3b;
    --wl-success: #5fd39a;
    --wl-success-soft: #13291f;
    --wl-danger: #ff8a80;
    --wl-danger-soft: #34171a;
    --wl-warning: #f3c063;
    --wl-warning-soft: #2f2412;
    color-scheme: dark;
  }
}

:root[data-theme="dark"] {
  --wl-brand: #7d93ff;
  --wl-brand-hover: #9aaaff;
  --wl-brand-contrast: #0d1020;
  --wl-seek: #7d93ff;
  --wl-seek-soft: #1c2240;
  --wl-offer: #ff8a63;
  --wl-offer-soft: #3a1f17;
  --wl-bg: #0f1016;
  --wl-surface: #171922;
  --wl-surface-muted: #20222d;
  --wl-ink: #eceef5;
  --wl-ink-muted: #a3a7b7;
  --wl-line: #2b2e3b;
  --wl-success: #5fd39a;
  --wl-success-soft: #13291f;
  --wl-danger: #ff8a80;
  --wl-danger-soft: #34171a;
  --wl-warning: #f3c063;
  --wl-warning-soft: #2f2412;
  color-scheme: dark;
}

/* Las variables de marca se exponen como utilidades de Tailwind:
   bg-brand, text-ink, border-line, bg-seek-soft, rounded-wl, font-display... */
@theme inline {
  --color-brand: var(--wl-brand);
  --color-brand-hover: var(--wl-brand-hover);
  --color-brand-contrast: var(--wl-brand-contrast);
  --color-seek: var(--wl-seek);
  --color-seek-soft: var(--wl-seek-soft);
  --color-offer: var(--wl-offer);
  --color-offer-soft: var(--wl-offer-soft);
  --color-bg: var(--wl-bg);
  --color-surface: var(--wl-surface);
  --color-surface-muted: var(--wl-surface-muted);
  --color-ink: var(--wl-ink);
  --color-ink-muted: var(--wl-ink-muted);
  --color-line: var(--wl-line);
  --color-success: var(--wl-success);
  --color-success-soft: var(--wl-success-soft);
  --color-danger: var(--wl-danger);
  --color-danger-soft: var(--wl-danger-soft);
  --color-warning: var(--wl-warning);
  --color-warning-soft: var(--wl-warning-soft);

  --radius-wl: var(--wl-radius);
  --radius-wl-lg: var(--wl-radius-lg);

  --font-sans: var(--wl-font-sans);
  --font-display: var(--wl-font-display);
}

@layer base {
  html {
    -webkit-text-size-adjust: 100%;
    text-rendering: optimizeLegibility;
  }

  body {
    @apply bg-bg text-ink font-sans antialiased;
    min-height: 100dvh;
  }

  h1, h2, h3 {
    @apply font-display tracking-tight text-balance;
  }

  :focus-visible {
    outline: 2px solid var(--wl-brand);
    outline-offset: 2px;
  }

  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
      animation-duration: 0.01ms !important;
      transition-duration: 0.01ms !important;
    }
  }
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/types/domain.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Tipos del dominio usados en la interfaz. Reflejan las columnas que cada
 * consulta pide (nunca SELECT *). Cuando se generen los tipos de Supabase
 * (npm run db:types) se pueden derivar de ahí.
 */
import type { BusinessHours } from "../schemas/business";
import type { PriceType } from "../lib/format";

export interface CityRef {
  id: number;
  name: string;
  slug: string;
  province_name: string;
  province_slug: string;
}

export interface Profile {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  bio: string | null;
  avatar_path: string | null;
  intent: "seeker" | "provider";
  city: CityRef | null;
  whatsapp?: string | null;
  phone?: string | null;
  instagram: string | null;
  facebook: string | null;
  tiktok: string | null;
  website: string | null;
  followers_count: number;
  following_count: number;
  created_at: string;
}

export interface CategoryRef {
  id: number;
  name: string;
  slug: string;
  seo_noun: string | null;
}

export interface SubcategoryRef {
  id: number;
  category_id: number;
  name: string;
  slug: string;
}

export type BusinessStatus = "draft" | "active" | "inactive" | "suspended";

export interface CatalogItem {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  price: number | null;
  currency: string;
  price_type: PriceType;
  cover_path: string | null;
  status: "active" | "hidden" | "archived";
  sort_order: number;
  duration_min?: number | null;
  service_area?: string | null;
}

export interface Business {
  id: string;
  owner_id: string;
  slug: string;
  name: string;
  tagline: string | null;
  description: string | null;
  logo_path: string | null;
  cover_path: string | null;
  status: BusinessStatus;
  verification: "none" | "pending" | "verified" | "rejected";
  category: CategoryRef | null;
  subcategories: SubcategoryRef[];
  city: CityRef | null;
  whatsapp?: string | null;
  phone?: string | null;
  email?: string | null;
  instagram: string | null;
  facebook: string | null;
  tiktok: string | null;
  website: string | null;
  hours: BusinessHours | null;
  availability: string | null;
  followers_count: number;
  posts_count: number;
  rating_sum: number;
  rating_count: number;
  created_at: string;
  updated_at: string;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/utils/form.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Valores enviados en un formulario POST, para volver a mostrarlos cuando la
 * validación falla (así el usuario no reescribe todo). Nunca devuelve
 * contraseñas.
 */
export async function getSubmittedValues(request: Request): Promise<Record<string, string>> {
  const data = await getSubmittedForm(request);
  if (!data) return {};
  const values: Record<string, string> = {};
  for (const [key, value] of data.entries()) {
    if (typeof value === "string" && !key.toLowerCase().includes("password")) {
      values[key] = value.slice(0, 5000);
    }
  }
  return values;
}

/** El FormData completo enviado (para campos repetidos como casillas múltiples). */
export async function getSubmittedForm(request: Request): Promise<FormData | null> {
  if (request.method !== "POST") return null;
  try {
    return await request.clone().formData();
  } catch {
    return null;
  }
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/utils/slug.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * "Pastelería Ana & Co." -> "pasteleria-ana-co"
 * Igual que la función slugify() de la base de datos.
 */
export function slugify(input: string, maxLength = 80): string {
  return input
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, maxLength)
    .replace(/-+$/g, "");
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'astro.config.mjs' << '__WORKLINK_FIN_DEL_ARCHIVO__'
// @ts-check
import { defineConfig, envField } from "astro/config";
import { loadEnv } from "vite";
import tailwindcss from "@tailwindcss/vite";
import vercel from "@astrojs/vercel";
import preact from "@astrojs/preact";

// Lee .env también al cargar la configuración (Vercel inyecta las variables).
const { PUBLIC_SITE_URL } = loadEnv(process.env.NODE_ENV ?? "development", process.cwd(), "");

// https://docs.astro.build/en/reference/configuration-reference/
export default defineConfig({
  // URL pública del sitio: canonical, sitemap y links de emails.
  site: PUBLIC_SITE_URL || "http://localhost:4321",

  // Todas las rutas se renderizan en el servidor salvo las que declaren
  // `export const prerender = true` (páginas estáticas).
  output: "server",

  adapter: vercel({
    // Analíticas de rendimiento (Core Web Vitals) del panel de Vercel.
    webAnalytics: { enabled: false },
  }),

  integrations: [preact()],

  vite: {
    plugins: [tailwindcss()],
  },

  // Variables de entorno tipadas y validadas al arrancar (astro:env).
  env: {
    schema: {
      PUBLIC_SUPABASE_URL: envField.string({ context: "client", access: "public", url: true }),
      PUBLIC_SUPABASE_ANON_KEY: envField.string({ context: "client", access: "public" }),
      PUBLIC_SITE_URL: envField.string({
        context: "client",
        access: "public",
        url: true,
        default: "http://localhost:4321",
      }),
      // Solo servidor. Opcional hasta que se use (webhooks, cron, admin).
      SUPABASE_SERVICE_ROLE_KEY: envField.string({ context: "server", access: "secret", optional: true }),
      // Secreto que Vercel Cron envía para autorizar las tareas programadas.
      CRON_SECRET: envField.string({ context: "server", access: "secret", optional: true }),
    },
    validateSecrets: true,
  },

  security: {
    // Rechaza envíos de formularios desde otros dominios (CSRF).
    checkOrigin: true,
  },

  prefetch: {
    prefetchAll: false,
    defaultStrategy: "hover",
  },
});
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'vercel.json' << '__WORKLINK_FIN_DEL_ARCHIVO__'
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "crons": [
    {
      "path": "/api/cron/limpiar-archivos",
      "schedule": "0 7 * * *"
    }
  ]
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir '.env.example' << '__WORKLINK_FIN_DEL_ARCHIVO__'
# Copiá este archivo como .env y completá los valores.
# .env NO se sube a Git (está en .gitignore).

# Supabase → Project Settings → API
PUBLIC_SUPABASE_URL=https://TU-PROYECTO.supabase.co
# Clave pública: "anon" o "publishable" (empieza con eyJ... o sb_publishable_...)
PUBLIC_SUPABASE_ANON_KEY=

# URL del sitio (en local, la de astro dev; en Vercel, el dominio real)
PUBLIC_SITE_URL=http://localhost:4321

# Solo servidor. NUNCA con prefijo PUBLIC_.
# Supabase -> Project Settings -> API Keys -> Secret key (sb_secret_...)
SUPABASE_SERVICE_ROLE_KEY=

# Secreto para las tareas programadas (Vercel Cron). Inventá uno largo y al azar.
CRON_SECRET=
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'supabase/migrations/20261008001200_social.sql' << '__WORKLINK_FIN_DEL_ARCHIVO__'
-- =============================================================================
-- 0012 · Interacción social (Etapa 6)
-- =============================================================================
-- * Me gusta y guardados de publicaciones (una fila por usuario y publicación).
-- * Comentarios en publicaciones (texto plano, hasta 1000 caracteres).
-- * Seguir personas y emprendimientos.
-- * Todos los contadores (likes_count, comments_count, saves_count,
--   followers_count, following_count) los mantiene la base con triggers:
--   nadie puede escribirlos desde la app.
-- * Quién dio me gusta, quién guardó y a quién sigue cada uno es privado: cada
--   usuario ve solo lo suyo. Los números son públicos.
-- * Bloqueos: si una persona bloqueó a otra (en cualquier sentido), no pueden
--   comentarse ni seguirse, y al bloquear se borran los seguimientos mutuos.
-- * Límites anti-abuso configurables en settings.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Contadores sin tocar updated_at
-- -----------------------------------------------------------------------------
-- updated_at indica cambios de contenido (lo usarán el sitemap y la caché).
-- Los triggers de contadores activan esta marca para no modificarlo.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('worklink.counter_update', true), '') = 'on' then
    return new;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Suma (o resta) a un contador de una tabla, sin bajar de cero.
-- Uso interno de los triggers; no se expone a la API.
create or replace function public.bump_counter(p_table text, p_column text, p_id uuid, p_delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_table not in ('posts', 'profiles', 'businesses')
     or p_column not in ('likes_count', 'comments_count', 'saves_count', 'followers_count', 'following_count') then
    raise exception 'Contador inválido';
  end if;
  perform set_config('worklink.counter_update', 'on', true);
  execute format('update public.%I set %I = greatest(%I + $1, 0) where id = $2', p_table, p_column, p_column)
    using p_delta, p_id;
  perform set_config('worklink.counter_update', 'off', true);
end;
$$;

revoke execute on function public.bump_counter(text, text, uuid, integer) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Contadores de seguidores en perfiles
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column followers_count integer not null default 0,
  add column following_count integer not null default 0,
  add constraint profiles_follow_counters_nonneg check (followers_count >= 0 and following_count >= 0);

-- Visibles también para visitantes sin cuenta.
grant select (followers_count, following_count) on public.profiles to anon;

create or replace function public.tg_profiles_protect()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_system_call() then
    return new;
  end if;

  if new.id <> old.id or new.created_at <> old.created_at then
    raise exception 'No se pueden modificar id ni created_at' using errcode = '42501';
  end if;

  if new.followers_count <> old.followers_count or new.following_count <> old.following_count then
    raise exception 'Campo administrado por el sistema' using errcode = '42501';
  end if;

  if new.status is distinct from old.status and not (select public.has_role('moderator')) then
    raise exception 'Solo moderación puede cambiar el estado de una cuenta' using errcode = '42501';
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Funciones de apoyo para las políticas
-- -----------------------------------------------------------------------------

-- ¿El usuario actual puede interactuar con la publicación? Debe estar
-- publicada, con autor activo, y sin bloqueo entre el usuario y el autor.
create or replace function public.can_interact_with_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.posts p
    join public.profiles a on a.id = p.author_id and a.status = 'active'
    where p.id = p_post_id
      and p.status = 'published'
      and p.deleted_at is null
      and not public.is_blocked_between((select auth.uid()), p.author_id)
  );
$$;

revoke execute on function public.can_interact_with_post(uuid) from public, anon;
grant  execute on function public.can_interact_with_post(uuid) to authenticated, service_role;

-- ¿El usuario actual puede seguir a esta persona? (activa, no es él mismo, sin bloqueo)
create or replace function public.can_follow_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_profile_id <> (select auth.uid())
     and exists (select 1 from public.profiles p where p.id = p_profile_id and p.status = 'active')
     and not public.is_blocked_between((select auth.uid()), p_profile_id);
$$;

revoke execute on function public.can_follow_profile(uuid) from public, anon;
grant  execute on function public.can_follow_profile(uuid) to authenticated, service_role;

-- (is_business_public ya existe desde la migración 0005.)

-- Límite genérico: cuántas filas creó el usuario en una tabla en un período.
-- Lanza 'rate_limited' si se pasa. Uso interno de los triggers.
create or replace function public.enforce_rate_limit(
  p_count bigint, p_setting text, p_default integer, p_message text
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_count >= public.setting_int(p_setting, p_default) then
    raise exception '%', p_message using errcode = 'P0001', hint = 'rate_limited';
  end if;
end;
$$;

revoke execute on function public.enforce_rate_limit(bigint, text, integer, text) from public, anon;
grant  execute on function public.enforce_rate_limit(bigint, text, integer, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Me gusta
-- -----------------------------------------------------------------------------
create table public.post_likes (
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index post_likes_user_idx on public.post_likes (user_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Guardados
-- -----------------------------------------------------------------------------
create table public.post_saves (
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index post_saves_user_idx on public.post_saves (user_id, created_at desc);

-- La fecha la pone la base (para ordenar "Guardados" sin que se pueda falsear).
create or replace function public.tg_reaction_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_system_call() then
    new.user_id := (select auth.uid());
    new.created_at := now();
  end if;
  return new;
end;
$$;

create trigger post_likes_before_insert
  before insert on public.post_likes
  for each row execute function public.tg_reaction_before_insert();

create trigger post_saves_before_insert
  before insert on public.post_saves
  for each row execute function public.tg_reaction_before_insert();

create or replace function public.tg_post_likes_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('posts', 'likes_count', new.post_id, 1);
  else
    perform public.bump_counter('posts', 'likes_count', old.post_id, -1);
  end if;
  return null;
end;
$$;

create trigger post_likes_counter
  after insert or delete on public.post_likes
  for each row execute function public.tg_post_likes_counter();

create or replace function public.tg_post_saves_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('posts', 'saves_count', new.post_id, 1);
  else
    perform public.bump_counter('posts', 'saves_count', old.post_id, -1);
  end if;
  return null;
end;
$$;

create trigger post_saves_counter
  after insert or delete on public.post_saves
  for each row execute function public.tg_post_saves_counter();

-- -----------------------------------------------------------------------------
-- Comentarios
-- -----------------------------------------------------------------------------
create table public.post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts (id) on delete cascade,
  author_id  uuid not null references public.profiles (id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now(),
  constraint post_comments_body_len check (char_length(btrim(body)) between 1 and 1000)
);

create index post_comments_post_idx   on public.post_comments (post_id, created_at desc, id desc);
create index post_comments_author_idx on public.post_comments (author_id, created_at desc);

create or replace function public.tg_post_comments_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.body := btrim(new.body);
  if public.is_system_call() then
    return new;
  end if;

  new.author_id := (select auth.uid());
  new.created_at := now();

  perform public.enforce_rate_limit(
    (select count(*) from public.post_comments c
      where c.author_id = new.author_id and c.created_at > now() - interval '1 hour'),
    'limits.comments_per_hour', 60,
    'Escribiste muchos comentarios seguidos. Esperá un rato y probá de nuevo.'
  );
  return new;
end;
$$;

create trigger post_comments_before_insert
  before insert on public.post_comments
  for each row execute function public.tg_post_comments_before_insert();

-- Los comentarios no se editan (se borran y se escriben de nuevo).
create or replace function public.tg_post_comments_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('posts', 'comments_count', new.post_id, 1);
  else
    perform public.bump_counter('posts', 'comments_count', old.post_id, -1);
  end if;
  return null;
end;
$$;

create trigger post_comments_counter
  after insert or delete on public.post_comments
  for each row execute function public.tg_post_comments_counter();

-- -----------------------------------------------------------------------------
-- Seguir personas
-- -----------------------------------------------------------------------------
create table public.profile_follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followed_id uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followed_id),
  constraint profile_follows_not_self check (follower_id <> followed_id)
);

create index profile_follows_followed_idx on public.profile_follows (followed_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Seguir emprendimientos
-- -----------------------------------------------------------------------------
create table public.business_follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  business_id uuid not null references public.businesses (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, business_id)
);

create index business_follows_business_idx on public.business_follows (business_id, created_at desc);

create or replace function public.tg_follows_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_system_call() then
    return new;
  end if;

  new.follower_id := (select auth.uid());
  new.created_at := now();

  perform public.enforce_rate_limit(
    (select count(*) from public.profile_follows f
      where f.follower_id = new.follower_id and f.created_at > now() - interval '24 hours')
    + (select count(*) from public.business_follows f
      where f.follower_id = new.follower_id and f.created_at > now() - interval '24 hours'),
    'limits.follows_per_day', 200,
    'Seguiste a muchas cuentas hoy. Probá de nuevo mañana.'
  );
  return new;
end;
$$;

create trigger profile_follows_before_insert
  before insert on public.profile_follows
  for each row execute function public.tg_follows_before_insert();

create trigger business_follows_before_insert
  before insert on public.business_follows
  for each row execute function public.tg_follows_before_insert();

create or replace function public.tg_profile_follows_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('profiles', 'followers_count', new.followed_id, 1);
    perform public.bump_counter('profiles', 'following_count', new.follower_id, 1);
  else
    perform public.bump_counter('profiles', 'followers_count', old.followed_id, -1);
    perform public.bump_counter('profiles', 'following_count', old.follower_id, -1);
  end if;
  return null;
end;
$$;

create trigger profile_follows_counter
  after insert or delete on public.profile_follows
  for each row execute function public.tg_profile_follows_counter();

create or replace function public.tg_business_follows_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump_counter('businesses', 'followers_count', new.business_id, 1);
    perform public.bump_counter('profiles', 'following_count', new.follower_id, 1);
  else
    perform public.bump_counter('businesses', 'followers_count', old.business_id, -1);
    perform public.bump_counter('profiles', 'following_count', old.follower_id, -1);
  end if;
  return null;
end;
$$;

create trigger business_follows_counter
  after insert or delete on public.business_follows
  for each row execute function public.tg_business_follows_counter();

-- Al bloquear a alguien se cortan los seguimientos en ambos sentidos.
create or replace function public.tg_user_blocks_unfollow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.profile_follows
  where (follower_id = new.blocker_id and followed_id = new.blocked_id)
     or (follower_id = new.blocked_id and followed_id = new.blocker_id);
  return null;
end;
$$;

create trigger user_blocks_unfollow
  after insert on public.user_blocks
  for each row execute function public.tg_user_blocks_unfollow();

-- -----------------------------------------------------------------------------
-- Seguridad a nivel de fila
-- -----------------------------------------------------------------------------
alter table public.post_likes       enable row level security;
alter table public.post_saves       enable row level security;
alter table public.post_comments    enable row level security;
alter table public.profile_follows  enable row level security;
alter table public.business_follows enable row level security;

-- Me gusta: cada uno ve y maneja solo los suyos.
create policy "post_likes: veo los míos" on public.post_likes
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "post_likes: doy me gusta" on public.post_likes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.can_interact_with_post(post_id))
  );

create policy "post_likes: quito mi me gusta" on public.post_likes
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Guardados: igual que me gusta.
create policy "post_saves: veo los míos" on public.post_saves
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "post_saves: guardo" on public.post_saves
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.can_interact_with_post(post_id))
  );

create policy "post_saves: quito de guardados" on public.post_saves
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Comentarios: visibles si la publicación lo es (o para quien la edita y
-- moderación). Comenta cualquier usuario activo sin bloqueo con el autor.
-- Borran: quien lo escribió, quien edita la publicación y moderación.
create policy "post_comments: lectura" on public.post_comments
  for select to anon, authenticated
  using (
    (select public.is_post_public(post_id))
    or (select public.can_edit_post(post_id))
    or (select public.has_role('moderator'))
  );

create policy "post_comments: comentar" on public.post_comments
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.can_interact_with_post(post_id))
  );

create policy "post_comments: borrar" on public.post_comments
  for delete to authenticated
  using (
    author_id = (select auth.uid())
    or (select public.can_edit_post(post_id))
    or (select public.has_role('moderator'))
  );

-- Seguir personas: cada uno ve a quién sigue y quién lo sigue.
create policy "profile_follows: veo los míos" on public.profile_follows
  for select to authenticated
  using (follower_id = (select auth.uid()) or followed_id = (select auth.uid()));

create policy "profile_follows: sigo" on public.profile_follows
  for insert to authenticated
  with check (
    follower_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.can_follow_profile(followed_id))
  );

create policy "profile_follows: dejo de seguir" on public.profile_follows
  for delete to authenticated
  using (follower_id = (select auth.uid()));

-- Seguir emprendimientos: cada uno ve a quién sigue; el equipo ve sus seguidores.
create policy "business_follows: veo los míos" on public.business_follows
  for select to authenticated
  using (follower_id = (select auth.uid()) or (select public.is_business_member(business_id)));

create policy "business_follows: sigo" on public.business_follows
  for insert to authenticated
  with check (
    follower_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.is_business_public(business_id))
  );

create policy "business_follows: dejo de seguir" on public.business_follows
  for delete to authenticated
  using (follower_id = (select auth.uid()));

-- Sin UPDATE en ninguna: se crean y se borran.
revoke all on public.post_likes, public.post_saves, public.post_comments,
  public.profile_follows, public.business_follows from anon, authenticated;
grant select, insert, delete on public.post_likes, public.post_saves, public.post_comments,
  public.profile_follows, public.business_follows to authenticated;
grant select on public.post_comments to anon;

-- -----------------------------------------------------------------------------
-- Feed "Siguiendo": ids de publicaciones de personas y emprendimientos que
-- sigue el usuario actual, paginadas por cursor (published_at, id).
-- SECURITY INVOKER: aplica RLS como cualquier consulta. La app trae después
-- el detalle de esas publicaciones (máximo 50 por llamada).
-- -----------------------------------------------------------------------------
create or replace function public.following_feed_ids(
  p_type      public.post_type default null,
  p_before_at timestamptz      default null,
  p_before_id uuid             default null,
  p_limit     integer          default 20
)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id
  from public.posts p
  where p.status = 'published'
    and p.deleted_at is null
    and (p_type is null or p.type = p_type)
    and (p_before_at is null or (p.published_at, p.id) < (p_before_at, coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    and (
      p.author_id in (select f.followed_id from public.profile_follows f where f.follower_id = (select auth.uid()))
      or p.business_id in (select f.business_id from public.business_follows f where f.follower_id = (select auth.uid()))
    )
  order by p.published_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.following_feed_ids(public.post_type, timestamptz, uuid, integer) from public, anon;
grant  execute on function public.following_feed_ids(public.post_type, timestamptz, uuid, integer) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Límites (editables por admin)
-- -----------------------------------------------------------------------------
insert into public.settings (key, value, is_public, description) values
  ('limits.comments_per_hour', '60',  false, 'Comentarios por usuario cada hora'),
  ('limits.follows_per_day',   '200', false, 'Cuentas que un usuario puede empezar a seguir cada 24 h')
on conflict (key) do nothing;

-- Avisa a la API (PostgREST) que recargue el esquema con las tablas nuevas.
notify pgrst, 'reload schema';
__WORKLINK_FIN_DEL_ARCHIVO__

echo ""
echo "============================================================"
echo " Listo. 107 archivos de la Etapa 6 instalados."
echo " Siguiente paso: subí la migración nueva a Supabase con"
echo "     npx supabase db push"
echo "============================================================"
