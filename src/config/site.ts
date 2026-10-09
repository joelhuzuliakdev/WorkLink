/**
 * Configuración de rutas y navegación del sitio.
 */
export const routes = {
  home: "/",
  login: "/ingresar",
  signup: "/registrarse",
  forgotPassword: "/recuperar",
  resetPassword: "/cuenta/nueva-contrasena",
  authConfirm: "/auth/confirm",
  dashboard: "/panel",
  admin: "/admin",
} as const;

/**
 * Prefijos que requieren sesión. El middleware redirige al login si no hay
 * usuario, y vuelve a la página pedida después de ingresar.
 */
export const protectedPrefixes = ["/panel", "/cuenta", "/admin", "/notificaciones", "/mensajes", "/necesidades/nueva"] as const;

/** Prefijos que además requieren rol de staff (moderator o superior). */
export const staffPrefixes = ["/admin"] as const;

/**
 * Valida una ruta interna de redirección (?next=...). Evita redirecciones
 * abiertas a otros dominios ("//evil.com", "https://...").
 */
export function safeNextPath(value: string | null | undefined, fallback: string = routes.home): string {
  if (!value) return fallback;
  if (!value.startsWith("/") || value.startsWith("//") || value.startsWith("/\\")) return fallback;
  return value;
}
