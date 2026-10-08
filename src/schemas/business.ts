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
