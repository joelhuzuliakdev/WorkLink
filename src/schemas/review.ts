import { z } from "astro/zod";
import { optionalText } from "./common";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const uuid = z.string().regex(UUID);
const emptyToUndefined = (value: unknown) => (value === "" || value === null ? undefined : value);

export const reviewSchema = z.object({
  subject_type: z.enum(["business", "profile"]),
  subject_id: uuid,
  review_id: z.preprocess(emptyToUndefined, uuid.optional()),
  rating: z.coerce
    .number({ error: "Elegí de 1 a 5 estrellas" })
    .int({ error: "Elegí de 1 a 5 estrellas" })
    .min(1, { error: "Elegí de 1 a 5 estrellas" })
    .max(5, { error: "Elegí de 1 a 5 estrellas" }),
  body: optionalText(1000, "El comentario"),
});

export const reviewRefSchema = z.object({ review_id: uuid });

export const replySchema = z.object({
  review_id: uuid,
  reply: optionalText(1000, "La respuesta"),
});

export const REPORT_REASONS = {
  spam: "Spam o publicidad",
  offensive: "Ofensiva o discriminatoria",
  fake: "Es falsa (no hubo trato real)",
  scam: "Estafa o engaño",
  other: "Otro motivo",
} as const;

export const reportSchema = z.object({
  target_type: z.enum(["review", "post", "comment", "profile", "business", "need"]),
  target_id: uuid,
  reason: z.enum(Object.keys(REPORT_REASONS) as [keyof typeof REPORT_REASONS, ...(keyof typeof REPORT_REASONS)[]], {
    error: "Elegí un motivo",
  }),
  details: optionalText(500, "El detalle"),
});
