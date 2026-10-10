import { z } from "astro/zod";
import { emailSchema } from "./auth";

const empty = (value: unknown) => (value === null || (typeof value === "string" && value.trim() === "") ? undefined : value);

/** Formulario público del botón de arrepentimiento (no hace falta cuenta). */
export const withdrawalSchema = z.object({
  full_name: z
    .string({ error: "Escribí tu nombre y apellido" })
    .trim()
    .min(3, { error: "Escribí tu nombre y apellido" })
    .max(120, { error: "El nombre puede tener hasta 120 caracteres" }),
  email: emailSchema,
  dni: z.preprocess(
    empty,
    z
      .string()
      .transform((v) => v.replace(/\D/g, ""))
      .refine((v) => /^\d{7,8}$/.test(v), { error: "El DNI tiene que tener 7 u 8 números" })
      .nullish(),
  ),
  subscription_id: z.preprocess(empty, z.uuid().nullish()),
  detail: z.preprocess(empty, z.string().trim().max(1000, { error: "El comentario puede tener hasta 1000 caracteres" }).nullish()),
});

/** Administración: devolver y cancelar un plan por arrepentimiento. */
export const refundWithdrawalSchema = z.object({
  withdrawal_id: z.uuid(),
  subscription_id: z.uuid({ error: "Elegí el plan a devolver" }),
});

/** Administración: rechazar o dar por resuelto un pedido. */
export const resolveWithdrawalSchema = z.object({
  withdrawal_id: z.uuid(),
  status: z.enum(["rejected", "closed"]),
  note: z.preprocess(empty, z.string().trim().max(1000).nullish()),
});
