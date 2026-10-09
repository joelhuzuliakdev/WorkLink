import type { APIRoute } from "astro";
import { getAdminPayments, PAYMENT_STATUS } from "../../../services/billing";

/**
 * Pagos de un mes en CSV (se abre con Excel): para el contador.
 * Solo administración: se revisa el rol en la base y RLS solo devuelve los
 * pagos a administración.
 */
export const GET: APIRoute = async ({ locals, url }) => {
  const { data: isAdmin } = await locals.supabase.rpc("has_role", { min_role: "admin" });
  if (isAdmin !== true) return new Response("Solo administración.", { status: 403 });

  const mes = /^\d{4}-\d{2}$/.test(url.searchParams.get("mes") ?? "") ? url.searchParams.get("mes")! : new Date().toISOString().slice(0, 7);
  const payments = await getAdminPayments(locals.supabase, mes);

  // Excel en español: separador ";" y coma decimal. Evita que una celda empiece con = + - @ (inyección de fórmulas).
  const safe = (v: string) => {
    const text = v.replace(/"/g, '""');
    return `"${/^[=+\-@]/.test(text) ? `'${text}` : text}"`;
  };
  const amount = (n: number) => n.toFixed(2).replace(".", ",");
  const lines = [
    ["Fecha", "Usuario", "Nombre", "Plan", "Estado", "Bruto", "Comisión MP", "Neto", "N.º pago Mercado Pago"].map(safe).join(";"),
    ...payments.map((p) =>
      [
        safe(new Date(p.paid_at ?? p.created_at).toLocaleString("es-AR", { timeZone: "America/Argentina/Cordoba" })),
        safe(p.user?.username ?? ""),
        safe([p.user?.first_name, p.user?.last_name].filter(Boolean).join(" ")),
        safe(p.plan?.name ?? p.plan_id),
        safe(PAYMENT_STATUS[p.status] ?? p.status),
        amount(p.amount),
        amount(p.fee),
        amount(p.net),
        safe(p.mp_payment_id),
      ].join(";"),
    ),
  ];
  return new Response("﻿" + lines.join("\r\n"), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="worklink-pagos-${mes}.csv"`,
      "Cache-Control": "private, no-store",
    },
  });
};
