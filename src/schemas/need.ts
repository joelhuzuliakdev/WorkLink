import { z } from "astro/zod";
import { optionalAmount, optionalId, optionalText } from "./common";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const emptyToUndefined = (value: unknown) => (value === "" || value === null ? undefined : value);
const uuid = z.string().regex(UUID);

export const needSchema = z
  .object({
    title: z
      .string({ error: "Escribí qué necesitás" })
      .trim()
      .min(10, { error: "Contalo en al menos 10 caracteres, por ejemplo “Necesito electricista”" })
      .max(140, { error: "El título puede tener hasta 140 caracteres" }),
    description: z
      .string({ error: "Contá los detalles" })
      .trim()
      .min(20, { error: "Sumá algunos detalles (al menos 20 caracteres): qué, dónde, cuándo" })
      .max(5000, { error: "La descripción puede tener hasta 5000 caracteres" }),
    category_id: z.coerce.number({ error: "Elegí un rubro" }).int().positive({ error: "Elegí un rubro" }),
    subcategory_id: optionalId,
    city_id: z.coerce.number({ error: "Elegí la ciudad" }).int().positive({ error: "Elegí la ciudad" }),
    needed_by: z.preprocess(
      emptyToUndefined,
      z
        .string()
        .regex(/^\d{4}-\d{2}-\d{2}$/, { error: "Fecha inválida" })
        .optional(),
    ),
    budget_min: optionalAmount,
    budget_max: optionalAmount,
  })
  .refine((v) => v.budget_min == null || v.budget_max == null || v.budget_min <= v.budget_max, {
    message: "El presupuesto mínimo no puede ser mayor que el máximo",
    path: ["budget_max"],
  });

export type NeedInput = z.infer<typeof needSchema>;

export const needRefSchema = z.object({ need_id: uuid });

export const proposalSchema = z.object({
  need_id: uuid,
  message: z
    .string({ error: "Escribí tu propuesta" })
    .trim()
    .min(20, { error: "Contá tu propuesta en al menos 20 caracteres" })
    .max(2000, { error: "La propuesta puede tener hasta 2000 caracteres" }),
  amount: optionalAmount,
  availability: optionalText(120, "La disponibilidad"),
  business_id: z.preprocess(emptyToUndefined, uuid.optional()),
});

export const proposalUpdateSchema = proposalSchema.omit({ need_id: true, business_id: true }).extend({ proposal_id: uuid });

export const proposalRefSchema = z.object({ proposal_id: uuid });
