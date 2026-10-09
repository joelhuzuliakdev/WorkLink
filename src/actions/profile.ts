import { ActionError, defineAction } from "astro:actions";
import { profileSchema } from "../schemas/profile";
import { dbError, requireUser } from "../lib/auth/guards";
import { isOwnMediaPath } from "../lib/media";
import { mediaExists, removeMedia } from "../services/storage";

export const profile = {
  update: defineAction({
    accept: "form",
    input: profileSchema,
    handler: async (input, { locals }) => {
      const user = requireUser(locals.user);
      const supabase = locals.supabase;

      if (input.avatar_path) {
        if (!isOwnMediaPath(input.avatar_path, user.id) || !(await mediaExists(supabase, "avatar", input.avatar_path))) {
          throw new ActionError({ code: "BAD_REQUEST", message: "La foto no se subió correctamente. Volvé a elegirla." });
        }
      }

      if (input.cover_path) {
        if (!isOwnMediaPath(input.cover_path, user.id) || !(await mediaExists(supabase, "cover", input.cover_path))) {
          throw new ActionError({ code: "BAD_REQUEST", message: "La portada no se subió correctamente. Volvé a elegirla." });
        }
      }

      const { data: current } = await supabase.from("profiles").select("avatar_path, cover_path").eq("id", user.id).single();

      const { error } = await supabase
        .from("profiles")
        .update({
          username: input.username,
          first_name: input.first_name,
          last_name: input.last_name,
          bio: input.bio ?? null,
          situation: input.situation ?? null,
          headline: input.headline ?? null,
          city_id: input.city_id ?? null,
          // La provincia la completa la base a partir de la ciudad.
          province_id: null,
          avatar_path: input.avatar_path ?? null,
          cover_path: input.cover_path ?? null,
          whatsapp: input.whatsapp ?? null,
          phone: input.phone ?? null,
          instagram: input.instagram ?? null,
          facebook: input.facebook ?? null,
          tiktok: input.tiktok ?? null,
          website: input.website ?? null,
        })
        .eq("id", user.id);

      if (error) {
        if (error.code === "23505") {
          throw new ActionError({ code: "CONFLICT", message: `El usuario @${input.username} ya está en uso. Elegí otro.` });
        }
        throw dbError(error, "No pudimos guardar tu perfil. Probá de nuevo.");
      }

      if (current?.avatar_path && current.avatar_path !== input.avatar_path) {
        await removeMedia(supabase, "avatar", current.avatar_path);
      }
      if (current?.cover_path && current.cover_path !== input.cover_path) {
        await removeMedia(supabase, "cover", current.cover_path);
      }

      return { saved: true, username: input.username };
    },
  }),
};
