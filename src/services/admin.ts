import type { SupabaseClient } from "@supabase/supabase-js";
import { displayName } from "./profiles";
import { postHeadline } from "./posts";
import { needPath, postPath } from "../lib/urls";

/**
 * Panel de administración y denuncias. Todo pasa por RLS y por funciones de
 * la base que revisan el rol (moderate, admin_stats, admin_report_groups):
 * el frontend nunca decide permisos.
 */

export type TargetType = "review" | "post" | "comment" | "profile" | "business" | "need";

/** ?tipo= de /denunciar → tipo de la base. */
export const TARGET_FROM_PARAM: Record<string, TargetType | undefined> = {
  resena: "review",
  publicacion: "post",
  comentario: "comment",
  perfil: "profile",
  emprendimiento: "business",
  necesidad: "need",
};

export const TARGET_LABELS: Record<TargetType, string> = {
  review: "Reseña",
  post: "Publicación",
  comment: "Comentario",
  profile: "Perfil",
  business: "Emprendimiento",
  need: "Necesidad",
};

export const REASON_LABELS: Record<string, string> = {
  spam: "Spam",
  offensive: "Ofensivo",
  fake: "Falso",
  scam: "Estafa",
  other: "Otro",
};

export const ACTION_LABELS: Record<string, string> = {
  hide: "Ocultó / quitó",
  restore: "Restauró",
  delete: "Borró",
  suspend: "Suspendió",
  reactivate: "Reactivó",
  verify: "Verificó",
  unverify: "Quitó la verificación",
  dismiss: "Descartó la denuncia",
  role: "Cambió el rol",
};

export interface ModerationTarget {
  type: TargetType;
  id: string;
  title: string;
  excerpt: string | null;
  href: string;
  /** Estado tal como lo guarda la base (published, hidden, suspended...). */
  status: string;
  /** true si hoy no se ve públicamente. */
  hidden: boolean;
  ownerName: string | null;
  ownerUsername: string | null;
}

type Person = { username: string; first_name: string | null; last_name: string | null } | null;
const PERSON = "username, first_name, last_name";
const clip = (text: string | null | undefined, max = 220) => (text ? (text.length > max ? `${text.slice(0, max)}…` : text) : null);
const owner = (p: Person) => ({ ownerName: p ? displayName(p) : null, ownerUsername: p?.username ?? null });

/** Datos para mostrar varios contenidos del mismo tipo (vista previa en el panel). */
export async function getModerationTargets(supabase: SupabaseClient, type: TargetType, ids: string[]): Promise<Map<string, ModerationTarget>> {
  const out = new Map<string, ModerationTarget>();
  if (!ids.length) return out;
  const unique = [...new Set(ids)];

  if (type === "review") {
    const { data } = await supabase
      .from("reviews")
      .select(`id, rating, body, status, author:profiles!reviews_author_id_fkey ( ${PERSON} ), business:businesses ( slug, name ), subject:profiles!reviews_profile_id_fkey ( ${PERSON} )`)
      .in("id", unique);
    for (const r of (data ?? []) as unknown as {
      id: string;
      rating: number;
      body: string | null;
      status: string;
      author: Person;
      business: { slug: string; name: string } | null;
      subject: Person;
    }[]) {
      const about = r.business ? r.business.name : r.subject ? displayName(r.subject) : "—";
      const base = r.business ? `/e/${r.business.slug}/resenas` : r.subject ? `/u/${r.subject.username}/resenas` : "/";
      out.set(r.id, {
        type,
        id: r.id,
        title: `${"★".repeat(r.rating)}${"☆".repeat(5 - r.rating)} sobre ${about}`,
        excerpt: clip(r.body),
        href: `${base}#r-${r.id}`,
        status: r.status,
        hidden: r.status !== "published",
        ...owner(r.author),
      });
    }
  } else if (type === "post") {
    const { data } = await supabase.from("posts").select(`id, title, body, status, deleted_at, author:profiles!posts_author_id_fkey ( ${PERSON} )`).in("id", unique);
    for (const p of (data ?? []) as unknown as { id: string; title: string | null; body: string; status: string; deleted_at: string | null; author: Person }[]) {
      out.set(p.id, {
        type,
        id: p.id,
        title: postHeadline(p, 90),
        excerpt: p.title ? clip(p.body) : null,
        href: postPath(p),
        status: p.deleted_at ? "deleted" : p.status,
        hidden: Boolean(p.deleted_at) || p.status !== "published",
        ...owner(p.author),
      });
    }
  } else if (type === "comment") {
    const { data } = await supabase
      .from("post_comments")
      .select(`id, body, author:profiles!post_comments_author_id_fkey ( ${PERSON} ), post:posts ( id, title, body )`)
      .in("id", unique);
    for (const c of (data ?? []) as unknown as { id: string; body: string; author: Person; post: { id: string; title: string | null; body: string } | null }[]) {
      out.set(c.id, {
        type,
        id: c.id,
        title: c.post ? `En “${postHeadline(c.post, 60)}”` : "Comentario",
        excerpt: clip(c.body),
        href: c.post ? `${postPath(c.post)}#c-${c.id}` : "/",
        status: "published",
        hidden: false,
        ...owner(c.author),
      });
    }
  } else if (type === "profile") {
    const { data } = await supabase.from("profiles").select(`id, ${PERSON}, headline, bio, status`).in("id", unique);
    for (const p of (data ?? []) as unknown as { id: string; username: string; first_name: string | null; last_name: string | null; headline: string | null; bio: string | null; status: string }[]) {
      out.set(p.id, {
        type,
        id: p.id,
        title: `${displayName(p)} (@${p.username})`,
        excerpt: clip(p.headline ?? p.bio),
        href: `/u/${p.username}`,
        status: p.status,
        hidden: p.status !== "active",
        ownerName: displayName(p),
        ownerUsername: p.username,
      });
    }
  } else if (type === "business") {
    const { data } = await supabase
      .from("businesses")
      .select(`id, slug, name, tagline, status, verification, owner:profiles!businesses_owner_id_fkey ( ${PERSON} )`)
      .in("id", unique);
    for (const b of (data ?? []) as unknown as { id: string; slug: string; name: string; tagline: string | null; status: string; owner: Person }[]) {
      out.set(b.id, {
        type,
        id: b.id,
        title: b.name,
        excerpt: clip(b.tagline),
        href: `/e/${b.slug}`,
        status: b.status,
        hidden: b.status !== "active",
        ...owner(b.owner),
      });
    }
  } else if (type === "need") {
    const { data } = await supabase
      .from("needs")
      .select(`id, slug, title, description, status, deleted_at, author:profiles!needs_author_id_fkey ( ${PERSON} )`)
      .in("id", unique);
    for (const n of (data ?? []) as unknown as { id: string; slug: string; title: string; description: string; status: string; deleted_at: string | null; author: Person }[]) {
      out.set(n.id, {
        type,
        id: n.id,
        title: n.title,
        excerpt: clip(n.description),
        href: needPath(n),
        status: n.deleted_at ? "deleted" : n.status,
        hidden: Boolean(n.deleted_at),
        ...owner(n.author),
      });
    }
  }
  return out;
}

export async function getModerationTarget(supabase: SupabaseClient, type: TargetType, id: string): Promise<ModerationTarget | null> {
  return (await getModerationTargets(supabase, type, [id])).get(id) ?? null;
}

/** Varios tipos mezclados (denuncias e historial). */
export async function getTargetsMixed(supabase: SupabaseClient, items: { target_type: TargetType; target_id: string }[]) {
  const byType = new Map<TargetType, string[]>();
  for (const item of items) byType.set(item.target_type, [...(byType.get(item.target_type) ?? []), item.target_id]);
  const maps = await Promise.all([...byType.entries()].map(([type, ids]) => getModerationTargets(supabase, type, ids)));
  const all = new Map<string, ModerationTarget>();
  for (const map of maps) for (const [id, target] of map) all.set(`${target.type}:${id}`, target);
  return all;
}

export interface AdminStats {
  users: number;
  users_week: number;
  users_suspended: number;
  businesses: number;
  businesses_week: number;
  posts: number;
  posts_week: number;
  needs_open: number;
  needs_awarded: number;
  proposals_week: number;
  messages_week: number;
  reviews: number;
  reports_open: number;
  reviews_hidden: number;
}

export async function getAdminStats(supabase: SupabaseClient): Promise<AdminStats | null> {
  const { data, error } = await supabase.rpc("admin_stats");
  if (error) {
    console.error("[admin]", error.message);
    return null;
  }
  return data as AdminStats;
}

export interface ReportGroup {
  target_type: TargetType;
  target_id: string;
  reports: number;
  reasons: string[];
  details: string[] | null;
  last_at: string;
  target: ModerationTarget | null;
}

export async function getReportGroups(supabase: SupabaseClient, status: "open" | "resolved" | "dismissed" = "open", limit = 50): Promise<ReportGroup[]> {
  const { data, error } = await supabase.rpc("admin_report_groups", { p_status: status, p_limit: limit });
  if (error) throw error;
  const groups = (data ?? []) as Omit<ReportGroup, "target">[];
  const targets = await getTargetsMixed(supabase, groups);
  return groups.map((g) => ({ ...g, target: targets.get(`${g.target_type}:${g.target_id}`) ?? null }));
}

export interface ModerationLogEntry {
  id: string;
  target_type: TargetType;
  target_id: string;
  action: string;
  note: string | null;
  created_at: string;
  moderator: Person;
  target: ModerationTarget | null;
}

export async function getModerationLog(supabase: SupabaseClient, limit = 50): Promise<ModerationLogEntry[]> {
  const { data, error } = await supabase
    .from("moderation_actions")
    .select(`id, target_type, target_id, action, note, created_at, moderator:profiles!moderation_actions_moderator_id_fkey ( ${PERSON} )`)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  const rows = (data ?? []) as unknown as Omit<ModerationLogEntry, "target">[];
  const targets = await getTargetsMixed(supabase, rows);
  return rows.map((r) => ({ ...r, target: targets.get(`${r.target_type}:${r.target_id}`) ?? null }));
}

export interface AdminUser {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  status: "active" | "suspended" | "banned";
  verified_at: string | null;
  created_at: string;
  followers_count: number;
  role: "moderator" | "admin" | "super_admin" | null;
}

/** Busca cuentas por usuario o nombre (o las últimas registradas). */
export async function searchUsers(
  supabase: SupabaseClient,
  { q, status }: { q: string; status: "all" | "active" | "suspended" | "staff" },
): Promise<AdminUser[]> {
  let query = supabase
    .from("profiles")
    .select("id, username, first_name, last_name, avatar_path, status, verified_at, created_at, followers_count")
    .order("created_at", { ascending: false })
    .limit(50);
  const term = q.replace(/[%_,()*\\]/g, " ").trim();
  if (term) query = query.or(`username.ilike.%${term}%,first_name.ilike.%${term}%,last_name.ilike.%${term}%`);
  if (status === "active") query = query.eq("status", "active");
  if (status === "suspended") query = query.neq("status", "active");

  const [{ data, error }, roles] = await Promise.all([query, supabase.from("user_roles").select("user_id, role")]);
  if (error) throw error;
  // user_roles: el equipo ve todos los roles (RLS).
  const roleOf = new Map(((roles.data ?? []) as { user_id: string; role: AdminUser["role"] }[]).map((r) => [r.user_id, r.role]));
  let users = ((data ?? []) as Omit<AdminUser, "role">[]).map((u) => ({ ...u, role: roleOf.get(u.id) ?? null }));
  if (status === "staff") {
    const staffIds = [...roleOf.keys()];
    if (!term) {
      const { data: staff } = await supabase
        .from("profiles")
        .select("id, username, first_name, last_name, avatar_path, status, verified_at, created_at, followers_count")
        .in("id", staffIds.length ? staffIds : ["00000000-0000-0000-0000-000000000000"]);
      users = ((staff ?? []) as Omit<AdminUser, "role">[]).map((u) => ({ ...u, role: roleOf.get(u.id) ?? null }));
    } else {
      users = users.filter((u) => u.role);
    }
  }
  return users;
}

export interface AdminBusiness {
  id: string;
  slug: string;
  name: string;
  logo_path: string | null;
  status: "draft" | "active" | "inactive" | "suspended";
  verification: string;
  created_at: string;
  followers_count: number;
  rating_sum: number;
  rating_count: number;
  owner: Person;
  category: { name: string } | null;
  city: { name: string } | null;
}

export async function searchAdminBusinesses(
  supabase: SupabaseClient,
  { q, status }: { q: string; status: "all" | "active" | "suspended" | "pending" },
): Promise<AdminBusiness[]> {
  let query = supabase
    .from("businesses")
    .select(
      `id, slug, name, logo_path, status, verification, created_at, followers_count, rating_sum, rating_count,
       owner:profiles!businesses_owner_id_fkey ( ${PERSON} ), category:categories ( name ), city:cities ( name )`,
    )
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(50);
  const term = q.replace(/[%_,()*\\]/g, " ").trim();
  if (term) query = query.ilike("name", `%${term}%`);
  if (status === "active") query = query.eq("status", "active");
  if (status === "suspended") query = query.eq("status", "suspended");
  if (status === "pending") query = query.eq("verification", "pending");
  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as unknown as AdminBusiness[];
}
