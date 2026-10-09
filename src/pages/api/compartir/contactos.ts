import type { APIRoute } from "astro";
import { getConversations } from "../../../services/messages";
import { displayName } from "../../../services/profiles";
import { mediaUrl } from "../../../lib/media";

/**
 * Personas para compartir una publicación por mensaje: primero con quienes
 * hablaste hace poco y a quienes seguís; con ?q= busca también por nombre.
 * Solo con sesión; la base no devuelve cuentas suspendidas.
 */
type Person = { id: string; username: string; first_name: string | null; last_name: string | null; avatar_path: string | null; verified_at: string | null };
const COLUMNS = "id, username, first_name, last_name, avatar_path, verified_at";

export const GET: APIRoute = async ({ locals, url }) => {
  const { supabase, user } = locals;
  if (!user) return Response.json({ error: "Ingresá para compartir." }, { status: 401 });
  const q = (url.searchParams.get("q") ?? "").replace(/\s+/g, " ").trim().slice(0, 60);

  const people = new Map<string, Person>();
  if (q.length >= 2) {
    const { data } = await supabase.rpc("search_profile_ids", { p_query: q, p_city_id: null, p_situation: null, p_limit: 20, p_offset: 0 });
    const ids = ((data ?? []) as { id: string }[]).map((r) => r.id).filter((id) => id !== user.id);
    if (ids.length) {
      const { data: rows } = await supabase.from("profiles").select(COLUMNS).in("id", ids);
      const byId = new Map(((rows ?? []) as Person[]).map((p) => [p.id, p]));
      for (const id of ids) if (byId.get(id)) people.set(id, byId.get(id)!);
    }
  } else {
    const [conversations, { data: follows }] = await Promise.all([
      getConversations(supabase, user.id, 15),
      supabase.from("profile_follows").select("followed_id").eq("follower_id", user.id).order("created_at", { ascending: false }).limit(40),
    ]);
    for (const c of conversations) if (c.other) people.set(c.other.id, { ...c.other, verified_at: c.other.verified_at });
    const ids = ((follows ?? []) as { followed_id: string }[]).map((f) => f.followed_id).filter((id) => !people.has(id));
    if (ids.length) {
      const { data: rows } = await supabase.from("profiles").select(COLUMNS).in("id", ids).eq("status", "active");
      for (const p of (rows ?? []) as Person[]) people.set(p.id, p);
    }
  }

  return Response.json(
    {
      people: [...people.values()].slice(0, 30).map((p) => ({
        username: p.username,
        name: displayName(p),
        avatar: mediaUrl("avatar", p.avatar_path, 96),
        initials: displayName(p).split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase(),
        verified: Boolean(p.verified_at),
      })),
    },
    { headers: { "Cache-Control": "private, no-store" } },
  );
};
