import { z } from "astro/zod";
import { normalizeArgentinePhone, normalizeFacebook, normalizeHandle, normalizeWebsite } from "../lib/contact";
import { parseArgentineAmount } from "../lib/format";

/**
 * Piezas de validación reutilizables. Los campos vacíos de un formulario
 * llegan como "" o null: se convierten a null para guardar NULL en la base.
 */

const emptyToNull = (value: unknown) => (typeof value === "string" && value.trim() === "" ? null : value);

/** Texto opcional con largo máximo. */
export const optionalText = (max: number, label = "Este campo") =>
  z.preprocess(
    emptyToNull,
    z
      .string()
      .trim()
      .max(max, { error: `${label} puede tener hasta ${max} caracteres` })
      .nullable()
      .optional(),
  );

/** Entero positivo opcional (ids de select / ciudad). */
export const optionalId = z.preprocess(emptyToNull, z.coerce.number().int().positive().nullable().optional());

export const optionalWhatsapp = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const phone = normalizeArgentinePhone(value, { mobile: true });
      if (!phone) {
        ctx.addIssue({ code: "custom", message: "Escribí el número con característica, por ejemplo 351 555-1234" });
        return z.NEVER;
      }
      return phone;
    }),
);

export const optionalPhone = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const phone = normalizeArgentinePhone(value, { mobile: false });
      if (!phone) {
        ctx.addIssue({ code: "custom", message: "Escribí el número con característica, por ejemplo 0351 422-1234" });
        return z.NEVER;
      }
      return phone;
    }),
);

const socialHandle = (host: "instagram.com" | "tiktok.com", label: string) =>
  z.preprocess(
    emptyToNull,
    z
      .string()
      .nullable()
      .optional()
      .transform((value, ctx) => {
        if (!value) return null;
        const handle = normalizeHandle(value, host);
        if (!handle) {
          ctx.addIssue({ code: "custom", message: `Escribí tu usuario de ${label}, por ejemplo @mi.negocio` });
          return z.NEVER;
        }
        return handle;
      }),
  );

export const optionalInstagram = socialHandle("instagram.com", "Instagram");
export const optionalTiktok = socialHandle("tiktok.com", "TikTok");

export const optionalFacebook = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const url = normalizeFacebook(value);
      if (!url) {
        ctx.addIssue({ code: "custom", message: "Escribí el enlace de tu página o tu usuario de Facebook" });
        return z.NEVER;
      }
      return url;
    }),
);

export const optionalWebsite = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const url = normalizeWebsite(value);
      if (!url) {
        ctx.addIssue({ code: "custom", message: "Escribí una dirección web válida, por ejemplo minegocio.com.ar" });
        return z.NEVER;
      }
      return url;
    }),
);

/** Importe en pesos ("12.500,50"). Opcional. */
export const optionalAmount = z.preprocess(
  emptyToNull,
  z
    .string()
    .nullable()
    .optional()
    .transform((value, ctx) => {
      if (!value) return null;
      const amount = parseArgentineAmount(value);
      if (amount === null || amount > 999_999_999) {
        ctx.addIssue({ code: "custom", message: "Escribí un importe válido, por ejemplo 12.500" });
        return z.NEVER;
      }
      return amount;
    }),
);

/** Carpeta de imagen subida ("uuid/uuid") o vacío para quitarla. */
export const optionalMediaPath = z.preprocess(
  emptyToNull,
  z
    .string()
    .regex(/^[0-9a-f-]{36}\/[0-9a-f-]{36}$/, { error: "Imagen inválida" })
    .nullable()
    .optional(),
);
