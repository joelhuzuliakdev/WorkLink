import type { PostMediaItem } from "../islands/PostMediaUploader";
import type { PostView } from "../services/posts";
import { mediaUrl, postFileUrl } from "./media";

/** Archivos guardados de una publicación, en el formato del componente de subida. */
export function mediaItemsFromPost(post: PostView): PostMediaItem[] {
  return post.media.map((m) => ({
    id: m.id,
    path: m.path,
    kind: m.kind,
    mime: m.mime,
    bytes: m.bytes,
    width: m.width ?? 1,
    height: m.height ?? 1,
    duration: m.duration_s ?? undefined,
    preview: m.kind === "image" ? (mediaUrl("post", m.path, 480) ?? "") : postFileUrl(m.path, "poster.webp"),
  }));
}

/** Archivos enviados en un formulario con error (para no perder lo subido). */
export function mediaItemsFromSubmitted(raw: FormDataEntryValue | null): PostMediaItem[] {
  if (typeof raw !== "string" || !raw) return [];
  try {
    const list = JSON.parse(raw) as Omit<PostMediaItem, "preview">[];
    if (!Array.isArray(list)) return [];
    return list.slice(0, 10).map((item) => ({
      ...item,
      preview: item.kind === "image" ? (mediaUrl("post", item.path, 480) ?? "") : postFileUrl(item.path, "poster.webp"),
    }));
  } catch {
    return [];
  }
}
