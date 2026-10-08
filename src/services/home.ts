import type { SupabaseClient } from "@supabase/supabase-js";
import { getFeed, type Cursor, type PostView } from "./posts";

/**
 * Feed del inicio para usuarios logueados:
 *  - "following": publicaciones de quienes sigue + las propias.
 *  - "featured":  si todavía no sigue a nadie, las de cuentas con plan pago.
 *  - "latest":    si no hay destacadas (o lo que sigue no publicó nada), lo
 *                 último publicado en WorkLink.
 * El modo se decide en la primera página y viaja en el enlace "Cargar más".
 */
export type HomeMode = "following" | "featured" | "latest";

export const HOME_MODES: HomeMode[] = ["following", "featured", "latest"];

export async function getHomeFeed(
  supabase: SupabaseClient,
  { followingCount, mode, cursor }: { followingCount: number; mode?: HomeMode | null; cursor?: Cursor | null },
): Promise<{ mode: HomeMode; posts: PostView[]; nextCursor: string | null }> {
  if (mode) {
    const page = await getFeed(supabase, { following: mode === "following", featured: mode === "featured", cursor });
    return { mode, ...page };
  }

  if (followingCount > 0) {
    const page = await getFeed(supabase, { following: true });
    if (page.posts.length) return { mode: "following", ...page };
  } else {
    const page = await getFeed(supabase, { featured: true });
    if (page.posts.length) return { mode: "featured", ...page };
  }
  return { mode: "latest", ...(await getFeed(supabase, {})) };
}
