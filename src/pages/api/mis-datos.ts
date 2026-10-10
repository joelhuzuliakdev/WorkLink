import type { APIRoute } from "astro";

/**
 * Descargar mis datos (derecho de acceso, Ley 25.326). Devuelve un JSON con
 * todo lo que la persona cargó. La base arma el archivo con export_my_data(),
 * que solo lee los datos de quien tiene la sesión: no se puede pedir el de otra
 * cuenta cambiando nada en la URL. Nunca se cachea.
 */
const ORDER = [
  "generado",
  "cuenta",
  "perfil",
  "emprendimientos",
  "publicaciones",
  "comentarios",
  "necesidades",
  "propuestas",
  "resenas_escritas",
  "mensajes_enviados",
  "personas_que_seguis",
  "emprendimientos_que_seguis",
  "guardados",
  "bloqueados",
  "planes",
  "pagos",
  "verificacion",
];

export const GET: APIRoute = async ({ locals }) => {
  if (!locals.user) return new Response("Ingresá para descargar tus datos.", { status: 401 });

  const { data, error } = await locals.supabase.rpc("export_my_data");
  if (error || !data) {
    console.error("[mis-datos]", error?.code, error?.message);
    return new Response("No pudimos preparar tus datos. Probá de nuevo en unos minutos.", { status: 500 });
  }

  const raw = data as Record<string, unknown>;
  const ordered = Object.fromEntries([...ORDER.filter((k) => k in raw).map((k) => [k, raw[k]]), ...Object.entries(raw).filter(([k]) => !ORDER.includes(k))]);
  const day = new Date().toISOString().slice(0, 10);

  return new Response(JSON.stringify({ worklink: ordered }, null, 2), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": `attachment; filename="worklink-mis-datos-${day}.json"`,
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
};
