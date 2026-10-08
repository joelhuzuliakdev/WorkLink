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
