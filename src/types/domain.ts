/**
 * Tipos del dominio usados en la interfaz. Reflejan las columnas que cada
 * consulta pide (nunca SELECT *). Cuando se generen los tipos de Supabase
 * (npm run db:types) se pueden derivar de ahí.
 */
import type { BusinessHours } from "../schemas/business";
import type { PriceType } from "../lib/format";

export interface CityRef {
  id: number;
  name: string;
  slug: string;
  province_name: string;
  province_slug: string;
}

export interface Profile {
  id: string;
  username: string;
  first_name: string | null;
  last_name: string | null;
  bio: string | null;
  avatar_path: string | null;
  situation: "job_seeking" | "entrepreneur" | "freelancer" | "hiring" | null;
  headline: string | null;
  verified_at: string | null;
  intent: "seeker" | "provider";
  city: CityRef | null;
  whatsapp?: string | null;
  phone?: string | null;
  instagram: string | null;
  facebook: string | null;
  tiktok: string | null;
  website: string | null;
  followers_count: number;
  following_count: number;
  created_at: string;
}

export interface CategoryRef {
  id: number;
  name: string;
  slug: string;
  seo_noun: string | null;
}

export interface SubcategoryRef {
  id: number;
  category_id: number;
  name: string;
  slug: string;
}

export type BusinessStatus = "draft" | "active" | "inactive" | "suspended";

export interface CatalogItem {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  price: number | null;
  currency: string;
  price_type: PriceType;
  cover_path: string | null;
  status: "active" | "hidden" | "archived";
  sort_order: number;
  duration_min?: number | null;
  service_area?: string | null;
}

export interface Business {
  id: string;
  owner_id: string;
  slug: string;
  name: string;
  tagline: string | null;
  description: string | null;
  logo_path: string | null;
  cover_path: string | null;
  status: BusinessStatus;
  verification: "none" | "pending" | "verified" | "rejected";
  category: CategoryRef | null;
  subcategories: SubcategoryRef[];
  city: CityRef | null;
  whatsapp?: string | null;
  phone?: string | null;
  email?: string | null;
  instagram: string | null;
  facebook: string | null;
  tiktok: string | null;
  website: string | null;
  hours: BusinessHours | null;
  availability: string | null;
  followers_count: number;
  posts_count: number;
  rating_sum: number;
  rating_count: number;
  created_at: string;
  updated_at: string;
}
