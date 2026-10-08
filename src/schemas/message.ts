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
