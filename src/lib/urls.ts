import { slugify } from "../utils/slug";

/**
 * URLs públicas. La de una publicación lleva un texto legible y el id al final:
 * /p/busco-fotografo-para-casamiento-6f1c...  (lo único que importa es el id).
 */
export function postPath(post: { id: string; title: string | null; body: string }): string {
  const words = slugify((post.title || post.body).slice(0, 80), 60);
  return `/p/${words ? `${words}-` : ""}${post.id}`;
}

/** Extrae el id del final de /p/[ref]. */
export function postIdFromRef(ref: string | undefined): string | null {
  const match = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/.exec(ref ?? "");
  return match ? match[1] : null;
}

export const businessPath = (slug: string) => `/e/${slug}`;
export const profilePath = (username: string) => `/u/${username}`;
