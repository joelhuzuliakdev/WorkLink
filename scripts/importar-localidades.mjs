#!/usr/bin/env node
/**
 * Importa todas las localidades de Argentina desde Georef (API oficial del
 * Estado: apis.datos.gob.ar/georef) a la tabla cities de Supabase.
 *
 * Uso (desde la carpeta del proyecto, con el .env completo):
 *     npm run db:localidades              -> importa
 *     npm run db:localidades -- --prueba  -> solo muestra qué haría, sin escribir
 *     npm run db:localidades -- --archivo localidades.json  -> usa un archivo descargado
 *
 * - Se puede correr más de una vez: actualiza las que ya existen (por su id
 *   de Georef) y agrega las nuevas. Nunca borra ciudades.
 * - Las ciudades que ya estaban cargadas (sin id de Georef) se vinculan por
 *   provincia + nombre, así no se duplican y los perfiles que las usan siguen igual.
 * - Si en una provincia hay dos localidades con el mismo nombre, la dirección
 *   (slug) de la segunda lleva el departamento: "san-jose-tulumba".
 * - Necesita SUPABASE_SERVICE_ROLE_KEY (la clave secreta) porque escribe en una
 *   tabla que solo administra el sistema. La clave se lee del .env y no sale
 *   de tu computadora.
 */
import { readFile } from "node:fs/promises";
import { createClient } from "@supabase/supabase-js";

const args = process.argv.slice(2);
const dryRun = args.includes("--prueba");
const fileArg = args.includes("--archivo") ? args[args.indexOf("--archivo") + 1] : null;

try {
  process.loadEnvFile(".env");
} catch {
  // Sin .env: se usan las variables de entorno del sistema.
}

const url = process.env.PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("Faltan PUBLIC_SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en el archivo .env");
  process.exit(1);
}

const GEOREF = process.env.GEOREF_URL ?? "https://apis.datos.gob.ar/georef/api/localidades";
const PAGE = 1000;

const supabase = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

/** Igual que src/utils/slug.ts y la función slugify() de la base. */
function slugify(input, maxLength = 80) {
  return input
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, maxLength)
    .replace(/-+$/g, "");
}

const normalize = (text) => slugify(text, 200);

async function fetchGeoref() {
  if (fileArg) {
    console.log(`Leyendo ${fileArg}…`);
    const json = JSON.parse(await readFile(fileArg, "utf8"));
    return json.localidades ?? json;
  }

  const all = [];
  let start = 0;
  let total = Infinity;
  while (start < total) {
    const params = new URLSearchParams({
      max: String(PAGE),
      inicio: String(start),
      campos: "id,nombre,provincia.id,departamento.nombre,centroide",
      orden: "id",
    });
    const res = await fetch(`${GEOREF}?${params}`);
    if (!res.ok) throw new Error(`Georef respondió ${res.status}. Probá de nuevo en unos minutos.`);
    const json = await res.json();
    total = json.total;
    all.push(...json.localidades);
    start += json.cantidad || PAGE;
    console.log(`  descargadas ${all.length} de ${total}`);
    if (!json.cantidad) break;
  }
  return all;
}

async function fetchExisting() {
  const rows = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await supabase
      .from("cities")
      .select("id, province_id, name, slug, georef_id, lat, lng, department")
      .range(from, from + 999);
    if (error) throw error;
    rows.push(...data);
    if (data.length < 1000) break;
  }
  return rows;
}

async function main() {
  console.log(dryRun ? "Modo prueba: no se va a escribir nada.\n" : "");
  console.log("Descargando localidades de Georef…");
  const source = (await fetchGeoref()).filter((l) => l?.id && l?.nombre && l?.provincia?.id);
  console.log(`Localidades recibidas: ${source.length}`);

  const { data: provinces, error: provError } = await supabase.from("provinces").select("id");
  if (provError) throw provError;
  const provinceIds = new Set(provinces.map((p) => p.id));

  const existing = await fetchExisting();
  const byGeoref = new Map(existing.filter((c) => c.georef_id).map((c) => [c.georef_id, c]));
  const unlinked = new Map(existing.filter((c) => !c.georef_id).map((c) => [`${c.province_id}|${normalize(c.name)}`, c]));
  const usedSlugs = new Set(existing.map((c) => `${c.province_id}|${c.slug}`));

  // Primero las cabeceras (localidad con el mismo nombre que su departamento):
  // si hay nombres repetidos, la más conocida se queda con la dirección corta.
  source.sort((a, b) => {
    const aHead = normalize(a.nombre) === normalize(a.departamento?.nombre ?? "") ? 0 : 1;
    const bHead = normalize(b.nombre) === normalize(b.departamento?.nombre ?? "") ? 0 : 1;
    return aHead - bHead || String(a.id).localeCompare(String(b.id));
  });

  const updates = [];
  const inserts = [];
  let skipped = 0;

  for (const loc of source) {
    const provinceId = Number(loc.provincia.id);
    if (!provinceIds.has(provinceId)) {
      skipped++;
      continue;
    }
    const georefId = String(loc.id);
    const name = loc.nombre.trim();
    const department = loc.departamento?.nombre?.trim() || null;
    const lat = typeof loc.centroide?.lat === "number" ? Number(loc.centroide.lat.toFixed(5)) : null;
    const lng = typeof loc.centroide?.lon === "number" ? Number(loc.centroide.lon.toFixed(5)) : null;

    const known = byGeoref.get(georefId);
    if (known) {
      // Solo se actualiza si cambió algo (así correrlo de nuevo es rápido).
      if (known.name !== name || known.department !== department || Number(known.lat) !== lat || Number(known.lng) !== lng) {
        updates.push({ id: known.id, name, department, lat, lng });
      }
      continue;
    }

    const seeded = unlinked.get(`${provinceId}|${normalize(name)}`);
    if (seeded) {
      unlinked.delete(`${provinceId}|${normalize(name)}`);
      updates.push({ id: seeded.id, georef_id: georefId, department, lat, lng });
      continue;
    }

    const base = slugify(name) || `localidad-${georefId}`;
    const candidates = [base, slugify(`${name} ${loc.departamento?.nombre ?? ""}`), `${base}-${georefId}`];
    const slug = candidates.find((s) => s && !usedSlugs.has(`${provinceId}|${s}`)) ?? `${base}-${georefId}`;
    usedSlugs.add(`${provinceId}|${slug}`);
    inserts.push({ province_id: provinceId, name, slug, department, lat, lng, georef_id: georefId });
  }

  console.log(`\nNuevas: ${inserts.length} · Para actualizar: ${updates.length} · Sin provincia válida: ${skipped}`);
  if (dryRun) {
    console.log("Ejemplos de nuevas:", inserts.slice(0, 5).map((c) => `${c.name} (${c.slug})`).join(", "));
    return;
  }

  for (let i = 0; i < inserts.length; i += 500) {
    const { error } = await supabase.from("cities").insert(inserts.slice(i, i + 500));
    if (error) throw error;
    console.log(`  agregadas ${Math.min(i + 500, inserts.length)} de ${inserts.length}`);
  }

  let done = 0;
  for (const { id, ...changes } of updates) {
    const { error } = await supabase.from("cities").update(changes).eq("id", id);
    if (error) throw error;
    done++;
    if (done % 500 === 0) console.log(`  actualizadas ${done} de ${updates.length}`);
  }

  const { count } = await supabase.from("cities").select("id", { count: "exact", head: true });
  console.log(`\nListo. Ciudades en WorkLink: ${count}.`);
}

main().catch((error) => {
  console.error("\nNo se pudo completar la importación:", error.message ?? error);
  process.exit(1);
});
