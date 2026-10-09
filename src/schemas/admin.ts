import { z } from "astro/zod";
import { optionalText } from "./common";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export const moderateSchema = z.object({
  target_type: z.enum(["review", "post", "comment", "profile", "business", "need"]),
  target_id: z.string().regex(UUID),
  action: z.enum(["hide", "restore", "delete", "suspend", "reactivate", "verify", "unverify", "dismiss"]),
  note: optionalText(500, "La nota"),
});

export const setRoleSchema = z.object({
  user_id: z.string().regex(UUID),
  role: z.preprocess((v) => (v === "" ? null : v), z.enum(["moderator", "admin", "super_admin"]).nullable()),
});
