-- =============================================================================
-- 0019 · Tipos para propuestas (Etapa 10)
-- =============================================================================
-- Van en una migración aparte porque Postgres no deja usar un valor nuevo de
-- un enum en la misma transacción en que se agrega (lo usa la 0020).
-- =============================================================================

create type public.proposal_status as enum ('pending', 'accepted', 'declined', 'withdrawn');

alter type public.notification_type add value if not exists 'need_proposal';
alter type public.notification_type add value if not exists 'proposal_accepted';
alter type public.notification_type add value if not exists 'need_match';
