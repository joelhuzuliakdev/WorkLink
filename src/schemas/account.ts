import { z } from "astro/zod";
import { emailSchema, passwordSchema } from "./auth";

/**
 * Validaciones de Configuración de la cuenta. Se usan en el servidor (Astro
 * Actions); los permisos los controla la base y Supabase Auth.
 */

const currentPassword = z.preprocess(
  (value) => (value === null || value === "" ? undefined : value),
  z.string().max(72).nullish(),
);

export const changeEmailSchema = z.object({ email: emailSchema });

export const changePasswordSchema = z
  .object({
    current_password: currentPassword,
    password: passwordSchema,
    password_confirm: z.string(),
  })
  .refine((data) => data.password === data.password_confirm, {
    error: "Las contraseñas no coinciden",
    path: ["password_confirm"],
  });

export const profileRefSchema = z.object({
  profile_id: z.uuid({ error: "Cuenta inválida" }),
});

export const deleteAccountSchema = z.object({
  confirm: z
    .string({ error: "Escribí BORRAR para confirmar" })
    .trim()
    .refine((value) => value.toUpperCase() === "BORRAR", { error: "Escribí BORRAR (en mayúsculas) para confirmar" }),
  current_password: currentPassword,
});
