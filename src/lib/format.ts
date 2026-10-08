/**
 * Formatos para Argentina: pesos, números y fechas en es-AR, mostrados en la
 * zona horaria de Córdoba (la base guarda todo en UTC).
 */
const TIME_ZONE = "America/Argentina/Cordoba";

const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 2 });
const moneyRound = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 });
const number = new Intl.NumberFormat("es-AR");

export function formatMoney(amount: number | string | null | undefined): string {
  if (amount === null || amount === undefined || amount === "") return "";
  const value = typeof amount === "string" ? Number(amount) : amount;
  if (!Number.isFinite(value)) return "";
  return Number.isInteger(value) ? moneyRound.format(value) : money.format(value);
}

export type PriceType = "fixed" | "from" | "ask";

/** "$ 12.500" · "Desde $ 350.000" · "Consultar precio" */
export function formatPrice(amount: number | string | null | undefined, priceType: PriceType): string {
  if (priceType === "ask" || amount === null || amount === undefined) return "Consultar precio";
  const formatted = formatMoney(amount);
  return priceType === "from" ? `Desde ${formatted}` : formatted;
}

export function formatNumber(value: number): string {
  return number.format(value);
}

export function formatDate(value: string | Date, options: Intl.DateTimeFormatOptions = { dateStyle: "long" }): string {
  return new Intl.DateTimeFormat("es-AR", { timeZone: TIME_ZONE, ...options }).format(new Date(value));
}

/** "Miembro desde octubre de 2026" */
export function formatMonthYear(value: string | Date): string {
  return new Intl.DateTimeFormat("es-AR", { timeZone: TIME_ZONE, month: "long", year: "numeric" }).format(new Date(value));
}

/** Convierte "12.500,50" o "12500.5" en 12500.5. Devuelve null si no es un número válido. */
export function parseArgentineAmount(input: string): number | null {
  const raw = input.replace(/[$\s]/g, "").trim();
  if (!raw) return null;
  let normalized = raw;
  if (raw.includes(",")) {
    normalized = raw.replace(/\./g, "").replace(",", ".");
  } else if (/^\d{1,3}(\.\d{3})+$/.test(raw)) {
    normalized = raw.replace(/\./g, "");
  }
  if (!/^\d+(\.\d{1,2})?$/.test(normalized)) return null;
  const value = Number(normalized);
  return Number.isFinite(value) ? value : null;
}

/**
 * "Villa María, Córdoba" · "Córdoba capital" (cuando la ciudad se llama igual
 * que la provincia, para no repetir "Córdoba, Córdoba").
 */
export function formatLocation(city: { name: string; province_name: string } | null | undefined): string | null {
  if (!city) return null;
  if (city.name === city.province_name) return `${city.name} capital`;
  return city.province_name ? `${city.name}, ${city.province_name}` : city.name;
}
