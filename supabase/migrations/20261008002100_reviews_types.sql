-- =============================================================================
-- 0021 · Tipos para reseñas y denuncias (Etapa 11)
-- =============================================================================
-- Van en una migración aparte porque los valores nuevos de un enum no se
-- pueden usar en la misma transacción en la que se agregan.
-- =============================================================================

alter type public.notification_type add value if not exists 'review_received';
alter type public.notification_type add value if not exists 'review_reply';

-- Qué se puede denunciar (se usa ahora para reseñas y en la Etapa 12 para el resto).
create type public.report_target as enum ('review', 'post', 'comment', 'profile', 'business', 'need');
create type public.report_reason as enum ('spam', 'offensive', 'fake', 'scam', 'other');
create type public.report_status as enum ('open', 'resolved', 'dismissed');
