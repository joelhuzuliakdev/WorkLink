import { z } from "astro/zod";
import {
  optionalFacebook,
  optionalId,
  optionalInstagram,
  optionalMediaPath,
  optionalText,
  optionalTiktok,
  optionalWebsite,
  optionalWhatsapp,
  optionalPhone,
} from "./common";
import { SITUATION_VALUES } from "../config/situations";

const personName = (label: string) =>
  z
    .string({ error: `Ingresá tu ${label}` })
    .trim()
    .min(2, { error: `Tu ${label} debe tener al menos 2 letras` })
    .max(60, { error: `Tu ${label} puede tener hasta 60 caracteres` })
    .regex(/^[\p{L}][\p{L}\s'.-]*$/u, { error: `Tu ${label} solo puede tener letras` });

export const profileSchema = z.object({
  username: z
    .string({ error: "Elegí un nombre de usuario" })
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9_.]{3,30}$/, {
      error: "Entre 3 y 30 caracteres: letras sin tilde, números, punto o guion bajo",
    }),
  first_name: personName("nombre"),
  last_name: personName("apellido"),
  bio: optionalText(500, "La descripción"),
  situation: z.preprocess((value) => (value === "" || value === null ? undefined : value), z.enum(SITUATION_VALUES).optional()),
  headline: optionalText(80, "Tu rubro"),
  city_id: optionalId,
  avatar_path: optionalMediaPath,
  whatsapp: optionalWhatsapp,
  phone: optionalPhone,
  instagram: optionalInstagram,
  facebook: optionalFacebook,
  tiktok: optionalTiktok,
  website: optionalWebsite,
});

export type ProfileInput = z.infer<typeof profileSchema>;
