/**
 * Normalización de datos de contacto: la gente escribe "351 15-555-1234",
 * "@mi.negocio" o "instagram.com/mi.negocio/". Acá se guardan en un formato
 * único y se arman los enlaces.
 */

/**
 * Teléfonos argentinos a formato internacional "+549XXXXXXXXXX" (móvil).
 * Acepta: "+54 9 351 555-1234", "0351 15 555-1234", "3515551234".
 * Devuelve null si no se puede interpretar.
 */
export function normalizeArgentinePhone(input: string, { mobile = true } = {}): string | null {
  let digits = input.replace(/\D/g, "");
  if (!digits) return null;
  if (digits.startsWith("00")) digits = digits.slice(2);

  if (digits.startsWith("54")) {
    digits = digits.slice(2);
    if (digits.startsWith("9")) digits = digits.slice(1);
  }
  if (digits.startsWith("0")) digits = digits.slice(1);

  // "351 15 5551234" -> "351 5551234": el 15 va después de la característica.
  const withFifteen = /^(\d{2,4})15(\d{6,8})$/.exec(digits);
  if (withFifteen && withFifteen[1].length + withFifteen[2].length === 10) {
    digits = withFifteen[1] + withFifteen[2];
  }

  if (digits.length !== 10) return null;
  return mobile ? `+549${digits}` : `+54${digits}`;
}

/** Enlace de WhatsApp a partir del número normalizado. */
export function whatsappUrl(phone: string, message?: string): string {
  const base = `https://wa.me/${phone.replace(/\D/g, "")}`;
  return message ? `${base}?text=${encodeURIComponent(message)}` : base;
}

/** "@mi.negocio", "instagram.com/mi.negocio" -> "mi.negocio" */
export function normalizeHandle(input: string, host: "instagram.com" | "tiktok.com"): string | null {
  let value = input.trim();
  if (!value) return null;
  value = value.replace(/^https?:\/\//i, "").replace(/^www\./i, "");
  if (value.toLowerCase().startsWith(host)) value = value.slice(host.length);
  value = value.replace(/^\/+/, "").replace(/^@/, "").split(/[/?#]/)[0] ?? "";
  return /^[A-Za-z0-9._]{1,40}$/.test(value) ? value : null;
}

/** Facebook: acepta usuario o URL de página. Devuelve la URL completa. */
export function normalizeFacebook(input: string): string | null {
  const value = input.trim();
  if (!value) return null;
  if (/^https?:\/\/(www\.|m\.)?facebook\.com\/.+/i.test(value)) return value.slice(0, 120);
  if (/^(www\.|m\.)?facebook\.com\/.+/i.test(value)) return `https://${value}`.slice(0, 120);
  if (/^[A-Za-z0-9.]{3,60}$/.test(value)) return `https://facebook.com/${value}`;
  return null;
}

/** Sitio web: agrega https:// si falta y valida que sea una URL. */
export function normalizeWebsite(input: string): string | null {
  const value = input.trim();
  if (!value) return null;
  const withProtocol = /^https?:\/\//i.test(value) ? value : `https://${value}`;
  try {
    const url = new URL(withProtocol);
    if (!url.hostname.includes(".")) return null;
    return url.toString().slice(0, 200);
  } catch {
    return null;
  }
}

export const instagramUrl = (handle: string) => `https://instagram.com/${handle}`;
export const tiktokUrl = (handle: string) => `https://www.tiktok.com/@${handle}`;
