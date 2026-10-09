import { z } from "astro/zod";
import { optionalAmount, optionalId, optionalText } from "./common";
import { POST_MAX_IMAGES } from "../config/media";

/**
 * Tipos de publicación. "service" queda solo para publicaciones viejas (ahora
 * es "Ofrezco"). Para contratar a alguien se usa Necesidades, no una publicación.
 */
export const POST_TYPES = [
  { value: "offer", label: "Ofrezco", formLabel: "Ofrezco un servicio", hint: "Tu oficio, profesión o lo que sabés hacer.", needsBusiness: false, legacy: false },
  { value: "product", label: "Producto", formLabel: "Vendo un producto", hint: "Algo que vendés desde tu emprendimiento.", needsBusiness: true, legacy: false },
  { value: "promotion", label: "Promoción", formLabel: "Promoción", hint: "Una oferta o descuento de tu emprendimiento.", needsBusiness: true, legacy: false },
  { value: "seeking", label: "Busco trabajo", formLabel: "Busco trabajo", hint: "Contá que estás buscando empleo o changas.", needsBusiness: false, legacy: false },
  { value: "service", label: "Servicio", formLabel: "Servicio", hint: "", needsBusiness: true, legacy: true },
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
