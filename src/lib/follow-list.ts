import type { AstroGlobal } from "astro";
import { getPublicProfile } from "../services/profiles";
import { profilePath } from "./urls";
import type { Profile } from "../types/domain";
import type { ProfileSituation } from "../services/posts";

export type FollowPerson = {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  headline: string | null;
  verified_at: string | null;
  situation: ProfileSituation | null;
};

export interface FollowListData {
  kind: "followers" | "following";
  profile: Profile;
  people: FollowPerson[];
  following: Set<string>;
  page: number;
  hasMore: boolean;
  base: string;
  self: string;
  viewerId: string;
}

const PAGE = 30;

/**
 * Seguidores / seguidos de /u/[usuario]. Solo con sesión: la base devuelve la
 * lista sin cuentas suspendidas ni personas bloqueadas (profile_follow_ids).
 * Devuelve una Response (redirección o 404) o los datos para mostrar.
 */
export async function loadFollowList(Astro: AstroGlobal, kind: "followers" | "following"): Promise<Response | FollowListData> {
  const { supabase, user } = Astro.locals;
  const username = (Astro.params.username ?? "").toLowerCase();
  if (!/^[a-z0-9_.]{3,30}$/.test(username)) return Astro.rewrite("/404");
  const base = profilePath(username);
  const self = `${base}/${kind === "followers" ? "seguidores" : "seguidos"}`;
  if (!user) return Astro.redirect(`/ingresar?next=${encodeURIComponent(self)}`);

  const profile = await getPublicProfile(supabase, username, { withContact: false });
  if (!profile) return Astro.rewrite("/404");

  const page = Math.max(1, Math.min(100, Number.parseInt(Astro.url.searchParams.get("pagina") ?? "1", 10) || 1));
  const { data: idRows, error } = await supabase.rpc("profile_follow_ids", {
    p_profile_id: profile.id,
    p_kind: kind,
    p_limit: PAGE + 1,
    p_offset: (page - 1) * PAGE,
  });
  if (error) throw error;
  const allIds = ((idRows ?? []) as { id: string }[]).map((r) => r.id);
  const ids = allIds.slice(0, PAGE);

  const [{ data: rows }, { data: mine }] = ids.length
    ? await Promise.all([
        supabase.from("profiles").select("id, username, first_name, last_name, avatar_path, headline, verified_at, situation").in("id", ids),
        supabase.from("profile_follows").select("followed_id").eq("follower_id", user.id).in("followed_id", ids),
      ])
    : [{ data: [] }, { data: [] }];
  const byId = new Map(((rows ?? []) as FollowPerson[]).map((p) => [p.id, p]));

  return {
    kind,
    profile,
    people: ids.map((id) => byId.get(id)).filter((p): p is FollowPerson => Boolean(p)),
    following: new Set(((mine ?? []) as { followed_id: string }[]).map((r) => r.followed_id)),
    page,
    hasMore: allIds.length > PAGE,
    base,
    self,
    viewerId: user.id,
  };
}
