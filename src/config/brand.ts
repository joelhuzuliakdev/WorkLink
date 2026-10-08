/**
 * Identidad de marca de WorkLink (provisional).
 *
 * Nombre, textos y rutas del logo viven SOLO acá y en /public/brand.
 * Los colores y la tipografía están en src/styles/global.css (variables --wl-*).
 */
export const brand = {
  name: "WorkLink",
  shortName: "WorkLink",
  tagline: "Conectamos lo que necesitás con quien lo ofrece",
  description:
    "Encontrá emprendedores, profesionales, productos y servicios cerca tuyo, o publicá lo que necesitás y recibí propuestas. Empezamos en Córdoba.",
  logo: {
    /** Logo con texto (cabeceras). */
    full: "/brand/logo.svg",
    /** Solo el símbolo (favicon, avatares de la plataforma). */
    mark: "/brand/mark.svg",
  },
  /** Color principal para la barra del navegador en móviles. */
  themeColor: "#2f4fd8",
  locale: "es_AR",
  social: {
    instagram: null as string | null,
  },
} as const;

export type Brand = typeof brand;
