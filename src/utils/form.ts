/**
 * Valores enviados en un formulario POST, para volver a mostrarlos cuando la
 * validación falla (así el usuario no reescribe todo). Nunca devuelve
 * contraseñas.
 */
export async function getSubmittedValues(request: Request): Promise<Record<string, string>> {
  if (request.method !== "POST") return {};
  try {
    const data = await request.clone().formData();
    const values: Record<string, string> = {};
    for (const [key, value] of data.entries()) {
      if (typeof value === "string" && !key.toLowerCase().includes("password")) {
        values[key] = value.slice(0, 500);
      }
    }
    return values;
  } catch {
    return {};
  }
}
