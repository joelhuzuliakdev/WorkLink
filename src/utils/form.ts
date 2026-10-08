/**
 * Valores enviados en un formulario POST, para volver a mostrarlos cuando la
 * validación falla (así el usuario no reescribe todo). Nunca devuelve
 * contraseñas.
 */
export async function getSubmittedValues(request: Request): Promise<Record<string, string>> {
  const data = await getSubmittedForm(request);
  if (!data) return {};
  const values: Record<string, string> = {};
  for (const [key, value] of data.entries()) {
    if (typeof value === "string" && !key.toLowerCase().includes("password")) {
      values[key] = value.slice(0, 5000);
    }
  }
  return values;
}

/** El FormData completo enviado (para campos repetidos como casillas múltiples). */
export async function getSubmittedForm(request: Request): Promise<FormData | null> {
  if (request.method !== "POST") return null;
  try {
    return await request.clone().formData();
  } catch {
    return null;
  }
}
