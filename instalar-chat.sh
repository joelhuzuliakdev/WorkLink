#!/usr/bin/env bash
# =============================================================================
# WorkLink · chat más chico con ✕ y avisos de mensajes al momento (incluye la Etapa 9)
# =============================================================================
# Uso, en Git Bash, desde la carpeta raíz del proyecto (donde está package.json):
#     bash instalar-chat.sh
#
# Crea o reemplaza los archivos de src/ y public/, astro.config.mjs, vercel.json
# y .env.example, y agrega la migración 0017 (incluye todo lo anterior). NO toca tu .env, node_modules ni
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
# Archivos que cambiaron de lugar (si quedaran, Astro tendría dos rutas iguales).
rm -f 'src/pages/u/[username].astro'

echo "Instalando archivos de la Etapa 9..."

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
          emailRedirectTo: confirmUrl(routes.home),
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

      return { redirectTo: safeNextPath(input.next, routes.home) };
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
import { messages } from "./messages";

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
  messages,
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/actions/messages.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { ActionError, defineAction } from "astro:actions";
import { conversationRefSchema, sendMessageSchema } from "../schemas/message";
import { dbError, requireUser } from "../lib/auth/guards";

/**
 * Mensajes privados. La base controla quién puede escribir (participantes,
 * sin bloqueo, cuenta activa) y los límites; acá se traducen los errores.
 */
export const messages = {
  send: defineAction({
    accept: "form",
    input: sendMessageSchema,
    handler: async ({ conversation_id, body, post_id }, { locals }) => {
      const user = requireUser(locals.user);
      const { data, error } = await locals.supabase
        .from("messages")
        .insert({ conversation_id, sender_id: user.id, body, post_id: post_id ?? null })
        .select("id, sender_id, body, created_at, post:posts ( id, title, body )")
        .single();
      if (error) {
        if (error.code === "42501") {
          throw new ActionError({ code: "FORBIDDEN", message: "No podés escribir en esta conversación." });
        }
        throw dbError(error, "No pudimos enviar el mensaje. Probá de nuevo.");
      }
      return data as unknown as { id: string; sender_id: string; body: string; created_at: string; post: { id: string; title: string | null; body: string } | null };
    },
  }),

  hide: defineAction({
    accept: "form",
    input: conversationRefSchema,
    handler: async ({ conversation_id }, { locals }) => {
      requireUser(locals.user);
      const { error } = await locals.supabase.rpc("hide_conversation", { p_conversation_id: conversation_id });
      if (error) throw dbError(error, "No pudimos ocultar la conversación.");
      return { ok: true };
    },
  }),
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
          situation: input.situation ?? null,
          headline: input.headline ?? null,
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

      return { saved: true, username: input.username };
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
  /** En celulares muestra solo el símbolo (deja lugar a los íconos del encabezado). */
  collapseOnMobile?: boolean;
  class?: string;
}

const { variant = "full", collapseOnMobile = false, class: className = "" } = Astro.props;
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
      <span class:list={["font-display text-xl font-bold tracking-tight text-ink", collapseOnMobile && "hidden sm:inline"]}>
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

escribir 'src/components/directory/BusinessResultCard.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Emprendimiento en resultados del buscador y del directorio. */
import Avatar from "../ui/Avatar.astro";
import type { BusinessResult } from "../../services/search";
import { followersLabel } from "../../services/social";

interface Props {
  business: BusinessResult;
  /** Ocultar el rubro (en la página del rubro ya se sabe). */
  hideCategory?: boolean;
}

const { business: b, hideCategory = false } = Astro.props;
const meta = [hideCategory ? null : b.category?.name, b.city ? `${b.city.name}${b.city.provinces ? `, ${b.city.provinces.name}` : ""}` : null]
  .filter(Boolean)
  .join(" · ");
---

<a href={`/e/${b.slug}`} class="flex items-start gap-4 p-4 hover:bg-surface-muted">
  <Avatar name={b.name} path={b.logo_path} purpose="logo" shape="rounded" size={56} />
  <span class="min-w-0 flex-1">
    <span class="flex flex-wrap items-center gap-x-2">
      <span class="font-semibold">{b.name}</span>
      {b.verification === "verified" && <span class="text-sm text-seek" title="Verificado">✓ Verificado</span>}
    </span>
    {meta && <span class="block truncate text-sm text-ink-muted">{meta}</span>}
    {b.tagline && <span class="mt-1 line-clamp-2 block text-sm">{b.tagline}</span>}
    <span class="mt-1 block text-xs text-ink-muted">
      {followersLabel(b.followers_count)}{b.posts_count > 0 && ` · ${b.posts_count} ${b.posts_count === 1 ? "publicación" : "publicaciones"}`}
    </span>
  </span>
</a>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/directory/PersonResultRow.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Persona en resultados del buscador. */
import Avatar from "../ui/Avatar.astro";
import SituationBadge from "../social/SituationBadge.astro";
import VerifiedBadge from "../ui/VerifiedBadge.astro";
import type { PersonResult } from "../../services/search";
import { followersLabel } from "../../services/social";
import { displayName } from "../../services/profiles";

interface Props {
  person: PersonResult;
}

const { person } = Astro.props;
---

<a href={`/u/${person.username}`} class="flex items-center gap-3 p-3 hover:bg-surface-muted">
  <Avatar name={displayName(person)} path={person.avatar_path} size={48} />
  <span class="min-w-0 flex-1">
    <span class="flex flex-wrap items-center gap-2">
      <span class="inline-flex items-center gap-1 font-semibold">{displayName(person)}{person.verified_at && <VerifiedBadge />}</span>
      <SituationBadge situation={person.situation} />
    </span>
    <span class="block truncate text-sm text-ink-muted">
      {[person.headline, person.city?.name, followersLabel(person.followers_count)].filter(Boolean).join(" · ")}
    </span>
  </span>
</a>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/home/Composer.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Caja "¿Qué querés publicar?" (estilo Facebook). Lleva al formulario de
 * publicación; los atajos abren el formulario con el tipo ya elegido.
 */
import Avatar from "../ui/Avatar.astro";
import type { ViewerProfile } from "../../lib/viewer";
import { displayName } from "../../services/profiles";

interface Props {
  viewer: ViewerProfile;
  class?: string;
}

const { viewer, class: className = "" } = Astro.props;
const name = viewer.first_name ?? viewer.username;
const href = "/panel/publicaciones/nueva";
const shortcut = "flex h-10 flex-1 items-center justify-center gap-2 rounded-wl text-sm font-semibold text-ink-muted hover:bg-surface-muted";
---

<section class:list={["rounded-wl-lg border border-line bg-surface p-3", className]} aria-label="Crear publicación">
  <div class="flex items-center gap-3">
    <a href={`/u/${viewer.username}`} class="shrink-0"><Avatar name={displayName(viewer)} path={viewer.avatar_path} size={40} /></a>
    <a href={href} class="flex h-10 flex-1 items-center rounded-full bg-surface-muted px-4 text-ink-muted hover:bg-line/60">
      ¿Qué querés publicar, {name}?
    </a>
  </div>
  <div class="mt-2 flex gap-1 border-t border-line pt-2">
    <a href={href} class={shortcut}>
      <svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-success stroke-2" aria-hidden="true"><rect x="3.5" y="5" width="17" height="14" rx="2" /><circle cx="9" cy="10" r="1.6" /><path stroke-linejoin="round" d="m4 17 5-4.5 3.5 3 3-2.5 4.5 4" /></svg>
      Foto o video
    </a>
    <a href={`${href}?tipo=offer`} class={shortcut}>
      <span class="text-offer" aria-hidden="true">●</span> Ofrezco
    </a>
    <a href={`${href}?tipo=seeking`} class={shortcut}>
      <span class="text-seek" aria-hidden="true">●</span> Busco
    </a>
  </div>
</section>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/home/HomeFeed.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Inicio para usuarios logueados (estilo Facebook): buscador, caja para
 * publicar y el feed (quienes sigue → destacadas → lo último).
 * En pantallas grandes suma una columna con el perfil y accesos rápidos.
 */
import Avatar from "../ui/Avatar.astro";
import Alert from "../ui/Alert.astro";
import FeedPage from "../posts/FeedPage.astro";
import SearchBox from "./SearchBox.astro";
import Composer from "./Composer.astro";
import SituationBadge from "../social/SituationBadge.astro";
import VerifiedBadge from "../ui/VerifiedBadge.astro";
import type { ViewerProfile } from "../../lib/viewer";
import { getHomeFeed, HOME_MODES, type HomeMode } from "../../services/home";
import { decodeCursor } from "../../services/posts";
import { getViewerReactions } from "../../services/social";
import { displayName } from "../../services/profiles";

interface Props {
  viewer: ViewerProfile;
}

const { viewer } = Astro.props;
const { supabase } = Astro.locals;

// Página siguiente sin JavaScript: /?modo=following&desde=...
const cursor = decodeCursor(Astro.url.searchParams.get("desde"));
const modeParam = Astro.url.searchParams.get("modo") as HomeMode | null;
const { mode, posts, nextCursor } = await getHomeFeed(supabase, {
  followingCount: viewer.following_count,
  mode: cursor && modeParam && HOME_MODES.includes(modeParam) ? modeParam : null,
  cursor,
});
const reactions = await getViewerReactions(supabase, viewer.id, posts.map((p) => p.id));
const more = (cursor: string) => `modo=${mode}&desde=${cursor}`;

const headings = {
  following: { title: "Para vos", text: "Lo que publican las personas y emprendimientos que seguís." },
  featured: { title: "Destacados", text: "Todavía no seguís a nadie: mirá lo que publican las cuentas destacadas y seguí las que te interesen." },
  latest: {
    title: "Lo último en WorkLink",
    text:
      viewer.following_count > 0
        ? "Las cuentas que seguís todavía no publicaron. Mientras tanto, mirá lo último."
        : "Todavía no seguís a nadie: tocá “Seguir” en las personas y emprendimientos que te interesen.",
  },
};
const heading = headings[mode];
const published = Astro.url.searchParams.get("publicada") === "1";
const name = displayName(viewer);

const links = [
  { href: `/u/${viewer.username}`, label: "Mi perfil" },
  { href: "/mensajes", label: "Mensajes" },
  { href: "/panel/publicaciones", label: "Mis publicaciones" },
  { href: "/panel/guardados", label: "Guardados" },
  { href: "/panel/emprendimientos", label: "Mis emprendimientos" },
  { href: "/publicaciones", label: "Todas las publicaciones" },
  { href: "/rubros", label: "Explorar rubros" },
];
---

<div class="mx-auto grid max-w-6xl gap-6 px-4 py-6 lg:grid-cols-[minmax(0,1fr)_300px]">
  <div class="mx-auto flex w-full max-w-2xl flex-col gap-4">
    <SearchBox />
    {published && <Alert tone="success">¡Listo! Tu publicación ya está en WorkLink.</Alert>}
    <Composer viewer={viewer} />

    <div class="pt-2">
      <h1 class="text-xl font-bold">{heading.title}</h1>
      <p class="text-sm text-ink-muted">{heading.text}</p>
    </div>

    {
      posts.length === 0 ? (
        <div class="rounded-wl-lg border border-dashed border-line bg-surface p-10 text-center">
          <h2 class="text-lg font-semibold">Todavía no hay publicaciones</h2>
          <p class="mt-1 text-ink-muted">¡Hacé la primera! Contá qué ofrecés o qué estás buscando.</p>
        </div>
      ) : (
        <div class="flex flex-col gap-4" data-feed>
          <FeedPage
            posts={posts}
            reactions={reactions}
            priorityCount={1}
            nextHref={nextCursor ? `/?${more(nextCursor)}` : null}
            nextFragmentHref={nextCursor ? `/inicio/mas?${more(nextCursor)}` : null}
          />
        </div>
      )
    }

    {
      !nextCursor && mode === "following" && posts.length > 0 && (
        <div class="rounded-wl-lg border border-line bg-surface p-6 text-center">
          <p class="font-semibold">¡Ya estás al día!</p>
          <p class="mt-1 text-sm text-ink-muted">Viste todo lo nuevo de las cuentas que seguís.</p>
          <a href="/publicaciones" class="mt-3 inline-block font-semibold text-brand hover:underline">Seguir viendo publicaciones de WorkLink →</a>
        </div>
      )
    }
  </div>

  <aside class="hidden lg:block" aria-label="Accesos rápidos">
    <div class="sticky top-20 flex flex-col gap-4">
      <section class="rounded-wl-lg border border-line bg-surface p-4">
        <a href={`/u/${viewer.username}`} class="flex items-center gap-3">
          <Avatar name={name} path={viewer.avatar_path} size={48} />
          <span class="min-w-0">
            <span class="flex items-center gap-1 font-semibold"><span class="truncate">{name}</span>{viewer.verified_at && <VerifiedBadge />}</span>
            {viewer.headline && <span class="block truncate text-sm text-ink-muted">{viewer.headline}</span>}
          </span>
        </a>
        {viewer.situation ? (
          <SituationBadge situation={viewer.situation} size="md" class="mt-3" />
        ) : (
          <a href="/panel/perfil#situacion" class="mt-3 block rounded-wl bg-surface-muted px-3 py-2 text-sm">
            <strong>Contá tu situación:</strong> ¿buscás empleo, tenés un emprendimiento u ofrecés servicios?
          </a>
        )}
        <nav class="mt-4 flex flex-col border-t border-line pt-2 text-sm">
          {links.map((link) => (
            <a href={link.href} class="rounded-wl px-2 py-2 font-medium text-ink-muted hover:bg-surface-muted hover:text-ink">{link.label}</a>
          ))}
        </nav>
      </section>
    </div>
  </aside>
</div>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/home/Landing.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Landing de WorkLink para visitantes sin cuenta: qué es, para quién sirve,
 * cómo funciona, qué se puede hacer y preguntas frecuentes.
 *
 * El elemento central es la "escena" del hero: tres publicaciones de ejemplo
 * (personas ficticias) que muestran la idea de la plataforma — alguien busca,
 * alguien ofrece, y se conectan en los comentarios.
 */
import Button from "../ui/Button.astro";
import { routes } from "../../config/site";
import { SITUATIONS } from "../../config/situations";

const examples = ["electricista", "tortas", "diseño web", "niñera", "fotografía"];

// Qué puede hacer cada persona según su situación (mismos nombres que en el perfil).
const forWho: Record<string, { title: string; points: string[] }> = {
  job_seeking: {
    title: "Si buscás empleo",
    points: ["Mostrá en tu perfil qué sabés hacer y dónde vivís.", "Seguí a emprendimientos de tu zona y enterate cuando buscan gente."],
  },
  entrepreneur: {
    title: "Si tenés un emprendimiento",
    points: ["Creale su página con logo, catálogo, horarios y contacto.", "Publicá productos y promociones con fotos o video."],
  },
  freelancer: {
    title: "Si ofrecés tus servicios",
    points: ["Contá tu oficio o profesión y mostrá tus trabajos.", "Que te encuentren por el buscador y te escriban por WhatsApp."],
  },
  hiring: {
    title: "Si necesitás contratar",
    points: ["Publicá lo que buscás y recibí respuestas en los comentarios.", "Mirá el perfil, los trabajos y quién sigue a cada persona antes de decidir."],
  },
};

const steps = [
  { title: "Creá tu cuenta", text: "Es gratis. Poné tu foto, tu ciudad y contá tu situación: si buscás empleo, tenés un emprendimiento, ofrecés servicios o buscás contratar." },
  { title: "Publicá", text: "Como en Facebook: escribí qué ofrecés o qué buscás y sumá hasta 10 fotos o un video corto." },
  { title: "Conectá", text: "La gente te sigue, comenta y te escribe. Vos hacés lo mismo con quienes te interesan, sin intermediarios." },
];

const features = [
  { title: "Inicio a tu medida", text: "Ves lo que publican las personas y emprendimientos que seguís.", icon: "M4 6h16M4 12h16M4 18h10" },
  { title: "Publicaciones con fotos y video", text: "Hasta 10 fotos o un video de 60 segundos, con precio si querés.", icon: "M4 5h16v14H4zM8 10.5a1.5 1.5 0 1 0 0-.01M4 17l5-4.5 3.5 3 3-2.5L20 17" },
  { title: "Páginas de emprendimiento", text: "Logo, portada, catálogo de productos y servicios, horarios y contacto.", icon: "M4 9.5 5.5 4h13L20 9.5M4 9.5h16M4 9.5V20h16V9.5M9.5 20v-5h5v5" },
  { title: "Buscador", text: "Encontrá personas por nombre o rubro, emprendimientos y publicaciones.", icon: "M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13ZM20 20l-4.5-4.5" },
  { title: "Me gusta, comentarios y guardados", text: "Preguntá por precio o disponibilidad y guardá lo que querés ver después.", icon: "M12 20s-7.5-4.6-9.2-9.3C1.6 7.3 3.9 4 7.3 4c2 0 3.6 1.1 4.7 2.8C13.1 5.1 14.7 4 16.7 4c3.4 0 5.7 3.3 4.5 6.7C19.5 15.4 12 20 12 20Z" },
  { title: "Tus datos, cuidados", text: "Tu WhatsApp y teléfono solo los ven personas con cuenta. Podés bloquear a quien quieras.", icon: "M12 3 5 6v5c0 4.5 3 8.3 7 10 4-1.7 7-5.5 7-10V6l-7-3Z" },
];

const faqs = [
  { q: "¿Cuánto cuesta?", a: "Crear tu cuenta, armar tu perfil, publicar y crear la página de tu emprendimiento es gratis. Más adelante vas a poder destacar tus publicaciones con una suscripción opcional." },
  { q: "¿Necesito tener un emprendimiento?", a: "No. Podés usar WorkLink solo con tu perfil personal, para buscar trabajo, ofrecer tus servicios o encontrar a quien contratar. La página de emprendimiento es opcional." },
  { q: "¿Quién ve mi WhatsApp?", a: "Solo las personas que tienen cuenta en WorkLink. Los visitantes sin cuenta y los buscadores como Google no lo ven." },
  { q: "¿En qué ciudades funciona?", a: "Arrancamos en Córdoba, pero podés sumarte desde cualquier ciudad de Argentina." },
  { q: "¿Cómo contacto a alguien?", a: "Desde su perfil o su página: por WhatsApp, o comentando su publicación. El trato lo arreglan directamente entre ustedes." },
];

const sceneBadge = (value: string) => SITUATIONS.find((s) => s.value === value)!;
---

<!-- Hero -->
<section class="relative overflow-hidden">
  <div class="mx-auto grid max-w-6xl items-center gap-12 px-4 pb-16 pt-10 sm:pt-16 lg:grid-cols-[1.05fr_1fr] lg:pb-24">
    <div>
      <h1 class="max-w-xl text-4xl font-extrabold leading-[1.05] tracking-tight sm:text-6xl">
        Mostrá lo que hacés. Encontrá a quien lo necesita.
      </h1>
      <p class="mt-5 max-w-xl text-lg leading-relaxed text-ink-muted">
        WorkLink es la red de trabajo de tu ciudad. Publicás como en Facebook, contás si buscás empleo, tenés un
        emprendimiento u ofrecés servicios, y te conectás con gente de tu zona.
      </p>

      <div class="mt-8 flex flex-wrap gap-3">
        <Button href={routes.signup} size="lg">Crear cuenta gratis</Button>
        <Button href={routes.login} variant="secondary" size="lg">Ya tengo cuenta</Button>
      </div>

      <form action="/buscar" method="GET" role="search" class="mt-10 max-w-xl">
        <label for="landing-q" class="text-sm font-semibold">¿Buscás a alguien? Probá sin crear cuenta:</label>
        <div class="relative mt-2">
          <input
            id="landing-q"
            name="q"
            type="search"
            maxlength={100}
            autocomplete="off"
            enterkeyhint="search"
            placeholder="Electricista, tortas, diseño web…"
            class="h-12 w-full rounded-full border border-line bg-surface pl-5 pr-28 text-base focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25"
          />
          <button type="submit" class="absolute right-1.5 top-1/2 h-9 -translate-y-1/2 rounded-full bg-ink px-4 text-sm font-semibold text-bg hover:opacity-90">
            Buscar
          </button>
        </div>
        <p class="mt-3 flex flex-wrap gap-x-3 gap-y-1 text-sm text-ink-muted">
          <a href="/rubros" class="font-semibold text-ink underline decoration-line underline-offset-4 hover:decoration-ink">Ver todos los rubros</a>
          {examples.map((example) => (
            <a href={`/buscar?q=${encodeURIComponent(example)}`} class="underline decoration-line underline-offset-4 hover:text-ink hover:decoration-ink">
              {example}
            </a>
          ))}
        </p>
      </form>
    </div>

    <!-- Escena: alguien busca, alguien ofrece, y se conectan. Personas ficticias. -->
    <div class="relative mx-auto w-full max-w-md lg:max-w-none" aria-label="Ejemplo de cómo se ve WorkLink" role="img">
      <div class="absolute -inset-x-10 -top-10 bottom-0 -z-10 rounded-[3rem] bg-seek-soft/70 lg:-right-24" aria-hidden="true"></div>

      <article class="scene-card relative z-10 rounded-wl-lg border border-line bg-surface p-4 shadow-[0_18px_40px_-24px_rgb(20_22_31/0.45)] sm:mr-10" aria-hidden="true">
        <header class="flex items-center gap-3">
          <span class="grid h-10 w-10 place-items-center rounded-full bg-warning-soft font-bold text-warning">LM</span>
          <span class="min-w-0 flex-1">
            <span class="flex flex-wrap items-center gap-2 font-semibold">Lucía M. <span class:list={["rounded-full px-2 py-0.5 text-xs", sceneBadge("hiring").class]}>{sceneBadge("hiring").badge}</span></span>
            <span class="block text-xs text-ink-muted">hace 12 min · Villa Carlos Paz</span>
          </span>
          <span class="rounded-full bg-seek-soft px-2.5 py-1 text-xs font-semibold text-seek">Busco</span>
        </header>
        <p class="mt-3">Busco electricista matriculado para revisar la instalación de un local antes de abrir. ¿Alguien recomienda?</p>
        <div class="mt-3 flex items-center gap-4 border-t border-line pt-2 text-sm text-ink-muted">
          <span>♥ 8</span><span>3 comentarios</span>
        </div>
        <div class="mt-2 flex gap-2.5">
          <span class="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-success-soft text-xs font-bold text-success">MR</span>
          <p class="rounded-wl-lg bg-surface-muted px-3 py-2 text-sm">
            <span class="font-semibold">Martín R.</span> ¡Hola Lucía! Soy electricista matriculado y estoy cerca. Te escribo por WhatsApp.
          </p>
        </div>
      </article>

      <article class="scene-card relative z-20 -mt-4 ml-6 rounded-wl-lg border border-line bg-surface p-4 shadow-[0_18px_40px_-24px_rgb(20_22_31/0.45)] sm:ml-16" aria-hidden="true">
        <header class="flex items-center gap-3">
          <span class="grid h-10 w-10 place-items-center rounded-full bg-offer-soft font-bold text-offer">CS</span>
          <span class="min-w-0 flex-1">
            <span class="flex flex-wrap items-center gap-2 font-semibold">Carla S. <span class:list={["rounded-full px-2 py-0.5 text-xs", sceneBadge("entrepreneur").class]}>{sceneBadge("entrepreneur").badge}</span></span>
            <span class="block text-xs text-ink-muted">Dulce Carla · hace 1 h · Córdoba</span>
          </span>
          <span class="rounded-full bg-warning-soft px-2.5 py-1 text-xs font-semibold text-warning">Promoción</span>
        </header>
        <p class="mt-3">Tortas personalizadas para cumpleaños. Este mes, 10% off encargando con una semana de anticipación 🎂</p>
        <div class="mt-3 grid grid-cols-3 gap-1 overflow-hidden rounded-wl" aria-hidden="true">
          <span class="h-16 bg-offer-soft"></span><span class="h-16 bg-warning-soft"></span><span class="h-16 bg-seek-soft"></span>
        </div>
      </article>

      <article class="scene-card relative z-10 -mt-3 mr-4 rounded-wl-lg border border-line bg-surface p-4 shadow-[0_18px_40px_-24px_rgb(20_22_31/0.45)] sm:mr-16" aria-hidden="true">
        <header class="flex items-center gap-3">
          <span class="grid h-10 w-10 place-items-center rounded-full bg-seek-soft font-bold text-seek">JP</span>
          <span class="min-w-0 flex-1">
            <span class="flex flex-wrap items-center gap-2 font-semibold">Joaquín P. <span class:list={["rounded-full px-2 py-0.5 text-xs", sceneBadge("job_seeking").class]}>{sceneBadge("job_seeking").badge}</span></span>
            <span class="block text-xs text-ink-muted">Cajero y repositor · hace 3 h · Río Cuarto</span>
          </span>
        </header>
        <p class="mt-3">Tengo experiencia en atención al público y disponibilidad de lunes a sábado. ¡Cualquier dato me ayuda!</p>
      </article>
    </div>
  </div>
</section>

<!-- Para quién -->
<section class="border-y border-line bg-surface" aria-labelledby="para-quien">
  <div class="mx-auto max-w-6xl px-4 py-16 sm:py-20">
    <h2 id="para-quien" class="max-w-2xl text-3xl font-bold tracking-tight sm:text-4xl">Una cuenta, cuatro maneras de usarla</h2>
    <p class="mt-3 max-w-2xl text-ink-muted">
      En tu perfil elegís tu situación y se muestra en todo lo que publicás. Así, quien te lee sabe enseguida si buscás,
      ofrecés o contratás.
    </p>

    <div class="mt-10 grid gap-x-10 gap-y-10 md:grid-cols-2">
      {
        SITUATIONS.map((situation) => {
          const info = forWho[situation.value];
          return (
            <div class="flex gap-4">
              <span class:list={["mt-1 w-1.5 shrink-0 rounded-full", situation.class]} aria-hidden="true" />
              <div>
                <span class:list={["inline-block rounded-full px-2.5 py-0.5 text-xs font-semibold", situation.class]}>{situation.badge}</span>
                <h3 class="mt-2 text-xl font-semibold">{info.title}</h3>
                <ul class="mt-2 flex flex-col gap-1.5 text-ink-muted">
                  {info.points.map((point) => (
                    <li class="flex gap-2"><span aria-hidden="true">✓</span>{point}</li>
                  ))}
                </ul>
              </div>
            </div>
          );
        })
      }
    </div>
  </div>
</section>

<!-- Cómo funciona (es una secuencia: lleva números) -->
<section class="mx-auto max-w-6xl px-4 py-16 sm:py-20" aria-labelledby="como-funciona">
  <h2 id="como-funciona" class="text-3xl font-bold tracking-tight sm:text-4xl">Cómo funciona</h2>
  <ol class="mt-10 grid gap-8 md:grid-cols-3">
    {
      steps.map((step, index) => (
        <li class="relative">
          <span class="text-5xl font-extrabold leading-none text-brand/30" aria-hidden="true">{index + 1}</span>
          <h3 class="mt-3 text-xl font-semibold">{step.title}</h3>
          <p class="mt-2 text-ink-muted">{step.text}</p>
        </li>
      ))
    }
  </ol>
</section>

<!-- Qué podés hacer -->
<section class="bg-surface-muted/60" aria-labelledby="funciones">
  <div class="mx-auto grid max-w-6xl gap-12 px-4 py-16 sm:py-20 lg:grid-cols-[1fr_2fr]">
    <div>
      <h2 id="funciones" class="text-3xl font-bold tracking-tight sm:text-4xl">Todo lo que necesitás para que te encuentren</h2>
      <p class="mt-3 text-ink-muted">Pensado para el celular, rápido aunque tengas poca señal.</p>
    </div>
    <ul class="grid gap-x-8 gap-y-8 sm:grid-cols-2">
      {
        features.map((feature) => (
          <li class="flex gap-4">
            <span class="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-surface text-brand ring-1 ring-line">
              <svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-current stroke-2" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d={feature.icon} />
              </svg>
            </span>
            <div>
              <h3 class="font-semibold">{feature.title}</h3>
              <p class="mt-1 text-sm text-ink-muted">{feature.text}</p>
            </div>
          </li>
        ))
      }
    </ul>
  </div>
</section>

<!-- Preguntas frecuentes -->
<section class="mx-auto max-w-3xl px-4 py-16 sm:py-20" aria-labelledby="preguntas">
  <h2 id="preguntas" class="text-3xl font-bold tracking-tight sm:text-4xl">Preguntas frecuentes</h2>
  <div class="mt-8 divide-y divide-line border-y border-line">
    {
      faqs.map((faq) => (
        <details class="group py-4">
          <summary class="flex cursor-pointer list-none items-center justify-between gap-4 text-lg font-semibold">
            {faq.q}
            <span class="text-2xl font-normal text-ink-muted transition-transform group-open:rotate-45" aria-hidden="true">+</span>
          </summary>
          <p class="mt-2 text-ink-muted">{faq.a}</p>
        </details>
      ))
    }
  </div>
</section>

<!-- Cierre -->
<section class="px-4 pb-20">
  <div class="mx-auto flex max-w-6xl flex-col items-start gap-6 rounded-wl-lg bg-brand px-6 py-12 text-brand-contrast sm:px-12 md:flex-row md:items-center md:justify-between">
    <div>
      <h2 class="text-3xl font-bold tracking-tight">Sumate a WorkLink</h2>
      <p class="mt-2 max-w-xl opacity-90">Creá tu cuenta en un minuto y empezá a publicar hoy. Es gratis.</p>
    </div>
    <a href={routes.signup} class="inline-flex h-12 shrink-0 items-center rounded-wl bg-brand-contrast px-6 font-semibold text-brand hover:opacity-90">
      Crear cuenta gratis
    </a>
  </div>
</section>

<style>
  /* Única animación de la página: las tarjetas de la escena entran en cascada. */
  @media (prefers-reduced-motion: no-preference) {
    .scene-card {
      animation: scene-in 0.6s cubic-bezier(0.2, 0.7, 0.2, 1) both;
    }
    .scene-card:nth-of-type(2) {
      animation-delay: 0.15s;
    }
    .scene-card:nth-of-type(3) {
      animation-delay: 0.3s;
    }
  }
  @keyframes scene-in {
    from {
      opacity: 0;
      transform: translateY(14px);
    }
  }
</style>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/home/SearchBox.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Caja de búsqueda grande (inicio y /buscar). Funciona sin JavaScript. */
interface Props {
  value?: string;
  autofocus?: boolean;
  class?: string;
}

const { value = "", autofocus = false, class: className = "" } = Astro.props;
---

<form action="/buscar" method="GET" role="search" class:list={["relative", className]}>
  <label for="search-q" class="sr-only">Buscar en WorkLink</label>
  <svg viewBox="0 0 24 24" class="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 fill-none stroke-ink-muted stroke-2" aria-hidden="true">
    <circle cx="11" cy="11" r="7" /><path stroke-linecap="round" d="m20 20-3.5-3.5" />
  </svg>
  <input
    id="search-q"
    type="search"
    name="q"
    value={value}
    maxlength={100}
    autofocus={autofocus}
    autocomplete="off"
    enterkeyhint="search"
    placeholder="Buscá personas, emprendimientos o servicios"
    class="h-12 w-full rounded-full border border-line bg-surface pl-12 pr-28 text-base text-ink placeholder:text-ink-muted focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25"
  />
  <button type="submit" class="absolute right-1.5 top-1/2 h-9 -translate-y-1/2 rounded-full bg-brand px-4 text-sm font-semibold text-brand-contrast hover:bg-brand-hover">
    Buscar
  </button>
</form>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/layout/Footer.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import Logo from "../brand/Logo.astro";
import { brand } from "../../config/brand";

const year = new Date().getFullYear();
const links = [
  { href: "/rubros", label: "Rubros" },
  { href: "/publicaciones", label: "Publicaciones" },
  { href: "/buscar", label: "Buscar" },
  { href: "/terminos", label: "Términos" },
  { href: "/privacidad", label: "Privacidad" },
];
---

<footer class="mt-auto border-t border-line">
  <div class="mx-auto flex max-w-6xl flex-col gap-4 px-4 py-8 text-sm text-ink-muted">
    <nav aria-label="Pie de página">
      <ul class="flex flex-wrap gap-x-5 gap-y-2">
        {links.map((link) => <li><a href={link.href} class="hover:text-ink hover:underline">{link.label}</a></li>)}
      </ul>
    </nav>
    <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex items-center gap-3">
        <Logo variant="mark" />
        <p>{brand.tagline}.</p>
      </div>
      <p>© {year} {brand.name} · Hecho en Córdoba, Argentina</p>
    </div>
  </div>
</footer>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/layout/Header.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import Logo from "../brand/Logo.astro";
import Button from "../ui/Button.astro";
import Avatar from "../ui/Avatar.astro";
import { actions } from "astro:actions";
import { routes } from "../../config/site";
import { getViewerProfile } from "../../lib/viewer";
import { displayName } from "../../services/profiles";
import { countUnread } from "../../services/notifications";
import { countUnreadConversations } from "../../services/messages";

const user = Astro.locals.user;
const viewer = await getViewerProfile(Astro.locals);
const [unread, unreadMessages] = user
  ? await Promise.all([countUnread(Astro.locals.supabase, user.id), countUnreadConversations(Astro.locals.supabase)])
  : [0, 0];
const badge = (n: number) => (n > 99 ? "99+" : String(n));
const logoutAction = `/salir${actions.auth.signOut}`;
const query = Astro.url.pathname === "/buscar" ? (Astro.url.searchParams.get("q") ?? "") : "";
---

<header class="sticky top-0 z-30 border-b border-line bg-bg/85 backdrop-blur supports-[backdrop-filter]:bg-bg/70">
  <div class="mx-auto flex h-16 max-w-6xl items-center gap-3 px-4">
    <a href={routes.home} class="shrink-0 rounded-wl" aria-label="WorkLink, ir al inicio">
      <Logo collapseOnMobile={Boolean(user)} />
    </a>

    <form action="/buscar" method="GET" role="search" class="hidden max-w-xs flex-1 md:block">
      <label for="header-search" class="sr-only">Buscar en WorkLink</label>
      <input
        id="header-search"
        type="search"
        name="q"
        value={query}
        maxlength={100}
        placeholder="Buscar personas, servicios…"
        class="h-10 w-full rounded-full border border-line bg-surface-muted px-4 text-sm text-ink placeholder:text-ink-muted focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25"
      />
    </form>

    <nav aria-label="Cuenta" class="ml-auto flex items-center gap-1.5 sm:gap-2">
      <a href="/buscar" class:list={["h-10 w-10 place-items-center rounded-full text-ink-muted hover:bg-surface-muted hover:text-ink md:hidden", user ? "grid" : "hidden min-[420px]:grid"]} aria-label="Buscar">
        <svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-current stroke-2" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path stroke-linecap="round" d="m20 20-3.5-3.5" /></svg>
      </a>
      {
        user ? (
          <>
            <a
              href="/mensajes"
              class="relative grid h-10 w-10 place-items-center rounded-full text-ink-muted hover:bg-surface-muted hover:text-ink"
              aria-label={unreadMessages ? `Mensajes (${unreadMessages} sin leer)` : "Mensajes"}
            >
              <svg viewBox="0 0 24 24" class="h-[22px] w-[22px] fill-none stroke-current stroke-2" aria-hidden="true">
                <path stroke-linejoin="round" d="M20 12.5c0 4-3.6 7-8 7-1.2 0-2.3-.2-3.3-.6L4 20l1.2-3.6C4.4 15.3 4 14 4 12.5c0-4 3.6-7 8-7s8 3 8 7Z" />
              </svg>
              <span
                data-messages-badge
                hidden={unreadMessages === 0}
                class="absolute -right-0.5 -top-0.5 grid h-5 min-w-5 place-items-center rounded-full bg-danger px-1 text-[11px] font-bold leading-none text-white"
              >
                {badge(unreadMessages)}
              </span>
            </a>
            <a
              href="/notificaciones"
              class="relative grid h-10 w-10 place-items-center rounded-full text-ink-muted hover:bg-surface-muted hover:text-ink"
              aria-label={unread ? `Notificaciones (${unread} sin leer)` : "Notificaciones"}
              data-notifications-link
            >
              <svg viewBox="0 0 24 24" class="h-[22px] w-[22px] fill-none stroke-current stroke-2" aria-hidden="true">
                <path stroke-linejoin="round" d="M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16Z" /><path stroke-linecap="round" d="M10 20.5a2.2 2.2 0 0 0 4 0" />
              </svg>
              <span
                data-notifications-badge
                hidden={unread === 0}
                class="absolute -right-0.5 -top-0.5 grid h-5 min-w-5 place-items-center rounded-full bg-danger px-1 text-[11px] font-bold leading-none text-white"
              >
                {badge(unread)}
              </span>
            </a>
            {viewer && (
              <a href={`/u/${viewer.username}`} class="flex items-center gap-2 rounded-full p-0.5 hover:bg-surface-muted sm:pr-3" aria-label="Mi perfil">
                <Avatar name={displayName(viewer)} path={viewer.avatar_path} size={32} />
                <span class="hidden text-sm font-semibold sm:inline">{viewer.first_name ?? viewer.username}</span>
              </a>
            )}
            <Button href={routes.dashboard} variant="ghost" size="sm">
              Mi panel
            </Button>
            <form method="POST" action={logoutAction} class="hidden sm:block">
              <Button type="submit" variant="secondary" size="sm">
                Salir
              </Button>
            </form>
          </>
        ) : (
          <>
            <a href="/rubros" class="hidden rounded-wl px-3 py-2 text-sm font-medium text-ink-muted hover:text-ink sm:inline-block">Rubros</a>
            <Button href={routes.login} variant="ghost" size="sm">
              Ingresar
            </Button>
            <Button href={routes.signup} size="sm" class="whitespace-nowrap">
              Crear cuenta
            </Button>
          </>
        )
      }
    </nav>
  </div>
</header>

{
  user && (
    <script>
      import "../../scripts/notifications";
    </script>
  )
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/posts/FeedPage.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Una página de publicaciones + enlace "Cargar más". Se usa en las páginas
 * completas y en los fragmentos que se agregan con JavaScript.
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
    <div class="flex justify-center pt-2" data-load-more-wrapper>
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

<script>
  import "../../scripts/load-more";
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/posts/PostCard.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Publicación en el feed, estilo Facebook: quién publica (con su situación),
 * cuándo y dónde, el texto con "Ver más", el mosaico de fotos o el video, y
 * el pie con me gusta, comentar, compartir y guardar.
 */
import Avatar from "../ui/Avatar.astro";
import PostActions from "../social/PostActions.astro";
import PostGallery from "./PostGallery.astro";
import PostOwnerMenu from "./PostOwnerMenu.astro";
import VerifiedBadge from "../ui/VerifiedBadge.astro";
import SituationBadge from "../social/SituationBadge.astro";
import type { PostView } from "../../services/posts";
import { POST_TYPE_LABELS, postHeadline } from "../../services/posts";
import { formatDate, formatMoney, formatRelative } from "../../lib/format";
import { businessPath, postPath, profilePath } from "../../lib/urls";
import { displayName } from "../../services/profiles";

interface Props {
  post: PostView;
  /** true para las primeras publicaciones visibles (carga prioritaria de la imagen). */
  priority?: boolean;
  /** Estado del usuario actual (me gusta / guardada). */
  liked?: boolean;
  saved?: boolean;
}

const { post, priority = false, liked = false, saved = false } = Astro.props;
const href = postPath(post);
const type = POST_TYPE_LABELS[post.type];
// Arriba siempre la persona (lleva a su perfil, donde se la puede seguir);
// si publicó desde un emprendimiento, debajo va el nombre del emprendimiento.
const personName = post.author ? displayName(post.author) : "";
const profileHref = post.author ? profilePath(post.author.username) : null;
const site = Astro.site ?? new URL(Astro.url.origin);
const shareUrl = new URL(href, site).toString();
const headline = postHeadline(post, 120);
// Quien publicó ve el menú para editar o eliminar.
const isOwner = Astro.locals.user?.id === post.author_id;
---

<article class="rounded-wl-lg border border-line bg-surface" data-post-card>
  <header class="flex items-start gap-3 px-4 pt-3">
    {
      profileHref && (
        <a href={profileHref} class="shrink-0" aria-label={`Perfil de ${personName}`}>
          <Avatar name={personName} path={post.author?.avatar_path} size={42} />
        </a>
      )
    }
    <div class="min-w-0 flex-1">
      <p class="flex flex-wrap items-center gap-x-2 gap-y-0.5 leading-tight">
        <span class="inline-flex items-center gap-1">
          {profileHref ? (
            <a href={profileHref} class="font-semibold hover:underline">{personName}</a>
          ) : (
            <span class="font-semibold">{personName}</span>
          )}
          {post.author?.verified_at && <VerifiedBadge />}
        </span>
        <SituationBadge situation={post.author?.situation} />
      </p>
      {
        post.business && (
          <a href={businessPath(post.business.slug)} class="mt-1 flex w-fit max-w-full items-center gap-1.5 text-sm font-medium text-ink hover:underline">
            <Avatar name={post.business.name} path={post.business.logo_path} purpose="logo" shape="rounded" size={18} />
            <span class="truncate">{post.business.name}</span>
            {post.business.verification === "verified" && <span class="text-seek" title="Verificado">✓</span>}
          </a>
        )
      }
      <p class="mt-0.5 truncate text-xs text-ink-muted">
        {!post.business && post.author?.headline && <>{post.author.headline} · </>}
        <a href={href} class="hover:underline">
          <time datetime={post.published_at} title={formatDate(post.published_at, { dateStyle: "long", timeStyle: "short" })}>{formatRelative(post.published_at)}</time>
        </a>
        {post.city && ` · ${post.city.name}`}
      </p>
    </div>
    <span class:list={["shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold", type.class]}>{type.label}</span>
    {isOwner && <PostOwnerMenu postId={post.id} class="-mr-2" />}
  </header>

  <div class="px-4 pt-3">
    {post.title && (
      <h2 class="font-semibold leading-snug">
        <a href={href} class="hover:underline">{post.title}</a>
      </h2>
    )}
    <p class:list={["line-clamp-5 whitespace-pre-line break-words", post.title && "mt-1"]} data-clamp>{post.body}</p>
    <button type="button" data-expand hidden class="mt-0.5 text-sm font-semibold text-ink-muted hover:underline">Ver más</button>
    {
      post.price !== null && (
        <p class="mt-2 font-semibold">
          {formatMoney(post.price)}
          {post.category && <span class="ml-2 text-sm font-normal text-ink-muted">{post.subcategory?.name ?? post.category.name}</span>}
        </p>
      )
    }
  </div>

  {
    post.media.length > 0 && (
      <div class="mt-3">
        <PostGallery media={post.media} href={href} alt={headline} priority={priority} />
      </div>
    )
  }

  <PostActions post={post} liked={liked} saved={saved} postHref={href} shareUrl={shareUrl} shareTitle={`${headline} — en WorkLink`} class="mt-1" />
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
  /** Tipo preseleccionado (?tipo=offer|seeking desde la caja del inicio). */
  defaultType?: string | null;
  /** Nombre de la persona, para la opción "Publicar como". */
  personName?: string;
}

const { action, post = null, businesses, categories, submitted = null, fieldErrors = {}, city = null, media, submitLabel, defaultBusinessId = null, defaultType = null, personName = "Yo" } = Astro.props;

const v = (name: string, saved: unknown) =>
  submitted ? String(submitted.get(name) ?? "") : saved === null || saved === undefined ? "" : String(saved);
const err = (name: string) => fieldErrors[name]?.[0];

// Como en Facebook, por defecto se publica como persona; el emprendimiento se
// elige en "Publicar como" (o viene preseleccionado desde su página).
const businessId = v("business_id", post ? post.business_id : (defaultBusinessId ?? ""));
const validDefaultType = POST_TYPES.some((t) => t.value === defaultType && (!t.needsBusiness || businessId)) ? defaultType : null;
const type = v("type", post?.type ?? validDefaultType ?? "offer");
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
            <option value="" selected={businessId === ""}>{personName} (mi perfil)</option>
            {activeBusinesses.map((b) => (
              <option value={b.id} selected={businessId === b.id}>{b.name} (emprendimiento)</option>
            ))}
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

escribir 'src/components/posts/PostGallery.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Mosaico de fotos de una publicación en el feed (estilo Facebook):
 *  1 foto  → ocupa todo el ancho, con su proporción (entre 4:5 y 1.91:1)
 *  2 fotos → dos columnas
 *  3 fotos → una grande a la izquierda y dos a la derecha
 *  4 fotos → cuadrícula de 2×2
 *  5+      → dos arriba y tres abajo; la última muestra "+N"
 * Un video se muestra con su portada y el ícono de reproducir.
 * Todo lleva a la página de la publicación.
 */
import type { PostMediaView } from "../../services/posts";
import { mediaSrcSet, mediaUrl, postFileUrl } from "../../lib/media";

interface Props {
  media: PostMediaView[];
  href: string;
  alt: string;
  priority?: boolean;
}

const { media, href, alt, priority = false } = Astro.props;
const first = media[0];
const count = media.length;
const shown = media.slice(0, 5);
const extra = count - shown.length;
const ratio = first?.width && first?.height ? Math.min(Math.max(first.width / first.height, 0.8), 1.91) : 4 / 3;

// Posición de cada foto en la grilla según la cantidad.
const layouts: Record<number, { grid: string; cells: string[]; aspect: string }> = {
  2: { grid: "grid-cols-2", cells: ["", ""], aspect: "1 / 1" },
  3: { grid: "grid-cols-2 grid-rows-2", cells: ["row-span-2", "", ""], aspect: "1 / 1" },
  4: { grid: "grid-cols-2 grid-rows-2", cells: ["", "", "", ""], aspect: "1 / 1" },
  5: { grid: "grid-cols-6 grid-rows-[3fr_2fr]", cells: ["col-span-3", "col-span-3", "col-span-2", "col-span-2", "col-span-2"], aspect: "6 / 5" },
};
const layout = layouts[Math.min(count, 5)];
const sizes = (cell: string) => (cell.includes("col-span-2") ? "(min-width: 672px) 220px, 33vw" : "(min-width: 672px) 330px, 50vw");
---

{
  first &&
    (first.kind === "video" ? (
      <a href={href} class="relative block w-full overflow-hidden bg-black" style={{ aspectRatio: String(ratio) }}>
        <img
          src={postFileUrl(first.path, "poster.webp")}
          alt={alt}
          loading={priority ? "eager" : "lazy"}
          decoding="async"
          class="h-full w-full object-contain"
        />
        <span class="absolute inset-0 grid place-items-center">
          <span class="grid h-16 w-16 place-items-center rounded-full bg-black/60 text-3xl text-white" aria-hidden="true">▶</span>
        </span>
        <span class="sr-only">Ver video</span>
      </a>
    ) : count === 1 ? (
      <a href={href} class="block w-full overflow-hidden bg-surface-muted" style={{ aspectRatio: String(ratio) }}>
        <img
          src={mediaUrl("post", first.path, 960)}
          srcset={mediaSrcSet("post", first.path)}
          sizes="(min-width: 672px) 640px, 100vw"
          width={first.width ?? undefined}
          height={first.height ?? undefined}
          alt={alt}
          loading={priority ? "eager" : "lazy"}
          fetchpriority={priority ? "high" : undefined}
          decoding="async"
          class="h-full w-full object-cover"
        />
      </a>
    ) : (
      <a href={href} class:list={["grid w-full gap-0.5 bg-surface", layout.grid]} style={{ aspectRatio: layout.aspect }} aria-label={`Ver las ${count} fotos`}>
        {shown.map((m, index) => (
          <span class:list={["relative block min-h-0 overflow-hidden bg-surface-muted", layout.cells[index]]}>
            <img
              src={mediaUrl("post", m.path, 480)}
              srcset={mediaSrcSet("post", m.path)}
              sizes={sizes(layout.cells[index])}
              alt={index === 0 ? alt : ""}
              loading={priority && index < 2 ? "eager" : "lazy"}
              decoding="async"
              class="h-full w-full object-cover"
            />
            {index === shown.length - 1 && extra > 0 && (
              <span class="absolute inset-0 grid place-items-center bg-black/50 text-3xl font-bold text-white">+{extra}</span>
            )}
          </span>
        ))}
      </a>
    ))
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/posts/PostOwnerMenu.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Menú "⋯" de una publicación propia: Editar y Eliminar.
 * Eliminar pide confirmación y, con JavaScript, saca la publicación de la
 * página sin recargar (scripts/social.ts). Sin JavaScript, el formulario
 * va a "Mis publicaciones", que la elimina y muestra el aviso.
 */
import { actions } from "astro:actions";

interface Props {
  postId: string;
  /** Adónde ir después de eliminar (en la página de la publicación). */
  redirectTo?: string;
  class?: string;
}

const { postId, redirectTo, class: className = "" } = Astro.props;
const item = "flex w-full items-center gap-2 rounded-wl px-3 py-2 text-left text-sm font-medium hover:bg-surface-muted";
---

<details class:list={["relative", className]} data-post-menu>
  <summary
    class="grid h-8 w-8 cursor-pointer list-none place-items-center rounded-full text-ink-muted hover:bg-surface-muted hover:text-ink [&::-webkit-details-marker]:hidden"
    aria-label="Opciones de la publicación"
  >
    <svg viewBox="0 0 24 24" class="h-5 w-5 fill-current" aria-hidden="true"><circle cx="5" cy="12" r="1.8" /><circle cx="12" cy="12" r="1.8" /><circle cx="19" cy="12" r="1.8" /></svg>
  </summary>
  <div class="absolute right-0 top-9 z-20 w-44 rounded-wl-lg border border-line bg-surface p-1 shadow-lg">
    <a href={`/panel/publicaciones/${postId}`} class={item}>Editar</a>
    <form method="POST" action={`/panel/publicaciones${actions.posts.remove}`} data-delete-post data-redirect={redirectTo}>
      <input type="hidden" name="post_id" value={postId} />
      <button type="submit" class:list={[item, "text-danger"]}>Eliminar</button>
    </form>
  </div>
</details>

<script>
  import "../../scripts/social";
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
import VerifiedBadge from "../ui/VerifiedBadge.astro";
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
                      <a href={profilePath(comment.author.username)} class="inline-flex items-center gap-1 font-semibold hover:underline">{name}{comment.author.verified_at && <VerifiedBadge size={14} />}</a>
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
 * Pie de una publicación (estilo Facebook):
 *  - fila de totales: ♥ cantidad de me gusta · N comentarios
 *  - botones: Me gusta · Comentar · Compartir · Guardar
 * Con sesión, Me gusta y Guardar son botones (los maneja scripts/social.ts);
 * sin sesión, llevan a /ingresar y vuelven a la publicación.
 */
import { routes } from "../../config/site";

interface Props {
  post: { id: string; likes_count: number; comments_count: number };
  liked?: boolean;
  saved?: boolean;
  /** Página de la publicación (sin #). */
  postHref: string;
  /** URL absoluta para compartir. */
  shareUrl: string;
  shareTitle: string;
  /** En la página de la publicación, "Comentar" baja al formulario. */
  commentsHref?: string;
  class?: string;
}

const { post, liked = false, saved = false, postHref, shareUrl, shareTitle, commentsHref = `${postHref}#comentarios`, class: className = "" } =
  Astro.props;
const loggedIn = Boolean(Astro.locals.user);
const loginHref = `${routes.login}?next=${encodeURIComponent(postHref)}`;
const fmt = (n: number) => n.toLocaleString("es-AR");

const action =
  "group flex h-10 min-w-0 flex-1 items-center justify-center gap-1 whitespace-nowrap rounded-wl text-[13px] font-semibold text-ink-muted transition-colors hover:bg-surface-muted sm:gap-1.5 sm:text-sm";
const icon = "h-[18px] w-[18px] shrink-0 fill-none stroke-current stroke-2 sm:h-5 sm:w-5";
const heart = "M12 20.5s-7.5-4.6-9.2-9.3C1.6 7.8 3.9 4.5 7.3 4.5c2 0 3.6 1.1 4.7 2.8 1.1-1.7 2.7-2.8 4.7-2.8 3.4 0 5.7 3.3 4.5 6.7-1.7 4.7-9.2 9.3-9.2 9.3Z";
const bookmark = "M6.5 3.5h11a1 1 0 0 1 1 1v16l-6.5-4.2-6.5 4.2v-16a1 1 0 0 1 1-1Z";
---

<div class:list={["px-1.5 sm:px-3", className]}>
  <div class="flex min-h-9 items-center justify-between gap-3 px-1 text-sm text-ink-muted">
    <span data-likes-wrap={post.id} hidden={post.likes_count === 0} class="inline-flex items-center gap-1.5">
      <span class="grid h-5 w-5 place-items-center rounded-full bg-danger text-white" aria-hidden="true">
        <svg viewBox="0 0 24 24" class="h-3 w-3 fill-current"><path d={heart} /></svg>
      </span>
      <span data-likes-for={post.id}>{fmt(post.likes_count)}</span>
      <span class="sr-only">me gusta</span>
    </span>
    <span></span>
    {
      post.comments_count > 0 && (
        <a href={commentsHref} class="hover:underline">
          {fmt(post.comments_count)} {post.comments_count === 1 ? "comentario" : "comentarios"}
        </a>
      )
    }
  </div>

  <div class="flex items-center border-t border-line py-1">
    {
      loggedIn ? (
        <button type="button" class:list={[action, "aria-pressed:text-danger"]} data-social="like" data-id={post.id} aria-pressed={liked ? "true" : "false"}>
          <svg viewBox="0 0 24 24" class:list={[icon, "group-aria-pressed:fill-current"]} aria-hidden="true">
            <path stroke-linejoin="round" d={heart} />
          </svg>
          <span>Me gusta</span>
        </button>
      ) : (
        <a href={loginHref} class={action}>
          <svg viewBox="0 0 24 24" class={icon} aria-hidden="true"><path stroke-linejoin="round" d={heart} /></svg>
          <span>Me gusta</span>
        </a>
      )
    }

    <a href={commentsHref} class={action}>
      <svg viewBox="0 0 24 24" class={icon} aria-hidden="true">
        <path stroke-linejoin="round" d="M20 12.5c0 4-3.6 7-8 7-1.2 0-2.3-.2-3.3-.6L4 20l1.2-3.6C4.4 15.3 4 14 4 12.5c0-4 3.6-7 8-7s8 3 8 7Z" />
      </svg>
      <span>Comentar</span>
    </a>

    <button type="button" class={action} data-share-url={shareUrl} data-share-title={shareTitle}>
      <svg viewBox="0 0 24 24" class={icon} aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 15V4m0 0L8 8m4-4 4 4M6 12v6.5a1.5 1.5 0 0 0 1.5 1.5h9a1.5 1.5 0 0 0 1.5-1.5V12" />
      </svg>
      <span>Compartir</span>
    </button>

    {
      loggedIn ? (
        <button
          type="button"
          class:list={[action, "aria-pressed:text-brand"]}
          data-social="save"
          data-id={post.id}
          aria-pressed={saved ? "true" : "false"}
          data-label-on="Guardada"
          data-label-off="Guardar"
        >
          <svg viewBox="0 0 24 24" class:list={[icon, "group-aria-pressed:fill-current"]} aria-hidden="true">
            <path stroke-linejoin="round" d={bookmark} />
          </svg>
          <span data-label>{saved ? "Guardada" : "Guardar"}</span>
        </button>
      ) : (
        <a href={loginHref} class={action}>
          <svg viewBox="0 0 24 24" class={icon} aria-hidden="true"><path stroke-linejoin="round" d={bookmark} /></svg>
          <span>Guardar</span>
        </a>
      )
    }
  </div>
</div>

<script>
  import "../../scripts/social";
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/components/social/SituationBadge.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Etiqueta con la situación de una persona: "Busca empleo", "Emprendedor/a"... */
import type { ProfileSituation } from "../../services/posts";
import { situationInfo } from "../../config/situations";

interface Props {
  situation: ProfileSituation | null | undefined;
  size?: "sm" | "md";
  class?: string;
}

const { situation, size = "sm", class: className = "" } = Astro.props;
const info = situationInfo(situation);
---

{
  info && (
    <span
      class:list={[
        "inline-flex shrink-0 items-center rounded-full font-semibold",
        size === "md" ? "px-3 py-1 text-sm" : "px-2 py-0.5 text-xs",
        info.class,
        className,
      ]}
    >
      {info.badge}
    </span>
  )
}
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

escribir 'src/components/ui/VerifiedBadge.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Tilde azul de cuenta verificada por WorkLink. */
interface Props {
  size?: number;
  class?: string;
}

const { size = 16, class: className = "" } = Astro.props;
---

<span class:list={["inline-flex shrink-0 align-[-0.15em] text-seek", className]} title="Cuenta verificada por WorkLink">
  <svg viewBox="0 0 24 24" width={size} height={size} aria-hidden="true">
    <path
      fill="currentColor"
      d="M12 1.5l2.6 1.9 3.2-.1 1 3.1 2.6 1.9-1 3.1 1 3.1-2.6 1.9-1 3.1-3.2-.1L12 22.5l-2.6-1.9-3.2.1-1-3.1-2.6-1.9 1-3.1-1-3.1 2.6-1.9 1-3.1 3.2.1L12 1.5Z"
    />
    <path fill="none" stroke="var(--wl-surface, #fff)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="m8 12.2 2.7 2.7L16.2 9.4" />
  </svg>
  <span class="sr-only">Cuenta verificada</span>
</span>
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
export const protectedPrefixes = ["/panel", "/cuenta", "/admin", "/notificaciones", "/mensajes"] as const;

/** Prefijos que además requieren rol de staff (moderator o superior). */
export const staffPrefixes = ["/admin"] as const;

/**
 * Valida una ruta interna de redirección (?next=...). Evita redirecciones
 * abiertas a otros dominios ("//evil.com", "https://...").
 */
export function safeNextPath(value: string | null | undefined, fallback: string = routes.home): string {
  if (!value) return fallback;
  if (!value.startsWith("/") || value.startsWith("//") || value.startsWith("/\\")) return fallback;
  return value;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/config/situations.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { ProfileSituation } from "../services/posts";

/**
 * Situación laboral que cada persona puede mostrar en su perfil y en sus
 * publicaciones. El orden es el del formulario.
 */
export const SITUATIONS: { value: ProfileSituation; label: string; badge: string; hint: string; class: string }[] = [
  {
    value: "job_seeking",
    label: "Busco empleo",
    badge: "Busca empleo",
    hint: "Estás buscando trabajo en relación de dependencia.",
    class: "bg-seek-soft text-seek",
  },
  {
    value: "entrepreneur",
    label: "Tengo un emprendimiento",
    badge: "Emprendedor/a",
    hint: "Vendés productos o servicios con tu propio emprendimiento.",
    class: "bg-offer-soft text-offer",
  },
  {
    value: "freelancer",
    label: "Ofrezco mis servicios",
    badge: "Ofrece servicios",
    hint: "Trabajás por tu cuenta: oficios, profesiones, changas.",
    class: "bg-success-soft text-success",
  },
  {
    value: "hiring",
    label: "Busco contratar",
    badge: "Busca contratar",
    hint: "Necesitás sumar personas a tu equipo o contratar un servicio.",
    class: "bg-warning-soft text-warning",
  },
];

export const SITUATION_VALUES = SITUATIONS.map((s) => s.value) as [ProfileSituation, ...ProfileSituation[]];

export function situationInfo(value: ProfileSituation | null | undefined) {
  return value ? (SITUATIONS.find((s) => s.value === value) ?? null) : null;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/env.d.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/// <reference types="astro/client" />

import type { SupabaseClient } from "@supabase/supabase-js";
import type { SessionUser } from "./lib/auth/session";
import type { ViewerProfile } from "./lib/viewer";

declare global {
  namespace App {
    interface Locals {
      /** Cliente de Supabase con la sesión de esta request (RLS aplica). */
      supabase: SupabaseClient;
      /** Usuario autenticado, o null si es un visitante. */
      user: SessionUser | null;
      /** Perfil del usuario actual (se carga una vez, al pedirlo). Usar getViewerProfile(). */
      viewerProfile?: Promise<ViewerProfile | null>;
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
  department?: string | null;
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
                {city.department && city.department !== city.name && (
                  <span class="block text-xs text-ink-muted">Depto. {city.department}</span>
                )}
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
  /** Oculta solo el Footer (pantallas de altura completa, como el chat). */
  hideFooter?: boolean;
}

const { title, description = brand.description, canonicalPath, noindex = false, image, bare = false, hideFooter = false } = Astro.props;

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
    {!bare && !hideFooter && <Footer />}
  </body>
</html>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/layouts/PanelLayout.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Layout del área privada: navegación del panel + contenido. Siempre noindex. */
import BaseLayout from "./BaseLayout.astro";
import { getViewerProfile } from "../lib/viewer";

interface Props {
  title: string;
  heading?: string;
  description?: string;
  /** Enlace "volver" opcional sobre el título. */
  back?: { href: string; label: string };
}

const { title, heading = title, description, back } = Astro.props;
const path = Astro.url.pathname;

const viewer = await getViewerProfile(Astro.locals);

const links = [
  { href: "/panel", label: "Resumen", active: path === "/panel" },
  { href: viewer ? `/u/${viewer.username}` : "/panel/perfil", label: "Mi perfil", active: path.startsWith("/panel/perfil") },
  { href: "/panel/publicaciones", label: "Mis publicaciones", active: path.startsWith("/panel/publicaciones") },
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

escribir 'src/lib/viewer.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { ProfileSituation } from "../services/posts";

/** Datos básicos del perfil del usuario logueado (encabezado, inicio, panel). */
export interface ViewerProfile {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  situation: ProfileSituation | null;
  headline: string | null;
  following_count: number;
  verified_at: string | null;
}

/**
 * Perfil del usuario actual, consultado una sola vez por request aunque lo
 * pidan varios componentes (queda guardado en locals).
 */
export function getViewerProfile(locals: App.Locals): Promise<ViewerProfile | null> {
  if (!locals.user) return Promise.resolve(null);
  locals.viewerProfile ??= (async () => {
    const { data, error } = await locals.supabase
      .from("profiles")
      .select("id, username, first_name, last_name, avatar_path, situation, headline, following_count, verified_at")
      .eq("id", locals.user!.id)
      .maybeSingle();
    if (error) {
      console.error("[viewer]", error.message);
      return null;
    }
    return (data as ViewerProfile | null) ?? null;
  })();
  return locals.viewerProfile;
}
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
 * Además borra las notificaciones leídas hace más de 90 días.
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

  const oldRead = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
  const { count: notifications, error: notifError } = await supabase
    .from("notifications")
    .delete({ count: "exact" })
    .lt("read_at", oldRead);
  if (notifError) console.error("[cron/limpiar-archivos] notificaciones", notifError.message);

  return Response.json({
    ok: true,
    media: removedRows.length,
    files: removedFiles,
    notifications: notifications ?? 0,
    more: (rows?.length ?? 0) === BATCH,
  });
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/api/mensajes/[id].ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { APIRoute } from "astro";
import { getConversation, getMessagesAfter, markConversationRead } from "../../../services/messages";

/**
 * Mensajes nuevos de una conversación (la pide la pantalla del chat cada
 * pocos segundos): GET /api/mensajes/<id>?despues=<fecha ISO>
 * Responde los mensajes nuevos y hasta dónde leyó la otra persona ("Visto").
 * Si llegaron mensajes de la otra persona, marca la conversación como leída.
 */
export const GET: APIRoute = async ({ params, url, locals }) => {
  const headers = { "Cache-Control": "private, no-store" };
  const user = locals.user;
  if (!user) return Response.json({ error: "unauthorized" }, { status: 401, headers });

  const id = params.id ?? "";
  const after = url.searchParams.get("despues") ?? "";
  if (!/^[0-9a-f-]{36}$/.test(id) || Number.isNaN(Date.parse(after))) {
    return Response.json({ error: "bad_request" }, { status: 400, headers });
  }

  const conversation = await getConversation(locals.supabase, id, user.id);
  if (!conversation) return Response.json({ error: "not_found" }, { status: 404, headers });

  const messages = await getMessagesAfter(locals.supabase, id, after);
  if (messages.some((m) => m.sender_id !== user.id)) await markConversationRead(locals.supabase, id);

  return Response.json({ messages, otherLastReadAt: conversation.otherLastReadAt }, { headers });
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/api/notificaciones.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { APIRoute } from "astro";
import { countUnread } from "../../services/notifications";
import { countUnreadConversations } from "../../services/messages";

/**
 * Cantidad de notificaciones sin leer del usuario actual (para la campanita).
 * y de conversaciones con mensajes sin leer (para el ícono de mensajes).
 * GET /api/notificaciones -> { unread, messages }. Privado: nunca se cachea.
 */
export const GET: APIRoute = async ({ locals }) => {
  const headers = { "Cache-Control": "private, no-store" };
  if (!locals.user) return Response.json({ unread: 0, messages: 0 }, { status: 401, headers });
  const [unread, messages] = await Promise.all([countUnread(locals.supabase, locals.user.id), countUnreadConversations(locals.supabase)]);
  return Response.json({ unread, messages }, { headers });
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
 * Buscador: personas, emprendimientos y publicaciones, con filtros por rubro,
 * ciudad, situación (personas) y tipo (publicaciones). Sin texto funciona
 * como directorio ("Tecnología en Villa María").
 *
 *   ?q=texto  &ver=todo|personas|emprendimientos|publicaciones
 *   &rubro=slug  &ciudad=id  &situacion=job_seeking...  &tipo=offer...  &pagina=2
 *
 * Los resultados no se indexan (contenido variable); las páginas indexables
 * del directorio son /rubros/...
 */
import BaseLayout from "../layouts/BaseLayout.astro";
import PostCard from "../components/posts/PostCard.astro";
import BusinessResultCard from "../components/directory/BusinessResultCard.astro";
import PersonResultRow from "../components/directory/PersonResultRow.astro";
import CityPicker from "../islands/CityPicker.tsx";
import { hasCriteria, normalizeQuery, searchBusinesses, searchPeople, searchPosts, SEARCH_MIN, SEARCH_PAGE, type BusinessResult, type Paged, type PersonResult, type SearchFilters } from "../services/search";
import { getViewerReactions } from "../services/social";
import { getCategoryTree } from "../services/categories";
import { getCity } from "../services/locations";
import { SITUATIONS } from "../config/situations";
import { POST_TYPES, type PostType } from "../schemas/post";
import type { PostView, ProfileSituation } from "../services/posts";

const { supabase, user } = Astro.locals;
const params = Astro.url.searchParams;

const TABS = [
  { value: "todo", label: "Todo" },
  { value: "personas", label: "Personas" },
  { value: "emprendimientos", label: "Emprendimientos" },
  { value: "publicaciones", label: "Publicaciones" },
] as const;
type Tab = (typeof TABS)[number]["value"];

const tab: Tab = (TABS.find((t) => t.value === params.get("ver"))?.value ?? "todo") as Tab;
const page = Math.max(1, Math.min(50, Number.parseInt(params.get("pagina") ?? "1", 10) || 1));

const categories = await getCategoryTree(supabase);
const category = categories.find((c) => c.slug === params.get("rubro")) ?? null;
const cityIdParam = Number.parseInt(params.get("ciudad") ?? "", 10);
const city = Number.isInteger(cityIdParam) && cityIdParam > 0 ? await getCity(supabase, cityIdParam) : null;
const situation = (SITUATIONS.find((s) => s.value === params.get("situacion"))?.value ?? null) as ProfileSituation | null;
const type = (POST_TYPES.find((t) => t.value === params.get("tipo"))?.value ?? null) as PostType | null;

const filters: SearchFilters = {
  q: normalizeQuery(params.get("q")),
  categoryId: category?.id ?? null,
  cityId: city?.id ?? null,
  // Cada filtro aplica solo a su pestaña.
  situation: tab === "personas" ? situation : null,
  type: tab === "publicaciones" ? type : null,
};
const ready = hasCriteria(filters);
const tooShort = filters.q.length > 0 && filters.q.length < SEARCH_MIN && !filters.categoryId && !filters.cityId;

const offset = (page - 1) * SEARCH_PAGE;
const none = <T,>(): Promise<Paged<T>> => Promise.resolve({ items: [], hasMore: false });
const show = (which: Tab) => ready && (tab === "todo" || tab === which);
const size = (preview: number) => (tab === "todo" ? preview : SEARCH_PAGE);
const from = tab === "todo" ? 0 : offset;
const [people, businesses, posts] = await Promise.all([
  show("personas") ? searchPeople(supabase, filters, size(5), from) : none<PersonResult>(),
  show("emprendimientos") ? searchBusinesses(supabase, filters, size(6), from) : none<BusinessResult>(),
  show("publicaciones") ? searchPosts(supabase, filters, size(10), from) : none<PostView>(),
]);
const reactions = await getViewerReactions(supabase, user?.id, posts.items.map((p) => p.id));
const total = people.items.length + businesses.items.length + posts.items.length;

// Enlaces que conservan los filtros actuales.
function link(changes: Record<string, string | null>) {
  const next = new URLSearchParams();
  const base: Record<string, string | null> = {
    q: filters.q || null,
    ver: tab === "todo" ? null : tab,
    rubro: category?.slug ?? null,
    ciudad: city ? String(city.id) : null,
    situacion: situation,
    tipo: type,
    ...changes,
  };
  for (const [key, value] of Object.entries(base)) if (value) next.set(key, value);
  const s = next.toString();
  return `/buscar${s ? `?${s}` : ""}`;
}

const titleParts = [filters.q && `“${filters.q}”`, category?.name, city && `en ${city.name}`].filter(Boolean).join(" ");
const selectClass = "h-11 w-full rounded-wl border border-line bg-surface px-3 text-base text-ink focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25";
---

<BaseLayout title={titleParts ? `Buscar ${titleParts}` : "Buscar"} noindex canonicalPath="/buscar">
  <section class="mx-auto flex max-w-3xl flex-col gap-5 px-4 py-6">
    <h1 class="sr-only">Buscar en WorkLink</h1>

    <form action="/buscar" method="GET" role="search" class="flex flex-col gap-3 rounded-wl-lg border border-line bg-surface p-4">
      {tab !== "todo" && <input type="hidden" name="ver" value={tab} />}
      <div class="relative">
        <label for="buscar-q" class="sr-only">Qué buscás</label>
        <input
          id="buscar-q"
          type="search"
          name="q"
          value={filters.q}
          maxlength={100}
          autofocus={!ready}
          autocomplete="off"
          enterkeyhint="search"
          placeholder="Nombre, rubro o lo que necesitás"
          class="h-12 w-full rounded-full border border-line bg-surface-muted px-5 text-base focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25"
        />
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <div class="flex flex-col gap-1.5">
          <label for="buscar-rubro" class="text-sm font-medium">Rubro</label>
          <select id="buscar-rubro" name="rubro" class={selectClass}>
            <option value="">Todos los rubros</option>
            {categories.map((c) => <option value={c.slug} selected={c.id === category?.id}>{c.name}</option>)}
          </select>
        </div>
        <CityPicker
          client:load
          name="ciudad"
          label="Ciudad"
          initialCity={city ? { id: city.id, name: city.name, province_name: city.province_name } : null}
          hint="Dejala vacía para buscar en todo el país."
        />
        {tab === "personas" && (
          <div class="flex flex-col gap-1.5">
            <label for="buscar-situacion" class="text-sm font-medium">Situación</label>
            <select id="buscar-situacion" name="situacion" class={selectClass}>
              <option value="">Todas</option>
              {SITUATIONS.map((s) => <option value={s.value} selected={s.value === situation}>{s.label}</option>)}
            </select>
          </div>
        )}
        {tab === "publicaciones" && (
          <div class="flex flex-col gap-1.5">
            <label for="buscar-tipo" class="text-sm font-medium">Tipo de publicación</label>
            <select id="buscar-tipo" name="tipo" class={selectClass}>
              <option value="">Todas</option>
              {POST_TYPES.map((t) => <option value={t.value} selected={t.value === type}>{t.label}</option>)}
            </select>
          </div>
        )}
      </div>
      <div class="flex flex-wrap items-center gap-3">
        <button type="submit" class="h-11 rounded-wl bg-brand px-6 font-semibold text-brand-contrast hover:bg-brand-hover">Buscar</button>
        {(filters.q || category || city || situation || type) && (
          <a href={tab === "todo" ? "/buscar" : `/buscar?ver=${tab}`} class="text-sm font-semibold text-ink-muted hover:text-ink">Limpiar filtros</a>
        )}
      </div>
    </form>

    <nav aria-label="Qué mostrar" class="flex gap-1 overflow-x-auto border-b border-line">
      {
        TABS.map((t) => (
          <a
            href={link({ ver: t.value === "todo" ? null : t.value, pagina: null, situacion: t.value === "personas" ? situation : null, tipo: t.value === "publicaciones" ? type : null })}
            aria-current={t.value === tab ? "page" : undefined}
            class:list={[
              "whitespace-nowrap border-b-2 px-3 py-2.5 text-sm font-semibold",
              t.value === tab ? "border-brand text-ink" : "border-transparent text-ink-muted hover:text-ink",
            ]}
          >
            {t.label}
          </a>
        ))
      }
    </nav>

    {
      !ready ? (
        tooShort ? (
          <p class="text-center text-ink-muted">Escribí al menos {SEARCH_MIN} letras, o elegí un rubro o una ciudad.</p>
        ) : (
          <div>
            <p class="text-ink-muted">Escribí qué buscás, o elegí un rubro para ver quiénes lo ofrecen:</p>
            <ul class="mt-4 flex flex-wrap gap-2">
              {categories.map((c) => (
                <li>
                  <a href={link({ rubro: c.slug })} class="inline-block rounded-full border border-line bg-surface px-3 py-1.5 text-sm hover:border-brand">
                    {c.name}
                  </a>
                </li>
              ))}
            </ul>
            <p class="mt-6 text-sm">
              <a href="/rubros" class="font-semibold text-brand hover:underline">Ver el directorio completo de rubros</a>
            </p>
          </div>
        )
      ) : total === 0 ? (
        <div class="rounded-wl-lg border border-dashed border-line bg-surface p-10 text-center">
          <h2 class="text-lg font-semibold">No encontramos resultados</h2>
          <p class="mt-1 text-ink-muted">
            {city ? "Probá sacando la ciudad para buscar en todo el país, o con otra palabra." : "Probá con otra palabra, o más corta (por ejemplo “foto” en vez de “fotógrafa profesional”)."}
          </p>
        </div>
      ) : (
        <>
          {people.items.length > 0 && (
            <section aria-labelledby="r-personas">
              <div class="mb-3 flex items-baseline justify-between gap-4">
                <h2 id="r-personas" class="text-lg font-semibold">Personas</h2>
                {tab === "todo" && people.hasMore && <a href={link({ ver: "personas" })} class="text-sm font-semibold text-brand hover:underline">Ver todas</a>}
              </div>
              <ul class="divide-y divide-line overflow-hidden rounded-wl-lg border border-line bg-surface">
                {people.items.map((person) => (
                  <li><PersonResultRow person={person} /></li>
                ))}
              </ul>
            </section>
          )}

          {businesses.items.length > 0 && (
            <section aria-labelledby="r-emprendimientos">
              <div class="mb-3 flex items-baseline justify-between gap-4">
                <h2 id="r-emprendimientos" class="text-lg font-semibold">Emprendimientos</h2>
                {tab === "todo" && businesses.hasMore && <a href={link({ ver: "emprendimientos" })} class="text-sm font-semibold text-brand hover:underline">Ver todos</a>}
              </div>
              <ul class="divide-y divide-line overflow-hidden rounded-wl-lg border border-line bg-surface">
                {businesses.items.map((b) => (
                  <li><BusinessResultCard business={b} /></li>
                ))}
              </ul>
            </section>
          )}

          {posts.items.length > 0 && (
            <section aria-labelledby="r-publicaciones">
              <div class="mb-3 flex items-baseline justify-between gap-4">
                <h2 id="r-publicaciones" class="text-lg font-semibold">Publicaciones</h2>
                {tab === "todo" && posts.hasMore && <a href={link({ ver: "publicaciones" })} class="text-sm font-semibold text-brand hover:underline">Ver todas</a>}
              </div>
              <div class="flex flex-col gap-4">
                {posts.items.map((post) => (
                  <PostCard post={post} liked={reactions.liked.has(post.id)} saved={reactions.saved.has(post.id)} />
                ))}
              </div>
            </section>
          )}

          {tab !== "todo" && (page > 1 || people.hasMore || businesses.hasMore || posts.hasMore) && (
            <nav class="flex justify-between gap-4" aria-label="Páginas">
              {page > 1 ? <a href={link({ pagina: page - 1 > 1 ? String(page - 1) : null })} class="font-semibold text-brand hover:underline">← Anteriores</a> : <span />}
              {(people.hasMore || businesses.hasMore || posts.hasMore) && (
                <a href={link({ pagina: String(page + 1) })} class="font-semibold text-brand hover:underline">Más resultados →</a>
              )}
            </nav>
          )}
        </>
      )
    }
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
import { newMessagePath } from "../../services/messages";
import { directoryPath } from "../../services/directory";

const { supabase, user } = Astro.locals;
const slug = (Astro.params.slug ?? "").toLowerCase();
if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) return Astro.rewrite("/404");

const business = await getBusinessBySlug(supabase, slug, { withContact: Boolean(user) });
if (!business) return Astro.rewrite("/404");

const { data: membership } = user
  ? await supabase.from("business_members").select("role").eq("business_id", business.id).eq("user_id", user.id).maybeSingle()
  : { data: null };
const canEdit = Boolean(membership);

const [catalog, { posts: businessPosts }, following, { data: owner }] = await Promise.all([
  getCatalog(supabase, business.id, { onlyPublic: true }),
  getFeed(supabase, { businessId: business.id, limit: 6 }),
  isFollowing(supabase, user?.id, "business", business.id),
  supabase.from("profiles").select("username").eq("id", business.owner_id).eq("status", "active").maybeSingle(),
]);
// Mensajes privados: le llegan a quien creó el emprendimiento.
const messageHref = owner && owner.username && user?.id !== business.owner_id ? newMessagePath(owner.username) : null;
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
    { name: "Inicio", url: new URL("/", site).toString() },
    ...(business.category
      ? [
          { name: business.category.name, url: new URL(directoryPath.category(business.category.slug), site).toString() },
          ...(business.city?.province_slug
            ? [
                {
                  name: `${business.category.name} en ${business.city.name}`,
                  url: new URL(directoryPath.landing(business.category.slug, business.city.province_slug, business.city.slug), site).toString(),
                },
              ]
            : []),
        ]
      : []),
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
            {business.category ? (
              <a
                href={business.city?.province_slug
                  ? directoryPath.landing(business.category.slug, business.city.province_slug, business.city.slug)
                  : directoryPath.category(business.category.slug)}
                class="hover:text-ink hover:underline"
              >
                {[business.category.name, location].filter(Boolean).join(" · ")}
              </a>
            ) : (
              location
            )}
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
                <div class="flex flex-col gap-4">
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
                {messageHref && <Button href={messageHref} variant="secondary" block>Enviar mensaje</Button>}
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
                {!messageHref && !business.whatsapp && !business.phone && !business.email && (
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
 * Inicio.
 *  - Con sesión: el feed personal (buscador, caja para publicar, publicaciones
 *    de quienes sigue). No se indexa: es distinto para cada persona.
 *  - Sin sesión: la landing que explica qué es WorkLink y para qué sirve.
 */
import BaseLayout from "../layouts/BaseLayout.astro";
import HomeFeed from "../components/home/HomeFeed.astro";
import Landing from "../components/home/Landing.astro";
import { getViewerProfile } from "../lib/viewer";
import { jsonLdScript } from "../lib/seo/business";
import { brand } from "../config/brand";

const viewer = await getViewerProfile(Astro.locals);

const site = Astro.site ?? new URL(Astro.url.origin);
// Datos estructurados: Google puede mostrar la caja de búsqueda del sitio.
const websiteJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  name: brand.name,
  url: new URL("/", site).toString(),
  inLanguage: "es-AR",
  potentialAction: {
    "@type": "SearchAction",
    target: { "@type": "EntryPoint", urlTemplate: new URL("/buscar?q={search_term_string}", site).toString() },
    "query-input": "required name=search_term_string",
  },
};
---

{
  viewer ? (
    <BaseLayout title="Inicio" noindex>
      <HomeFeed viewer={viewer} />
    </BaseLayout>
  ) : (
    <BaseLayout
      title="Red de trabajo, servicios y emprendimientos de tu ciudad"
      description="Publicá como en Facebook, contá si buscás empleo, tenés un emprendimiento u ofrecés servicios, y conectá con gente de tu zona. Gratis."
      canonicalPath="/"
    >
      <script slot="head" type="application/ld+json" set:html={jsonLdScript(websiteJsonLd)} />
      <Landing />
    </BaseLayout>
  )
}
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

escribir 'src/pages/inicio/mas.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Fragmento HTML con la página siguiente del inicio (lo pide "Cargar más").
 * Solo para usuarios logueados. No se indexa.
 */
import FeedPage from "../../components/posts/FeedPage.astro";
import { getHomeFeed, HOME_MODES, type HomeMode } from "../../services/home";
import { decodeCursor } from "../../services/posts";
import { getViewerReactions } from "../../services/social";

export const partial = true;

const { supabase, user } = Astro.locals;
const cursor = decodeCursor(Astro.url.searchParams.get("desde"));
const mode = Astro.url.searchParams.get("modo") as HomeMode | null;
if (!user || !cursor || !mode || !HOME_MODES.includes(mode)) return new Response(null, { status: 400 });

const page = await getHomeFeed(supabase, { followingCount: 0, mode, cursor });
const reactions = await getViewerReactions(supabase, user.id, page.posts.map((p) => p.id));
const more = (next: string) => `modo=${mode}&desde=${next}`;

Astro.response.headers.set("X-Robots-Tag", "noindex");
---

<FeedPage
  posts={page.posts}
  reactions={reactions}
  nextHref={page.nextCursor ? `/?${more(page.nextCursor)}` : null}
  nextFragmentHref={page.nextCursor ? `/inicio/mas?${more(page.nextCursor)}` : null}
/>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/mensajes/[id].astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Conversación privada. Funciona sin JavaScript (formulario común); con
 * JavaScript envía sin recargar y trae los mensajes nuevos cada pocos
 * segundos (scripts/chat.ts). Al abrirla se marca como leída.
 */
import { actions, isInputError } from "astro:actions";
import BaseLayout from "../../layouts/BaseLayout.astro";
import Avatar from "../../components/ui/Avatar.astro";
import VerifiedBadge from "../../components/ui/VerifiedBadge.astro";
import SituationBadge from "../../components/social/SituationBadge.astro";
import { getConversation, getMessages, markConversationRead } from "../../services/messages";
import { getPost, postHeadline } from "../../services/posts";
import { displayName } from "../../services/profiles";
import { formatDate } from "../../lib/format";
import { postPath, profilePath } from "../../lib/urls";
import { MESSAGE_MAX } from "../../schemas/message";

const { supabase, user } = Astro.locals;
const id = Astro.params.id ?? "";
if (!/^[0-9a-f-]{36}$/.test(id)) return Astro.rewrite("/404");

// Envío sin JavaScript: volver a la conversación con GET.
const sent = Astro.getActionResult(actions.messages.send);
if (sent && !sent.error) return Astro.redirect(`/mensajes/${id}#ultimo`, 303);
const hidden = Astro.getActionResult(actions.messages.hide);
if (hidden && !hidden.error) return Astro.redirect("/mensajes?oculta=1", 303);
const sendError = sent?.error ? (isInputError(sent.error) ? sent.error.fields.body?.[0] : sent.error.message) : null;

const conversation = await getConversation(supabase, id, user!.id);
if (!conversation) return Astro.rewrite("/404");

const before = Astro.url.searchParams.get("antes");
const { messages, hasOlder } = await getMessages(supabase, id, { before });
if (conversation.unread) await markConversationRead(supabase, id);

// Consulta sobre una publicación (viene de "Enviar mensaje" en una publicación).
const postParam = Astro.url.searchParams.get("publicacion");
const contextPost = postParam && /^[0-9a-f-]{36}$/.test(postParam) ? await getPost(supabase, postParam) : null;

const other = conversation.other;
const name = other ? displayName(other) : "Usuario";
const me = user!.id;
const dayKey = (iso: string) => formatDate(iso, { year: "numeric", month: "2-digit", day: "2-digit" });
const today = dayKey(new Date().toISOString());
const yesterday = dayKey(new Date(Date.now() - 86400000).toISOString());
const dayLabel = (iso: string) => {
  const key = dayKey(iso);
  return key === today ? "Hoy" : key === yesterday ? "Ayer" : formatDate(iso, { weekday: "long", day: "numeric", month: "long" });
};
const lastMine = [...messages].reverse().find((m) => m.sender_id === me);
const seen = Boolean(lastMine && conversation.otherLastReadAt && conversation.otherLastReadAt >= lastMine.created_at);
const lastAt = messages.length ? messages[messages.length - 1].created_at : new Date(0).toISOString();
---

<BaseLayout title={`Mensajes con ${name}`} noindex hideFooter>
  <section
    class="mx-auto flex h-[calc(100dvh-4rem)] w-full flex-col bg-surface md:my-6 md:h-[min(620px,calc(100dvh-7rem))] md:max-w-md md:overflow-hidden md:rounded-wl-lg md:border md:border-line md:shadow-xl"
    data-chat
    data-conversation={id}
    data-me={me}
    data-last={lastAt}
    data-other-read={conversation.otherLastReadAt ?? ""}
  >
    <header class="flex items-center gap-2 border-b border-line px-2 py-2">
      <a href="/mensajes" class="grid h-8 w-8 shrink-0 place-items-center rounded-full text-ink-muted hover:bg-surface-muted" aria-label="Todos los mensajes" title="Todos los mensajes">
        <svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-current stroke-2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M15 5l-7 7 7 7" /></svg>
      </a>
      {other ? (
        <a href={profilePath(other.username)} class="flex min-w-0 flex-1 items-center gap-3">
          <Avatar name={name} path={other.avatar_path} size={34} />
          <span class="min-w-0">
            <span class="flex items-center gap-1.5 text-sm font-semibold">
              <span class="truncate">{name}</span>
              {other.verified_at && <VerifiedBadge size={14} />}
              <SituationBadge situation={other.situation} />
            </span>
            {other.headline && <span class="block truncate text-xs text-ink-muted">{other.headline}</span>}
          </span>
        </a>
      ) : (
        <span class="flex-1 font-semibold">{name}</span>
      )}
      <form method="POST" action={actions.messages.hide} data-confirm="¿Ocultar esta conversación de tu bandeja?">
        <input type="hidden" name="conversation_id" value={id} />
        <button type="submit" class="rounded-wl px-2 py-1 text-xs font-semibold text-ink-muted hover:bg-surface-muted hover:text-ink">Ocultar</button>
      </form>
      <a href="/mensajes" class="grid h-8 w-8 shrink-0 place-items-center rounded-full text-ink-muted hover:bg-surface-muted hover:text-ink" aria-label="Cerrar conversación" title="Cerrar" data-chat-close>
        <svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-current stroke-2" aria-hidden="true"><path stroke-linecap="round" d="M6 6l12 12M18 6 6 18" /></svg>
      </a>
    </header>

    <div class="flex-1 overflow-y-auto px-3 py-3 text-[15px]" data-chat-scroll>
      {hasOlder && messages[0] && (
        <p class="mb-4 text-center">
          <a href={`/mensajes/${id}?antes=${encodeURIComponent(messages[0].created_at)}`} class="text-sm font-semibold text-brand hover:underline">Ver mensajes anteriores</a>
        </p>
      )}
      {messages.length === 0 && (
        <p class="mt-10 text-center text-sm text-ink-muted" data-chat-empty>
          Escribile a {other?.first_name ?? name}. Los mensajes son privados: solo los ven ustedes dos.
        </p>
      )}
      <ol class="flex flex-col gap-1.5" data-chat-list>
        {messages.map((m, index) => {
          const mine = m.sender_id === me;
          const newDay = index === 0 || dayKey(messages[index - 1].created_at) !== dayKey(m.created_at);
          return (
            <>
              {newDay && <li class="my-3 text-center text-xs font-semibold capitalize text-ink-muted" data-day={dayKey(m.created_at)}>{dayLabel(m.created_at)}</li>}
              <li class:list={["flex", mine ? "justify-end" : "justify-start"]} data-message={m.id}>
                <div class:list={["max-w-[78%] rounded-2xl px-3 py-1.5", mine ? "rounded-br-md bg-brand text-brand-contrast" : "rounded-bl-md bg-surface-muted text-ink"]}>
                  {m.post && (
                    <a href={postPath(m.post)} class:list={["mb-1.5 block rounded-wl border px-2.5 py-1.5 text-xs", mine ? "border-white/30 hover:bg-white/10" : "border-line hover:bg-surface"]}>
                      Consulta sobre: <strong>{postHeadline(m.post, 60)}</strong>
                    </a>
                  )}
                  <p class="whitespace-pre-line break-words">{m.body}</p>
                  <time datetime={m.created_at} class:list={["mt-0.5 block text-right text-[11px]", mine ? "opacity-75" : "text-ink-muted"]}>
                    {formatDate(m.created_at, { hour: "2-digit", minute: "2-digit" })}
                  </time>
                </div>
              </li>
            </>
          );
        })}
      </ol>
      <p class="mt-1 text-right text-xs text-ink-muted" data-chat-seen hidden={!seen}>Visto</p>
      <span id="ultimo"></span>
    </div>

    <form method="POST" action={actions.messages.send} class="border-t border-line p-2.5" data-chat-form>
      <input type="hidden" name="conversation_id" value={id} />
      {contextPost && (
        <div class="mb-2 flex items-center justify-between gap-2 rounded-wl bg-surface-muted px-3 py-2 text-sm" data-chat-context>
          <span class="min-w-0 truncate">Consulta sobre: <strong>{postHeadline(contextPost, 60)}</strong></span>
          <input type="hidden" name="post_id" value={contextPost.id} />
        </div>
      )}
      {sendError && <p class="mb-2 text-sm text-danger" role="alert" data-chat-error>{sendError}</p>}
      <p class="mb-2 hidden text-sm text-danger" role="alert" data-chat-error-js></p>
      <div class="flex items-end gap-2">
        <label for="chat-body" class="sr-only">Mensaje</label>
        <textarea
          id="chat-body"
          name="body"
          rows="1"
          maxlength={MESSAGE_MAX}
          required
          placeholder="Escribí un mensaje…"
          class="max-h-32 min-h-10 flex-1 resize-none rounded-2xl border border-line bg-surface-muted px-3.5 py-2 text-base focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25"
        ></textarea>
        <button type="submit" class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-brand text-brand-contrast hover:bg-brand-hover disabled:opacity-50" aria-label="Enviar">
          <svg viewBox="0 0 24 24" class="h-5 w-5 fill-current" aria-hidden="true"><path d="M3.4 20.4 21 12 3.4 3.6 3.4 10l12.6 2-12.6 2z" /></svg>
        </button>
      </div>
    </form>
  </section>
</BaseLayout>

<script>
  import "../../scripts/chat";
</script>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/mensajes/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Bandeja de mensajes: conversaciones de la más reciente a la más vieja. */
import BaseLayout from "../../layouts/BaseLayout.astro";
import Avatar from "../../components/ui/Avatar.astro";
import VerifiedBadge from "../../components/ui/VerifiedBadge.astro";
import { getConversations } from "../../services/messages";
import { displayName } from "../../services/profiles";
import { formatRelative } from "../../lib/format";

const { supabase, user } = Astro.locals;
const conversations = await getConversations(supabase, user!.id);
const hidden = Astro.url.searchParams.get("oculta") === "1";
---

<BaseLayout title="Mensajes" noindex>
  <section class="mx-auto max-w-2xl px-4 py-8">
    <h1 class="text-2xl font-bold">Mensajes</h1>
    {hidden && <p class="mt-3 text-sm text-ink-muted">Ocultaste la conversación. Si te vuelven a escribir, aparece de nuevo.</p>}

    {
      conversations.length === 0 ? (
        <div class="mt-6 rounded-wl-lg border border-dashed border-line bg-surface p-10 text-center">
          <p class="font-semibold">Todavía no tenés mensajes.</p>
          <p class="mt-1 text-sm text-ink-muted">Para escribirle a alguien, entrá a su perfil o a una publicación y tocá “Enviar mensaje”.</p>
        </div>
      ) : (
        <ul class="mt-6 divide-y divide-line overflow-hidden rounded-wl-lg border border-line bg-surface">
          {conversations.map((c) => {
            const name = c.other ? displayName(c.other) : "Usuario";
            const mine = c.last_sender_id === user!.id;
            return (
              <li>
                <a href={`/mensajes/${c.id}`} class:list={["flex items-center gap-3 p-4 hover:bg-surface-muted", c.unread && "bg-seek-soft/60"]}>
                  <Avatar name={name} path={c.other?.avatar_path} size={52} />
                  <span class="min-w-0 flex-1">
                    <span class="flex items-baseline justify-between gap-3">
                      <span class:list={["inline-flex min-w-0 items-center gap-1", c.unread ? "font-bold" : "font-semibold"]}>
                        <span class="truncate">{name}</span>
                        {c.other?.verified_at && <VerifiedBadge size={14} />}
                      </span>
                      {c.last_message_at && <span class:list={["shrink-0 text-xs", c.unread ? "font-semibold text-seek" : "text-ink-muted"]}>{formatRelative(c.last_message_at)}</span>}
                    </span>
                    <span class:list={["block truncate text-sm", c.unread ? "font-semibold text-ink" : "text-ink-muted"]}>
                      {mine && "Vos: "}{c.last_message_preview}
                    </span>
                  </span>
                  {c.unread && <span class="h-2.5 w-2.5 shrink-0 rounded-full bg-seek" aria-label="Sin leer" />}
                </a>
              </li>
            );
          })}
        </ul>
      )
    }
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/mensajes/nuevo.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Empezar (o retomar) una conversación: /mensajes/nuevo?con=usuario&publicacion=id
 * La base verifica que la persona exista, que no haya bloqueo y los límites.
 */
import BaseLayout from "../../layouts/BaseLayout.astro";
import Button from "../../components/ui/Button.astro";

const { supabase, user } = Astro.locals;
const username = (Astro.url.searchParams.get("con") ?? "").toLowerCase();
const postId = Astro.url.searchParams.get("publicacion");
let message = "Esa cuenta no existe o no está disponible.";

if (/^[a-z0-9_.]{3,30}$/.test(username)) {
  const { data: other } = await supabase.from("profiles").select("id").eq("username", username).eq("status", "active").maybeSingle();
  if (other?.id === user!.id) {
    message = "No podés escribirte a vos.";
  } else if (other) {
    const { data, error } = await supabase.rpc("start_conversation", { p_other: other.id });
    if (!error && data) {
      const query = postId && /^[0-9a-f-]{36}$/.test(postId) ? `?publicacion=${postId}` : "";
      return Astro.redirect(`/mensajes/${data}${query}`);
    }
    message = error?.message ?? "No pudimos abrir la conversación.";
  }
}
---

<BaseLayout title="Mensajes" noindex>
  <section class="mx-auto max-w-xl px-4 py-16 text-center">
    <h1 class="text-2xl font-bold">No pudimos abrir la conversación</h1>
    <p class="mt-2 text-ink-muted">{message}</p>
    <div class="mt-6"><Button href="/mensajes" variant="secondary">Ir a mis mensajes</Button></div>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/notificaciones.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Notificaciones del usuario: me gusta, comentarios y nuevos seguidores.
 * Al abrir la página se marcan como leídas (las nuevas se ven resaltadas
 * esta vez). Ruta protegida por el middleware.
 */
import BaseLayout from "../layouts/BaseLayout.astro";
import Avatar from "../components/ui/Avatar.astro";
import VerifiedBadge from "../components/ui/VerifiedBadge.astro";
import { decodeCursor, getNotifications, markAllRead, type NotificationView } from "../services/notifications";
import { displayName } from "../services/profiles";
import { postHeadline } from "../services/posts";
import { formatDate, formatRelative } from "../lib/format";
import { postPath, profilePath } from "../lib/urls";

const { supabase, user } = Astro.locals;
const cursor = decodeCursor(Astro.url.searchParams.get("antes"));
const { items, nextCursor } = await getNotifications(supabase, user!.id, cursor);
if (items.some((n) => !n.read_at)) await markAllRead(supabase);

function describe(n: NotificationView) {
  const name = n.actor ? displayName(n.actor) : "Alguien";
  const post = n.post ? `“${postHeadline(n.post, 60)}”` : "tu publicación";
  switch (n.type) {
    case "post_like":
      return { name, text: `le gustó tu publicación ${post}.`, href: n.post ? postPath(n.post) : "#", icon: "♥", tone: "bg-danger text-white" };
    case "post_comment":
      return {
        name,
        text: `comentó tu publicación ${post}:`,
        quote: n.comment?.body,
        href: n.post ? `${postPath(n.post)}${n.comment ? `#c-${n.comment.id}` : "#comentarios"}` : "#",
        icon: "💬",
        tone: "bg-seek text-white",
      };
    case "profile_follow":
      return { name, text: "empezó a seguirte.", href: n.actor ? profilePath(n.actor.username) : "#", icon: "+", tone: "bg-success text-white" };
    case "business_follow":
      return {
        name,
        text: `empezó a seguir a ${n.business?.name ?? "tu emprendimiento"}.`,
        href: n.actor ? profilePath(n.actor.username) : "#",
        icon: "+",
        tone: "bg-offer text-white",
      };
  }
}
---

<BaseLayout title="Notificaciones" noindex>
  <section class="mx-auto max-w-2xl px-4 py-8">
    <h1 class="text-2xl font-bold">Notificaciones</h1>

    {
      items.length === 0 ? (
        <div class="mt-6 rounded-wl-lg border border-dashed border-line bg-surface p-10 text-center">
          <p class="font-semibold">{cursor ? "No hay notificaciones más viejas." : "Todavía no tenés notificaciones."}</p>
          <p class="mt-1 text-sm text-ink-muted">Cuando alguien le dé me gusta a lo que publicás, lo comente o te siga, te avisamos acá.</p>
        </div>
      ) : (
        <ul class="mt-6 divide-y divide-line overflow-hidden rounded-wl-lg border border-line bg-surface">
          {items.map((n) => {
            const d = describe(n);
            const unread = !n.read_at;
            return (
              <li>
                <a href={d.href} class:list={["flex gap-3 p-4 hover:bg-surface-muted", unread && "bg-seek-soft/60"]}>
                  <span class="relative shrink-0">
                    <Avatar name={d.name} path={n.actor?.avatar_path} size={48} />
                    <span class:list={["absolute -bottom-1 -right-1 grid h-6 w-6 place-items-center rounded-full border-2 border-surface text-xs font-bold", d.tone]} aria-hidden="true">
                      {d.icon}
                    </span>
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block">
                      <strong>{d.name}</strong>{n.actor?.verified_at && <VerifiedBadge size={14} class="ml-1" />} {d.text}
                    </span>
                    {d.quote && <span class="mt-1 line-clamp-2 block text-sm text-ink-muted">“{d.quote}”</span>}
                    <time datetime={n.created_at} title={formatDate(n.created_at, { dateStyle: "long", timeStyle: "short" })} class:list={["mt-1 block text-xs", unread ? "font-semibold text-seek" : "text-ink-muted"]}>
                      {formatRelative(n.created_at)}
                    </time>
                  </span>
                  {unread && <span class="mt-2 h-2.5 w-2.5 shrink-0 rounded-full bg-seek" aria-label="Nueva" />}
                </a>
              </li>
            );
          })}
        </ul>
      )
    }

    {
      nextCursor && (
        <div class="mt-6 text-center">
          <a href={`/notificaciones?antes=${nextCursor}`} class="font-semibold text-brand hover:underline">Ver anteriores</a>
        </div>
      )
    }
  </section>
</BaseLayout>
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
import SituationBadge from "../../components/social/SituationBadge.astro";
import VerifiedBadge from "../../components/ui/VerifiedBadge.astro";
import FollowButton from "../../components/social/FollowButton.astro";
import CommentsSection from "../../components/social/CommentsSection.astro";
import { getComments, getViewerReactions, isFollowing } from "../../services/social";
import { newMessagePath } from "../../services/messages";
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
// Arriba la persona que publicó (con su perfil para seguirla); debajo, el emprendimiento si lo hay.
const personName = post.author ? displayName(post.author) : "";
const personHref = post.author ? profilePath(post.author.username) : null;
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
  user ? isFollowing(supabase, user.id, "profile", post.author_id) : Promise.resolve(false),
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
      <div class="flex min-w-0 flex-1 basis-full items-center gap-3 sm:basis-0">
        {personHref && (
          <a href={personHref} class="shrink-0" aria-label={`Perfil de ${personName}`}>
            <Avatar name={personName} path={post.author?.avatar_path} size={48} />
          </a>
        )}
        <span class="min-w-0">
          <span class="flex flex-wrap items-center gap-x-2 font-semibold">
            <span class="inline-flex min-w-0 items-center gap-1">
              {personHref ? <a href={personHref} class="truncate hover:underline">{personName}</a> : <span class="truncate">{personName}</span>}
              {post.author?.verified_at && <VerifiedBadge />}
            </span>
            <SituationBadge situation={post.author?.situation} />
          </span>
          {post.business ? (
            <a href={businessPath(post.business.slug)} class="mt-0.5 flex w-fit max-w-full items-center gap-1.5 text-sm font-medium hover:underline">
              <Avatar name={post.business.name} path={post.business.logo_path} purpose="logo" shape="rounded" size={18} />
              <span class="truncate">{post.business.name}</span>
              {post.business.verification === "verified" && <span class="text-seek">✓</span>}
            </a>
          ) : (
            post.author?.headline && <span class="block truncate text-sm text-ink-muted">{post.author.headline}</span>
          )}
          <span class="block text-sm text-ink-muted">
            <time datetime={post.published_at} title={formatDate(post.published_at, { dateStyle: "long", timeStyle: "short" })}>{formatRelative(post.published_at)}</time>
            {post.city && ` · ${post.city.name}`}
          </span>
        </span>
      </div>
      <span class:list={["rounded-full px-3 py-1 text-sm font-semibold", type.class]}>{type.label}</span>
      {showFollow && (
        <FollowButton
          kind="profile"
          id={post.author_id}
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
        postHref={canonical}
        shareUrl={absoluteUrl}
        shareTitle={shareText}
        commentsHref="#comentarios"
        class="-mx-3 mt-6 border-b border-line"
      />
    )}

    <div class="mt-6 flex flex-wrap gap-2">
      {post.business ? (
        <Button href={`${businessPath(post.business.slug)}#contacto`} size="lg">Contactar a {post.business.name}</Button>
      ) : post.author ? (
        <Button href={profilePath(post.author.username)} size="lg">Ver perfil de {displayName(post.author)}</Button>
      ) : null}
      {post.author && !isOwner && isPublic && (
        <Button href={newMessagePath(post.author.username, post.id)} variant="secondary" size="lg">Enviar mensaje</Button>
      )}
      <Button href={whatsappShare} variant="secondary" size="lg" target="_blank" rel="noopener">Compartir por WhatsApp</Button>
      {isOwner && <Button href={`/panel/publicaciones/${post.id}`} variant="ghost" size="lg">Editar</Button>}
      {isOwner && (
        <form method="POST" action={`/panel/publicaciones${actions.posts.remove}`} data-delete-post data-redirect={post.author ? `/u/${post.author.username}` : "/"}>
          <input type="hidden" name="post_id" value={post.id} />
          <Button type="submit" variant="ghost" size="lg" class="text-danger">Eliminar</Button>
        </form>
      )}
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
      <section class="mx-auto max-w-2xl px-4 pb-16">
        <h2 class="mb-4 text-lg font-semibold">Más de {post.business.name}</h2>
        <div class="flex flex-col gap-4">
          {more.map((item) => <PostCard post={item} liked={reactions.liked.has(item.id)} saved={reactions.saved.has(item.id)} />)}
        </div>
      </section>
    )
  }
</BaseLayout>

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
        <div class="flex max-w-2xl flex-col gap-4">
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
 * Resumen del panel: perfil, páginas de emprendimiento y accesos.
 * (El feed está en el inicio "/".) Ruta protegida por el middleware.
 */
import PanelLayout from "../../layouts/PanelLayout.astro";
import Alert from "../../components/ui/Alert.astro";
import Button from "../../components/ui/Button.astro";
import Avatar from "../../components/ui/Avatar.astro";
import { hasRole } from "../../lib/auth/session";
import { displayName, getOwnProfile, profileCompleteness } from "../../services/profiles";
import { getMyBusinesses } from "../../services/businesses";
import { routes } from "../../config/site";
import { actions } from "astro:actions";

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
const logoutAction = `/salir${actions.auth.signOut}`;
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
      <div class="mt-auto flex flex-wrap gap-2 pt-4">
        {profile && <Button href={`/u/${profile.username}`} variant="secondary" size="sm">Ver mi perfil</Button>}
        <Button href="/panel/perfil" variant="ghost" size="sm">{completeness.percent < 100 ? "Completar perfil" : "Editar perfil"}</Button>
      </div>
    </section>

    <section class="flex flex-col rounded-wl-lg border border-line bg-surface p-5">
      <h2 class="font-semibold">Páginas de emprendimiento</h2>
      {
        businesses.length === 0 ? (
          <p class="mt-1 text-sm text-ink-muted">
            Como una página de Facebook: si tenés un negocio o emprendimiento, creale su página con logo, catálogo de
            productos y servicios, horarios y contacto. Podés publicar en nombre de la página y la gente la puede seguir.
            {isProvider ? "" : " Es opcional: también podés publicar solo desde tu perfil."}
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

  <ul class="mt-6 grid gap-3 sm:grid-cols-3">
    <li><a href="/" class="block rounded-wl-lg border border-line bg-surface p-4 text-sm hover:border-brand"><strong>Inicio</strong><span class="block text-ink-muted">Lo que publican las cuentas que seguís.</span></a></li>
    <li><a href="/panel/publicaciones/nueva" class="block rounded-wl-lg border border-line bg-surface p-4 text-sm hover:border-brand"><strong>Crear publicación</strong><span class="block text-ink-muted">Contá qué ofrecés o qué buscás.</span></a></li>
    <li><a href="/panel/guardados" class="block rounded-wl-lg border border-line bg-surface p-4 text-sm hover:border-brand"><strong>Guardados</strong><span class="block text-ink-muted">Publicaciones para ver después.</span></a></li>
  </ul>

  {isStaff && (
    <div class="mt-10">
      <Button href={routes.admin} variant="secondary">Ir al panel administrativo</Button>
    </div>
  )}

  <form method="POST" action={logoutAction} class="mt-10 border-t border-line pt-6">
    <Button type="submit" variant="ghost" size="sm">Cerrar sesión</Button>
  </form>
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
import { SITUATIONS } from "../../config/situations";

const { supabase, user } = Astro.locals;

const result = Astro.getActionResult(actions.profile.update);
if (result && !result.error) {
  return Astro.redirect(`/u/${result.data.username}?guardado=1`);
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
const situation = v("situation", profile.situation);
---

<PanelLayout title="Editar perfil" description="Así te ven las personas en WorkLink." back={{ href: `/u/${profile.username}`, label: "Volver a mi perfil" }}>
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
      <Field
        name="headline"
        label="Tu rubro o profesión (opcional)"
        maxlength={80}
        placeholder="Ej.: Electricista matriculado, Diseñadora gráfica, Estudiante de enfermería"
        value={v("headline", profile.headline)}
        hint="Aparece debajo de tu nombre en tu perfil y en tus publicaciones."
        error={err("headline")}
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

    <section id="situacion" class="flex scroll-mt-24 flex-col gap-3">
      <div>
        <h2 class="text-lg font-semibold">Tu situación</h2>
        <p class="text-sm text-ink-muted">Se muestra como etiqueta en tu perfil y en tus publicaciones, para que te encuentren quienes te necesitan.</p>
      </div>
      <fieldset class="grid gap-2 sm:grid-cols-2">
        <legend class="sr-only">Situación</legend>
        {SITUATIONS.map((option) => (
          <label class="flex cursor-pointer gap-3 rounded-wl border border-line bg-surface p-3 has-[:checked]:border-brand has-[:checked]:bg-brand/5">
            <input type="radio" name="situation" value={option.value} checked={situation === option.value} class="mt-1 accent-[var(--wl-brand)]" />
            <span>
              <span class="block font-semibold">{option.label}</span>
              <span class="block text-sm text-ink-muted">{option.hint}</span>
            </span>
          </label>
        ))}
        <label class="flex cursor-pointer items-center gap-3 rounded-wl border border-line bg-surface p-3 has-[:checked]:border-brand has-[:checked]:bg-brand/5 sm:col-span-2">
          <input type="radio" name="situation" value="" checked={!situation} class="accent-[var(--wl-brand)]" />
          <span class="text-sm">Prefiero no mostrarlo</span>
        </label>
      </fieldset>
      {err("situation") && <p class="text-sm text-danger" role="alert">{err("situation")}</p>}
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
import { displayName, getOwnProfile } from "../../../services/profiles";
import { getSubmittedForm } from "../../../utils/form";
import { mediaItemsFromSubmitted } from "../../../lib/post-media";

const { supabase, user } = Astro.locals;

const result = Astro.getActionResult(actions.posts.create);
if (result && !result.error) return Astro.redirect("/?publicada=1");

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
const defaultType = Astro.url.searchParams.get("tipo");
// Por defecto se publica como persona: se usa la ciudad del perfil.
const personalCity = defaultBusinessId ? null : (profile?.city ?? null);
---

<PanelLayout title="Crear publicación" back={{ href: "/", label: "Inicio" }}>
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
      defaultType={defaultType}
      personName={profile ? displayName(profile) : "Yo"}
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
  <section class="mx-auto max-w-2xl px-4 py-8">
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
        <div class="mt-6 flex flex-col gap-4" data-feed>
          <FeedPage posts={posts} reactions={reactions} nextHref={nextHref} nextFragmentHref={nextFragmentHref} priorityCount={cursor ? 0 : 2} />
        </div>
      )
    }
  </section>
</BaseLayout>

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
  return Astro.redirect(routes.home);
}

const result = Astro.getActionResult(actions.auth.signUp);

// Sin confirmación de email (desarrollo): la sesión ya existe.
if (result && !result.error && !result.data.needsConfirmation) {
  return Astro.redirect(routes.home);
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

escribir 'src/pages/robots.txt.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { APIRoute } from "astro";

/** robots.txt: deja indexar lo público y apunta al sitemap. */
export const GET: APIRoute = ({ site, url }) => {
  const origin = (site ?? new URL(url.origin)).toString().replace(/\/$/, "");
  const body = [
    "User-agent: *",
    "Allow: /",
    "Disallow: /panel",
    "Disallow: /cuenta",
    "Disallow: /admin",
    "Disallow: /api/",
    "Disallow: /buscar",
    "Disallow: /inicio/",
    "Disallow: /salir",
    "Disallow: /*?desde=",
    "",
    `Sitemap: ${origin}/sitemap.xml`,
    "",
  ].join("\n");
  return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=3600, s-maxage=86400" } });
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/rubros/[categoria]/[provincia]/[ciudad].astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Landing rubro + ciudad: /rubros/fotografia/cordoba/villa-maria
 * "Fotógrafos en Villa María": emprendimientos del rubro en la ciudad,
 * publicaciones recientes y enlaces a ciudades y rubros cercanos.
 * Se indexa solo si tiene contenido suficiente (umbrales seo.* en settings).
 */
import BaseLayout from "../../../../layouts/BaseLayout.astro";
import BusinessResultCard from "../../../../components/directory/BusinessResultCard.astro";
import PostCard from "../../../../components/posts/PostCard.astro";
import {
  categoryNoun,
  countBusinesses,
  countRecentPosts,
  directoryPath,
  getCategoryBySlug,
  getCategoryCities,
  getCityBySlugs,
  getCityCategories,
  getSeoThresholds,
  isIndexableLanding,
} from "../../../../services/directory";
import { searchBusinesses, searchPosts } from "../../../../services/search";
import { getViewerReactions } from "../../../../services/social";
import { breadcrumbJsonLd, jsonLdScript } from "../../../../lib/seo/business";

const { supabase, user } = Astro.locals;
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const { categoria = "", provincia = "", ciudad = "" } = Astro.params;
if (![categoria, provincia, ciudad].every((s) => SLUG.test(s))) return Astro.rewrite("/404");

const [category, city] = await Promise.all([getCategoryBySlug(supabase, categoria), getCityBySlugs(supabase, provincia, ciudad)]);
if (!category || !city) return Astro.rewrite("/404");

const page = Math.max(1, Math.min(50, Number.parseInt(Astro.url.searchParams.get("pagina") ?? "1", 10) || 1));
const PER_PAGE = 20;

const [total, recentPosts, thresholds, businesses, posts, otherCities, allCategories] = await Promise.all([
  countBusinesses(supabase, category.id, city.id),
  countRecentPosts(supabase, category.id, city.id),
  getSeoThresholds(supabase),
  searchBusinesses(supabase, { q: "", categoryId: category.id, cityId: city.id }, PER_PAGE, (page - 1) * PER_PAGE),
  page === 1
    ? searchPosts(supabase, { q: "", categoryId: category.id, cityId: city.id, situation: null, type: null }, 6)
    : Promise.resolve({ items: [], hasMore: false }),
  getCategoryCities(supabase, category.id, 13),
  getCityCategories(supabase, city.id),
]);
const reactions = await getViewerReactions(supabase, user?.id, posts.items.map((p) => p.id));

const noun = categoryNoun(category);
const title = `${noun} en ${city.name}`;
const base = directoryPath.landing(category.slug, city.province.slug, city.slug);
const indexable = page === 1 && isIndexableLanding(thresholds, total, recentPosts);
const site = Astro.site ?? new URL(Astro.url.origin);
const description = total
  ? `${total} ${total === 1 ? "emprendimiento" : "emprendimientos"} de ${category.name.toLowerCase()} en ${city.name}, ${city.province.name}. Mirá sus trabajos, precios y contactalos por WhatsApp en WorkLink.`
  : `${noun} en ${city.name}, ${city.province.name}: encontrá emprendedores y profesionales cerca tuyo en WorkLink.`;
const nearby = otherCities.filter((c) => c.city_id !== city.id).slice(0, 12);
const otherCategories = allCategories.filter((c) => c.id !== category.id);

const jsonLd = [
  breadcrumbJsonLd([
    { name: "Inicio", url: new URL("/", site).toString() },
    { name: "Rubros", url: new URL(directoryPath.index, site).toString() },
    { name: category.name, url: new URL(directoryPath.category(category.slug), site).toString() },
    { name: title, url: new URL(base, site).toString() },
  ]),
  ...(businesses.items.length
    ? [
        {
          "@context": "https://schema.org",
          "@type": "ItemList",
          name: title,
          itemListElement: businesses.items.map((b, index) => ({
            "@type": "ListItem",
            position: (page - 1) * PER_PAGE + index + 1,
            url: new URL(`/e/${b.slug}`, site).toString(),
            name: b.name,
          })),
        },
      ]
    : []),
];
const pageLink = (n: number) => (n > 1 ? `${base}?pagina=${n}` : base);
---

<BaseLayout title={page > 1 ? `${title} (página ${page})` : title} description={description} canonicalPath={page > 1 ? `${base}?pagina=${page}` : base} noindex={!indexable}>
  <script slot="head" type="application/ld+json" set:html={jsonLdScript(jsonLd)} />
  <section class="mx-auto max-w-5xl px-4 py-8">
    <nav aria-label="Ubicación" class="flex flex-wrap gap-x-1.5 text-sm text-ink-muted">
      <a href={directoryPath.index} class="hover:text-ink hover:underline">Rubros</a> <span aria-hidden="true">/</span>
      <a href={directoryPath.category(category.slug)} class="hover:text-ink hover:underline">{category.name}</a> <span aria-hidden="true">/</span>
      <span>{city.name}</span>
    </nav>
    <h1 class="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{title}</h1>
    <p class="mt-2 max-w-2xl text-ink-muted">
      {total > 0
        ? `${total} ${total === 1 ? "emprendimiento" : "emprendimientos"} de ${category.name.toLowerCase()} en ${city.name}, ${city.province.name}.`
        : `Todavía no hay emprendimientos de ${category.name.toLowerCase()} en ${city.name}.`}
    </p>

    <div class="mt-8 grid gap-10 lg:grid-cols-[minmax(0,1fr)_280px]">
      <div class="flex min-w-0 flex-col gap-10">
        {
          businesses.items.length > 0 ? (
            <section aria-label="Emprendimientos">
              <ul class="divide-y divide-line overflow-hidden rounded-wl-lg border border-line bg-surface">
                {businesses.items.map((b) => (
                  <li><BusinessResultCard business={b} hideCategory /></li>
                ))}
              </ul>
              {(page > 1 || businesses.hasMore) && (
                <nav class="mt-6 flex justify-between gap-4" aria-label="Páginas">
                  {page > 1 ? <a href={pageLink(page - 1)} class="font-semibold text-brand hover:underline">← Anteriores</a> : <span />}
                  {businesses.hasMore && <a href={pageLink(page + 1)} class="font-semibold text-brand hover:underline">Más emprendimientos →</a>}
                </nav>
              )}
            </section>
          ) : (
            <div class="rounded-wl-lg border border-dashed border-line bg-surface p-8 text-center">
              <p class="font-semibold">¿Tenés un emprendimiento de {category.name.toLowerCase()} en {city.name}?</p>
              <p class="mt-1 text-sm text-ink-muted">Creá su página gratis y sé el primero en aparecer acá.</p>
              <a href="/panel/emprendimientos/nuevo" class="mt-4 inline-block font-semibold text-brand hover:underline">Crear la página de mi emprendimiento</a>
            </div>
          )
        }

        {
          posts.items.length > 0 && (
            <section aria-labelledby="publicaciones-recientes">
              <h2 id="publicaciones-recientes" class="mb-4 text-xl font-semibold">Publicaciones recientes</h2>
              <div class="flex flex-col gap-4">
                {posts.items.map((post) => (
                  <PostCard post={post} liked={reactions.liked.has(post.id)} saved={reactions.saved.has(post.id)} />
                ))}
              </div>
            </section>
          )
        }
      </div>

      <aside class="flex flex-col gap-8">
        {
          nearby.length > 0 && (
            <section aria-labelledby="otras-ciudades">
              <h2 id="otras-ciudades" class="font-semibold">{category.name} en otras ciudades</h2>
              <ul class="mt-3 flex flex-col">
                {nearby.map((c) => (
                  <li>
                    <a href={directoryPath.landing(category.slug, c.province_slug, c.city_slug)} class="flex justify-between gap-3 border-b border-line py-2 text-sm hover:text-brand">
                      <span>{c.city_name}</span>
                      <span class="text-ink-muted">{c.businesses}</span>
                    </a>
                  </li>
                ))}
              </ul>
            </section>
          )
        }
        {otherCategories.length > 0 && (
        <section aria-labelledby="otros-rubros">
          <h2 id="otros-rubros" class="font-semibold">Otros rubros en {city.name}</h2>
          <ul class="mt-3 flex flex-wrap gap-2">
            {otherCategories.map((c) => (
              <li>
                <a href={directoryPath.landing(c.slug, city.province.slug, city.slug)} class="inline-block rounded-full border border-line bg-surface px-3 py-1 text-sm hover:border-brand">
                  {c.name}
                </a>
              </li>
            ))}
          </ul>
        </section>
        )}
      </aside>
    </div>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/rubros/[categoria]/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Un rubro en todo el país: emprendimientos (paginados), ciudades donde hay y
 * especialidades. Se indexa si tiene suficientes emprendimientos.
 */
import BaseLayout from "../../../layouts/BaseLayout.astro";
import BusinessResultCard from "../../../components/directory/BusinessResultCard.astro";
import { categoryNoun, countBusinesses, directoryPath, getCategoryBySlug, getCategoryCities, getSeoThresholds } from "../../../services/directory";
import { searchBusinesses } from "../../../services/search";
import { breadcrumbJsonLd, jsonLdScript } from "../../../lib/seo/business";

const { supabase } = Astro.locals;
const slug = (Astro.params.categoria ?? "").toLowerCase();
const category = /^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug) ? await getCategoryBySlug(supabase, slug) : null;
if (!category) return Astro.rewrite("/404");

const page = Math.max(1, Math.min(50, Number.parseInt(Astro.url.searchParams.get("pagina") ?? "1", 10) || 1));
const subcategory = category.subcategories.find((s) => s.slug === Astro.url.searchParams.get("especialidad")) ?? null;
const PER_PAGE = 20;

const [total, cities, thresholds, businesses] = await Promise.all([
  countBusinesses(supabase, category.id),
  getCategoryCities(supabase, category.id, 60),
  getSeoThresholds(supabase),
  searchBusinesses(supabase, { q: "", categoryId: category.id, cityId: null, subcategoryId: subcategory?.id ?? null }, PER_PAGE, (page - 1) * PER_PAGE),
]);

const noun = categoryNoun(category);
const base = directoryPath.category(category.slug);
const indexable = total >= thresholds.minBusinessesAlt && page === 1 && !subcategory;
const site = Astro.site ?? new URL(Astro.url.origin);
const link = (changes: Record<string, string | null>) => {
  const params = new URLSearchParams();
  const all = { especialidad: subcategory?.slug ?? null, pagina: null, ...changes };
  for (const [k, v] of Object.entries(all)) if (v) params.set(k, v);
  const s = params.toString();
  return `${base}${s ? `?${s}` : ""}`;
};
const jsonLd = [
  breadcrumbJsonLd([
    { name: "Inicio", url: new URL("/", site).toString() },
    { name: "Rubros", url: new URL(directoryPath.index, site).toString() },
    { name: category.name, url: new URL(base, site).toString() },
  ]),
];
---

<BaseLayout
  title={`${noun} en Argentina`}
  description={category.description ?? `${noun}: emprendedores y profesionales de ${category.name.toLowerCase()} en tu ciudad. Mirá sus trabajos y contactalos en WorkLink.`}
  canonicalPath={base}
  noindex={!indexable}
>
  <script slot="head" type="application/ld+json" set:html={jsonLdScript(jsonLd)} />
  <section class="mx-auto max-w-5xl px-4 py-8">
    <nav aria-label="Ubicación" class="flex flex-wrap gap-x-1.5 text-sm text-ink-muted">
      <a href={directoryPath.index} class="hover:text-ink hover:underline">Rubros</a> <span aria-hidden="true">/</span> <span>{category.name}</span>
    </nav>
    <h1 class="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{noun} en Argentina</h1>
    <p class="mt-2 text-ink-muted">
      {total > 0 ? `${total} ${total === 1 ? "emprendimiento" : "emprendimientos"} en WorkLink.` : "Todavía no hay emprendimientos en este rubro."}
      {category.description && ` ${category.description}`}
    </p>

    {
      category.subcategories.length > 0 && (
        <ul class="mt-5 flex flex-wrap gap-2" aria-label="Especialidades">
          <li>
            <a href={link({ especialidad: null })} aria-current={!subcategory ? "page" : undefined} class:list={["inline-block rounded-full border px-3 py-1.5 text-sm", !subcategory ? "border-brand bg-brand text-brand-contrast" : "border-line bg-surface hover:border-brand"]}>
              Todas
            </a>
          </li>
          {category.subcategories.map((s) => (
            <li>
              <a href={link({ especialidad: s.slug })} aria-current={subcategory?.id === s.id ? "page" : undefined} class:list={["inline-block rounded-full border px-3 py-1.5 text-sm", subcategory?.id === s.id ? "border-brand bg-brand text-brand-contrast" : "border-line bg-surface hover:border-brand"]}>
                {s.name}
              </a>
            </li>
          ))}
        </ul>
      )
    }

    <div class="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1fr)_280px]">
      <div>
        {
          businesses.items.length > 0 ? (
            <ul class="divide-y divide-line overflow-hidden rounded-wl-lg border border-line bg-surface">
              {businesses.items.map((b) => (
                <li><BusinessResultCard business={b} hideCategory /></li>
              ))}
            </ul>
          ) : (
            <div class="rounded-wl-lg border border-dashed border-line bg-surface p-8 text-center">
              <p class="font-semibold">{subcategory ? `Todavía no hay emprendimientos de ${subcategory.name.toLowerCase()}.` : "Todavía no hay emprendimientos en este rubro."}</p>
              <p class="mt-1 text-sm text-ink-muted">¿Tenés uno? <a href="/panel/emprendimientos/nuevo" class="font-semibold text-brand hover:underline">Creá su página gratis</a>.</p>
            </div>
          )
        }
        {
          (page > 1 || businesses.hasMore) && (
            <nav class="mt-6 flex justify-between gap-4" aria-label="Páginas">
              {page > 1 ? <a href={link({ pagina: page > 2 ? String(page - 1) : null })} class="font-semibold text-brand hover:underline">← Anteriores</a> : <span />}
              {businesses.hasMore && <a href={link({ pagina: String(page + 1) })} class="font-semibold text-brand hover:underline">Más emprendimientos →</a>}
            </nav>
          )
        }
      </div>

      {
        cities.length > 0 && (
          <aside aria-labelledby="ciudades">
            <h2 id="ciudades" class="font-semibold">{category.name} por ciudad</h2>
            <ul class="mt-3 flex flex-col">
              {cities.map((c) => (
                <li>
                  <a href={directoryPath.landing(category.slug, c.province_slug, c.city_slug)} class="flex justify-between gap-3 border-b border-line py-2 text-sm hover:text-brand">
                    <span>{c.city_name}, {c.province_name}</span>
                    <span class="text-ink-muted">{c.businesses}</span>
                  </a>
                </li>
              ))}
            </ul>
          </aside>
        )
      }
    </div>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/rubros/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Directorio: todos los rubros, con cuántos emprendimientos tiene cada uno. */
import BaseLayout from "../../layouts/BaseLayout.astro";
import { directoryPath, getDirectoryCategories } from "../../services/directory";
import { breadcrumbJsonLd, jsonLdScript } from "../../lib/seo/business";

const categories = await getDirectoryCategories(Astro.locals.supabase);
const site = Astro.site ?? new URL(Astro.url.origin);
const crumbs = breadcrumbJsonLd([
  { name: "Inicio", url: new URL("/", site).toString() },
  { name: "Rubros", url: new URL(directoryPath.index, site).toString() },
]);
---

<BaseLayout
  title="Rubros: emprendedores y servicios por categoría"
  description="Encontrá emprendedores, profesionales y servicios de tu ciudad por rubro: gastronomía, belleza, tecnología, oficios y más."
  canonicalPath={directoryPath.index}
>
  <script slot="head" type="application/ld+json" set:html={jsonLdScript(crumbs)} />
  <section class="mx-auto max-w-5xl px-4 py-10">
    <h1 class="text-3xl font-bold tracking-tight sm:text-4xl">Rubros</h1>
    <p class="mt-2 max-w-2xl text-ink-muted">Elegí un rubro para ver los emprendimientos que lo ofrecen y en qué ciudades están.</p>

    <ul class="mt-8 grid gap-x-8 gap-y-1 sm:grid-cols-2 lg:grid-cols-3">
      {
        categories.map((c) => (
          <li>
            <a href={directoryPath.category(c.slug)} class="flex items-baseline justify-between gap-3 border-b border-line py-3 hover:text-brand">
              <span class="font-semibold">{c.name}</span>
              <span class="text-sm text-ink-muted">{c.businesses > 0 ? `${c.businesses} ${c.businesses === 1 ? "emprendimiento" : "emprendimientos"}` : "Sin emprendimientos aún"}</span>
            </a>
          </li>
        ))
      }
    </ul>

    <p class="mt-10 text-sm text-ink-muted">
      ¿Tenés un emprendimiento? <a href="/panel/emprendimientos/nuevo" class="font-semibold text-brand hover:underline">Creá su página gratis</a> y aparecé en tu rubro.
    </p>
  </section>
</BaseLayout>
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

escribir 'src/pages/sitemap.xml.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { APIRoute } from "astro";
import { directoryPath, getDirectoryCategories, getSeoThresholds } from "../services/directory";
import { postPath } from "../lib/urls";

/**
 * Mapa del sitio para buscadores: páginas públicas indexables.
 *  - inicio, publicaciones y directorio de rubros
 *  - rubros con suficientes emprendimientos y pares rubro + ciudad
 *  - emprendimientos activos y publicaciones públicas recientes
 * Se genera en cada pedido y la CDN lo guarda una hora. Máximo 50.000 URLs
 * (límite del protocolo); cuando se acerque, se divide en un índice.
 */
const MAX_POSTS = 10000;
const MAX_BUSINESSES = 30000;

const escape = (value: string) => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export const GET: APIRoute = async ({ locals, site, url }) => {
  const { supabase } = locals;
  const origin = site ?? new URL(url.origin);
  const abs = (path: string) => new URL(path, origin).toString();

  const thresholds = await getSeoThresholds(supabase);
  const [categories, pairs, businesses, posts] = await Promise.all([
    getDirectoryCategories(supabase),
    supabase.rpc("directory_landing_pairs", { p_min: thresholds.minBusinesses }),
    supabase
      .from("businesses")
      .select("slug, updated_at")
      .eq("status", "active")
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(MAX_BUSINESSES),
    supabase
      .from("posts")
      .select("id, title, body, updated_at")
      .eq("status", "published")
      .is("deleted_at", null)
      .order("published_at", { ascending: false })
      .limit(MAX_POSTS),
  ]);

  const entries: { loc: string; lastmod?: string }[] = [
    { loc: abs("/") },
    { loc: abs("/publicaciones") },
    { loc: abs(directoryPath.index) },
    ...categories.filter((c) => c.businesses >= thresholds.minBusinessesAlt).map((c) => ({ loc: abs(directoryPath.category(c.slug)) })),
    ...((pairs.data ?? []) as { category_slug: string; province_slug: string; city_slug: string; last_updated: string }[]).map((p) => ({
      loc: abs(directoryPath.landing(p.category_slug, p.province_slug, p.city_slug)),
      lastmod: p.last_updated,
    })),
    ...((businesses.data ?? []) as { slug: string; updated_at: string }[]).map((b) => ({ loc: abs(`/e/${b.slug}`), lastmod: b.updated_at })),
    ...((posts.data ?? []) as { id: string; title: string | null; body: string; updated_at: string }[]).map((p) => ({
      loc: abs(postPath(p)),
      lastmod: p.updated_at,
    })),
  ];

  const xml = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...entries.map(
      (e) => `  <url><loc>${escape(e.loc)}</loc>${e.lastmod ? `<lastmod>${new Date(e.lastmod).toISOString()}</lastmod>` : ""}</url>`,
    ),
    "</urlset>",
    "",
  ].join("\n");

  return new Response(xml, {
    headers: {
      "Content-Type": "application/xml; charset=utf-8",
      "Cache-Control": "public, max-age=0, s-maxage=3600, stale-while-revalidate=86400",
    },
  });
};
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

escribir 'src/pages/u/[username]/index.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Perfil de una persona (estilo Facebook): foto, nombre, rubro y situación,
 * datos, emprendimientos y todo lo que publicó (con "Cargar más").
 * Si es el propio perfil: botones "Editar perfil" y caja para publicar.
 * No se indexa en buscadores (privacidad): lo indexable son los emprendimientos.
 */
import BaseLayout from "../../../layouts/BaseLayout.astro";
import Avatar from "../../../components/ui/Avatar.astro";
import Button from "../../../components/ui/Button.astro";
import FeedPage from "../../../components/posts/FeedPage.astro";
import Composer from "../../../components/home/Composer.astro";
import FollowButton from "../../../components/social/FollowButton.astro";
import SituationBadge from "../../../components/social/SituationBadge.astro";
import VerifiedBadge from "../../../components/ui/VerifiedBadge.astro";
import { decodeCursor, getFeed } from "../../../services/posts";
import { followersLabel, getViewerReactions, isFollowing } from "../../../services/social";
import { displayName, getPublicProfile } from "../../../services/profiles";
import { getPublicBusinessesByOwner } from "../../../services/businesses";
import { instagramUrl, tiktokUrl, whatsappUrl } from "../../../lib/contact";
import { formatLocation, formatMonthYear } from "../../../lib/format";
import { getViewerProfile } from "../../../lib/viewer";
import { routes } from "../../../config/site";
import { newMessagePath } from "../../../services/messages";
import Alert from "../../../components/ui/Alert.astro";

const { supabase, user } = Astro.locals;
const username = (Astro.params.username ?? "").toLowerCase();
if (!/^[a-z0-9_.]{3,30}$/.test(username)) return Astro.rewrite("/404");

const profile = await getPublicProfile(supabase, username, { withContact: Boolean(user) });
if (!profile) return Astro.rewrite("/404");

const isMe = user?.id === profile.id;
const cursor = decodeCursor(Astro.url.searchParams.get("desde"));
const [businesses, { posts, nextCursor }, following, viewer] = await Promise.all([
  getPublicBusinessesByOwner(supabase, profile.id),
  getFeed(supabase, { authorId: profile.id, cursor }),
  isMe ? Promise.resolve(false) : isFollowing(supabase, user?.id, "profile", profile.id),
  isMe ? getViewerProfile(Astro.locals) : Promise.resolve(null),
]);
const reactions = await getViewerReactions(supabase, user?.id, posts.map((p) => p.id));
const name = displayName(profile);
const base = `/u/${profile.username}`;
const location = formatLocation(profile.city);
const firstName = profile.first_name ?? name;
---

<BaseLayout title={name} description={profile.headline ?? profile.bio ?? `Perfil de ${name} en WorkLink.`} noindex>
  <div class="h-28 bg-gradient-to-r from-brand via-seek to-offer sm:h-40" aria-hidden="true"></div>

  <section class="mx-auto max-w-3xl px-4">
    <div class="-mt-14 flex flex-col gap-4 sm:-mt-16 sm:flex-row sm:items-end">
      <Avatar name={name} path={profile.avatar_path} size={128} priority class="border-4 border-bg" />
      <div class="min-w-0 flex-1 sm:pb-2">
        <h1 class="flex items-center gap-2 text-2xl font-bold sm:text-3xl">{name}{profile.verified_at && <VerifiedBadge size={24} />}</h1>
        {profile.headline && <p class="mt-0.5 text-lg text-ink">{profile.headline}</p>}
        <p class="mt-1 text-sm text-ink-muted">
          <span data-followers={profile.id}>{followersLabel(profile.followers_count)}</span>
          {" · "}{profile.following_count.toLocaleString("es-AR")} seguidos
        </p>
      </div>
      <div class="flex flex-wrap gap-2 sm:pb-2">
        {
          isMe ? (
            <>
              <Button href="/panel/perfil">Editar perfil</Button>
              <Button href="/panel/publicaciones/nueva" variant="secondary">Publicar</Button>
            </>
          ) : (
            <>
              <FollowButton kind="profile" id={profile.id} following={following} returnTo={base} />
              <Button href={newMessagePath(profile.username)} variant="secondary">Mensaje</Button>
              {profile.whatsapp && (
                <Button href={whatsappUrl(profile.whatsapp, `Hola ${firstName}, te encontré en WorkLink.`)} variant="secondary" target="_blank" rel="noopener">
                  WhatsApp
                </Button>
              )}
            </>
          )
        }
      </div>
    </div>

    {isMe && Astro.url.searchParams.get("guardado") === "1" && <Alert tone="success" class="mt-6">Guardamos los cambios de tu perfil.</Alert>}

    <div class="mt-6 grid gap-6 md:grid-cols-[260px_minmax(0,1fr)]">
      <aside class="flex flex-col gap-4">
        <section class="rounded-wl-lg border border-line bg-surface p-4">
          <h2 class="font-semibold">Información</h2>
          {profile.situation && <SituationBadge situation={profile.situation} size="md" class="mt-3" />}
          {profile.bio && <p class="mt-3 whitespace-pre-line text-sm">{profile.bio}</p>}
          <ul class="mt-3 flex flex-col gap-1.5 text-sm text-ink-muted">
            {location && <li>📍 {location}</li>}
            <li>📅 En WorkLink desde {formatMonthYear(profile.created_at)}</li>
            {profile.instagram && <li><a href={instagramUrl(profile.instagram)} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">Instagram @{profile.instagram}</a></li>}
            {profile.tiktok && <li><a href={tiktokUrl(profile.tiktok)} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">TikTok @{profile.tiktok}</a></li>}
            {profile.facebook && <li><a href={profile.facebook.startsWith("http") ? profile.facebook : `https://${profile.facebook}`} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">Facebook</a></li>}
            {profile.website && <li><a href={profile.website} target="_blank" rel="noopener nofollow" class="text-brand hover:underline">Sitio web</a></li>}
          </ul>
          {isMe && !profile.situation && (
            <a href="/panel/perfil#situacion" class="mt-3 block rounded-wl bg-surface-muted px-3 py-2 text-sm">
              <strong>Completá tu situación:</strong> ¿buscás empleo, tenés un emprendimiento u ofrecés servicios?
            </a>
          )}
        </section>

        {(businesses.length > 0 || isMe) && (
          <section class="rounded-wl-lg border border-line bg-surface p-4">
            <h2 class="font-semibold">Emprendimientos</h2>
            {businesses.length > 0 ? (
              <ul class="mt-3 flex flex-col gap-2">
                {businesses.map((b) => (
                  <li>
                    <a href={`/e/${b.slug}`} class="flex items-center gap-3 rounded-wl p-1 hover:bg-surface-muted">
                      <Avatar name={b.name} path={b.logo_path} purpose="logo" shape="rounded" size={40} />
                      <span class="min-w-0">
                        <span class="block truncate text-sm font-semibold">{b.name}{b.verification === "verified" && <span class="ml-1 text-seek">✓</span>}</span>
                        <span class="block truncate text-xs text-ink-muted">{[b.categories?.name, b.cities?.name].filter(Boolean).join(" · ")}</span>
                      </span>
                    </a>
                  </li>
                ))}
              </ul>
            ) : (
              <p class="mt-2 text-sm text-ink-muted">
                Si tenés un emprendimiento, creale su página con catálogo, horarios y contacto.
                <a href="/panel/emprendimientos/nuevo" class="font-semibold text-brand hover:underline">Crear página</a>
              </p>
            )}
          </section>
        )}
      </aside>

      <div class="flex min-w-0 flex-col gap-4 pb-16">
        {isMe && viewer && !cursor && <Composer viewer={viewer} />}
        <h2 class="text-lg font-semibold">Publicaciones</h2>
        {
          posts.length === 0 ? (
            <p class="rounded-wl-lg border border-dashed border-line bg-surface p-8 text-center text-ink-muted">
              {isMe ? "Todavía no publicaste nada. ¡Contá qué ofrecés o qué estás buscando!" : `${firstName} todavía no publicó nada.`}
            </p>
          ) : (
            <div class="flex flex-col gap-4" data-feed>
              <FeedPage
                posts={posts}
                reactions={reactions}
                nextHref={nextCursor ? `${base}?desde=${nextCursor}` : null}
                nextFragmentHref={nextCursor ? `${base}/mas?desde=${nextCursor}` : null}
              />
            </div>
          )
        }
      </div>
    </div>
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/pages/u/[username]/mas.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Fragmento con la página siguiente de publicaciones de un perfil ("Cargar más"). */
import FeedPage from "../../../components/posts/FeedPage.astro";
import { decodeCursor, getFeed } from "../../../services/posts";
import { getViewerReactions } from "../../../services/social";

export const partial = true;

const { supabase, user } = Astro.locals;
const username = (Astro.params.username ?? "").toLowerCase();
const cursor = decodeCursor(Astro.url.searchParams.get("desde"));
if (!/^[a-z0-9_.]{3,30}$/.test(username) || !cursor) return new Response(null, { status: 400 });

const { data: profile } = await supabase.from("profiles").select("id").eq("username", username).eq("status", "active").maybeSingle();
if (!profile) return new Response(null, { status: 404 });

const { posts, nextCursor } = await getFeed(supabase, { authorId: profile.id, cursor });
const reactions = await getViewerReactions(supabase, user?.id, posts.map((p) => p.id));
const base = `/u/${username}`;

Astro.response.headers.set("X-Robots-Tag", "noindex");
---

<FeedPage
  posts={posts}
  reactions={reactions}
  nextHref={nextCursor ? `${base}?desde=${nextCursor}` : null}
  nextFragmentHref={nextCursor ? `${base}/mas?desde=${nextCursor}` : null}
/>
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

escribir 'src/schemas/message.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import { z } from "astro/zod";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const emptyToUndefined = (value: unknown) => (value === "" || value === null ? undefined : value);

export const MESSAGE_MAX = 2000;

export const sendMessageSchema = z.object({
  conversation_id: z.string().regex(UUID),
  body: z
    .string({ error: "Escribí un mensaje" })
    .trim()
    .min(1, { error: "Escribí un mensaje" })
    .max(MESSAGE_MAX, { error: `El mensaje puede tener hasta ${MESSAGE_MAX} caracteres` }),
  post_id: z.preprocess(emptyToUndefined, z.string().regex(UUID).optional()),
});

export const conversationRefSchema = z.object({
  conversation_id: z.string().regex(UUID),
});
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
import { SITUATION_VALUES } from "../config/situations";

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
  situation: z.preprocess((value) => (value === "" || value === null ? undefined : value), z.enum(SITUATION_VALUES).optional()),
  headline: optionalText(80, "Tu rubro"),
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

escribir 'src/scripts/chat.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Pantalla de conversación:
 *  - envía sin recargar (y si algo falla, deja el texto para reintentar)
 *  - trae los mensajes nuevos cada 4 segundos mientras la pestaña está a la vista
 *  - muestra "Visto" cuando la otra persona leyó el último mensaje propio
 *  - Enter envía en computadora (Shift+Enter hace un salto de línea)
 * Los textos se insertan con textContent: nunca como HTML.
 */
import { actions } from "astro:actions";

interface ChatMessage {
  id: string;
  sender_id: string;
  body: string;
  created_at: string;
  post: { id: string; title: string | null; body: string } | null;
}

const TZ = "America/Argentina/Cordoba";
const POLL_MS = 4000;
const dayKey = (iso: string) =>
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(iso));
const timeLabel = (iso: string) => new Intl.DateTimeFormat("es-AR", { timeZone: TZ, hour: "2-digit", minute: "2-digit" }).format(new Date(iso));

function slug(text: string) {
  return text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60)
    .replace(/-+$/g, "");
}

const root = document.querySelector<HTMLElement>("[data-chat]");
if (root) {
  const conversationId = root.dataset.conversation!;
  const me = root.dataset.me!;
  const list = root.querySelector<HTMLOListElement>("[data-chat-list]")!;
  const scroller = root.querySelector<HTMLElement>("[data-chat-scroll]")!;
  const form = root.querySelector<HTMLFormElement>("[data-chat-form]")!;
  const textarea = form.querySelector<HTMLTextAreaElement>("textarea")!;
  const sendButton = form.querySelector<HTMLButtonElement>("button[type=submit]")!;
  const seen = root.querySelector<HTMLElement>("[data-chat-seen]")!;
  const errorBox = root.querySelector<HTMLElement>("[data-chat-error-js]")!;
  let last = root.dataset.last!;
  let otherRead = root.dataset.otherRead || "";
  let lastMineAt = [...list.querySelectorAll<HTMLElement>("li[data-message]")]
    .filter((li) => li.classList.contains("justify-end"))
    .map((li) => li.querySelector("time")?.getAttribute("datetime") ?? "")
    .pop() ?? "";

  const nearBottom = () => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 120;
  const toBottom = () => (scroller.scrollTop = scroller.scrollHeight);
  toBottom();

  const updateSeen = () => {
    seen.hidden = !(lastMineAt && otherRead && otherRead >= lastMineAt);
  };

  function render(message: ChatMessage) {
    if (list.querySelector(`[data-message="${message.id}"]`)) return;
    root!.querySelector("[data-chat-empty]")?.remove();

    const days = list.querySelectorAll<HTMLElement>("li[data-day]");
    const lastDay = days[days.length - 1]?.dataset.day;
    const key = dayKey(message.created_at);
    if (lastDay !== key) {
      const sep = document.createElement("li");
      sep.className = "my-3 text-center text-xs font-semibold text-ink-muted";
      sep.dataset.day = key;
      sep.textContent = "Hoy";
      list.append(sep);
    }

    const mine = message.sender_id === me;
    const li = document.createElement("li");
    li.className = `flex ${mine ? "justify-end" : "justify-start"}`;
    li.dataset.message = message.id;
    const bubble = document.createElement("div");
    bubble.className = `max-w-[78%] rounded-2xl px-3 py-1.5 ${mine ? "rounded-br-md bg-brand text-brand-contrast" : "rounded-bl-md bg-surface-muted text-ink"}`;
    if (message.post) {
      const link = document.createElement("a");
      const words = slug(message.post.title || message.post.body);
      link.href = `/p/${words ? `${words}-` : ""}${message.post.id}`;
      link.className = `mb-1.5 block rounded-wl border px-2.5 py-1.5 text-xs ${mine ? "border-white/30" : "border-line"}`;
      link.append("Consulta sobre: ");
      const strong = document.createElement("strong");
      strong.textContent = (message.post.title || message.post.body).slice(0, 60);
      link.append(strong);
      bubble.append(link);
    }
    const text = document.createElement("p");
    text.className = "whitespace-pre-line break-words";
    text.textContent = message.body;
    const time = document.createElement("time");
    time.dateTime = message.created_at;
    time.className = `mt-0.5 block text-right text-[11px] ${mine ? "opacity-75" : "text-ink-muted"}`;
    time.textContent = timeLabel(message.created_at);
    bubble.append(text, time);
    li.append(bubble);
    list.append(li);

    if (message.created_at > last) last = message.created_at;
    if (mine && message.created_at > lastMineAt) lastMineAt = message.created_at;
  }

  // Altura automática del cuadro de texto.
  const resize = () => {
    textarea.style.height = "auto";
    textarea.style.height = `${Math.min(textarea.scrollHeight, 128)}px`;
  };
  textarea.addEventListener("input", resize);
  textarea.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey && !matchMedia("(pointer: coarse)").matches) {
      event.preventDefault();
      form.requestSubmit();
    }
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const body = textarea.value.trim();
    if (!body || sendButton.disabled) return;
    sendButton.disabled = true;
    errorBox.classList.add("hidden");
    try {
      const { data, error } = await actions.messages.send(new FormData(form));
      if (error) {
        errorBox.textContent = error.message || "No pudimos enviar el mensaje.";
        errorBox.classList.remove("hidden");
        return;
      }
      render(data as ChatMessage);
      textarea.value = "";
      resize();
      // La publicación consultada se cita solo en el primer mensaje.
      form.querySelector("[data-chat-context]")?.remove();
      form.querySelector("[data-chat-error]")?.remove();
      updateSeen();
      toBottom();
    } catch {
      errorBox.textContent = "Sin conexión. Tu mensaje no se envió: probá de nuevo.";
      errorBox.classList.remove("hidden");
    } finally {
      sendButton.disabled = false;
      textarea.focus();
    }
  });

  let polling = false;
  async function poll() {
    if (polling || document.visibilityState !== "visible") return;
    polling = true;
    try {
      const res = await fetch(`/api/mensajes/${conversationId}?despues=${encodeURIComponent(last)}`, { headers: { Accept: "application/json" } });
      if (res.ok) {
        const json = (await res.json()) as { messages: ChatMessage[]; otherLastReadAt: string | null };
        const stick = nearBottom();
        for (const message of json.messages) render(message);
        otherRead = json.otherLastReadAt ?? otherRead;
        updateSeen();
        if (json.messages.length && stick) toBottom();
      }
    } catch {
      /* sin conexión: se reintenta */
    } finally {
      polling = false;
    }
  }
  setInterval(poll, POLL_MS);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") void poll();
  });

  // Cerrar (✕): volver a la página anterior si vino de WorkLink; si no, a la bandeja.
  root.querySelector<HTMLAnchorElement>("[data-chat-close]")?.addEventListener("click", (event) => {
    const cameFromSite = document.referrer.startsWith(location.origin) && !document.referrer.includes(`/mensajes/${conversationId}`);
    if (cameFromSite && history.length > 1) {
      event.preventDefault();
      history.back();
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !textarea.value.trim()) root.querySelector<HTMLAnchorElement>("[data-chat-close]")?.click();
  });

  // Confirmación para "Ocultar".
  for (const confirmForm of root.querySelectorAll<HTMLFormElement>("form[data-confirm]")) {
    confirmForm.addEventListener("submit", (event) => {
      if (!window.confirm(confirmForm.dataset.confirm ?? "¿Confirmás?")) event.preventDefault();
    });
  }
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/scripts/load-more.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * "Cargar más" sin recargar: pide el fragmento HTML de la página siguiente y
 * lo agrega a la lista. Si algo falla, sigue el enlace normal (funciona sin JS).
 */
document.addEventListener("click", async (event) => {
  const link = (event.target as HTMLElement).closest<HTMLAnchorElement>("a[data-load-more]");
  if (!link || event.metaKey || event.ctrlKey || event.shiftKey) return;
  event.preventDefault();
  if (link.getAttribute("aria-busy") === "true") return;
  const wrapper = link.closest("[data-load-more-wrapper]");
  link.textContent = "Cargando…";
  link.setAttribute("aria-busy", "true");
  try {
    const res = await fetch(link.dataset.loadMore!, { headers: { Accept: "text/html" } });
    if (!res.ok) throw new Error(String(res.status));
    const html = await res.text();
    wrapper?.insertAdjacentHTML("afterend", html);
    wrapper?.remove();
  } catch {
    window.location.href = link.href;
  }
});
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/scripts/notifications.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Íconos de mensajes y notificaciones del encabezado: consulta cada 10
 * segundos mientras la pestaña está a la vista (y al volver a ella) cuántos
 * hay sin leer. Si llega un mensaje nuevo y no estás en Mensajes, muestra un
 * aviso abajo con un enlace para leerlo.
 * Es una consulta liviana (solo dos números); sin conexión, no hace nada.
 */
const INTERVAL = 10_000;
let timer: number | undefined;
let lastMessages: number | null = null;

const enabled = () => Boolean(document.querySelector("[data-notifications-badge]"));

function setBadges(selector: string, count: number) {
  for (const badge of document.querySelectorAll<HTMLElement>(selector)) {
    badge.textContent = count > 99 ? "99+" : String(count);
    badge.hidden = count === 0;
  }
}

function initialMessages(): number {
  const badge = document.querySelector<HTMLElement>("[data-messages-badge]");
  return badge && !badge.hidden ? Number.parseInt(badge.textContent ?? "0", 10) || 0 : 0;
}

function announce(text: string, href: string) {
  let box = document.getElementById("wl-message-toast") as HTMLAnchorElement | null;
  if (!box) {
    box = document.createElement("a");
    box.id = "wl-message-toast";
    box.setAttribute("role", "status");
    box.className =
      "fixed bottom-4 right-4 z-50 flex max-w-xs items-center gap-3 rounded-wl-lg bg-ink px-4 py-3 text-sm font-semibold text-white shadow-xl";
    document.body.append(box);
  }
  box.href = href;
  box.textContent = text;
  box.hidden = false;
  window.setTimeout(() => box && (box.hidden = true), 6000);
}

async function refresh() {
  if (document.visibilityState !== "visible" || !enabled()) return;
  try {
    const res = await fetch("/api/notificaciones", { headers: { Accept: "application/json" } });
    if (!res.ok) return;
    const { unread, messages } = (await res.json()) as { unread: number; messages: number };
    setBadges("[data-notifications-badge]", unread);
    setBadges("[data-messages-badge]", messages);
    for (const link of document.querySelectorAll<HTMLElement>("[data-notifications-link]")) {
      link.setAttribute("aria-label", unread ? `Notificaciones (${unread} sin leer)` : "Notificaciones");
    }
    if (lastMessages !== null && messages > lastMessages && !location.pathname.startsWith("/mensajes")) {
      announce("💬 Tenés un mensaje nuevo. Tocá para leerlo.", "/mensajes");
    }
    lastMessages = messages;
  } catch {
    /* sin conexión: se reintenta en el próximo ciclo */
  }
}

function start() {
  window.clearInterval(timer);
  timer = window.setInterval(refresh, INTERVAL);
}

if (enabled()) {
  lastMessages = initialMessages();
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      void refresh();
      start();
    } else {
      window.clearInterval(timer);
    }
  });
  window.addEventListener("focus", () => void refresh());
  start();
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/scripts/social.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Botones de me gusta, guardar, seguir y compartir, y el "Ver más" de los
 * textos largos (un solo manejador para toda la página, así también funcionan
 * en las tarjetas que agrega "Cargar más").
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
  if (kind === "like" && count !== null) {
    for (const el of document.querySelectorAll<HTMLElement>(`[data-likes-for="${id}"]`)) el.textContent = numberFormat.format(count);
    for (const el of document.querySelectorAll<HTMLElement>(`[data-likes-wrap="${id}"]`)) el.hidden = count === 0;
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
  const counter =
    button.querySelector<HTMLElement>("[data-count]") ??
    (kind === "like" ? document.querySelector<HTMLElement>(`[data-likes-for="${button.dataset.id}"]`) : null);
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

// Compartir: menú nativo del celular si existe; si no, copia el enlace.
document.addEventListener("click", async (event) => {
  const button = (event.target as HTMLElement).closest<HTMLButtonElement>("button[data-share-url]");
  if (!button) return;
  const url = button.dataset.shareUrl!;
  const title = button.dataset.shareTitle ?? document.title;
  try {
    if (navigator.share && matchMedia("(pointer: coarse)").matches) {
      await navigator.share({ title, url });
      return;
    }
    await navigator.clipboard.writeText(url);
    toast("¡Enlace copiado! Ya lo podés pegar donde quieras.");
  } catch {
    /* el usuario canceló */
  }
});

// "Ver más": muestra el botón solo si el texto quedó cortado.
function checkClamps(root: ParentNode = document) {
  for (const text of root.querySelectorAll<HTMLElement>("[data-clamp]:not([data-clamp-checked])")) {
    text.dataset.clampChecked = "1";
    const more = text.parentElement?.querySelector<HTMLElement>("[data-expand]");
    if (more && text.scrollHeight > text.clientHeight + 2) more.hidden = false;
  }
}
checkClamps();
new MutationObserver(() => checkClamps()).observe(document.body, { childList: true, subtree: true });

document.addEventListener("click", (event) => {
  const more = (event.target as HTMLElement).closest<HTMLElement>("[data-expand]");
  if (!more) return;
  const text = more.parentElement?.querySelector<HTMLElement>("[data-clamp]");
  text?.classList.remove("line-clamp-5");
  more.hidden = true;
});

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

// Eliminar una publicación propia: confirma, la elimina y la saca de la página.
document.addEventListener("submit", async (event) => {
  const form = (event.target as HTMLElement).closest<HTMLFormElement>("form[data-delete-post]");
  if (!form) return;
  event.preventDefault();
  if (!window.confirm("¿Eliminar esta publicación? No se puede deshacer.")) return;
  const button = form.querySelector<HTMLButtonElement>("button[type=submit]");
  if (button) button.disabled = true;
  try {
    const { error } = await actions.posts.remove(new FormData(form));
    if (error) {
      toast(error.message || "No pudimos eliminar la publicación.");
      if (button) button.disabled = false;
      return;
    }
    if (form.dataset.redirect) {
      window.location.href = form.dataset.redirect;
      return;
    }
    const card = form.closest<HTMLElement>("[data-post-card]");
    card?.remove();
    toast("Eliminaste la publicación.");
  } catch {
    toast("Sin conexión. Probá de nuevo.");
    if (button) button.disabled = false;
  }
});

// Cerrar el menú "⋯" al tocar fuera de él.
document.addEventListener("click", (event) => {
  for (const menu of document.querySelectorAll<HTMLDetailsElement>("details[data-post-menu][open]")) {
    if (!menu.contains(event.target as Node)) menu.open = false;
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

escribir 'src/services/directory.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Directorio por rubro y ciudad (páginas /rubros/...). Decide también si una
 * página se indexa en buscadores: solo si tiene contenido suficiente, para no
 * llenar Google de páginas vacías (umbrales editables en settings, seo.*).
 */

export interface DirectoryCategory {
  id: number;
  name: string;
  slug: string;
  seo_noun: string | null;
  description: string | null;
  businesses: number;
}

export interface CategoryCity {
  city_id: number;
  city_name: string;
  city_slug: string;
  province_id: number;
  province_name: string;
  province_slug: string;
  businesses: number;
}

export interface SeoThresholds {
  minBusinesses: number;
  minBusinessesAlt: number;
  minRecentPosts: number;
}

const DEFAULT_THRESHOLDS: SeoThresholds = { minBusinesses: 5, minBusinessesAlt: 3, minRecentPosts: 10 };

export async function getSeoThresholds(supabase: SupabaseClient): Promise<SeoThresholds> {
  const { data } = await supabase.from("settings").select("key, value").like("key", "seo.%");
  const get = (key: string, fallback: number) => {
    const raw = data?.find((row) => row.key === key)?.value;
    const n = Number(raw);
    return Number.isFinite(n) && n > 0 ? n : fallback;
  };
  return {
    minBusinesses: get("seo.landing_min_businesses", DEFAULT_THRESHOLDS.minBusinesses),
    minBusinessesAlt: get("seo.landing_min_businesses_alt", DEFAULT_THRESHOLDS.minBusinessesAlt),
    minRecentPosts: get("seo.landing_min_recent_posts", DEFAULT_THRESHOLDS.minRecentPosts),
  };
}

/** ¿La página rubro + ciudad tiene contenido suficiente para indexarse? */
export function isIndexableLanding(t: SeoThresholds, businesses: number, recentPosts: number): boolean {
  return businesses >= t.minBusinesses || (businesses >= t.minBusinessesAlt && recentPosts >= t.minRecentPosts);
}

export async function getDirectoryCategories(supabase: SupabaseClient): Promise<DirectoryCategory[]> {
  const { data, error } = await supabase.rpc("directory_categories");
  if (error) throw error;
  return ((data ?? []) as DirectoryCategory[]).map((c) => ({ ...c, businesses: Number(c.businesses) }));
}

export async function getCategoryCities(supabase: SupabaseClient, categoryId: number, limit = 40): Promise<CategoryCity[]> {
  const { data, error } = await supabase.rpc("directory_category_cities", { p_category_id: categoryId, p_limit: limit });
  if (error) throw error;
  return ((data ?? []) as CategoryCity[]).map((c) => ({ ...c, businesses: Number(c.businesses) }));
}

export async function getCityCategories(supabase: SupabaseClient, cityId: number) {
  const { data, error } = await supabase.rpc("directory_city_categories", { p_city_id: cityId });
  if (error) throw error;
  return ((data ?? []) as { id: number; name: string; slug: string; businesses: number }[]).map((c) => ({ ...c, businesses: Number(c.businesses) }));
}

export interface CategoryDetail {
  id: number;
  name: string;
  slug: string;
  seo_noun: string | null;
  description: string | null;
  subcategories: { id: number; name: string; slug: string }[];
}

export async function getCategoryBySlug(supabase: SupabaseClient, slug: string): Promise<CategoryDetail | null> {
  const { data, error } = await supabase
    .from("categories")
    .select("id, name, slug, seo_noun, description, subcategories ( id, name, slug, sort_order, active )")
    .eq("slug", slug)
    .eq("active", true)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  type SubRow = { id: number; name: string; slug: string; sort_order: number; active: boolean };
  const row = data as unknown as Omit<CategoryDetail, "subcategories"> & { subcategories: SubRow[] };
  return {
    ...row,
    subcategories: (row.subcategories ?? [])
      .filter((s) => s.active)
      .sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "es"))
      .map(({ id, name, slug }) => ({ id, name, slug })),
  };
}

export interface CityDetail {
  id: number;
  name: string;
  slug: string;
  province: { id: number; name: string; slug: string };
}

export async function getCityBySlugs(supabase: SupabaseClient, provinceSlug: string, citySlug: string): Promise<CityDetail | null> {
  const { data, error } = await supabase
    .from("cities")
    .select("id, name, slug, province:provinces!inner ( id, name, slug )")
    .eq("slug", citySlug)
    .eq("province.slug", provinceSlug)
    .maybeSingle();
  if (error) throw error;
  return (data as unknown as CityDetail | null) ?? null;
}

/** Cantidad de emprendimientos activos de un rubro (y opcionalmente una ciudad). */
export async function countBusinesses(supabase: SupabaseClient, categoryId: number, cityId?: number | null): Promise<number> {
  let query = supabase
    .from("businesses")
    .select("id", { count: "exact", head: true })
    .eq("category_id", categoryId)
    .eq("status", "active")
    .is("deleted_at", null);
  if (cityId) query = query.eq("city_id", cityId);
  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

/** Publicaciones de los últimos 90 días de un rubro en una ciudad. */
export async function countRecentPosts(supabase: SupabaseClient, categoryId: number, cityId: number): Promise<number> {
  const since = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .from("posts")
    .select("id", { count: "exact", head: true })
    .eq("category_id", categoryId)
    .eq("city_id", cityId)
    .eq("status", "published")
    .is("deleted_at", null)
    .gte("published_at", since);
  if (error) throw error;
  return count ?? 0;
}

/** "Fotógrafos" a partir de seo_noun ("fotógrafos") o del nombre del rubro. */
export function categoryNoun(category: { name: string; seo_noun: string | null }): string {
  const noun = category.seo_noun?.trim() || category.name;
  return noun.charAt(0).toLocaleUpperCase("es-AR") + noun.slice(1);
}

export const directoryPath = {
  index: "/rubros",
  category: (slug: string) => `/rubros/${slug}`,
  landing: (categorySlug: string, provinceSlug: string, citySlug: string) => `/rubros/${categorySlug}/${provinceSlug}/${citySlug}`,
};
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/home.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import { getFeed, type Cursor, type PostView } from "./posts";

/**
 * Feed del inicio para usuarios logueados:
 *  - "following": publicaciones de quienes sigue + las propias.
 *  - "featured":  si todavía no sigue a nadie, las de cuentas con plan pago.
 *  - "latest":    si no hay destacadas (o lo que sigue no publicó nada), lo
 *                 último publicado en WorkLink.
 * El modo se decide en la primera página y viaja en el enlace "Cargar más".
 */
export type HomeMode = "following" | "featured" | "latest";

export const HOME_MODES: HomeMode[] = ["following", "featured", "latest"];

export async function getHomeFeed(
  supabase: SupabaseClient,
  { followingCount, mode, cursor }: { followingCount: number; mode?: HomeMode | null; cursor?: Cursor | null },
): Promise<{ mode: HomeMode; posts: PostView[]; nextCursor: string | null }> {
  if (mode) {
    const page = await getFeed(supabase, { following: mode === "following", featured: mode === "featured", cursor });
    return { mode, ...page };
  }

  if (followingCount > 0) {
    const page = await getFeed(supabase, { following: true });
    if (page.posts.length) return { mode: "following", ...page };
  } else {
    const page = await getFeed(supabase, { featured: true });
    if (page.posts.length) return { mode: "featured", ...page };
  }
  return { mode: "latest", ...(await getFeed(supabase, {})) };
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

escribir 'src/services/messages.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Mensajes privados. RLS garantiza que solo los dos participantes ven la
 * conversación; las altas pasan por funciones de la base (start_conversation)
 * y por insert en messages (con bloqueos y límites controlados por la base).
 */

export interface ChatPerson {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  verified_at: string | null;
  situation: "job_seeking" | "entrepreneur" | "freelancer" | "hiring" | null;
  headline: string | null;
}

export interface ConversationView {
  id: string;
  other: ChatPerson | null;
  last_message_at: string | null;
  last_message_preview: string | null;
  last_sender_id: string | null;
  myLastReadAt: string;
  otherLastReadAt: string | null;
  hidden: boolean;
  unread: boolean;
}

export interface MessageView {
  id: string;
  sender_id: string;
  body: string;
  created_at: string;
  post: { id: string; title: string | null; body: string } | null;
}

const PERSON = "id, username, first_name, last_name, avatar_path, verified_at, situation, headline";
const CONVERSATION_COLUMNS = `id, user_low, user_high, last_message_at, last_message_preview, last_sender_id,
  low:profiles!conversations_user_low_fkey ( ${PERSON} ),
  high:profiles!conversations_user_high_fkey ( ${PERSON} ),
  conversation_members ( user_id, last_read_at, hidden_at )`;

type ConversationRow = {
  id: string;
  user_low: string;
  user_high: string;
  last_message_at: string | null;
  last_message_preview: string | null;
  last_sender_id: string | null;
  low: ChatPerson | null;
  high: ChatPerson | null;
  conversation_members: { user_id: string; last_read_at: string; hidden_at: string | null }[];
};

function toConversation(row: ConversationRow, me: string): ConversationView {
  const mine = row.conversation_members.find((m) => m.user_id === me);
  const theirs = row.conversation_members.find((m) => m.user_id !== me);
  const myLastReadAt = mine?.last_read_at ?? new Date(0).toISOString();
  return {
    id: row.id,
    other: row.user_low === me ? row.high : row.low,
    last_message_at: row.last_message_at,
    last_message_preview: row.last_message_preview,
    last_sender_id: row.last_sender_id,
    myLastReadAt,
    otherLastReadAt: theirs?.last_read_at ?? null,
    hidden: Boolean(mine?.hidden_at),
    unread: Boolean(row.last_message_at && row.last_sender_id !== me && row.last_message_at > myLastReadAt),
  };
}

/** Bandeja: conversaciones con mensajes, de la más reciente a la más vieja. */
export async function getConversations(supabase: SupabaseClient, me: string, limit = 50): Promise<ConversationView[]> {
  const { data, error } = await supabase
    .from("conversations")
    .select(CONVERSATION_COLUMNS)
    .or(`user_low.eq.${me},user_high.eq.${me}`)
    .not("last_message_at", "is", null)
    .order("last_message_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return ((data ?? []) as unknown as ConversationRow[])
    .map((row) => toConversation(row, me))
    .filter((c) => !c.hidden && c.other);
}

export async function getConversation(supabase: SupabaseClient, id: string, me: string): Promise<ConversationView | null> {
  const { data, error } = await supabase.from("conversations").select(CONVERSATION_COLUMNS).eq("id", id).maybeSingle();
  if (error) throw error;
  return data ? toConversation(data as unknown as ConversationRow, me) : null;
}

export const MESSAGES_PAGE = 50;

const MESSAGE_COLUMNS = "id, sender_id, body, created_at, post:posts ( id, title, body )";

/** Últimos mensajes (o los anteriores a `before`), en orden cronológico. */
export async function getMessages(
  supabase: SupabaseClient,
  conversationId: string,
  { before }: { before?: string | null } = {},
): Promise<{ messages: MessageView[]; hasOlder: boolean }> {
  let query = supabase
    .from("messages")
    .select(MESSAGE_COLUMNS)
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(MESSAGES_PAGE + 1);
  if (before && !Number.isNaN(Date.parse(before))) query = query.lt("created_at", before);
  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as MessageView[];
  return { messages: rows.slice(0, MESSAGES_PAGE).reverse(), hasOlder: rows.length > MESSAGES_PAGE };
}

/** Mensajes nuevos después de una fecha (para la actualización periódica). */
export async function getMessagesAfter(supabase: SupabaseClient, conversationId: string, after: string): Promise<MessageView[]> {
  const { data, error } = await supabase
    .from("messages")
    .select(MESSAGE_COLUMNS)
    .eq("conversation_id", conversationId)
    .gt("created_at", after)
    .order("created_at", { ascending: true })
    .limit(100);
  if (error) throw error;
  return (data ?? []) as unknown as MessageView[];
}

export async function markConversationRead(supabase: SupabaseClient, conversationId: string): Promise<void> {
  const { error } = await supabase.rpc("mark_conversation_read", { p_conversation_id: conversationId });
  if (error) console.error("[mensajes]", error.message);
}

export async function countUnreadConversations(supabase: SupabaseClient): Promise<number> {
  const { data, error } = await supabase.rpc("unread_conversations_count");
  if (error) {
    console.error("[mensajes]", error.message);
    return 0;
  }
  return Number(data ?? 0);
}

/** Enlace para escribirle a alguien (opcionalmente citando una publicación). */
export function newMessagePath(username: string, postId?: string | null): string {
  const params = new URLSearchParams({ con: username });
  if (postId) params.set("publicacion", postId);
  return `/mensajes/nuevo?${params}`;
}
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'src/services/notifications.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import { decodeCursor, encodeCursor, type Cursor } from "./posts";

/**
 * Notificaciones del usuario actual (RLS: cada uno ve solo las suyas).
 * Las crea la base con triggers; acá solo se leen y se marcan como leídas.
 */

export type NotificationType = "post_like" | "post_comment" | "profile_follow" | "business_follow";

export interface NotificationView {
  id: string;
  type: NotificationType;
  created_at: string;
  read_at: string | null;
  actor: { username: string; first_name: string | null; last_name: string | null; avatar_path: string | null; verified_at: string | null } | null;
  post: { id: string; title: string | null; body: string } | null;
  comment: { id: string; body: string } | null;
  business: { slug: string; name: string } | null;
}

export const NOTIFICATIONS_PAGE = 30;

const COLUMNS = `id, type, created_at, read_at,
  actor:profiles!notifications_actor_id_fkey ( username, first_name, last_name, avatar_path, verified_at ),
  post:posts ( id, title, body ),
  comment:post_comments ( id, body ),
  business:businesses ( slug, name )`;

export async function getNotifications(
  supabase: SupabaseClient,
  userId: string,
  cursor?: Cursor | null,
): Promise<{ items: NotificationView[]; nextCursor: string | null }> {
  let query = supabase
    .from("notifications")
    .select(COLUMNS)
    .eq("recipient_id", userId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(NOTIFICATIONS_PAGE + 1);
  if (cursor) {
    query = query.or(`created_at.lt."${cursor.publishedAt}",and(created_at.eq."${cursor.publishedAt}",id.lt.${cursor.id})`);
  }
  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as NotificationView[];
  const page = rows.slice(0, NOTIFICATIONS_PAGE);
  const last = page[page.length - 1];
  return {
    // Si la cuenta de quien la generó fue suspendida, RLS devuelve actor null: se omite.
    items: page.filter((n) => n.actor),
    nextCursor: rows.length > NOTIFICATIONS_PAGE && last ? encodeCursor({ published_at: last.created_at, id: last.id }) : null,
  };
}

export { decodeCursor };

export async function countUnread(supabase: SupabaseClient, userId: string): Promise<number> {
  const { count, error } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("recipient_id", userId)
    .is("read_at", null);
  if (error) {
    console.error("[notificaciones]", error.message);
    return 0;
  }
  return count ?? 0;
}

export async function markAllRead(supabase: SupabaseClient): Promise<void> {
  const { error } = await supabase.rpc("mark_notifications_read");
  if (error) console.error("[notificaciones]", error.message);
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

export type ProfileSituation = "job_seeking" | "entrepreneur" | "freelancer" | "hiring";

export interface PostAuthor {
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  situation: ProfileSituation | null;
  headline: string | null;
  verified_at: string | null;
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
  author: PostAuthor | null;
  business: { slug: string; name: string; logo_path: string | null; verification: string } | null;
  city: { name: string; slug: string; provinces: { name: string } | null } | null;
  category: { name: string; slug: string } | null;
  subcategory: { name: string } | null;
  media: PostMediaView[];
}

const POST_COLUMNS = `id, type, title, body, price, currency, tags, status, published_at, author_id, business_id,
  category_id, subcategory_id, city_id, likes_count, comments_count, saves_count,
  author:profiles!posts_author_id_fkey ( username, first_name, last_name, avatar_path, situation, headline, verified_at ),
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
  /** Solo de personas y emprendimientos que sigue el usuario actual (y las propias). */
  following?: boolean;
  /** Solo de cuentas con plan pago (destacadas del inicio). */
  featured?: boolean;
  cursor?: Cursor | null;
  limit?: number;
}

export async function getFeed(
  supabase: SupabaseClient,
  { type, businessId, authorId, personalOnly, following, featured, cursor, limit = FEED_PAGE_SIZE }: FeedFilters = {},
): Promise<{ posts: PostView[]; nextCursor: string | null }> {
  // "Siguiendo" y "Destacadas": la base devuelve los ids de la página (ya
  // filtrados) y después se traen esas publicaciones con todos sus datos.
  let followingIds: string[] | null = null;
  if (following || featured) {
    const page = { p_before_at: cursor?.publishedAt ?? null, p_before_id: cursor?.id ?? null, p_limit: limit + 1 };
    const { data, error } = following
      ? await supabase.rpc("following_feed_ids", { p_type: type ?? null, ...page })
      : await supabase.rpc("featured_feed_ids", page);
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

const PUBLIC_COLUMNS = `id, username, first_name, last_name, bio, avatar_path, situation, headline, verified_at, intent,
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

escribir 'src/services/search.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
import type { SupabaseClient } from "@supabase/supabase-js";
import { getPostsByIds, type PostView, type ProfileSituation } from "./posts";
import type { PostType } from "../schemas/post";

/**
 * Buscador y directorio: personas, emprendimientos y publicaciones con
 * filtros opcionales (texto, rubro, ciudad, situación, tipo). Las funciones de
 * la base devuelven ids ya filtrados y ordenados; acá se traen sus datos.
 */

export const SEARCH_MIN = 2;
export const SEARCH_MAX = 100;
export const SEARCH_PAGE = 20;

export function normalizeQuery(raw: string | null | undefined): string {
  return (raw ?? "").replace(/\s+/g, " ").trim().slice(0, SEARCH_MAX);
}

export interface PersonResult {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  headline: string | null;
  situation: ProfileSituation | null;
  verified_at: string | null;
  followers_count: number;
  city: { name: string } | null;
}

export interface BusinessResult {
  id: string;
  slug: string;
  name: string;
  tagline: string | null;
  logo_path: string | null;
  cover_path: string | null;
  verification: string;
  followers_count: number;
  posts_count: number;
  category: { name: string; slug: string } | null;
  city: { name: string; slug: string; provinces: { name: string; slug: string } | null } | null;
}

export interface SearchFilters {
  q: string;
  categoryId: number | null;
  cityId: number | null;
  situation: ProfileSituation | null;
  type: PostType | null;
}

export interface Paged<T> {
  items: T[];
  hasMore: boolean;
}

const ids = (data: unknown) => ((data ?? []) as { id: string }[]).map((row) => row.id);

function ordered<T extends { id: string }>(order: string[], rows: T[]): T[] {
  const byId = new Map(rows.map((row) => [row.id, row]));
  return order.map((id) => byId.get(id)).filter((row): row is T => Boolean(row));
}

/** Hay algo para buscar: texto válido o algún filtro. */
export function hasCriteria(f: SearchFilters): boolean {
  return f.q.length >= SEARCH_MIN || Boolean(f.categoryId || f.cityId || f.situation || f.type);
}

export async function searchPeople(supabase: SupabaseClient, f: SearchFilters, limit = SEARCH_PAGE, offset = 0): Promise<Paged<PersonResult>> {
  // Las personas no tienen rubro: si se filtra por rubro, no se listan.
  if (f.categoryId) return { items: [], hasMore: false };
  const { data, error } = await supabase.rpc("search_profile_ids", {
    p_query: f.q || null,
    p_city_id: f.cityId,
    p_situation: f.situation,
    p_limit: limit + 1,
    p_offset: offset,
  });
  if (error) throw error;
  const list = ids(data);
  const page = list.slice(0, limit);
  if (!page.length) return { items: [], hasMore: false };
  const { data: rows, error: rowsError } = await supabase
    .from("profiles")
    .select("id, username, first_name, last_name, avatar_path, headline, situation, verified_at, followers_count, city:cities ( name )")
    .in("id", page);
  if (rowsError) throw rowsError;
  return { items: ordered(page, (rows ?? []) as unknown as PersonResult[]), hasMore: list.length > limit };
}

export const BUSINESS_RESULT_COLUMNS = `id, slug, name, tagline, logo_path, cover_path, verification, followers_count, posts_count,
  category:categories ( name, slug ), city:cities ( name, slug, provinces ( name, slug ) )`;

export async function searchBusinesses(
  supabase: SupabaseClient,
  f: Pick<SearchFilters, "q" | "categoryId" | "cityId"> & { subcategoryId?: number | null; provinceId?: number | null },
  limit = SEARCH_PAGE,
  offset = 0,
): Promise<Paged<BusinessResult>> {
  const { data, error } = await supabase.rpc("search_business_ids", {
    p_query: f.q || null,
    p_category_id: f.categoryId,
    p_subcategory_id: f.subcategoryId ?? null,
    p_city_id: f.cityId,
    p_province_id: f.provinceId ?? null,
    p_limit: limit + 1,
    p_offset: offset,
  });
  if (error) throw error;
  const list = ids(data);
  const page = list.slice(0, limit);
  if (!page.length) return { items: [], hasMore: false };
  const { data: rows, error: rowsError } = await supabase.from("businesses").select(BUSINESS_RESULT_COLUMNS).in("id", page);
  if (rowsError) throw rowsError;
  return { items: ordered(page, (rows ?? []) as unknown as BusinessResult[]), hasMore: list.length > limit };
}

export async function searchPosts(supabase: SupabaseClient, f: SearchFilters, limit = SEARCH_PAGE, offset = 0): Promise<Paged<PostView>> {
  // Las publicaciones no tienen "situación" propia: ese filtro es de personas.
  if (f.situation) return { items: [], hasMore: false };
  const { data, error } = await supabase.rpc("search_post_ids", {
    p_query: f.q || null,
    p_type: f.type,
    p_category_id: f.categoryId,
    p_city_id: f.cityId,
    p_limit: limit + 1,
    p_offset: offset,
  });
  if (error) throw error;
  const list = ids(data);
  return { items: await getPostsByIds(supabase, list.slice(0, limit)), hasMore: list.length > limit };
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
  author: { username: string; first_name: string | null; last_name: string | null; avatar_path: string | null; verified_at: string | null } | null;
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
    .select("id, post_id, author_id, body, created_at, author:profiles!post_comments_author_id_fkey ( username, first_name, last_name, avatar_path, verified_at )")
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
  situation: "job_seeking" | "entrepreneur" | "freelancer" | "hiring" | null;
  headline: string | null;
  verified_at: string | null;
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

escribir 'scripts/importar-localidades.mjs' << '__WORKLINK_FIN_DEL_ARCHIVO__'
#!/usr/bin/env node
/**
 * Importa todas las localidades de Argentina desde Georef (API oficial del
 * Estado: apis.datos.gob.ar/georef) a la tabla cities de Supabase.
 *
 * Uso (desde la carpeta del proyecto, con el .env completo):
 *     npm run db:localidades              -> importa
 *     npm run db:localidades -- --prueba  -> solo muestra qué haría, sin escribir
 *     npm run db:localidades -- --archivo localidades.json  -> usa un archivo descargado
 *
 * - Se puede correr más de una vez: actualiza las que ya existen (por su id
 *   de Georef) y agrega las nuevas. Nunca borra ciudades.
 * - Las ciudades que ya estaban cargadas (sin id de Georef) se vinculan por
 *   provincia + nombre, así no se duplican y los perfiles que las usan siguen igual.
 * - Si en una provincia hay dos localidades con el mismo nombre, la dirección
 *   (slug) de la segunda lleva el departamento: "san-jose-tulumba".
 * - Necesita SUPABASE_SERVICE_ROLE_KEY (la clave secreta) porque escribe en una
 *   tabla que solo administra el sistema. La clave se lee del .env y no sale
 *   de tu computadora.
 */
import { readFile } from "node:fs/promises";
import { createClient } from "@supabase/supabase-js";

const args = process.argv.slice(2);
const dryRun = args.includes("--prueba");
const fileArg = args.includes("--archivo") ? args[args.indexOf("--archivo") + 1] : null;

try {
  process.loadEnvFile(".env");
} catch {
  // Sin .env: se usan las variables de entorno del sistema.
}

const url = process.env.PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("Faltan PUBLIC_SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en el archivo .env");
  process.exit(1);
}

const GEOREF = process.env.GEOREF_URL ?? "https://apis.datos.gob.ar/georef/api/localidades";
const PAGE = 1000;

const supabase = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

/** Igual que src/utils/slug.ts y la función slugify() de la base. */
function slugify(input, maxLength = 80) {
  return input
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, maxLength)
    .replace(/-+$/g, "");
}

const normalize = (text) => slugify(text, 200);

async function fetchGeoref() {
  if (fileArg) {
    console.log(`Leyendo ${fileArg}…`);
    const json = JSON.parse(await readFile(fileArg, "utf8"));
    return json.localidades ?? json;
  }

  const all = [];
  let start = 0;
  let total = Infinity;
  while (start < total) {
    const params = new URLSearchParams({
      max: String(PAGE),
      inicio: String(start),
      campos: "id,nombre,provincia.id,departamento.nombre,centroide",
      orden: "id",
    });
    const res = await fetch(`${GEOREF}?${params}`);
    if (!res.ok) throw new Error(`Georef respondió ${res.status}. Probá de nuevo en unos minutos.`);
    const json = await res.json();
    total = json.total;
    all.push(...json.localidades);
    start += json.cantidad || PAGE;
    console.log(`  descargadas ${all.length} de ${total}`);
    if (!json.cantidad) break;
  }
  return all;
}

async function fetchExisting() {
  const rows = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await supabase
      .from("cities")
      .select("id, province_id, name, slug, georef_id, lat, lng, department")
      .range(from, from + 999);
    if (error) throw error;
    rows.push(...data);
    if (data.length < 1000) break;
  }
  return rows;
}

async function main() {
  console.log(dryRun ? "Modo prueba: no se va a escribir nada.\n" : "");
  console.log("Descargando localidades de Georef…");
  const source = (await fetchGeoref()).filter((l) => l?.id && l?.nombre && l?.provincia?.id);
  console.log(`Localidades recibidas: ${source.length}`);

  const { data: provinces, error: provError } = await supabase.from("provinces").select("id");
  if (provError) throw provError;
  const provinceIds = new Set(provinces.map((p) => p.id));

  const existing = await fetchExisting();
  const byGeoref = new Map(existing.filter((c) => c.georef_id).map((c) => [c.georef_id, c]));
  const unlinked = new Map(existing.filter((c) => !c.georef_id).map((c) => [`${c.province_id}|${normalize(c.name)}`, c]));
  const usedSlugs = new Set(existing.map((c) => `${c.province_id}|${c.slug}`));

  // Primero las cabeceras (localidad con el mismo nombre que su departamento):
  // si hay nombres repetidos, la más conocida se queda con la dirección corta.
  source.sort((a, b) => {
    const aHead = normalize(a.nombre) === normalize(a.departamento?.nombre ?? "") ? 0 : 1;
    const bHead = normalize(b.nombre) === normalize(b.departamento?.nombre ?? "") ? 0 : 1;
    return aHead - bHead || String(a.id).localeCompare(String(b.id));
  });

  const updates = [];
  const inserts = [];
  let skipped = 0;

  for (const loc of source) {
    const provinceId = Number(loc.provincia.id);
    if (!provinceIds.has(provinceId)) {
      skipped++;
      continue;
    }
    const georefId = String(loc.id);
    const name = loc.nombre.trim();
    const department = loc.departamento?.nombre?.trim() || null;
    const lat = typeof loc.centroide?.lat === "number" ? Number(loc.centroide.lat.toFixed(5)) : null;
    const lng = typeof loc.centroide?.lon === "number" ? Number(loc.centroide.lon.toFixed(5)) : null;

    const known = byGeoref.get(georefId);
    if (known) {
      // Solo se actualiza si cambió algo (así correrlo de nuevo es rápido).
      if (known.name !== name || known.department !== department || Number(known.lat) !== lat || Number(known.lng) !== lng) {
        updates.push({ id: known.id, name, department, lat, lng });
      }
      continue;
    }

    const seeded = unlinked.get(`${provinceId}|${normalize(name)}`);
    if (seeded) {
      unlinked.delete(`${provinceId}|${normalize(name)}`);
      updates.push({ id: seeded.id, georef_id: georefId, department, lat, lng });
      continue;
    }

    const base = slugify(name) || `localidad-${georefId}`;
    const candidates = [base, slugify(`${name} ${loc.departamento?.nombre ?? ""}`), `${base}-${georefId}`];
    const slug = candidates.find((s) => s && !usedSlugs.has(`${provinceId}|${s}`)) ?? `${base}-${georefId}`;
    usedSlugs.add(`${provinceId}|${slug}`);
    inserts.push({ province_id: provinceId, name, slug, department, lat, lng, georef_id: georefId });
  }

  console.log(`\nNuevas: ${inserts.length} · Para actualizar: ${updates.length} · Sin provincia válida: ${skipped}`);
  if (dryRun) {
    console.log("Ejemplos de nuevas:", inserts.slice(0, 5).map((c) => `${c.name} (${c.slug})`).join(", "));
    return;
  }

  for (let i = 0; i < inserts.length; i += 500) {
    const { error } = await supabase.from("cities").insert(inserts.slice(i, i + 500));
    if (error) throw error;
    console.log(`  agregadas ${Math.min(i + 500, inserts.length)} de ${inserts.length}`);
  }

  let done = 0;
  for (const { id, ...changes } of updates) {
    const { error } = await supabase.from("cities").update(changes).eq("id", id);
    if (error) throw error;
    done++;
    if (done % 500 === 0) console.log(`  actualizadas ${done} de ${updates.length}`);
  }

  const { count } = await supabase.from("cities").select("id", { count: "exact", head: true });
  console.log(`\nListo. Ciudades en WorkLink: ${count}.`);
}

main().catch((error) => {
  console.error("\nNo se pudo completar la importación:", error.message ?? error);
  process.exit(1);
});
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'supabase/migrations/20261008001400_directory_search.sql' << '__WORKLINK_FIN_DEL_ARCHIVO__'
-- =============================================================================
-- 0014 · Buscador con filtros y directorio por rubro y ciudad (Etapa 7)
-- =============================================================================
-- * Búsquedas con filtros opcionales (texto, rubro, especialidad, ciudad,
--   provincia, tipo, situación). Sin texto, funcionan como directorio.
--   Devuelven solo ids; la app trae después las columnas públicas.
-- * Conteos por rubro y ciudad para las páginas del directorio y el sitemap.
-- * Los umbrales SEO pasan a ser públicos (la app decide si una página de
--   directorio se indexa según cuántos emprendimientos tiene).
-- Todas las funciones son SECURITY INVOKER: respetan RLS como cualquier consulta.
-- =============================================================================

-- "%texto%" con los comodines de LIKE escapados (busca el texto tal cual).
create or replace function public.like_contains(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '%' || replace(replace(replace(btrim(p_text), '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

-- Texto de búsqueda válido (2+ caracteres) o null.
create or replace function public.search_text(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when char_length(btrim(coalesce(p_text, ''))) >= 2 then btrim(p_text) end;
$$;

grant execute on function public.like_contains(text) to anon, authenticated, service_role;
grant execute on function public.search_text(text) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Ciudades: departamento (para distinguir localidades con el mismo nombre en
-- una provincia, por ejemplo "San José" de Tulumba y de San Javier). Lo
-- completa el importador de localidades (scripts/importar-localidades.mjs).
-- -----------------------------------------------------------------------------
alter table public.cities add column if not exists department text;

drop function if exists public.search_cities(text, smallint, integer);
create or replace function public.search_cities(
  q              text,
  p_province_id  smallint default null,
  max_results    integer  default 10
)
returns table (
  id             integer,
  name           text,
  slug           text,
  province_id    smallint,
  province_name  text,
  department     text
)
language sql
stable
set search_path = ''
as $$
  with term as (select coalesce(public.normalize_text(q), '') as t)
  select c.id, c.name, c.slug, c.province_id, p.name, c.department
  from public.cities c
  join public.provinces p on p.id = c.province_id
  where c.active
    and (p_province_id is null or c.province_id = p_province_id)
    and (
      (select t from term) = ''
      or public.normalize_text(c.name) like (select t from term) || '%'
      or public.normalize_text(c.name) like '% ' || (select t from term) || '%'
      or extensions.word_similarity((select t from term), public.normalize_text(c.name)) >= 0.45
    )
  order by
    (public.normalize_text(c.name) like (select t from term) || '%') desc,
    extensions.word_similarity((select t from term), public.normalize_text(c.name)) desc,
    c.population desc nulls last,
    c.name
  limit least(greatest(coalesce(max_results, 10), 1), 25);
$$;

grant execute on function public.search_cities(text, smallint, integer) to anon, authenticated;

-- Índice para buscar emprendimientos por nombre o frase corta.
drop index if exists public.businesses_name_trgm_idx;
create index if not exists businesses_search_trgm_idx on public.businesses
  using gin ((name || ' ' || coalesce(tagline, '')) extensions.gin_trgm_ops);

create index if not exists businesses_province_idx on public.businesses (province_id)
  where status = 'active' and deleted_at is null;

-- Reemplazan a las versiones de la migración 0013 (con menos parámetros).
drop function if exists public.search_profile_ids(text, integer);
drop function if exists public.search_post_ids(text, integer);

-- -----------------------------------------------------------------------------
-- Emprendimientos
-- -----------------------------------------------------------------------------
create or replace function public.search_business_ids(
  p_query          text     default null,
  p_category_id    integer  default null,
  p_subcategory_id integer  default null,
  p_city_id        integer  default null,
  p_province_id    smallint default null,
  p_limit          integer  default 20,
  p_offset         integer  default 0
)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select b.id
  from public.businesses b
  where b.status = 'active'
    and b.deleted_at is null
    and (p_category_id is null or b.category_id = p_category_id)
    and (p_subcategory_id is null or exists (
      select 1 from public.business_subcategories bs
      where bs.business_id = b.id and bs.subcategory_id = p_subcategory_id
    ))
    and (p_city_id is null or b.city_id = p_city_id)
    and (p_province_id is null or b.province_id = p_province_id)
    and (
      public.search_text(p_query) is null
      or (b.name || ' ' || coalesce(b.tagline, '')) ilike public.like_contains(p_query)
    )
  order by (b.plan_tier <> 'free') desc,
           (b.verification = 'verified') desc,
           b.search_boost desc,
           b.followers_count desc,
           b.created_at desc,
           b.id
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 1000);
$$;

-- -----------------------------------------------------------------------------
-- Personas
-- -----------------------------------------------------------------------------
create or replace function public.search_profile_ids(
  p_query     text                     default null,
  p_city_id   integer                  default null,
  p_situation public.profile_situation default null,
  p_limit     integer                  default 20,
  p_offset    integer                  default 0
)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id
  from public.profiles p
  where p.status = 'active'
    and (p_city_id is null or p.city_id = p_city_id)
    and (p_situation is null or p.situation = p_situation)
    and (
      public.search_text(p_query) is null
      or (coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || p.username::text || ' ' || coalesce(p.headline, ''))
         ilike public.like_contains(p_query)
    )
    -- Sin ningún filtro no se listan personas (privacidad: no es un padrón).
    and (public.search_text(p_query) is not null or p_city_id is not null or p_situation is not null)
  order by (p.plan_tier <> 'free') desc, p.followers_count desc, p.created_at desc, p.id
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 1000);
$$;

-- -----------------------------------------------------------------------------
-- Publicaciones
-- -----------------------------------------------------------------------------
create or replace function public.search_post_ids(
  p_query       text             default null,
  p_type        public.post_type default null,
  p_category_id integer          default null,
  p_city_id     integer          default null,
  p_limit       integer          default 20,
  p_offset      integer          default 0
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
    and (p_category_id is null or p.category_id = p_category_id)
    and (p_city_id is null or p.city_id = p_city_id)
    and (
      public.search_text(p_query) is null
      or (coalesce(p.title, '') || ' ' || p.body) ilike public.like_contains(p_query)
    )
  order by p.published_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 1000);
$$;

revoke execute on function public.search_business_ids(text, integer, integer, integer, smallint, integer, integer) from public;
revoke execute on function public.search_profile_ids(text, integer, public.profile_situation, integer, integer) from public;
revoke execute on function public.search_post_ids(text, public.post_type, integer, integer, integer, integer) from public;
grant execute on function public.search_business_ids(text, integer, integer, integer, smallint, integer, integer) to anon, authenticated, service_role;
grant execute on function public.search_profile_ids(text, integer, public.profile_situation, integer, integer) to anon, authenticated, service_role;
grant execute on function public.search_post_ids(text, public.post_type, integer, integer, integer, integer) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Directorio: rubros con cantidad de emprendimientos activos
-- -----------------------------------------------------------------------------
create or replace function public.directory_categories()
returns table (id integer, name text, slug text, seo_noun text, description text, businesses bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.name, c.slug, c.seo_noun, c.description,
         count(b.id) filter (where b.status = 'active' and b.deleted_at is null) as businesses
  from public.categories c
  left join public.businesses b on b.category_id = c.id
  where c.active
  group by c.id
  order by c.sort_order, c.name;
$$;

-- Ciudades con emprendimientos de un rubro (para su página y sus enlaces).
create or replace function public.directory_category_cities(p_category_id integer, p_limit integer default 40)
returns table (
  city_id integer, city_name text, city_slug text,
  province_id smallint, province_name text, province_slug text,
  businesses bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select ci.id, ci.name, ci.slug, pr.id, pr.name, pr.slug, count(*) as businesses
  from public.businesses b
  join public.cities ci on ci.id = b.city_id
  join public.provinces pr on pr.id = ci.province_id
  where b.category_id = p_category_id
    and b.status = 'active'
    and b.deleted_at is null
  group by ci.id, pr.id
  order by count(*) desc, ci.name
  limit least(greatest(coalesce(p_limit, 40), 1), 200);
$$;

-- Pares rubro + ciudad con al menos p_min emprendimientos (sitemap).
create or replace function public.directory_landing_pairs(p_min integer default 3)
returns table (category_slug text, province_slug text, city_slug text, businesses bigint, last_updated timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.slug, pr.slug, ci.slug, count(*), max(b.updated_at)
  from public.businesses b
  join public.categories c on c.id = b.category_id and c.active
  join public.cities ci on ci.id = b.city_id
  join public.provinces pr on pr.id = ci.province_id
  where b.status = 'active' and b.deleted_at is null
  group by c.slug, pr.slug, ci.slug
  having count(*) >= greatest(coalesce(p_min, 3), 1)
  order by count(*) desc
  limit 45000;
$$;

grant execute on function public.directory_categories() to anon, authenticated, service_role;
grant execute on function public.directory_category_cities(integer, integer) to anon, authenticated, service_role;
grant execute on function public.directory_landing_pairs(integer) to anon, authenticated, service_role;

-- Rubros con emprendimientos en una ciudad (enlaces "Otros rubros en ...").
create or replace function public.directory_city_categories(p_city_id integer)
returns table (id integer, name text, slug text, businesses bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.name, c.slug, count(*)
  from public.businesses b
  join public.categories c on c.id = b.category_id and c.active
  where b.city_id = p_city_id and b.status = 'active' and b.deleted_at is null
  group by c.id
  order by count(*) desc, c.name;
$$;

grant execute on function public.directory_city_categories(integer) to anon, authenticated, service_role;

-- El orden de resultados usa search_boost: visible también sin sesión (no es sensible).
grant select (search_boost) on public.businesses to anon;

-- Umbrales SEO legibles por la app sin sesión.
update public.settings set is_public = true where key like 'seo.%';

notify pgrst, 'reload schema';
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'supabase/migrations/20261008001500_notifications.sql' << '__WORKLINK_FIN_DEL_ARCHIVO__'
-- =============================================================================
-- 0015 · Notificaciones (Etapa 8)
-- =============================================================================
-- * Avisos dentro de WorkLink: me gusta en tu publicación, comentario en tu
--   publicación, alguien empezó a seguirte o a seguir tu emprendimiento.
-- * Las crea la base con triggers (nadie puede crear avisos falsos desde la
--   app). Cada usuario solo ve y marca como leídos los suyos.
-- * Sin avisos duplicados: dar y quitar me gusta varias veces deja un solo
--   aviso; al quitar el me gusta o dejar de seguir, el aviso se borra.
-- * Los leídos de más de 90 días los borra la limpieza diaria.
-- * Pensado para sumar después: mensajes (Etapa 9) y propuestas (Etapa 10).
-- =============================================================================

create type public.notification_type as enum ('post_like', 'post_comment', 'profile_follow', 'business_follow');

create table public.notifications (
  id            uuid primary key default gen_random_uuid(),
  recipient_id  uuid not null references public.profiles (id) on delete cascade,
  actor_id      uuid not null references public.profiles (id) on delete cascade,
  type          public.notification_type not null,
  post_id       uuid references public.posts (id) on delete cascade,
  comment_id    uuid references public.post_comments (id) on delete cascade,
  business_id   uuid references public.businesses (id) on delete cascade,
  created_at    timestamptz not null default now(),
  read_at       timestamptz,
  constraint notifications_not_self check (recipient_id <> actor_id)
);

-- Lista del usuario (más nuevas primero) y contador de no leídas.
create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc, id desc);
create index notifications_unread_idx on public.notifications (recipient_id) where read_at is null;
create index notifications_cleanup_idx on public.notifications (read_at) where read_at is not null;

-- Un solo aviso por persona y publicación (me gusta) o por seguimiento.
create unique index notifications_like_once on public.notifications (recipient_id, actor_id, post_id) where type = 'post_like';
create unique index notifications_follow_once on public.notifications (recipient_id, actor_id) where type = 'profile_follow';
create unique index notifications_business_follow_once on public.notifications (recipient_id, actor_id, business_id) where type = 'business_follow';

-- -----------------------------------------------------------------------------
-- Creación de avisos (solo desde triggers; SECURITY DEFINER)
-- -----------------------------------------------------------------------------
create or replace function public.notify(
  p_recipient uuid,
  p_actor     uuid,
  p_type      public.notification_type,
  p_post      uuid default null,
  p_comment   uuid default null,
  p_business  uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient is null or p_actor is null or p_recipient = p_actor then
    return;
  end if;
  -- Sin avisos entre personas con bloqueo.
  if public.is_blocked_between(p_recipient, p_actor) then
    return;
  end if;
  insert into public.notifications (recipient_id, actor_id, type, post_id, comment_id, business_id)
  values (p_recipient, p_actor, p_type, p_post, p_comment, p_business)
  on conflict do nothing;
end;
$$;

revoke execute on function public.notify(uuid, uuid, public.notification_type, uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.tg_notify_post_like()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.notify((select p.author_id from public.posts p where p.id = new.post_id), new.user_id, 'post_like', new.post_id);
  else
    delete from public.notifications n
    where n.type = 'post_like' and n.actor_id = old.user_id and n.post_id = old.post_id;
  end if;
  return null;
end;
$$;

create trigger post_likes_notify
  after insert or delete on public.post_likes
  for each row execute function public.tg_notify_post_like();

create or replace function public.tg_notify_post_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.notify((select p.author_id from public.posts p where p.id = new.post_id), new.author_id, 'post_comment', new.post_id, new.id);
  return null;
end;
$$;

-- Al borrar el comentario, el aviso se borra solo (comment_id on delete cascade).
create trigger post_comments_notify
  after insert on public.post_comments
  for each row execute function public.tg_notify_post_comment();

create or replace function public.tg_notify_profile_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.notify(new.followed_id, new.follower_id, 'profile_follow');
  else
    delete from public.notifications n
    where n.type = 'profile_follow' and n.actor_id = old.follower_id and n.recipient_id = old.followed_id;
  end if;
  return null;
end;
$$;

create trigger profile_follows_notify
  after insert or delete on public.profile_follows
  for each row execute function public.tg_notify_profile_follow();

-- Seguir un emprendimiento avisa a su dueño.
create or replace function public.tg_notify_business_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.notify((select b.owner_id from public.businesses b where b.id = new.business_id), new.follower_id, 'business_follow', null, null, new.business_id);
  else
    delete from public.notifications n
    where n.type = 'business_follow' and n.actor_id = old.follower_id and n.business_id = old.business_id;
  end if;
  return null;
end;
$$;

create trigger business_follows_notify
  after insert or delete on public.business_follows
  for each row execute function public.tg_notify_business_follow();

-- -----------------------------------------------------------------------------
-- Seguridad: cada uno ve sus avisos y solo puede marcarlos como leídos.
-- -----------------------------------------------------------------------------
alter table public.notifications enable row level security;

create policy "notifications: veo las mías" on public.notifications
  for select to authenticated
  using (recipient_id = (select auth.uid()));

create policy "notifications: marco las mías como leídas" on public.notifications
  for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

create policy "notifications: borro las mías" on public.notifications
  for delete to authenticated
  using (recipient_id = (select auth.uid()));

revoke all on public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
-- Solo la columna read_at se puede modificar.
grant update (read_at) on public.notifications to authenticated;

-- Marcar todas como leídas (una sola consulta, sin pasar ids).
create or replace function public.mark_notifications_read()
returns integer
language sql
security invoker
set search_path = ''
as $$
  with updated as (
    update public.notifications
    set read_at = now()
    where recipient_id = (select auth.uid()) and read_at is null
    returning 1
  )
  select count(*)::integer from updated;
$$;

revoke execute on function public.mark_notifications_read() from public, anon;
grant execute on function public.mark_notifications_read() to authenticated;

notify pgrst, 'reload schema';
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'supabase/migrations/20261008001600_profile_verification.sql' << '__WORKLINK_FIN_DEL_ARCHIVO__'
-- =============================================================================
-- 0016 · Verificación de personas (tilde azul)
-- =============================================================================
-- * verified_at: fecha en que WorkLink verificó la cuenta (null = no
--   verificada). Se muestra como tilde azul junto al nombre.
-- * Solo lo puede cambiar el sistema o un administrador: el usuario no puede
--   verificarse solo.
-- =============================================================================

alter table public.profiles add column if not exists verified_at timestamptz;

grant select (verified_at) on public.profiles to anon;

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

  if new.followers_count <> old.followers_count
     or new.following_count <> old.following_count
     or new.plan_tier <> old.plan_tier then
    raise exception 'Campo administrado por el sistema' using errcode = '42501';
  end if;

  if new.verified_at is distinct from old.verified_at and not (select public.has_role('admin')) then
    raise exception 'Solo la administración puede verificar cuentas' using errcode = '42501';
  end if;

  if new.status is distinct from old.status and not (select public.has_role('moderator')) then
    raise exception 'Solo moderación puede cambiar el estado de una cuenta' using errcode = '42501';
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';
__WORKLINK_FIN_DEL_ARCHIVO__

escribir 'supabase/migrations/20261008001700_messages.sql' << '__WORKLINK_FIN_DEL_ARCHIVO__'
-- =============================================================================
-- 0017 · Mensajes privados (Etapa 9)
-- =============================================================================
-- * Conversaciones de a dos. Una sola conversación por par de personas.
-- * Solo los dos participantes ven la conversación y sus mensajes (RLS).
-- * Con bloqueo (en cualquier sentido) no se puede empezar ni escribir.
-- * Cada participante tiene su estado: hasta dónde leyó (para "no leídos" y
--   "Visto") y si la ocultó de su bandeja (vuelve a aparecer con un mensaje nuevo).
-- * Un mensaje puede citar la publicación por la que se consulta.
-- * Límites anti-spam: conversaciones nuevas por día y mensajes por hora.
-- =============================================================================

create table public.conversations (
  id                    uuid primary key default gen_random_uuid(),
  -- Par ordenado (user_low < user_high): garantiza una conversación por par.
  user_low              uuid not null references public.profiles (id) on delete cascade,
  user_high             uuid not null references public.profiles (id) on delete cascade,
  created_by            uuid not null references public.profiles (id) on delete cascade,
  created_at            timestamptz not null default now(),
  last_message_at       timestamptz,
  last_message_preview  text,
  last_sender_id        uuid references public.profiles (id) on delete set null,
  constraint conversations_pair_order check (user_low < user_high),
  constraint conversations_pair_key unique (user_low, user_high)
);

create table public.conversation_members (
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  last_read_at     timestamptz not null default now(),
  hidden_at        timestamptz,
  primary key (conversation_id, user_id)
);

create index conversation_members_user_idx on public.conversation_members (user_id);

create table public.messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  sender_id        uuid not null references public.profiles (id) on delete cascade,
  body             text not null,
  post_id          uuid references public.posts (id) on delete set null,
  created_at       timestamptz not null default now(),
  constraint messages_body_len check (char_length(btrim(body)) between 1 and 2000)
);

create index messages_conversation_idx on public.messages (conversation_id, created_at desc, id desc);
create index messages_sender_recent_idx on public.messages (sender_id, created_at desc);

-- ¿El usuario actual participa de la conversación?
create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = (select auth.uid())
  );
$$;

revoke execute on function public.is_conversation_member(uuid) from public, anon;
grant  execute on function public.is_conversation_member(uuid) to authenticated, service_role;

-- La otra persona de la conversación (para el usuario actual).
create or replace function public.conversation_other(p_conversation_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when c.user_low = (select auth.uid()) then c.user_high else c.user_low end
  from public.conversations c
  where c.id = p_conversation_id
    and (select auth.uid()) in (c.user_low, c.user_high);
$$;

revoke execute on function public.conversation_other(uuid) from public, anon;
grant  execute on function public.conversation_other(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Empezar (o retomar) una conversación con otra persona. Devuelve su id.
-- -----------------------------------------------------------------------------
create or replace function public.start_conversation(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me     uuid := (select auth.uid());
  low    uuid;
  high   uuid;
  conv   uuid;
begin
  if me is null then
    raise exception 'Tenés que ingresar' using errcode = '42501';
  end if;
  if p_other is null or p_other = me then
    raise exception 'No podés escribirte a vos' using errcode = '22023';
  end if;
  if not public.is_active_user() then
    raise exception 'Tu cuenta no puede enviar mensajes' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other and p.status = 'active') then
    raise exception 'Esa cuenta no está disponible' using errcode = '42501';
  end if;
  if public.is_blocked_between(me, p_other) then
    raise exception 'No podés escribirle a esta persona' using errcode = '42501';
  end if;

  low  := least(me, p_other);
  high := greatest(me, p_other);

  select c.id into conv from public.conversations c where c.user_low = low and c.user_high = high;
  if conv is not null then
    return conv;
  end if;

  if (
    select count(*) from public.conversations c
    where c.created_by = me and c.created_at > now() - interval '24 hours'
  ) >= public.setting_int('limits.conversations_per_day', 30) then
    raise exception 'Empezaste muchas conversaciones hoy. Probá de nuevo mañana.'
      using errcode = 'P0001', hint = 'rate_limited';
  end if;

  insert into public.conversations (user_low, user_high, created_by)
  values (low, high, me)
  on conflict (user_low, user_high) do nothing
  returning id into conv;

  if conv is null then
    select c.id into conv from public.conversations c where c.user_low = low and c.user_high = high;
    return conv;
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  values (conv, me), (conv, p_other);
  return conv;
end;
$$;

revoke execute on function public.start_conversation(uuid) from public, anon;
grant  execute on function public.start_conversation(uuid) to authenticated;

-- Marcar como leída (hasta ahora) para el usuario actual.
create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.conversation_members
  set last_read_at = now()
  where conversation_id = p_conversation_id and user_id = (select auth.uid());
$$;

revoke execute on function public.mark_conversation_read(uuid) from public, anon;
grant  execute on function public.mark_conversation_read(uuid) to authenticated;

-- Ocultar de mi bandeja (vuelve a aparecer si llega un mensaje nuevo).
create or replace function public.hide_conversation(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.conversation_members
  set hidden_at = now(), last_read_at = now()
  where conversation_id = p_conversation_id and user_id = (select auth.uid());
$$;

revoke execute on function public.hide_conversation(uuid) from public, anon;
grant  execute on function public.hide_conversation(uuid) to authenticated;

-- Conversaciones con mensajes sin leer del usuario actual (para el ícono).
create or replace function public.unread_conversations_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.conversation_members m
  join public.conversations c on c.id = m.conversation_id
  where m.user_id = (select auth.uid())
    and c.last_message_at is not null
    and c.last_sender_id is distinct from m.user_id
    and c.last_message_at > m.last_read_at;
$$;

revoke execute on function public.unread_conversations_count() from public, anon;
grant  execute on function public.unread_conversations_count() to authenticated;

-- -----------------------------------------------------------------------------
-- Envío de mensajes: autor = usuario actual, límite por hora, y al guardarse
-- actualiza la conversación (último mensaje) y la vuelve a mostrar a ambos.
-- -----------------------------------------------------------------------------
create or replace function public.tg_messages_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.body := btrim(new.body);
  if public.is_system_call() then
    return new;
  end if;
  new.sender_id := (select auth.uid());
  new.created_at := now();

  perform public.enforce_rate_limit(
    (select count(*) from public.messages m
      where m.sender_id = new.sender_id and m.created_at > now() - interval '1 hour'),
    'limits.messages_per_hour', 200,
    'Mandaste muchos mensajes seguidos. Esperá un rato y probá de nuevo.'
  );
  return new;
end;
$$;

create trigger messages_before_insert
  before insert on public.messages
  for each row execute function public.tg_messages_before_insert();

create or replace function public.tg_messages_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations
  set last_message_at = new.created_at,
      last_message_preview = left(regexp_replace(new.body, '\s+', ' ', 'g'), 140),
      last_sender_id = new.sender_id
  where id = new.conversation_id;

  update public.conversation_members
  set hidden_at = null,
      last_read_at = case when user_id = new.sender_id then new.created_at else last_read_at end
  where conversation_id = new.conversation_id;
  return null;
end;
$$;

create trigger messages_after_insert
  after insert on public.messages
  for each row execute function public.tg_messages_after_insert();

-- -----------------------------------------------------------------------------
-- Seguridad
-- -----------------------------------------------------------------------------
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;

create policy "conversations: participantes" on public.conversations
  for select to authenticated
  using ((select auth.uid()) in (user_low, user_high));

create policy "conversation_members: participantes" on public.conversation_members
  for select to authenticated
  using ((select public.is_conversation_member(conversation_id)));

create policy "messages: participantes leen" on public.messages
  for select to authenticated
  using ((select public.is_conversation_member(conversation_id)));

create policy "messages: participantes escriben" on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and (select public.is_active_user())
    and (select public.is_conversation_member(conversation_id))
    and not public.is_blocked_between((select auth.uid()), public.conversation_other(conversation_id))
  );

-- Todo lo demás pasa por las funciones de arriba: sin UPDATE/DELETE directos.
revoke all on public.conversations, public.conversation_members, public.messages from anon, authenticated;
grant select on public.conversations, public.conversation_members to authenticated;
grant select, insert on public.messages to authenticated;

insert into public.settings (key, value, is_public, description) values
  ('limits.conversations_per_day', '30',  false, 'Conversaciones nuevas que una persona puede empezar cada 24 h'),
  ('limits.messages_per_hour',     '200', false, 'Mensajes por persona cada hora')
on conflict (key) do nothing;

notify pgrst, 'reload schema';
__WORKLINK_FIN_DEL_ARCHIVO__

# Comando para importar localidades (se agrega a package.json sin tocar lo demás).
npm pkg set "scripts.db:localidades=node scripts/importar-localidades.mjs"
echo "  ✓ package.json (script db:localidades)"

echo ""
echo "============================================================"
echo " Listo. 146 archivos de la Etapa 9 instalados."
echo " Siguientes pasos:"
echo "   1) npx supabase db push"
echo "   2) git add . / git commit / git push"
echo "============================================================"
