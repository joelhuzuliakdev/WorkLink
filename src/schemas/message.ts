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

/** Compartir una publicación por mensaje privado con hasta 10 personas. */
export const sharePostSchema = z.object({
  post_id: z.string().regex(UUID),
  usernames: z
    .array(z.string().trim().toLowerCase().regex(/^[a-z0-9_.]{3,30}$/))
    .min(1, { error: "Elegí al menos una persona" })
    .max(10, { error: "Podés compartir con hasta 10 personas a la vez" }),
  note: z.preprocess(emptyToUndefined, z.string().trim().max(500, { error: "El mensaje puede tener hasta 500 caracteres" }).optional()),
});
