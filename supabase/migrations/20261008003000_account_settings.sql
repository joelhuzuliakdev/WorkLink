-- =============================================================================
-- 0030 · Configuración de la cuenta: descargar mis datos y borrar la cuenta
-- =============================================================================
-- * Al borrar una cuenta se borran sus datos personales (todo cuelga de
--   profiles con ON DELETE CASCADE), PERO los registros de cobros se conservan
--   (obligación contable/impositiva, ver Política de privacidad punto 8): las
--   suscripciones y pagos quedan sin usuario (user_id = null), con el email
--   de Mercado Pago que ya tenían.
-- * Un aviso de Mercado Pago que llegue tarde para una cuenta borrada no debe
--   romper nada: los avisos sin destinatario se descartan.
-- * export_my_data(): todo lo que la persona cargó, en un JSON (derecho de
--   acceso, Ley 25.326). Solo devuelve los datos de quien la llama.
-- * my_account_info(): si tiene contraseña, email pendiente y proveedores.
-- =============================================================================

-- 1) Los cobros se conservan aunque se borre la cuenta -----------------------
alter table public.subscriptions alter column user_id drop not null;
alter table public.subscriptions drop constraint subscriptions_user_id_fkey;
alter table public.subscriptions
  add constraint subscriptions_user_id_fkey foreign key (user_id) references public.profiles (id) on delete set null;

alter table public.subscription_payments alter column user_id drop not null;
alter table public.subscription_payments drop constraint subscription_payments_user_id_fkey;
alter table public.subscription_payments
  add constraint subscription_payments_user_id_fkey foreign key (user_id) references public.profiles (id) on delete set null;

-- 2) Avisos sin destinatario (cuenta borrada): se descartan en silencio ------
create or replace function public.tg_notifications_skip_orphans()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.recipient_id is null then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_skip_orphans on public.notifications;
create trigger notifications_skip_orphans
  before insert on public.notifications
  for each row execute function public.tg_notifications_skip_orphans();

-- 3) Descargar mis datos -------------------------------------------------------
create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception 'Ingresá para descargar tus datos' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'generado', now(),
    'cuenta', (
      select jsonb_build_object('email', u.email, 'creada', u.created_at, 'ultimo_ingreso', u.last_sign_in_at)
      from auth.users u where u.id = me
    ),
    'perfil', (select to_jsonb(p) - 'rating_sum' from public.profiles p where p.id = me),
    'emprendimientos', coalesce((
      select jsonb_agg(to_jsonb(b) order by b.created_at) from public.businesses b where b.owner_id = me
    ), '[]'::jsonb),
    'publicaciones', coalesce((
      select jsonb_agg(to_jsonb(po) order by po.created_at) from public.posts po where po.author_id = me
    ), '[]'::jsonb),
    'comentarios', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.created_at) from public.post_comments c where c.author_id = me
    ), '[]'::jsonb),
    'necesidades', coalesce((
      select jsonb_agg(to_jsonb(n) order by n.created_at) from public.needs n where n.author_id = me
    ), '[]'::jsonb),
    'propuestas', coalesce((
      select jsonb_agg(to_jsonb(pr) order by pr.created_at) from public.proposals pr where pr.author_id = me
    ), '[]'::jsonb),
    'resenas_escritas', coalesce((
      select jsonb_agg(to_jsonb(r) - 'reports_count' order by r.created_at) from public.reviews r where r.author_id = me
    ), '[]'::jsonb),
    'mensajes_enviados', coalesce((
      select jsonb_agg(jsonb_build_object('conversacion', m.conversation_id, 'texto', m.body, 'publicacion', m.post_id, 'fecha', m.created_at) order by m.created_at)
      from public.messages m where m.sender_id = me
    ), '[]'::jsonb),
    'personas_que_seguis', coalesce((
      select jsonb_agg(jsonb_build_object('usuario', p.username, 'desde', f.created_at) order by f.created_at)
      from public.profile_follows f join public.profiles p on p.id = f.followed_id where f.follower_id = me
    ), '[]'::jsonb),
    'emprendimientos_que_seguis', coalesce((
      select jsonb_agg(jsonb_build_object('emprendimiento', b.slug, 'desde', f.created_at) order by f.created_at)
      from public.business_follows f join public.businesses b on b.id = f.business_id where f.follower_id = me
    ), '[]'::jsonb),
    'guardados', coalesce((
      select jsonb_agg(jsonb_build_object('publicacion', s.post_id, 'fecha', s.created_at) order by s.created_at)
      from public.post_saves s where s.user_id = me
    ), '[]'::jsonb),
    'bloqueados', coalesce((
      select jsonb_agg(jsonb_build_object('usuario', p.username, 'desde', ub.created_at) order by ub.created_at)
      from public.user_blocks ub join public.profiles p on p.id = ub.blocked_id where ub.blocker_id = me
    ), '[]'::jsonb),
    'planes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'plan', s.plan_id, 'estado', s.status, 'precio', s.price, 'email_mercado_pago', s.payer_email,
        'pagado_hasta', s.paid_through, 'inicio', s.started_at, 'cancelado', s.cancelled_at, 'creado', s.created_at
      ) order by s.created_at)
      from public.subscriptions s where s.user_id = me
    ), '[]'::jsonb),
    'pagos', coalesce((
      select jsonb_agg(jsonb_build_object('plan', sp.plan_id, 'estado', sp.status, 'monto', sp.amount, 'fecha', sp.paid_at) order by sp.created_at)
      from public.subscription_payments sp where sp.user_id = me
    ), '[]'::jsonb),
    'verificacion', coalesce((
      select jsonb_agg(jsonb_build_object('estado', v.status, 'motivo', v.reject_reason, 'enviada', v.created_at, 'revisada', v.reviewed_at) order by v.created_at)
      from public.verification_requests v where v.user_id = me
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

-- 4) Datos de acceso de la propia cuenta (para la pantalla Configuración) ----
-- ¿Tiene contraseña? (quien entró con Google puede no tenerla), si hay un
-- cambio de email esperando confirmación y con qué entra.
create or replace function public.my_account_info()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'email', u.email,
    'has_password', coalesce(u.encrypted_password, '') <> '',
    'pending_email', nullif(u.email_change, ''),
    'providers', coalesce(u.raw_app_meta_data -> 'providers', '[]'::jsonb),
    'created_at', u.created_at
  )
  from auth.users u
  where u.id = (select auth.uid());
$$;

revoke execute on function public.my_account_info() from public, anon;
grant execute on function public.my_account_info() to authenticated;

notify pgrst, 'reload schema';
