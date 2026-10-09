/**
 * Sonidos de aviso (mensaje nuevo y notificación), generados con Web Audio:
 * no hace falta descargar archivos.
 *
 * Los navegadores no dejan sonar nada hasta que la persona toca la página una
 * vez; por eso el audio se "desbloquea" con el primer toque o tecla.
 * Se puede apagar desde Notificaciones (se guarda en este navegador).
 */
const KEY = "wl-sound";
let ctx: AudioContext | null = null;
let lastPlayed = 0;

export function soundEnabled(): boolean {
  try {
    return localStorage.getItem(KEY) !== "off";
  } catch {
    return true;
  }
}

export function setSoundEnabled(on: boolean) {
  try {
    localStorage.setItem(KEY, on ? "on" : "off");
  } catch {
    /* modo privado: se ignora */
  }
}

function context(): AudioContext | null {
  if (ctx) return ctx;
  const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return null;
  ctx = new Ctor();
  return ctx;
}

// Primer toque o tecla: habilita el audio para el resto de la visita.
const unlock = () => {
  const c = context();
  if (c && c.state === "suspended") void c.resume();
};
for (const type of ["pointerdown", "keydown", "touchstart"]) {
  window.addEventListener(type, unlock, { once: true, passive: true });
}

/** "message": dos notas ascendentes (estilo chat). "notification": una nota suave. */
export function playChime(kind: "message" | "notification" = "notification") {
  if (!soundEnabled()) return;
  const now = Date.now();
  if (now - lastPlayed < 1500) return; // no repetir si llegan varios juntos
  const c = context();
  if (!c || c.state !== "running") return;
  lastPlayed = now;
  const notes = kind === "message" ? [660, 990] : [880];
  notes.forEach((freq, i) => {
    const start = c.currentTime + i * 0.13;
    const osc = c.createOscillator();
    const gain = c.createGain();
    osc.type = "sine";
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(0.18, start + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.35);
    osc.connect(gain).connect(c.destination);
    osc.start(start);
    osc.stop(start + 0.4);
  });
}
