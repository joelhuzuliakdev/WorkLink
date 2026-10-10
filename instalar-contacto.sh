#!/usr/bin/env bash
# WorkLink · titulares y email de contacto (Términos, Privacidad, pie de página y Cómo funciona)
# Uso (en la carpeta del proyecto): bash instalar-contacto.sh
set -euo pipefail
if [ ! -f package.json ] || [ ! -d src ]; then echo "ERROR: ejecutá este script desde la carpeta raíz de WorkLink."; exit 1; fi

cat > 'src/config/legal.ts' << '__WORKLINK_FIN_DEL_ARCHIVO__'
/**
 * Datos legales que aparecen en Términos y Privacidad.
 * Si arman una empresa (por ejemplo una SAS), cambiar `owner` por su nombre y CUIT.
 */
export const legal = {
  /** Nombre (o razón social) de quien es responsable de WorkLink. */
  owner: "Joel Huzuliak y Paula Osella",
  /** Email para consultas, reclamos y pedidos sobre datos personales. Vacío = no se muestra. */
  contactEmail: "worklinkcontacto@gmail.com",
  /** Jurisdicción para conflictos. */
  jurisdiction: "los tribunales ordinarios de la ciudad de Córdoba, Provincia de Córdoba",
  /** Fecha de la última actualización de los textos. */
  updatedAt: "10 de octubre de 2026",
};
__WORKLINK_FIN_DEL_ARCHIVO__
echo "  ✓ src/config/legal.ts"

cat > 'src/pages/privacidad.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/** Política de privacidad (Ley 25.326 de Protección de Datos Personales). */
import LegalPage from "../components/layout/LegalPage.astro";
import { legal } from "../config/legal";

const sections = [
  { id: "responsable", title: "Quién es responsable" },
  { id: "datos", title: "Qué datos usamos" },
  { id: "para-que", title: "Para qué los usamos" },
  { id: "quien-ve", title: "Quién ve tus datos" },
  { id: "verificacion", title: "DNI y selfie" },
  { id: "terceros", title: "Servicios que usamos" },
  { id: "cookies", title: "Cookies" },
  { id: "conservacion", title: "Cuánto tiempo los guardamos" },
  { id: "seguridad", title: "Seguridad" },
  { id: "derechos", title: "Tus derechos" },
  { id: "menores", title: "Menores de edad" },
  { id: "cambios", title: "Cambios" },
];
const contact = legal.contactEmail ? `escribiendo a ${legal.contactEmail}` : "desde los canales de contacto publicados en el sitio";
---

<LegalPage
  title="Política de privacidad"
  description="Qué datos personales usa WorkLink, para qué, quién los ve y cómo ejercer tus derechos (Ley 25.326)."
  sections={sections}
>
  <p>
    En WorkLink cuidamos tus datos. Esta política explica qué información usamos, para qué y qué derechos tenés, de acuerdo con la
    Ley 25.326 de Protección de Datos Personales de la República Argentina.
  </p>

  <section>
    <h2 id="responsable">1. Quién es responsable</h2>
    <p>
      Los responsables de la base de datos son {legal.owner}, titulares de WorkLink. Para cualquier consulta sobre tus datos, contactanos {contact}.
    </p>
  </section>

  <section>
    <h2 id="datos">2. Qué datos usamos</h2>
    <ul>
      <li><strong>De tu cuenta:</strong> nombre, apellido, email y contraseña (guardada cifrada; nunca la vemos). Si entrás con Google, recibimos tu nombre y tu email.</li>
      <li><strong>De tu perfil:</strong> lo que elijas completar: foto, descripción, ciudad, situación laboral, redes sociales, WhatsApp y teléfono.</li>
      <li><strong>Lo que publicás:</strong> publicaciones, fotos, videos, comentarios, reseñas, necesidades, propuestas y páginas de emprendimiento.</li>
      <li><strong>Mensajes privados:</strong> los guardamos para que puedas leerlos; solo los ven las dos personas de la conversación.</li>
      <li><strong>Actividad:</strong> a quién seguís, qué guardás, me gusta, denuncias y avisos.</li>
      <li><strong>Pagos:</strong> si contratás un plan, el plan, los montos, las fechas y el email de tu cuenta de Mercado Pago. No recibimos ni guardamos datos de tarjetas.</li>
      <li><strong>Verificación:</strong> si la pedís, una foto de tu DNI y una selfie (ver punto 5).</li>
      <li><strong>Datos técnicos:</strong> los que el servidor necesita para funcionar y protegerse (por ejemplo, la dirección IP y el tipo de navegador).</li>
    </ul>
  </section>

  <section>
    <h2 id="para-que">3. Para qué los usamos</h2>
    <ul>
      <li>Darte el servicio: mostrar tu perfil y tus publicaciones, conectarte con otras personas y enviarte avisos.</li>
      <li>Cobrar los planes que contrates y darte sus beneficios.</li>
      <li>Verificar identidades cuando se pide la tilde azul.</li>
      <li>Cuidar la comunidad: prevenir fraudes, revisar denuncias y hacer cumplir los <a href="/terminos">términos</a>.</li>
      <li>Mejorar WorkLink con estadísticas generales que no te identifican.</li>
    </ul>
    <p>No vendemos tus datos ni los usamos para publicidad de terceros.</p>
  </section>

  <section>
    <h2 id="quien-ve">4. Quién ve tus datos</h2>
    <ul>
      <li><strong>Cualquier persona (y buscadores como Google):</strong> las páginas de emprendimiento, las publicaciones y las necesidades.</li>
      <li><strong>Personas con cuenta:</strong> tu perfil, tu WhatsApp y tu teléfono si los cargaste. Los visitantes sin cuenta y los buscadores no los ven.</li>
      <li><strong>Solo vos y la otra persona:</strong> los mensajes privados y las propuestas de Necesidades (las ven quien la mandó y quien publicó la necesidad).</li>
      <li><strong>El equipo de WorkLink:</strong> puede ver el contenido denunciado para moderarlo. Solo la administración ve los pagos y los documentos de verificación.</li>
    </ul>
  </section>

  <section>
    <h2 id="verificacion">5. DNI y selfie</h2>
    <p>
      Las fotos de tu DNI y tu selfie se usan <strong>solo</strong> para verificar tu identidad. Se guardan en un espacio privado, al que solo
      acceden vos y la administración de WorkLink, y las fotos se procesan en tu dispositivo antes de subirse para quitarles los datos ocultos
      (como la ubicación). No las mostramos a nadie más ni las usamos para otra cosa. Podés pedirnos que las borremos cuando quieras (en ese
      caso se quita también la verificación); si borrás tu cuenta, se borran solas.
    </p>
  </section>

  <section>
    <h2 id="terceros">6. Servicios que usamos</h2>
    <p>Para funcionar, WorkLink usa proveedores que tratan datos por cuenta nuestra y con medidas de seguridad:</p>
    <ul>
      <li><strong>Supabase</strong>: base de datos, cuentas y archivos.</li>
      <li><strong>Vercel</strong>: alojamiento del sitio.</li>
      <li><strong>Mercado Pago</strong>: cobro de los planes (con su propia política de privacidad).</li>
      <li><strong>Google</strong>: solo si elegís ingresar con tu cuenta de Google.</li>
    </ul>
    <p>
      Algunos de estos servidores pueden estar fuera de la Argentina. Al usar WorkLink aceptás esa transferencia internacional, que se hace
      con proveedores que ofrecen niveles adecuados de protección.
    </p>
  </section>

  <section>
    <h2 id="cookies">7. Cookies</h2>
    <p>
      Usamos solo las cookies necesarias para mantener tu sesión iniciada y recordar algunas preferencias (por ejemplo, el sonido de los avisos).
      No usamos cookies de publicidad ni de seguimiento de terceros.
    </p>
  </section>

  <section>
    <h2 id="conservacion">8. Cuánto tiempo los guardamos</h2>
    <p>
      Guardamos tus datos mientras tengas la cuenta. Podés borrarla cuando quieras desde Configuración. Si la borrás, eliminamos tus datos personales, salvo los que la ley nos obligue a conservar
      (por ejemplo, los registros de pagos por razones contables e impositivas). Los avisos leídos se borran solos a los 90 días.
    </p>
  </section>

  <section>
    <h2 id="seguridad">9. Seguridad</h2>
    <p>
      Usamos conexiones cifradas, contraseñas cifradas, permisos por persona en la base de datos y accesos restringidos para el equipo. Ningún
      sistema es 100% infalible: si detectamos un incidente que afecte tus datos, te lo vamos a informar.
    </p>
  </section>

  <section>
    <h2 id="derechos">10. Tus derechos</h2>
    <p>
      Podés pedir en cualquier momento <strong>acceder</strong> a tus datos, <strong>corregirlos</strong>, <strong>actualizarlos</strong> o
      <strong>suprimirlos</strong>. La mayoría los podés cambiar vos mismo desde “Editar perfil”, y en “Configuración” (en el menú de tu foto) podés descargar una copia de tus datos o borrar tu cuenta. Para el resto, contactanos {contact}: respondemos los
      pedidos de acceso dentro de los 10 días corridos y los de corrección o supresión dentro de los 5 días hábiles, como indica la Ley 25.326.
    </p>
    <p class="rounded-wl border border-line bg-surface p-4 text-sm">
      La AGENCIA DE ACCESO A LA INFORMACIÓN PÚBLICA, en su carácter de Órgano de Control de la Ley N° 25.326, tiene la atribución de atender
      las denuncias y reclamos que interpongan quienes resulten afectados en sus derechos por incumplimiento de las normas vigentes en materia
      de protección de datos personales.
    </p>
  </section>

  <section>
    <h2 id="menores">11. Menores de edad</h2>
    <p>WorkLink es para mayores de 18 años. Si detectamos una cuenta de un menor, la damos de baja.</p>
  </section>

  <section>
    <h2 id="cambios">12. Cambios</h2>
    <p>Si cambiamos esta política de forma importante, te avisamos dentro de WorkLink antes de que se aplique.</p>
  </section>
</LegalPage>
__WORKLINK_FIN_DEL_ARCHIVO__
echo "  ✓ src/pages/privacidad.astro"

cat > 'src/components/layout/Footer.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
import Logo from "../brand/Logo.astro";
import { brand } from "../../config/brand";
import { legal } from "../../config/legal";

const year = new Date().getFullYear();
const links = [
  { href: "/como-funciona", label: "Cómo funciona" },
  { href: "/rubros", label: "Rubros" },
  { href: "/publicaciones", label: "Publicaciones" },
  { href: "/necesidades", label: "Necesidades" },
  { href: "/planes", label: "Planes" },
  { href: "/buscar", label: "Buscar" },
  { href: "/terminos", label: "Términos" },
  { href: "/privacidad", label: "Privacidad" },
  ...(legal.contactEmail ? [{ href: `mailto:${legal.contactEmail}`, label: "Contacto" }] : []),
];
---

<footer class="mt-auto border-t border-line">
  <div class="mx-auto flex max-w-6xl flex-col gap-4 px-4 py-8 text-sm text-ink-muted">
    <nav aria-label="Pie de página">
      <ul class="flex flex-wrap gap-x-5 gap-y-2">
        {links.map((link) => <li><a href={link.href} class="hover:text-ink hover:underline">{link.label}</a></li>)}
      </ul>
    </nav>
    <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex items-center gap-3">
        <Logo variant="mark" />
        <p>{brand.tagline}.</p>
      </div>
      <p>© {year} {brand.name}. Todos los derechos reservados.</p>
    </div>
  </div>
</footer>
__WORKLINK_FIN_DEL_ARCHIVO__
echo "  ✓ src/components/layout/Footer.astro"

cat > 'src/pages/como-funciona.astro' << '__WORKLINK_FIN_DEL_ARCHIVO__'
---
/**
 * Cómo funciona WorkLink: los usos principales explicados en pasos simples.
 * Página pública e indexable (ayuda a entender la plataforma antes de entrar).
 */
import BaseLayout from "../layouts/BaseLayout.astro";
import Button from "../components/ui/Button.astro";
import { routes } from "../config/site";
import { legal } from "../config/legal";

const { user } = Astro.locals;

const guides = [
  {
    id: "buscar",
    title: "Encontrar a quien necesitás",
    who: "Para quien busca un servicio o un producto",
    tone: "bg-seek-soft text-seek",
    d: "M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13ZM20 20l-4.5-4.5",
    steps: [
      { t: "Buscá", x: "Escribí lo que necesitás en el buscador (por ejemplo “electricista”) y elegí tu ciudad. También podés recorrer los rubros." },
      { t: "Compará", x: "Mirá las páginas de los emprendimientos: catálogo, fotos, horarios y las reseñas de otros clientes." },
      { t: "Hablá directo", x: "Escribile por mensaje privado o por WhatsApp. El trato lo arreglan entre ustedes." },
    ],
    cta: { href: "/buscar", label: "Ir al buscador" },
  },
  {
    id: "presupuestos",
    title: "Pedir presupuestos (Necesidades)",
    who: "Para quien quiere que lo contacten con precios",
    tone: "bg-seek-soft text-seek",
    d: "M9 4h6v3H9zM6 5.5H5V21h14V5.5h-1M9 12h6M9 16h4",
    steps: [
      { t: "Contá qué necesitás", x: "Publicá una necesidad: qué, en qué ciudad, para cuándo y, si querés, tu presupuesto." },
      { t: "Recibí propuestas", x: "Los emprendimientos de ese rubro en tu ciudad reciben un aviso y te mandan su propuesta con precio. Solo vos las ves." },
      { t: "Elegí una", x: "Compará precio, disponibilidad y reseñas. Al aceptar una, se abre el chat con esa persona para coordinar." },
    ],
    cta: { href: "/necesidades/nueva", label: "Publicar una necesidad" },
  },
  {
    id: "ofrecer",
    title: "Ofrecer lo tuyo",
    who: "Para quien trabaja por su cuenta o tiene un oficio",
    tone: "bg-offer-soft text-offer",
    d: "M4 10v4h3l5 4V6L7 10H4ZM16 9a4 4 0 0 1 0 6",
    steps: [
      { t: "Completá tu perfil", x: "Foto, descripción de lo que hacés, tu ciudad y un teléfono. Así te encuentran y te tienen confianza." },
      { t: "Publicá", x: "Mostrá tus trabajos con fotos o video. Lo ven quienes te siguen y aparece en el buscador." },
      { t: "Respondé necesidades", x: "En Necesidades ves lo que la gente está buscando en tu zona. Mandá tu propuesta con precio y ganá clientes." },
    ],
    cta: { href: "/publicar", label: "Publicar algo" },
  },
  {
    id: "emprendimiento",
    title: "La página de tu emprendimiento",
    who: "Para negocios y emprendimientos",
    tone: "bg-success-soft text-success",
    d: "M4 9.5 5.5 4h13L20 9.5M4 9.5h16M4 9.5V20h16V9.5M9.5 20v-5h5v5",
    steps: [
      { t: "Creala gratis", x: "Logo, portada, descripción, rubro, horarios, WhatsApp y redes. Es como una página de Facebook de tu negocio." },
      { t: "Cargá tu catálogo", x: "Productos y servicios con foto y precio. Podés publicar en nombre de la página y la gente la puede seguir." },
      { t: "Juntá reseñas", x: "Quienes te contraten o hablen con vos por WorkLink pueden dejarte estrellas. Las buenas reseñas te hacen aparecer mejor." },
    ],
    cta: { href: "/panel/emprendimientos/nuevo", label: "Crear mi emprendimiento" },
  },
  {
    id: "planes",
    title: "Destacarte y verificarte (opcional)",
    who: "Para quien quiere más visibilidad",
    tone: "bg-warning-soft text-warning",
    d: "M12 3l2.6 5.6 6 .7-4.5 4.1 1.2 6L12 16.4l-5.3 3 1.2-6L3.4 9.3l6-.7z",
    steps: [
      { t: "Destacado", x: "Tus publicaciones aparecen en “Destacados” y salís primero en el buscador." },
      { t: "Emprendimiento Pro", x: "Tu emprendimiento sale primero en su rubro y ciudad, con insignia PRO y verificación incluida." },
      { t: "Verificación", x: "La tilde azul: revisamos tu DNI y una selfie para confirmar que sos quien decís ser." },
    ],
    cta: { href: "/planes", label: "Ver planes y precios" },
  },
];

const tips = [
  { t: "Mensajes privados", x: "Hablá con cualquier persona sin compartir tu número. Te avisamos con un sonido cuando te escriben." },
  { t: "Seguir", x: "Seguí personas y emprendimientos para ver lo que publican en tu inicio." },
  { t: "Guardados", x: "Guardá publicaciones para verlas después: están en el menú de tu foto → Guardados." },
  { t: "Denunciar", x: "Si ves algo que no corresponde, tocá “Denunciar”. El equipo de WorkLink lo revisa." },
  { t: "Bloquear", x: "Si alguien te molesta, entrá a su perfil y tocá “Bloquear”: no va a poder escribirte ni comentar lo tuyo." },
  { t: "Tu cuenta", x: "En el menú de tu foto → Configuración cambiás tu email o contraseña, descargás tus datos o borrás tu cuenta." },
  ...(legal.contactEmail ? [{ t: "¿Necesitás ayuda?", x: `Escribinos a ${legal.contactEmail} y te respondemos.` }] : []),
];
---

<BaseLayout title="Cómo funciona" description="Cómo usar WorkLink: buscar a quien necesitás, pedir presupuestos, ofrecer tus servicios, crear la página de tu emprendimiento y destacarte.">
  <section class="mx-auto max-w-5xl px-4 py-10 sm:py-14">
    <div class="max-w-2xl">
      <h1 class="text-3xl font-bold tracking-tight sm:text-4xl">Cómo funciona WorkLink</h1>
      <p class="mt-3 text-lg text-ink-muted">
        WorkLink conecta a quienes necesitan algo con quienes lo ofrecen, en su ciudad. Elegí lo que querés hacer:
      </p>
    </div>

    <nav aria-label="Guías" class="mt-6 flex flex-wrap gap-2">
      {guides.map((g) => <a href={`#${g.id}`} class="rounded-full border border-line bg-surface px-3 py-1.5 text-sm font-medium hover:border-brand">{g.title}</a>)}
    </nav>

    <div class="mt-10 flex flex-col gap-8">
      {
        guides.map((g) => (
          <section id={g.id} class="scroll-mt-20 rounded-wl-lg border border-line bg-surface p-5 sm:p-8" aria-labelledby={`${g.id}-t`}>
            <div class="flex items-start gap-4">
              <span class:list={["grid h-12 w-12 shrink-0 place-items-center rounded-full", g.tone]} aria-hidden="true">
                <svg viewBox="0 0 24 24" class="h-6 w-6 fill-none stroke-current stroke-2"><path stroke-linecap="round" stroke-linejoin="round" d={g.d} /></svg>
              </span>
              <div>
                <h2 id={`${g.id}-t`} class="text-xl font-bold sm:text-2xl">{g.title}</h2>
                <p class="text-ink-muted">{g.who}</p>
              </div>
            </div>
            <ol class="mt-6 grid gap-4 sm:grid-cols-3">
              {g.steps.map((s, i) => (
                <li class="rounded-wl border border-line p-4">
                  <span class="grid h-8 w-8 place-items-center rounded-full bg-brand text-sm font-bold text-brand-contrast" aria-hidden="true">{i + 1}</span>
                  <h3 class="mt-3 font-semibold">{s.t}</h3>
                  <p class="mt-1 text-sm text-ink-muted">{s.x}</p>
                </li>
              ))}
            </ol>
            <div class="mt-5">
              <Button href={user || g.id === "buscar" || g.id === "planes" ? g.cta.href : routes.signup} variant="secondary">
                {user || g.id === "buscar" || g.id === "planes" ? g.cta.label : "Crear cuenta gratis"} →
              </Button>
            </div>
          </section>
        ))
      }
    </div>

    <section class="mt-12" aria-labelledby="mas">
      <h2 id="mas" class="text-2xl font-bold">Y además</h2>
      <ul class="mt-4 grid gap-4 sm:grid-cols-2">
        {tips.map((t) => (
          <li class="rounded-wl-lg border border-line bg-surface p-4">
            <h3 class="font-semibold">{t.t}</h3>
            <p class="mt-1 text-sm text-ink-muted">{t.x}</p>
          </li>
        ))}
      </ul>
    </section>

    {!user && (
      <div class="mt-12 rounded-wl-lg bg-brand p-6 text-center text-brand-contrast sm:p-10">
        <h2 class="text-2xl font-bold">¿Empezamos?</h2>
        <p class="mt-2 opacity-90">Crear tu cuenta es gratis y lleva un minuto.</p>
        <a href={routes.signup} class="mt-5 inline-flex h-12 items-center rounded-wl bg-brand-contrast px-6 font-semibold text-brand hover:opacity-90">Crear cuenta gratis</a>
      </div>
    )}
  </section>
</BaseLayout>
__WORKLINK_FIN_DEL_ARCHIVO__
echo "  ✓ src/pages/como-funciona.astro"

echo "Listo. Ahora: git add . / git commit / git push"
