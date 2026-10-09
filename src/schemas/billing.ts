import { z } from "astro/zod";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const uuid = z.string().regex(UUID);
const emptyToUndefined = (value: unknown) => (value === "" || value === null ? undefined : value);
const storagePath = z.string().regex(/^[0-9a-f-]{36}\/[0-9a-f-]{36}$/, { error: "Subí la foto de nuevo" });

export const subscribeSchema = z.object({
  plan_id: z.enum(["destacado", "pro", "verificacion"]),
  business_id: z.preprocess(emptyToUndefined, uuid.optional()),
  payer_email: z
    .string({ error: "Escribí el email de tu cuenta de Mercado Pago" })
    .trim()
    .toLowerCase()
    .max(200)
    .email({ error: "Escribí un email válido" }),
});

export const subscriptionRefSchema = z.object({ subscription_id: uuid });

export const verificationSchema = z.object({
  document_path: storagePath,
  selfie_path: storagePath,
});

export const reviewVerificationSchema = z.object({
  request_id: uuid,
  decision: z.enum(["approve", "reject"]),
  reason: z.preprocess(emptyToUndefined, z.string().trim().max(300).optional()),
});

export const updatePlanSchema = z.object({
  plan_id: z.enum(["destacado", "pro", "verificacion"]),
  price: z.preprocess(
    (v) => (typeof v === "string" ? Number(v.replace(/[$\s.]/g, "").replace(",", ".")) : v),
    z.number({ error: "Escribí el precio" }).min(100, { error: "El precio mínimo es $100" }).max(10_000_000),
  ),
  active: z.preprocess((v) => v === "on" || v === "true" || v === true, z.boolean()),
});
