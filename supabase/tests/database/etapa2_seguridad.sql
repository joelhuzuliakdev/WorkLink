-- =============================================================================
-- Tests de seguridad y reglas de negocio · Etapa 2
-- =============================================================================
-- Simulan requests reales: cambian al rol `authenticated` / `anon` con el JWT
-- de cada usuario de prueba, igual que hace PostgREST. Si algo falla, el script
-- se corta con el mensaje del caso. Todo corre dentro de una transacción que
-- se revierte al final: no deja datos.
--
-- Ejecutar contra la base local (después de `npx supabase db reset`):
--   npm run db:test
-- o directamente:
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--        -v ON_ERROR_STOP=1 -f supabase/tests/database/etapa2_seguridad.sql
-- =============================================================================

begin;

create schema tests;
grant usage on schema tests to anon, authenticated;

create table tests.ids (name text primary key, id uuid not null);
grant select on tests.ids to anon, authenticated;

create function tests.id(p_name text) returns uuid language sql stable as $$
    select id from tests.ids where name = p_name
$$;

-- Actuar como un usuario (o anónimo con p_name = null).
create function tests.as_user(p_name text) returns void language plpgsql as $$
begin
    execute 'reset role';
    if p_name is null then
        perform set_config('request.jwt.claims', '{"role":"anon"}', true);
        execute 'set local role anon';
    else
        perform set_config('request.jwt.claims',
        json_build_object('sub', tests.id(p_name), 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
    end if;
end $$;

create function tests.as_postgres() returns void language plpgsql as $$
    begin
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
end $$;

create function tests.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
    if cond is not true then
        raise exception 'FALLÓ: %', msg;
    end if;
    raise notice 'ok - %', msg;
end $$;

-- La sentencia debe fallar (opcionalmente con un fragmento del mensaje).
create function tests.throws(sql text, msg text, expected text default null) returns void language plpgsql as $$
declare err text;
begin
    begin
        execute sql;
    exception when others then
        err := sqlerrm;
    end;
    if err is null then
        raise exception 'FALLÓ (no dio error): %', msg;
    end if;
    if expected is not null and position(lower(expected) in lower(err)) = 0 then
        raise exception 'FALLÓ: % (error inesperado: %)', msg, err;
    end if;
    raise notice 'ok - % [%]', msg, err;
end $$;

-- Cantidad de filas afectadas por una sentencia (RLS filtra en silencio).
create function tests.rows(sql text) returns integer language plpgsql as $$
declare n integer;
begin
    execute sql;
    get diagnostics n = row_count;
    return n;
end $$;

grant execute on all functions in schema tests to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Usuarios de prueba
-- -----------------------------------------------------------------------------
with u as (
    insert into auth.users (email, raw_user_meta_data) values
        ('ana@test.ar',    '{"username":"ana","first_name":"Ana","intent":"provider"}'),
        ('beto@test.ar',   '{"username":"beto","intent":"seeker"}'),
        ('ana2@test.ar',   '{"username":"Ana"}'),
        ('mod@test.ar',    '{"username":"moderadora"}'),
        ('root@test.ar',   '{"username":"root_admin"}')
    returning id, email
)
insert into tests.ids
select split_part(email, '@', 1), id from u;

insert into public.user_roles (user_id, role) values
    (tests.id('mod'),  'moderator'),
    (tests.id('root'), 'super_admin');

-- =============================================================================
-- Perfiles
-- =============================================================================
select tests.ok(
    (select username::text from public.profiles where id = tests.id('ana')) = 'ana',
    'el registro crea el perfil con el username pedido');
select tests.ok(
    (select username::text from public.profiles where id = tests.id('ana2')) ~ '^ana[0-9]{4}$',
    'username duplicado recibe un sufijo único');
select tests.ok(
    (select intent from public.profiles where id = tests.id('ana')) = 'provider',
    'intent se toma del registro');

select tests.as_user('ana');
select tests.ok(tests.rows($$update public.profiles set bio = 'Fotógrafa' where id = tests.id('ana')$$) = 1,
    'el usuario edita su propio perfil');
select tests.ok(tests.rows($$update public.profiles set bio = 'hackeado' where id = tests.id('beto')$$) = 0,
    'no puede editar el perfil de otro cambiando el id');
select tests.throws($$update public.profiles set status = 'suspended' where id = tests.id('ana')$$,
    'no puede cambiar su propio estado', 'moderación');
select tests.throws($$update public.profiles set whatsapp = 'no-es-un-numero' where id = tests.id('ana')$$,
    'valida formato de WhatsApp', 'whatsapp');
select tests.throws($$update public.profiles set city_id = (select id from public.cities where slug = 'villa-maria'), province_id = 6 where id = tests.id('ana')$$,
    'ciudad y provincia deben ser coherentes', 'no pertenece');
select tests.ok(tests.rows($$update public.profiles set city_id = (select id from public.cities where slug = 'villa-maria'), whatsapp = '+5493511234567' where id = tests.id('ana')$$) = 1,
    'cargar solo la ciudad completa la provincia');
select tests.as_postgres();
select tests.ok((select province_id from public.profiles where id = tests.id('ana')) = 14,
    'province_id completado automáticamente (Córdoba)');

select tests.as_user(null);
select tests.throws($$select whatsapp from public.profiles limit 1$$,
    'visitante anónimo no lee WhatsApp de perfiles', 'permission denied');
select tests.ok((select count(*) from public.profiles where username = 'ana') = 1,
    'visitante anónimo ve el perfil público');

-- Moderación suspende -> el perfil deja de ser visible para terceros
select tests.as_user('mod');
select tests.ok(tests.rows($$update public.profiles set status = 'suspended' where id = tests.id('ana2')$$) = 1,
    'moderación puede suspender cuentas');
select tests.as_user('beto');
select tests.ok((select count(*) from public.profiles where id = tests.id('ana2')) = 0,
    'una cuenta suspendida no es visible para otros');
select tests.as_user('ana2');
select tests.throws($$insert into public.businesses (slug, name, category_id) values ('suspendida', 'Suspendida', 1)$$,
    'una cuenta suspendida no puede crear emprendimientos', 'row-level security');

-- =============================================================================
-- Roles
-- =============================================================================
select tests.as_user('ana');
select tests.throws($$insert into public.user_roles (user_id, role) values (tests.id('ana'), 'super_admin')$$,
    'un usuario no puede darse rol de admin', 'row-level security');
select tests.ok(not public.has_role('moderator'), 'has_role es falso para usuarios comunes');

select tests.as_user('root');
select tests.ok(tests.rows($$insert into public.user_roles (user_id, role) values (tests.id('beto'), 'moderator')$$) = 1,
    'super_admin asigna roles');
select tests.throws($$delete from public.user_roles where user_id = tests.id('root')$$,
    'super_admin no puede quitarse su propio rol', 'propio rol');
select tests.ok(tests.rows($$delete from public.user_roles where user_id = tests.id('beto')$$) = 1,
    'super_admin quita roles a otros');

select tests.as_user('mod');
select tests.throws($$insert into public.user_roles (user_id, role) values (tests.id('beto'), 'admin')$$,
    'un moderador no asigna roles', 'row-level security');

-- =============================================================================
-- Emprendimientos
-- =============================================================================
select tests.as_user('ana');
insert into public.businesses (owner_id, slug, name, category_id, city_id, verification, followers_count, plan_tier)
values (tests.id('beto'), 'ana-fotografia', 'Ana Fotografía',
        (select id from public.categories where slug = 'fotografia'),
        (select id from public.cities where slug = 'cordoba'),
        'verified', 9999, 'business');

select tests.as_postgres();
insert into tests.ids select 'biz_ana', id from public.businesses where slug = 'ana-fotografia';
select tests.ok(
    (select owner_id = tests.id('ana') and verification = 'none' and followers_count = 0 and plan_tier = 'free'
    from public.businesses where id = tests.id('biz_ana')),
    'al crear se ignoran owner_id, verificación, contadores y plan enviados por el cliente');
select tests.ok(
    exists (select 1 from public.business_members where business_id = tests.id('biz_ana') and user_id = tests.id('ana') and role = 'owner'),
    'el creador queda como titular (owner)');

select tests.as_user('beto');
select tests.ok(tests.rows($$update public.businesses set name = 'Robado' where id = tests.id('biz_ana')$$) = 0,
    'otro usuario no puede editar el emprendimiento');
select tests.throws($$insert into public.business_members (business_id, user_id, role) values (tests.id('biz_ana'), tests.id('beto'), 'owner')$$,
    'nadie se agrega solo como miembro', 'row-level security');

select tests.as_user('ana');
select tests.throws($$update public.businesses set verification = 'verified' where id = tests.id('biz_ana')$$,
    'el dueño no puede autoverificarse', 'verificación');
select tests.ok(tests.rows($$update public.businesses set verification = 'pending' where id = tests.id('biz_ana')$$) = 1,
    'el dueño puede solicitar verificación');
select tests.throws($$update public.businesses set followers_count = 100000 where id = tests.id('biz_ana')$$,
    'no se pueden inflar seguidores', 'sistema');
select tests.throws($$update public.businesses set status = 'suspended' where id = tests.id('biz_ana')$$,
    'el dueño no puede suspender', 'moderación');
select tests.throws($$insert into public.business_subcategories values (tests.id('biz_ana'), (select id from public.subcategories where slug = 'desarrollo-web'))$$,
    'subcategoría de otra categoría es rechazada', 'no pertenece');
select tests.ok(tests.rows($$insert into public.business_subcategories values (tests.id('biz_ana'), (select id from public.subcategories where slug = 'fotografia-de-bodas'))$$) = 1,
    'agrega subcategoría válida');
select tests.ok(tests.rows($$insert into public.business_members (business_id, user_id, role) values (tests.id('biz_ana'), tests.id('beto'), 'editor')$$) = 1,
    'la titular suma un editor');

select tests.as_user('beto');
select tests.ok(tests.rows($$update public.businesses set tagline = 'Bodas y eventos' where id = tests.id('biz_ana')$$) = 1,
    'el editor puede editar el perfil del emprendimiento');
select tests.throws($$update public.businesses set deleted_at = now() where id = tests.id('biz_ana')$$,
    'el editor no puede eliminar el emprendimiento', 'titular');
select tests.ok(tests.rows($$delete from public.business_members where business_id = tests.id('biz_ana') and user_id = tests.id('ana')$$) = 0,
    'el editor no puede sacar a la titular');
select tests.as_user('ana');
select tests.throws($$delete from public.business_members where business_id = tests.id('biz_ana') and user_id = tests.id('ana')$$,
    'la única titular no puede irse sin dejar otra', 'al menos un titular');

select tests.as_user('mod');
select tests.ok(tests.rows($$update public.businesses set verification = 'verified' where id = tests.id('biz_ana')$$) = 1,
    'moderación verifica');
select tests.as_postgres();
select tests.ok((select verified_at is not null from public.businesses where id = tests.id('biz_ana')),
    'verified_at se completa al verificar');

-- Borrador: invisible para otros
select tests.as_user('ana');
insert into public.businesses (slug, name, category_id, status)
values ('ana-borrador', 'Borrador', (select id from public.categories where slug = 'otros'), 'draft');
select tests.ok((select count(*) from public.businesses where slug = 'ana-borrador') = 1,
    'la dueña ve su borrador');
select tests.as_user('beto');
select tests.ok((select count(*) from public.businesses where slug = 'ana-borrador') = 0,
    'otros no ven borradores');
select tests.as_user(null);
select tests.ok((select count(*) from public.businesses where slug = 'ana-borrador') = 0,
    'visitantes no ven borradores');
select tests.ok((select count(*) from public.businesses where slug = 'ana-fotografia') = 1,
    'visitantes ven emprendimientos activos');
select tests.throws($$select phone from public.businesses limit 1$$,
    'visitante anónimo no lee el teléfono del emprendimiento', 'permission denied');

-- Cupo de emprendimientos por cuenta
select tests.as_postgres();
update public.settings set value = '2' where key = 'limits.max_businesses_per_user';
select tests.as_user('ana');
select tests.throws($$insert into public.businesses (slug, name, category_id) values ('ana-tercero', 'Tercero', 1)$$,
    'respeta el máximo de emprendimientos por cuenta', 'máximo');

-- Catálogo
select tests.as_user('ana');
select tests.ok(tests.rows($$insert into public.services (business_id, name, slug, price, price_type) values (tests.id('biz_ana'), 'Cobertura de boda', 'cobertura-de-boda', 350000, 'from')$$) = 1,
    'miembros cargan servicios');
select tests.throws($$insert into public.products (business_id, name, slug, price_type) values (tests.id('biz_ana'), 'Álbum', 'album', 'fixed')$$,
    'precio fijo exige importe', 'products_price_type');
select tests.as_user('ana2');
select tests.throws($$insert into public.services (business_id, name, slug, price_type) values (tests.id('biz_ana'), 'Intruso', 'intruso', 'ask')$$,
    'no miembros no cargan servicios', 'row-level security');

-- =============================================================================
-- Publicaciones y archivos
-- =============================================================================
select tests.as_user('ana');
insert into public.posts (author_id, business_id, type, body, category_id, city_id, tags, likes_count)
values (tests.id('beto'), tests.id('biz_ana'), 'service', 'Fechas libres para noviembre',
        (select id from public.categories where slug = 'fotografia'),
        (select id from public.cities where slug = 'cordoba'),
        array['Bodas', 'bodas', ' Fotografía ', ''], 500);
select tests.as_postgres();
insert into tests.ids select 'post_ana', id from public.posts where body = 'Fechas libres para noviembre';
select tests.ok(
    (select author_id = tests.id('ana') and likes_count = 0 and tags = array['bodas', 'fotografia']
    from public.posts where id = tests.id('post_ana')),
    'autor forzado, contadores en cero y tags normalizados');

select tests.as_user('ana2');
select tests.throws($$insert into public.posts (business_id, type, body) values (tests.id('biz_ana'), 'offer', 'spam')$$,
    'no se publica en nombre de un emprendimiento ajeno', 'row-level security');
select tests.as_user('beto');
-- Beto es editor del emprendimiento: puede editar
select tests.ok(tests.rows($$update public.posts set body = 'Últimas fechas de noviembre' where id = tests.id('post_ana')$$) = 1,
    'el equipo del emprendimiento edita sus publicaciones');
select tests.throws($$update public.posts set status = 'removed' where id = tests.id('post_ana')$$,
    'el autor no puede marcar como removida', 'moderación');

select tests.as_user('mod');
select tests.ok(tests.rows($$update public.posts set status = 'removed' where id = tests.id('post_ana')$$) = 1,
    'moderación remueve publicaciones');
select tests.as_user('ana');
select tests.throws($$update public.posts set status = 'published' where id = tests.id('post_ana')$$,
    'el autor no puede restaurar algo removido', 'removida');
select tests.as_user(null);
select tests.ok((select count(*) from public.posts where id = tests.id('post_ana')) = 0,
    'lo removido no es público');

-- Archivos
select tests.as_user('ana');
select tests.throws(format($$insert into public.media (bucket, path, kind, mime, bytes) values ('post-media', '%s/x.webp', 'image', 'image/webp', 1000)$$, tests.id('beto')),
    'no se registra un archivo en la carpeta de otro', 'media_path_owner');
select tests.throws(format($$insert into public.media (bucket, path, kind, mime, bytes) values ('post-media', '%s/x.exe', 'image', 'application/x-msdownload', 1000)$$, tests.id('ana')),
    'tipo MIME no permitido', 'media_mime_by_kind');
select tests.throws(format($$insert into public.media (bucket, path, kind, mime, bytes, duration_s) values ('post-media', '%s/v.mp4', 'video', 'video/mp4', 60 * 1024 * 1024, 30)$$, tests.id('ana')),
    'video de más de 50 MB rechazado', 'media_size_by_kind');

insert into public.posts (type, body) values ('offer', 'Post con foto');
insert into public.media (bucket, path, kind, mime, bytes, width, height, status)
values ('post-media', tests.id('ana')::text || '/foto.webp', 'image', 'image/webp', 120000, 1600, 1067, 'attached');
select tests.as_postgres();
insert into tests.ids select 'post_foto', id from public.posts where body = 'Post con foto';
insert into tests.ids select 'media_ana', id from public.media where path like '%/foto.webp';
select tests.ok((select status = 'pending' from public.media where id = tests.id('media_ana')),
    'el estado inicial del archivo lo fija el sistema (pending)');

select tests.as_user('beto');
insert into public.posts (type, body) values ('seeking', 'Post de Beto');
select tests.as_postgres();
insert into tests.ids select 'post_beto', id from public.posts where body = 'Post de Beto';
select tests.as_user('beto');
select tests.throws($$insert into public.post_media (post_id, media_id, position) values (tests.id('post_beto'), tests.id('media_ana'), 0)$$,
    'no se puede usar un archivo ajeno', 'row-level security');

select tests.as_user('ana');
select tests.ok(tests.rows($$insert into public.post_media (post_id, media_id, position) values (tests.id('post_foto'), tests.id('media_ana'), 0)$$) = 1,
    'vincula su archivo a su publicación');
select tests.as_postgres();
select tests.ok((select status = 'attached' from public.media where id = tests.id('media_ana')),
    'al vincular el archivo pasa a attached');
select tests.as_user('ana');
select tests.ok(tests.rows($$delete from public.media where id = tests.id('media_ana')$$) = 0,
    'un archivo en uso no se puede borrar');

-- =============================================================================
-- Necesidades
-- =============================================================================
select tests.as_user('beto');
insert into public.needs (author_id, title, description, category_id, city_id, budget_min, budget_max, status, proposals_count)
values (tests.id('ana'), 'Busco fotógrafo para casamiento en noviembre',
        'Casamiento de 120 invitados, ceremonia y fiesta en Córdoba capital.',
        (select id from public.categories where slug = 'fotografia'),
        (select id from public.cities where slug = 'cordoba'),
        300000, 600000, 'awarded', 50);
select tests.as_postgres();
insert into tests.ids select 'need_beto', id from public.needs where title like 'Busco fotógrafo%';
select tests.ok(
    (select author_id = tests.id('beto') and status = 'open' and proposals_count = 0
            and slug = 'busco-fotografo-para-casamiento-en-noviembre' and province_id = 14
    from public.needs where id = tests.id('need_beto')),
    'necesidad: autor, estado, contador, slug y provincia los fija el sistema');

select tests.as_user('beto');
select tests.throws($$update public.needs set status = 'awarded' where id = tests.id('need_beto')$$,
    'el autor no puede marcarla adjudicada a mano', 'no permitido');
select tests.throws($$update public.needs set budget_min = 900000 where id = tests.id('need_beto')$$,
    'presupuesto mínimo no puede superar al máximo', 'needs_budget');
select tests.throws($$update public.needs set needed_by = date '2020-01-01' where id = tests.id('need_beto')$$,
    'fecha requerida en el pasado rechazada', 'pasado');

select tests.as_user('ana');
select tests.ok(tests.rows($$update public.needs set title = 'Hackeado por Ana!!' where id = tests.id('need_beto')$$) = 0,
    'otro usuario no edita la necesidad');
select tests.as_user(null);
select tests.ok((select count(*) from public.needs where id = tests.id('need_beto')) = 1,
    'las necesidades son públicas');

select tests.as_user('beto');
select tests.ok(tests.rows($$update public.needs set status = 'closed' where id = tests.id('need_beto')$$) = 1,
    'el autor puede cerrarla');
select tests.throws($$update public.needs set description = 'Cambio después de cerrar la solicitud.' where id = tests.id('need_beto')$$,
    'no se edita una necesidad cerrada', 'cerrada');

-- =============================================================================
-- Categorías propuestas
-- =============================================================================
select tests.as_user('ana');
insert into public.category_requests (requested_by, kind, proposed_name, status)
values (tests.id('beto'), 'category', 'Mascotas', 'approved');
select tests.as_postgres();
insert into tests.ids select 'req_ana', id from public.category_requests where proposed_name = 'Mascotas';
select tests.ok(
    (select requested_by = tests.id('ana') and status = 'pending' from public.category_requests where id = tests.id('req_ana')),
    'la propuesta queda pendiente y a nombre de quien la hace');

select tests.as_user('ana');
update public.businesses set category_request_id = tests.id('req_ana'),
        category_id = (select id from public.categories where slug = 'otros')
    where slug = 'ana-borrador';
select tests.throws($$select public.approve_category_request(tests.id('req_ana'))$$,
    'un usuario no puede aprobar categorías', 'permiso denegado');

select tests.as_user('beto');
insert into public.category_requests (kind, proposed_name) values ('category', 'mascotas');

select tests.as_user('mod');
select tests.ok(
    (public.approve_category_request(tests.id('req_ana'), 'Mascotas', null, 'servicios para mascotas') ->> 'merged_twins')::int = 1,
    'moderación aprueba y fusiona la propuesta gemela');
select tests.as_user(null);
select tests.ok((select count(*) from public.categories where slug = 'mascotas' and active) = 1,
    'la categoría aprobada es global y visible para todos');
select tests.as_postgres();
select tests.ok(
    (select c.slug = 'mascotas' and b.category_request_id is null
    from public.businesses b join public.categories c on c.id = b.category_id
    where b.slug = 'ana-borrador'),
    'el emprendimiento que esperaba la propuesta fue reasignado');

select tests.as_user('ana');
insert into public.category_requests (kind, proposed_name) values ('category', 'Drones');
insert into public.category_requests (kind, parent_category_id, proposed_name)
    values ('subcategory', (select id from public.categories where slug = 'fotografia'), 'Fotografía con drones');
select tests.throws($$insert into public.category_requests (kind, proposed_name) values ('category', 'Una más')$$,
    'límite de 3 propuestas por semana', 'límite');
select tests.ok(
    (select count(*) from public.suggest_categories('fotografo bodas') where label like 'Fotografía%') >= 1,
    'suggest_categories encuentra parecidas sin tildes');

-- =============================================================================
-- Storage
-- =============================================================================
select tests.as_user('ana');
select tests.ok(tests.rows(format($$insert into storage.objects (bucket_id, name) values ('avatars', '%s/avatar.webp')$$, tests.id('ana'))) = 1,
    'sube a su carpeta');
select tests.throws(format($$insert into storage.objects (bucket_id, name) values ('avatars', '%s/avatar.webp')$$, tests.id('beto')),
    'no sube a la carpeta de otro', 'row-level security');
select tests.throws(format($$insert into storage.objects (bucket_id, name) values ('avatars', 'avatar.webp')$$),
    'no sube fuera de una carpeta de usuario', 'row-level security');

select tests.as_postgres();
select tests.ok(true, '— todos los tests de la Etapa 2 pasaron —');

rollback;