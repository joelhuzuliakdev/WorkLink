-- =============================================================================
-- seed.sql · Datos iniciales
-- =============================================================================
-- Se ejecuta automáticamente con `supabase db reset` (local) después de las
-- migraciones. En producción se corre una sola vez (ver README de la etapa).
-- Es idempotente: se puede volver a correr sin duplicar datos.
--
-- Contenido:
--   1. Las 24 jurisdicciones (códigos INDEC).
--   2. Ciudades principales de Córdoba (el listado completo de localidades
--      se importa desde Georef en la Etapa 4).
--   3. Categorías y subcategorías iniciales.
--   4. Configuración (límites, umbrales SEO).
-- =============================================================================

-- 1. Provincias -----------------------------------------------------------------
insert into public.provinces (id, name, slug) values
    ( 2, 'Ciudad Autónoma de Buenos Aires', 'caba'),
    ( 6, 'Buenos Aires',                    'buenos-aires'),
    (10, 'Catamarca',                       'catamarca'),
    (14, 'Córdoba',                         'cordoba'),
    (18, 'Corrientes',                      'corrientes'),
    (22, 'Chaco',                           'chaco'),
    (26, 'Chubut',                          'chubut'),
    (30, 'Entre Ríos',                      'entre-rios'),
    (34, 'Formosa',                         'formosa'),
    (38, 'Jujuy',                           'jujuy'),
    (42, 'La Pampa',                        'la-pampa'),
    (46, 'La Rioja',                        'la-rioja'),
    (50, 'Mendoza',                         'mendoza'),
    (54, 'Misiones',                        'misiones'),
    (58, 'Neuquén',                         'neuquen'),
    (62, 'Río Negro',                       'rio-negro'),
    (66, 'Salta',                           'salta'),
    (70, 'San Juan',                        'san-juan'),
    (74, 'San Luis',                        'san-luis'),
    (78, 'Santa Cruz',                      'santa-cruz'),
    (82, 'Santa Fe',                        'santa-fe'),
    (86, 'Santiago del Estero',             'santiago-del-estero'),
    (90, 'Tucumán',                         'tucuman'),
    (94, 'Tierra del Fuego',                'tierra-del-fuego')
on conflict (id) do update set name = excluded.name, slug = excluded.slug;

-- 2. Ciudades principales de Córdoba (sin coordenadas: las completa Georef) -----
insert into public.cities (province_id, name, slug)
select 14, name, public.slugify(name)
from (values
    ('Córdoba'), ('Río Cuarto'), ('Villa María'), ('San Francisco'), ('Villa Carlos Paz'),
    ('Alta Gracia'), ('Río Tercero'), ('Bell Ville'), ('Jesús María'), ('Río Segundo'),
    ('Pilar'), ('La Calera'), ('Villa Allende'), ('Mendiolaza'), ('Unquillo'),
    ('Río Ceballos'), ('Salsipuedes'), ('Malagueño'), ('Cosquín'), ('La Falda'),
    ('Marcos Juárez'), ('Villa Dolores'), ('Cruz del Eje'), ('Arroyito'), ('Laboulaye'),
    ('Deán Funes'), ('Oncativo'), ('Oliva'), ('Villa General Belgrano'),
    ('Santa Rosa de Calamuchita')
) as t (name)
on conflict (province_id, slug) do nothing;

-- 3. Categorías -------------------------------------------------------------------
insert into public.categories (name, slug, seo_noun, icon, sort_order) values
    ('Gastronomía',              'gastronomia',              'gastronomía',                'utensils',   10),
    ('Ropa y moda',              'ropa-y-moda',              'ropa y moda',                'shirt',      20),
    ('Belleza',                  'belleza',                  'servicios de belleza',       'sparkles',   30),
    ('Tecnología',               'tecnologia',               'servicios de tecnología',    'cpu',        40),
    ('Diseño',                   'diseno',                   'diseñadores',                'pen-tool',   50),
    ('Fotografía',               'fotografia',               'fotógrafos',                 'camera',     60),
    ('Servicios profesionales',  'servicios-profesionales',  'profesionales',              'briefcase',  70),
    ('Construcción',             'construccion',             'servicios de construcción',  'hard-hat',   80),
    ('Hogar',                    'hogar',                    'servicios para el hogar',    'home',       90),
    ('Automotores',              'automotores',              'servicios automotores',      'car',       100),
    ('Artesanías',               'artesanias',               'artesanos',                  'scissors',  110),
    ('Educación',                'educacion',                'clases y cursos',            'book-open', 120),
    ('Salud y bienestar',        'salud-y-bienestar',        'salud y bienestar',          'heart',     130),
    ('Eventos',                  'eventos',                  'servicios para eventos',     'party',     140),
    ('Marketing',                'marketing',                'servicios de marketing',     'megaphone', 150),
    ('Otros',                    'otros',                    'emprendedores',              'grid',      999)
on conflict (slug) do update
    et name = excluded.name, seo_noun = excluded.seo_noun, icon = excluded.icon, sort_order = excluded.sort_order;

-- Subcategorías -------------------------------------------------------------------
insert into public.subcategories (category_id, name, slug, seo_noun, sort_order)
select c.id, s.name, public.slugify(s.name), s.seo_noun, s.ord
from (values
    ('gastronomia', 'Hamburguesas',             'hamburgueserías',          10),
    ('gastronomia', 'Pastelería',               'pastelerías',              20),
    ('gastronomia', 'Tortas personalizadas',    'tortas personalizadas',    25),
    ('gastronomia', 'Panadería',                'panaderías',               30),
    ('gastronomia', 'Catering',                 'servicios de catering',    40),
    ('gastronomia', 'Comida saludable',         'comida saludable',         50),
    ('gastronomia', 'Viandas',                  'viandas',                  60),

    ('ropa-y-moda', 'Ropa personalizada',       'ropa personalizada',       10),
    ('ropa-y-moda', 'Indumentaria',             'indumentaria',             20),
    ('ropa-y-moda', 'Calzado',                  'calzado',                  30),
    ('ropa-y-moda', 'Accesorios',               'accesorios',               40),
    ('ropa-y-moda', 'Costura y arreglos',       'costureras',               50),

    ('belleza',     'Peluquería',               'peluquerías',              10),
    ('belleza',     'Uñas',                     'manicuras',                20),
    ('belleza',     'Maquillaje',               'maquilladoras',            30),
    ('belleza',     'Estética',                 'centros de estética',      40),

    ('tecnologia',  'Desarrollo web',           'desarrolladores web',      10),
    ('tecnologia',  'Desarrollo de software',   'desarrolladores de software', 20),
    ('tecnologia',  'Reparación de PC',         'técnicos de PC',           30),
    ('tecnologia',  'Soporte técnico',          'soporte técnico',          40),
    ('tecnologia',  'Redes',                    'técnicos en redes',        50),
    ('tecnologia',  'Reparación de celulares',  'técnicos de celulares',    60),

    ('diseno',      'Diseño gráfico',           'diseñadores gráficos',     10),
    ('diseno',      'Diseño de logos',          'diseñadores de logos',     20),
    ('diseno',      'Diseño de interiores',     'diseñadores de interiores', 30),
    ('diseno',      'Diseño UX/UI',             'diseñadores UX/UI',        40),

    ('fotografia',  'Fotografía de eventos',    'fotógrafos de eventos',    10),
    ('fotografia',  'Fotografía de bodas',      'fotógrafos de bodas',      20),
    ('fotografia',  'Fotografía de productos',  'fotógrafos de productos',  30),
    ('fotografia',  'Fotografía comercial',     'fotógrafos comerciales',   40),
    ('fotografia',  'Video y filmación',        'videógrafos',              50),

    ('servicios-profesionales', 'Contabilidad', 'contadores',               10),
    ('servicios-profesionales', 'Abogacía',     'abogados',                 20),
    ('servicios-profesionales', 'Arquitectura', 'arquitectos',              30),
    ('servicios-profesionales', 'Traducciones', 'traductores',              40),

    ('construccion', 'Albañilería',             'albañiles',                10),
    ('construccion', 'Electricidad',            'electricistas',            20),
    ('construccion', 'Plomería y gas',          'plomeros y gasistas',      30),
    ('construccion', 'Pintura',                 'pintores',                 40),
    ('construccion', 'Herrería',                'herreros',                 50),
    ('construccion', 'Carpintería',             'carpinteros',              60),

    ('hogar',       'Limpieza',                 'servicios de limpieza',    10),
    ('hogar',       'Jardinería',               'jardineros',               20),
    ('hogar',       'Mudanzas y fletes',        'fletes y mudanzas',        30),
    ('hogar',       'Climatización',            'técnicos en climatización', 40),
    ('hogar',       'Cerrajería',               'cerrajeros',               50),

    ('automotores', 'Mecánica',                 'mecánicos',                10),
    ('automotores', 'Chapa y pintura',          'chapistas',                20),
    ('automotores', 'Lavado y detailing',       'lavaderos de autos',       30),
    ('automotores', 'Gomería',                  'gomerías',                 40),

    ('artesanias',  'Cerámica',                 'ceramistas',               10),
    ('artesanias',  'Tejidos',                  'tejedoras',                20),
    ('artesanias',  'Velas y aromas',           'velas artesanales',        30),
    ('artesanias',  'Marroquinería',            'marroquineros',            40),

    ('educacion',   'Clases particulares',      'profesores particulares',  10),
    ('educacion',   'Idiomas',                  'profesores de idiomas',    20),
    ('educacion',   'Música',                   'profesores de música',     30),
    ('educacion',   'Cursos y talleres',        'cursos y talleres',        40),

    ('salud-y-bienestar', 'Nutrición',          'nutricionistas',           10),
    ('salud-y-bienestar', 'Entrenamiento personal', 'entrenadores personales', 20),
    ('salud-y-bienestar', 'Masajes',            'masajistas',               30),
    ('salud-y-bienestar', 'Psicología',         'psicólogos',               40),
    ('salud-y-bienestar', 'Yoga y meditación',  'clases de yoga',           50),

    ('eventos',     'Organización de eventos',  'organizadores de eventos', 10),
    ('eventos',     'DJ y sonido',              'DJs',                      20),
    ('eventos',     'Decoración',               'decoradores de eventos',   30),
    ('eventos',     'Animación infantil',       'animadores infantiles',    40),
    ('eventos',     'Alquiler de salones',      'salones de eventos',       50),

    ('marketing',   'Redes sociales',           'community managers',       10),
    ('marketing',   'Publicidad online',        'especialistas en publicidad online', 20),
    ('marketing',   'SEO',                      'especialistas en SEO',     30),
    ('marketing',   'Branding',                 'especialistas en branding', 40)
) as s (cat_slug, name, seo_noun, ord)
join public.categories c on c.slug = s.cat_slug
on conflict (category_id, slug) do update
    set name = excluded.name, seo_noun = excluded.seo_noun, sort_order = excluded.sort_order;

-- 4. Configuración ------------------------------------------------------------------
insert into public.settings (key, value, is_public, description) values
    ('limits.max_businesses_per_user',   '3',   false, 'Emprendimientos activos por cuenta'),
    ('limits.posts_per_day',             '20',  false, 'Publicaciones por usuario cada 24 h'),
    ('limits.needs_per_day',             '5',   false, 'Necesidades por usuario cada 24 h'),
    ('limits.category_requests_per_week','3',   false, 'Propuestas de categorías por usuario cada 7 días'),
    ('needs.expiry_days',                '30',  true,  'Días hasta que vence una necesidad'),
    ('seo.landing_min_businesses',       '5',   false, 'Emprendimientos activos para indexar una landing'),
    ('seo.landing_min_businesses_alt',   '3',   false, 'Mínimo alternativo combinado con publicaciones'),
    ('seo.landing_min_recent_posts',     '10',  false, 'Publicaciones recientes del mínimo alternativo'),
    ('site.default_province_slug',       '"cordoba"', true, 'Provincia por defecto de la experiencia'),
    ('site.currency',                    '"ARS"',     true, 'Moneda por defecto'),
    ('site.timezone',                    '"America/Argentina/Cordoba"', true, 'Zona horaria de visualización')
on conflict (key) do nothing;