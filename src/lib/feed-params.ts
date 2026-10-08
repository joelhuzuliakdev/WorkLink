import type { PostType } from "../schemas/post";
import { decodeCursor, type Cursor } from "../services/posts";

/**
 * Parámetros del feed /publicaciones, compartidos por la página completa y el
 * fragmento de "Cargar más":
 *   ?tipo=busco      filtra por tipo
 *   ?ver=siguiendo   solo cuentas que sigue el usuario (requiere sesión)
 *   ?desde=...       cursor de la página siguiente
 */
export const TYPE_SLUGS: Record<string, PostType> = {
  ofrezco: "offer",
  busco: "seeking",
  productos: "product",
  servicios: "service",
  promociones: "promotion",
};

export interface FeedParams {
  tipo: string;
  type: PostType | null;
  following: boolean;
  cursor: Cursor | null;
  /** Arma el query string conservando los filtros actuales ("" o "?..."). */
  query: (extra?: Record<string, string>) => string;
}

export function parseFeedParams(url: URL): FeedParams {
  const following = url.searchParams.get("ver") === "siguiendo";
  const rawTipo = url.searchParams.get("tipo") ?? "";
  const type = following ? null : (TYPE_SLUGS[rawTipo] ?? null);
  const tipo = type ? rawTipo : "";
  const cursor = decodeCursor(url.searchParams.get("desde"));

  const query = (extra: Record<string, string> = {}) => {
    const params = new URLSearchParams({
      ...(following ? { ver: "siguiendo" } : {}),
      ...(type ? { tipo } : {}),
      ...extra,
    }).toString();
    return params ? `?${params}` : "";
  };

  return { tipo, type, following, cursor, query };
}
