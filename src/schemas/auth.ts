import { z } from "astro/zod";

/**
 * Validaciones de autenticación. Se usan en el servidor (Astro Actions) y
 * sus mensajes se muestran en los formularios.
 */

export const emailSchema = z
  .string({ error: "Ingresá tu email" })
  .trim()
  .toLowerCase()
  .pipe(z.email({ error: "Ingresá un email válido" }).max(254, { error: "El email es demasiado largo" }));

/** 8 a 72 caracteres (límite de bcrypt), con al menos una letra y un número. */
export const passwordSchema = z
  .string({ error: "Ingresá una contraseña" })
  .min(8, { error: "La contraseña debe tener al menos 8 caracteres" })
  .max(72, { error: "La contraseña puede tener hasta 72 caracteres" })
  .regex(/[A-Za-zÁÉÍÓÚáéíóúÑñ]/, { error: "La contraseña debe incluir al menos una letra" })
  .regex(/[0-9]/, { error: "La contraseña debe incluir al menos un número" });

const personName = (label: string) =>
  z
    .string({ error: `Ingresá tu ${label}` })
    .trim()
    .min(2, { error: `Tu ${label} debe tener al menos 2 letras` })
    .max(60, { error: `Tu ${label} puede tener hasta 60 caracteres` })
    .regex(/^[\p{L}][\p{L}\s'.-]*$/u, { error: `Tu ${label} solo puede tener letras` });

export const signUpSchema = z.object({
  first_name: personName("nombre"),
  last_name: personName("apellido"),
  email: emailSchema,
  password: passwordSchema,
  intent: z.enum(["seeker", "provider"], { error: "Elegí qué venís a hacer" }),
  accept_terms: z.boolean().refine((value) => value, {
    error: "Tenés que aceptar los términos para crear la cuenta",
  }),
});

export const signInSchema = z.object({
  email: emailSchema,
  password: z.string({ error: "Ingresá tu contraseña" }).min(1, { error: "Ingresá tu contraseña" }).max(72),
  next: z.string().max(500).optional(),
});

export const forgotPasswordSchema = z.object({
  email: emailSchema,
});

export const resetPasswordSchema = z
  .object({
    password: passwordSchema,
    password_confirm: z.string(),
  })
  .refine((data) => data.password === data.password_confirm, {
    error: "Las contraseñas no coinciden",
    path: ["password_confirm"],
  });

export type SignUpInput = z.infer<typeof signUpSchema>;
export type SignInInput = z.infer<typeof signInSchema>;
