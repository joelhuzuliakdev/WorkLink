import type { APIRoute } from "astro";
import { skipCookie } from "../../lib/onboarding";

/** "No mostrar más" los primeros pasos (se recuerda un año en este navegador). */
export const POST: APIRoute = async ({ locals, cookies, redirect }) => {
  if (!locals.user) return redirect("/ingresar");
  cookies.set(skipCookie(locals.user.id), "listo", {
    path: "/",
    maxAge: 60 * 60 * 24 * 365,
    httpOnly: true,
    sameSite: "lax",
    secure: import.meta.env.PROD,
  });
  return redirect("/panel/publicaciones", 303);
};
