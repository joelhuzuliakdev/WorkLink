-- =============================================================================
-- 0031 · Tipos para el Botón de arrepentimiento (Etapa 14)
-- =============================================================================
-- En una migración aparte: los valores nuevos de un enum no se pueden usar en
-- la misma transacción en la que se agregan.
-- =============================================================================

-- Aviso a la administración: alguien pidió arrepentirse de un plan.
alter type public.notification_type add value if not exists 'withdrawal_request';
-- Aviso a la persona: su pedido de arrepentimiento ya se resolvió.
alter type public.notification_type add value if not exists 'withdrawal_resolved';

-- pending: recibido · refunded: plan cancelado y dinero devuelto
-- rejected: no corresponde (por ej., fuera de plazo) · closed: resuelto de otra forma
create type public.withdrawal_status as enum ('pending', 'refunded', 'rejected', 'closed');
