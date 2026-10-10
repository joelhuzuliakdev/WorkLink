import nodemailer, { type Transporter } from "nodemailer";
import { getSecret } from "astro:env/server";
import { PUBLIC_SITE_URL } from "astro:env/client";
import { brand } from "../config/brand";

/**
 * Envío de emails propios de WorkLink (no los de Supabase Auth, que se
 * configuran en el panel de Supabase): el código del botón de arrepentimiento
 * y los avisos al equipo.
 *
 * Usa SMTP (por ejemplo Gmail con una "contraseña de aplicación"). Si no está
 * configurado, no manda nada y devuelve false: la web sigue funcionando.
 * Los textos que vienen de usuarios se escapan siempre antes de ir al HTML.
 */

let transporter: Transporter | null = null;

export const isEmailConfigured = () => Boolean(getSecret("SMTP_HOST") && getSecret("SMTP_USER") && getSecret("SMTP_PASS"));

function getTransporter(): Transporter | null {
  if (!isEmailConfigured()) return null;
  if (transporter) return transporter;
  const port = Number(getSecret("SMTP_PORT") || 465);
  transporter = nodemailer.createTransport({
    host: getSecret("SMTP_HOST"),
    port,
    secure: port === 465,
    auth: { user: getSecret("SMTP_USER"), pass: getSecret("SMTP_PASS") },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
  });
  return transporter;
}

export const escapeHtml = (value: string) =>
  value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

/** Arma un email simple con la marca. `paragraphs` ya vienen escapados (usar escapeHtml). */
export function layout(title: string, paragraphs: string[], button?: { href: string; label: string }): string {
  const site = PUBLIC_SITE_URL.replace(/\/$/, "");
  return `<!doctype html><html lang="es"><body style="margin:0;background:#f6f6f3;font-family:Arial,Helvetica,sans-serif;color:#15171f">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f6f6f3;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border:1px solid #e4e4df;border-radius:16px">
<tr><td style="padding:24px 28px 8px"><a href="${site}" style="font-size:22px;font-weight:700;color:#2f4fd8;text-decoration:none">${brand.name}</a></td></tr>
<tr><td style="padding:8px 28px 24px">
<h1 style="font-size:20px;margin:8px 0 12px">${escapeHtml(title)}</h1>
${paragraphs.map((p) => `<p style="font-size:15px;line-height:1.55;margin:0 0 12px">${p}</p>`).join("\n")}
${button ? `<p style="margin:20px 0 8px"><a href="${button.href}" style="display:inline-block;background:#2f4fd8;color:#ffffff;text-decoration:none;font-weight:700;padding:12px 20px;border-radius:10px">${escapeHtml(button.label)}</a></p>` : ""}
</td></tr></table>
<p style="font-size:12px;color:#5b5f6e;margin:16px 0 0">${brand.name} · ${escapeHtml(brand.tagline)}</p>
</td></tr></table></body></html>`;
}

/** Manda un email. Nunca tira error hacia afuera: si falla, lo registra y devuelve false. */
export async function sendEmail(input: { to: string | string[]; subject: string; html: string; text: string; replyTo?: string }): Promise<boolean> {
  const t = getTransporter();
  if (!t) return false;
  try {
    await t.sendMail({
      from: { name: brand.name, address: getSecret("SMTP_USER")! },
      to: input.to,
      subject: input.subject,
      html: input.html,
      text: input.text,
      replyTo: input.replyTo,
    });
    return true;
  } catch (error) {
    console.error("[email] no se pudo enviar", input.subject, error instanceof Error ? error.message : error);
    return false;
  }
}
