import type { Business, CatalogItem } from "../../types/domain";
import { WEEK_DAYS } from "../../schemas/business";
import { mediaUrl } from "../media";
import { instagramUrl, tiktokUrl } from "../contact";

const SCHEMA_DAYS: Record<string, string> = {
  mon: "Monday",
  tue: "Tuesday",
  wed: "Wednesday",
  thu: "Thursday",
  fri: "Friday",
  sat: "Saturday",
  sun: "Sunday",
};

/**
 * Datos estructurados schema.org (LocalBusiness) para la página pública.
 * No incluye teléfono ni WhatsApp (son privados para visitantes).
 * AggregateRating solo cuando haya reseñas reales (Etapa 11).
 */
export function businessJsonLd(business: Business, url: string, catalog: { services: CatalogItem[]; products: CatalogItem[] }) {
  const sameAs = [
    business.instagram && instagramUrl(business.instagram),
    business.tiktok && tiktokUrl(business.tiktok),
    business.facebook,
    business.website,
  ].filter(Boolean);

  const openingHours = WEEK_DAYS.flatMap(({ key }) =>
    (business.hours?.[key] ?? []).map(([opens, closes]) => ({
      "@type": "OpeningHoursSpecification",
      dayOfWeek: SCHEMA_DAYS[key],
      opens,
      closes,
    })),
  );

  const offers = [...catalog.services, ...catalog.products]
    .filter((item) => item.price !== null && item.price_type !== "ask")
    .slice(0, 20)
    .map((item) => ({
      "@type": "Offer",
      name: item.name,
      price: Number(item.price),
      priceCurrency: item.currency,
    }));

  return {
    "@context": "https://schema.org",
    "@type": "LocalBusiness",
    "@id": `${url}#business`,
    name: business.name,
    url,
    description: business.tagline ?? business.description?.slice(0, 300) ?? undefined,
    image: mediaUrl("cover", business.cover_path) ?? mediaUrl("logo", business.logo_path) ?? undefined,
    logo: mediaUrl("logo", business.logo_path) ?? undefined,
    address: business.city
      ? {
          "@type": "PostalAddress",
          addressLocality: business.city.name,
          addressRegion: business.city.province_name,
          addressCountry: "AR",
        }
      : undefined,
    sameAs: sameAs.length ? sameAs : undefined,
    openingHoursSpecification: openingHours.length ? openingHours : undefined,
    makesOffer: offers.length ? offers : undefined,
    aggregateRating:
      business.rating_count > 0
        ? {
            "@type": "AggregateRating",
            ratingValue: (business.rating_sum / business.rating_count).toFixed(1),
            reviewCount: business.rating_count,
          }
        : undefined,
  };
}

export function breadcrumbJsonLd(items: { name: string; url: string }[]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: item.url,
    })),
  };
}

/** Serializa JSON-LD de forma segura dentro de <script> (evita cerrar la etiqueta). */
export function jsonLdScript(data: unknown): string {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
