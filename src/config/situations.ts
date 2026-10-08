import type { ProfileSituation } from "../services/posts";

/**
 * Situación laboral que cada persona puede mostrar en su perfil y en sus
 * publicaciones. El orden es el del formulario.
 */
export const SITUATIONS: { value: ProfileSituation; label: string; badge: string; hint: string; class: string }[] = [
  {
    value: "job_seeking",
    label: "Busco empleo",
    badge: "Busca empleo",
    hint: "Estás buscando trabajo en relación de dependencia.",
    class: "bg-seek-soft text-seek",
  },
  {
    value: "entrepreneur",
    label: "Tengo un emprendimiento",
    badge: "Emprendedor/a",
    hint: "Vendés productos o servicios con tu propio emprendimiento.",
    class: "bg-offer-soft text-offer",
  },
  {
    value: "freelancer",
    label: "Ofrezco mis servicios",
    badge: "Ofrece servicios",
    hint: "Trabajás por tu cuenta: oficios, profesiones, changas.",
    class: "bg-success-soft text-success",
  },
  {
    value: "hiring",
    label: "Busco contratar",
    badge: "Busca contratar",
    hint: "Necesitás sumar personas a tu equipo o contratar un servicio.",
    class: "bg-warning-soft text-warning",
  },
];

export const SITUATION_VALUES = SITUATIONS.map((s) => s.value) as [ProfileSituation, ...ProfileSituation[]];

export function situationInfo(value: ProfileSituation | null | undefined) {
  return value ? (SITUATIONS.find((s) => s.value === value) ?? null) : null;
}
