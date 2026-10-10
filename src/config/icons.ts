/**
 * Íconos de WorkLink (trazos de 24×24, estilo línea). Una sola fuente para
 * los componentes (.astro, con <Icon>) y para los scripts del navegador
 * (con iconSvg), así todo el sitio usa los mismos dibujos en vez de emojis,
 * que cambian según el celular.
 */
export const icons = {
  search: "M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13ZM20 20l-4.5-4.5",
  megaphone: "M4 10v4h3l5 4V6L7 10H4ZM16 9a4 4 0 0 1 0 6",
  chat: "M20 12a8 8 0 0 1-11.8 7L4 20l1.1-4A8 8 0 1 1 20 12Z",
  pin: "M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11ZM12 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z",
  calendar: "M4.5 6h15v14h-15zM4.5 10h15M8.5 3.5V7M15.5 3.5V7",
  paperclip: "M20 11.5 12 19.5a5 5 0 0 1-7-7L13.5 4a3.4 3.4 0 0 1 4.8 4.8L10 17.2a1.7 1.7 0 0 1-2.4-2.4L15 7.5",
  bell: "M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16ZM10 20.5h4",
  bellOff: "M8.7 5.7A6 6 0 0 1 18 11v4M6 11v5l-1.5 2H17M10 20.5h4M3.5 3.5l17 17",
  check: "m5 12.5 4.5 4.5L19 7.5",
  checkCircle: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM8 12.3l2.7 2.7L16.2 9.5",
  x: "M6 6l12 12M18 6 6 18",
  gear: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM19.4 13.5l1.6 1.2-2 3.4-1.9-.7a7.5 7.5 0 0 1-2.1 1.2L14.7 21h-4l-.3-2.4a7.5 7.5 0 0 1-2.1-1.2l-1.9.7-2-3.4 1.6-1.2a7.6 7.6 0 0 1 0-2.4L4.4 9.9l2-3.4 1.9.7a7.5 7.5 0 0 1 2.1-1.2L10.7 3h4l.3 2.4a7.5 7.5 0 0 1 2.1 1.2l1.9-.7 2 3.4-1.6 1.2a7.6 7.6 0 0 1 0 2.4Z",
  link: "M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1",
  phoneChat: "M20 12a8 8 0 0 1-11.8 7L4 20l1.1-4A8 8 0 1 1 20 12ZM9 9.2c0 3 2.8 5.8 5.8 5.8l1-1.6-1.9-.9-.8.8a4 4 0 0 1-2.4-2.4l.8-.8-.9-1.9L9 9.2Z",
  more: "M5 12h.01M12 12h.01M19 12h.01",
  camera: "M4 8h3.5L9 5.5h6L16.5 8H20v11H4zM12 16.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z",
  video: "M3.5 7h11v10h-11zM14.5 10.5 20.5 7v10l-6-3.5",
  heart: "M12 20s-7.5-4.6-7.5-10A4.5 4.5 0 0 1 12 7a4.5 4.5 0 0 1 7.5 3c0 5.4-7.5 10-7.5 10Z",
  plus: "M12 5v14M5 12h14",
  userPlus: "M10 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM3 20a7 7 0 0 1 11.5-5.4M18 14v6M15 17h6",
  star: "M12 3l2.6 5.6 6 .7-4.5 4.1 1.2 6L12 16.4l-5.3 3 1.2-6L3.4 9.3l6-.7z",
  alert: "M12 3.5 21.5 20h-19L12 3.5ZM12 10v4.5M12 17.2v.01",
  info: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 11v5.5M12 7.8v.01",
  shield: "M12 3 5 6v5c0 4.5 3 8.3 7 10 4-1.7 7-5.5 7-10V6l-7-3Z",
  user: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM4.5 20a7.5 7.5 0 0 1 15 0",
  lock: "M6 10.5h12V20H6zM8.5 10.5V7.5a3.5 3.5 0 0 1 7 0v3",
  mail: "M3.5 6h17v12h-17zM4 6.5l8 6.5 8-6.5",
  download: "M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19.5h14",
  trash: "M5 7h14M10 7V4.5h4V7M7 7l1 13h8l1-13M10.5 11v5.5M13.5 11v5.5",
  ban: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM5.6 5.6l12.8 12.8",
  logout: "M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10",
  devices: "M3.5 5h13v9h-13zM7 18h6M10 14v4M17 9h3.5v10H17z",
  share: "M12 15V4M8 7.5 12 3.5l4 4M5 12v7.5h14V12",
  sparkles: "M12 4l1.6 4.4L18 10l-4.4 1.6L12 16l-1.6-4.4L6 10l4.4-1.6zM18.5 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z",
  inbox: "M4 13.5 6.5 5h11l2.5 8.5V19H4zM4 13.5h4.5l1 2h5l1-2H20",
  key: "M14.5 9.5a4.5 4.5 0 1 0-3.2 4.3L13 15.5h2v2h2v2h3v-3l-5.8-5.8c.2-.4.3-.8.3-1.2ZM8 9.5h.01",
  chevronRight: "m9 6 6 6-6 6",
} as const;

export type IconName = keyof typeof icons;

/** SVG como texto, para los scripts del navegador. Solo usa datos propios (nunca texto de usuarios). */
export function iconSvg(name: IconName, className = "h-5 w-5"): string {
  return `<svg viewBox="0 0 24 24" class="${className} fill-none stroke-current stroke-2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="${icons[name]}"/></svg>`;
}
