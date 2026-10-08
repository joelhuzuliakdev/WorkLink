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
