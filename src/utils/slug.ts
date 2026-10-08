/**
 * "Pastelería Ana & Co." -> "pasteleria-ana-co"
 * Igual que la función slugify() de la base de datos.
 */
export function slugify(input: string, maxLength = 80): string {
  return input
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, maxLength)
    .replace(/-+$/g, "");
}
