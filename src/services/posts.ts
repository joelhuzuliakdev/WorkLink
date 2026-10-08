import type { SupabaseClient } from "@supabase/supabase-js";
import type { PostType } from "../schemas/post";

/**
 * Consultas de publicaciones. Paginación por cursor (published_at, id): cada
 * página pide las siguientes N a partir de la última vista, sin OFFSET, así
 * el costo es el mismo en la página 1 que en la 1000.
 */

export const FEED_PAGE_SIZE = 20;

export interface PostMediaView {
  id: string;
  path: string;
  kind: "image" | "video";
  mime: string;
  width: number | null;
  height: number | null;
  duration_s: number | null;
  bytes: number;
}

export type ProfileSituation = "job_seeking" | "entrepreneur" | "freelancer" | "hiring";

export interface PostAuthor {
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  situation: ProfileSituation | null;
  headline: string | null;
  verified_at: string | null;
}

export interface PostView {
  id: string;
  type: PostType;
  title: string | null;
  body: string;
  price: number | null;
  currency: string;
  tags: string[];
  status: "published" | "hidden" | "removed";
  published_at: string;
  author_id: string;
  business_id: string | null;
  category_id: number | null;
  subcategory_id: number | null;
  city_id: number | null;
  likes_count: number;
  comments_count: number;
  saves_count: number;
  author: PostAuthor | null;
  business: { slug: string; name: string; logo_path: string | null; verification: string } | null;
  city: { name: string; slug: string; provinces: { name: string } | null } | null;
  category: { name: string; slug: string } | null;
  subcategory: { name: string } | null;
  media: PostMediaView[];
}

const POST_COLUMNS = `id, type, title, body, price, currency, tags, status, published_at, author_id, business_id,
  category_id, subcategory_id, city_id, likes_count, comments_count, saves_count,
  author:profiles!posts_author_id_fkey ( username, first_name, last_name, avatar_path, situation, headline, verified_at ),
  business:businesses ( slug, name, logo_path, verification ),
  city:cities ( name, slug, provinces ( name ) ),
  category:categories ( name, slug ),
  subcategory:subcategories ( name ),
  post_media ( position, media ( id, path, kind, mime, width, height, duration_s, bytes ) )`;

type Row = Omit<PostView, "media"> & {
  post_media: { position: number; media: PostMediaView | null }[] | null;
};

function toPost(row: Row): PostView {
  const { post_media, ...rest } = row;
  return {
    ...rest,
    price: rest.price === null ? null : Number(rest.price),
    media: (post_media ?? [])
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((pm) => pm.media)
      .filter((m): m is PostMediaView => Boolean(m)),
  };
}

/**
 * Una publicación es visible si su autor y (si tiene) su emprendimiento lo
 * son: RLS devuelve null en esos campos cuando están suspendidos o inactivos.
 */
const isVisible = (post: PostView) => Boolean(post.author) && (!post.business_id || Boolean(post.business));

export interface Cursor {
  publishedAt: string;
  id: string;
}

export function encodeCursor(post: { published_at: string; id: string }): string {
  return Buffer.from(`${post.published_at}|${post.id}`).toString("base64url");
}

export function decodeCursor(value: string | null | undefined): Cursor | null {
  if (!value) return null;
  try {
    const [publishedAt, id] = Buffer.from(value, "base64url").toString("utf8").split("|");
    if (!publishedAt || !id || Number.isNaN(Date.parse(publishedAt)) || !/^[0-9a-f-]{36}$/.test(id)) return null;
    return { publishedAt, id };
  } catch {
    return null;
  }
}

export interface FeedFilters {
  type?: PostType | null;
  businessId?: string | null;
  authorId?: string | null;
  /** Solo publicaciones personales (sin emprendimiento). */
  personalOnly?: boolean;
  /** Solo de personas y emprendimientos que sigue el usuario actual (y las propias). */
  following?: boolean;
  /** Solo de cuentas con plan pago (destacadas del inicio). */
  featured?: boolean;
  cursor?: Cursor | null;
  limit?: number;
}

export async function getFeed(
  supabase: SupabaseClient,
  { type, businessId, authorId, personalOnly, following, featured, cursor, limit = FEED_PAGE_SIZE }: FeedFilters = {},
): Promise<{ posts: PostView[]; nextCursor: string | null }> {
  // "Siguiendo" y "Destacadas": la base devuelve los ids de la página (ya
  // filtrados) y después se traen esas publicaciones con todos sus datos.
  let followingIds: string[] | null = null;
  if (following || featured) {
    const page = { p_before_at: cursor?.publishedAt ?? null, p_before_id: cursor?.id ?? null, p_limit: limit + 1 };
    const { data, error } = following
      ? await supabase.rpc("following_feed_ids", { p_type: type ?? null, ...page })
      : await supabase.rpc("featured_feed_ids", page);
    if (error) throw error;
    followingIds = ((data ?? []) as { id: string }[]).map((row) => row.id);
    if (!followingIds.length) return { posts: [], nextCursor: null };
  }

  let query = supabase
    .from("posts")
    .select(POST_COLUMNS)
    .eq("status", "published")
    .is("deleted_at", null)
    .order("published_at", { ascending: false })
    .order("id", { ascending: false })
    .order("position", { referencedTable: "post_media" })
    .limit(limit + 1);

  if (followingIds) query = query.in("id", followingIds);
  if (type) query = query.eq("type", type);
  if (businessId) query = query.eq("business_id", businessId);
  if (authorId) query = query.eq("author_id", authorId);
  if (personalOnly) query = query.is("business_id", null);
  if (cursor && !followingIds) {
    query = query.or(
      `published_at.lt."${cursor.publishedAt}",and(published_at.eq."${cursor.publishedAt}",id.lt.${cursor.id})`,
    );
  }

  const { data, error } = await query;
  if (error) throw error;

  const rows = (data ?? []) as unknown as Row[];
  const hasMore = followingIds ? followingIds.length > limit : rows.length > limit;
  const page = rows.slice(0, limit);
  const last = page[page.length - 1];
  return {
    posts: page.map(toPost).filter(isVisible),
    nextCursor: hasMore && last ? encodeCursor(last) : null,
  };
}

/** Publicación individual (pública, o del autor/equipo aunque esté oculta). */
export async function getPost(supabase: SupabaseClient, id: string): Promise<PostView | null> {
  const { data, error } = await supabase
    .from("posts")
    .select(POST_COLUMNS)
    .eq("id", id)
    .is("deleted_at", null)
    .order("position", { referencedTable: "post_media" })
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  const post = toPost(data as unknown as Row);
  return isVisible(post) || post.status !== "published" ? post : null;
}

/**
 * Varias publicaciones por id, en el mismo orden pedido (para "Guardados").
 * Las que ya no son visibles (ocultas, eliminadas) se omiten.
 */
export async function getPostsByIds(supabase: SupabaseClient, ids: string[]): Promise<PostView[]> {
  if (!ids.length) return [];
  const { data, error } = await supabase
    .from("posts")
    .select(POST_COLUMNS)
    .in("id", ids)
    .eq("status", "published")
    .is("deleted_at", null)
    .order("position", { referencedTable: "post_media" });
  if (error) throw error;
  const byId = new Map(((data ?? []) as unknown as Row[]).map((row) => [row.id, toPost(row)]));
  return ids.map((id) => byId.get(id)).filter((post): post is PostView => Boolean(post) && isVisible(post!));
}

/** Publicaciones que el usuario puede gestionar: propias o de sus emprendimientos. */
export async function getManageablePosts(
  supabase: SupabaseClient,
  userId: string,
  businessIds: string[],
  { cursor, limit = 30 }: { cursor?: Cursor | null; limit?: number } = {},
): Promise<{ posts: PostView[]; nextCursor: string | null }> {
  const owners = [`author_id.eq.${userId}`];
  if (businessIds.length) owners.push(`business_id.in.(${businessIds.join(",")})`);

  let query = supabase
    .from("posts")
    .select(POST_COLUMNS)
    .is("deleted_at", null)
    .or(owners.join(","))
    .order("published_at", { ascending: false })
    .order("id", { ascending: false })
    .order("position", { referencedTable: "post_media" })
    .limit(limit + 1);

  if (cursor) {
    query = query.or(
      `published_at.lt."${cursor.publishedAt}",and(published_at.eq."${cursor.publishedAt}",id.lt.${cursor.id})`,
    );
  }

  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as Row[];
  const page = rows.slice(0, limit);
  const last = page[page.length - 1];
  return { posts: page.map(toPost), nextCursor: rows.length > limit && last ? encodeCursor(last) : null };
}

/** Texto corto para URL y títulos: el título, o el comienzo del texto. */
export function postHeadline(post: Pick<PostView, "title" | "body">, max = 70): string {
  const text = (post.title || post.body).replace(/\s+/g, " ").trim();
  return text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;
}

export const POST_TYPE_LABELS: Record<PostType, { label: string; class: string }> = {
  offer: { label: "Ofrezco", class: "bg-offer-soft text-offer" },
  seeking: { label: "Busco", class: "bg-seek-soft text-seek" },
  product: { label: "Producto", class: "bg-success-soft text-success" },
  service: { label: "Servicio", class: "bg-surface-muted text-ink" },
  promotion: { label: "Promoción", class: "bg-warning-soft text-warning" },
};
