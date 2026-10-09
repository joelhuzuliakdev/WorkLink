-- =============================================================================
-- 0025 · Tipos para suscripciones y verificación paga (Etapa 13)
-- =============================================================================
-- En una migración aparte: los valores nuevos de un enum no se pueden usar en
-- la misma transacción en la que se agregan.
-- =============================================================================

alter type public.notification_type add value if not exists 'plan_activated';
alter type public.notification_type add value if not exists 'plan_payment_failed';
alter type public.notification_type add value if not exists 'verification_approved';
alter type public.notification_type add value if not exists 'verification_rejected';

-- Estado de una suscripción, como lo informa Mercado Pago (preapproval).
create type public.subscription_status as enum ('pending', 'authorized', 'paused', 'cancelled');

create type public.verification_request_status as enum ('pending', 'approved', 'rejected');
