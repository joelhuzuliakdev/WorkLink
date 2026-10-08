import type { APIRoute } from "astro";
import type { EmailOtpType } from "@supabase/supabase-js";
import { routes, safeNextPath } from "../../config/site";

const OTP_TYPES: EmailOtpType[] = ["signup", "email", "recovery", "invite", "magiclink", "email_change"];

/**
 * Destino de los enlaces de los emails de Supabase (confirmar cuenta,
 * recuperar contraseña). Abre la sesión y redirige a `next`.
 *
 * Acepta dos formatos:
 *  - ?token_hash=...&type=...  (plantillas de email personalizadas; funciona
 *    aunque el enlace se abra en otro dispositivo o navegador)
 *  - ?code=...                 (flujo PKCE por defecto de Supabase; requiere
 *    abrir el enlace en el mismo navegador donde se pidió)
 */
export const GET: APIRoute = async ({ url, locals, redirect }) => {
  const next = safeNextPath(url.searchParams.get("next"));
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type") as EmailOtpType | null;
  const code = url.searchParams.get("code");

  if (tokenHash && type && OTP_TYPES.includes(type)) {
    const { error } = await locals.supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) return redirect(type === "recovery" ? routes.resetPassword : next);
    console.error("[auth/confirm] verifyOtp", error.code, error.message);
  } else if (code) {
    const { error } = await locals.supabase.auth.exchangeCodeForSession(code);
    if (!error) return redirect(next);
    console.error("[auth/confirm] exchangeCode", error.code, error.message);
  }

  return redirect(`${routes.login}?error=link`);
};
