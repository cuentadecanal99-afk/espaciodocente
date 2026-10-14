-- =========================================================
-- Migración: hilos conductores reales + "Lengua" pasa a "Prácticas del lenguaje"
-- Correr a mano en Supabase SQL Editor, completa (va en una transacción:
-- si algo falla no se aplica nada). Idempotente: se puede correr de nuevo.
--
-- 1. El área "Lengua" pasa a llamarse "Prácticas del lenguaje".
--    No se puede renombrar con un UPDATE directo: coordinador_permiso_materias
--    referencia areas(name) sin ON UPDATE CASCADE. Por eso se asegura que
--    exista "Prácticas del lenguaje", se mueven a ella todas las referencias
--    a "Lengua" (PUDs guardados, permisos de coordinadores, registros de
--    prompts) y recién después se borra "Lengua". Sus hilos demo se borran
--    en cascada.
--
-- 2. Reemplaza los hilos demo por los hilos reales de Matemática, Prácticas
--    del lenguaje, Naturales, Sociales y Language Arts. Las áreas se buscan
--    por nombre normalizado (sin tildes ni mayúsculas). Las demás áreas
--    quedan con los hilos que tienen hoy.
-- =========================================================

BEGIN;

-- ---------- 1. Lengua -> Prácticas del lenguaje ----------
DO $$
DECLARE
  v_destino text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.areas WHERE name = 'Lengua') THEN
    RAISE NOTICE 'No existe el área "Lengua": no hay nada que renombrar.';
    RETURN;
  END IF;

  -- Nombre real del área destino, si ya existe con otra capitalización
  SELECT name INTO v_destino FROM public.areas
  WHERE public.areas_nombre_normalizado(name) = public.areas_nombre_normalizado('Prácticas del lenguaje');

  IF v_destino IS NULL THEN
    INSERT INTO public.areas (name) VALUES ('Prácticas del lenguaje');
    v_destino := 'Prácticas del lenguaje';
  END IF;

  -- Permisos de coordinadores (FK a areas.name)
  INSERT INTO public.coordinador_permiso_materias (email, materia)
  SELECT email, v_destino FROM public.coordinador_permiso_materias WHERE materia = 'Lengua'
  ON CONFLICT (email, materia) DO NOTHING;
  DELETE FROM public.coordinador_permiso_materias WHERE materia = 'Lengua';

  -- PUDs guardados y presentados: así los gráficos de coordinadores no cuentan dos materias
  UPDATE public.pud_history SET subject = v_destino WHERE subject = 'Lengua';

  -- Tablas viejas o de registro, solo si existen
  IF to_regclass('public.planificaciones_pud') IS NOT NULL THEN
    UPDATE public.planificaciones_pud SET materia = v_destino WHERE materia = 'Lengua';
  END IF;
  IF to_regclass('public.coordinador_permisos') IS NOT NULL THEN
    UPDATE public.coordinador_permisos SET subjects = array_replace(subjects, 'Lengua', v_destino)
    WHERE 'Lengua' = ANY (subjects);
  END IF;

  DELETE FROM public.areas WHERE name = 'Lengua';
  RAISE NOTICE 'Área "Lengua" migrada a "%".', v_destino;
END $$;

-- ---------- 2. Hilos conductores reales ----------
INSERT INTO public.hilos_conductores (area_id, dimension, hilo)
SELECT a.id, v.dimension, v.hilo
FROM public.areas a
JOIN (VALUES
  -- Matemática
  ('Matemática', 'KNOWLEDGE',     '¿Qué es el saber matemático? / ¿Qué es – Qué significa “hacer” matemática? / ¿Qué implica hacer matemática?'),
  ('Matemática', 'METHOD',        '¿Cómo resuelvo lo planteado? ¿Cómo puedo resolver situaciones problemáticas?'),
  ('Matemática', 'PURPOSE',       '¿Para qué sirven las matemáticas?'),
  ('Matemática', 'COMMUNICATION', '¿Cómo comunicamos el saber matemático?'),

  -- Prácticas del lenguaje
  ('Prácticas del lenguaje', 'KNOWLEDGE',     '¿Qué debemos tener en cuenta para ser buenos comunicadores? (Contexto - uso)'),
  ('Prácticas del lenguaje', 'METHOD',        '¿Cómo podemos comunicarnos competentemente? (Práctica)'),
  ('Prácticas del lenguaje', 'PURPOSE',       '¿Para qué nos comunicamos? (Cambios y transformaciones que puedo generar a través de mi comunicación)'),
  ('Prácticas del lenguaje', 'COMMUNICATION', '¿Cómo comunicamos lo aprendido? (Elegir la manera de comunicar lo comprendido. Desempeño final - creatividad - claridad)'),

  -- Ciencias Naturales
  ('Naturales', 'KNOWLEDGE',     '¿Qué generan los cambios?'),
  ('Naturales', 'METHOD',        '¿De qué manera se producen los cambios? ¿Cómo conocemos el mundo que nos rodea? ¿Cómo razonar con evidencia? ¿Cómo se constituyen los sistemas y los procesos?'),
  ('Naturales', 'PURPOSE',       '¿Para qué sirven los cambios? ¿Para qué utilizamos los conocimientos científicos?'),
  ('Naturales', 'COMMUNICATION', '¿Cómo comunicamos lo aprendido? ¿Cómo expreso el conocimiento científico?'),

  -- Ciencias Sociales
  ('Sociales', 'KNOWLEDGE',     '¿Qué generan los cambios? ¿Cómo compartimos el planeta? ¿Cómo conocemos el mundo que nos rodea?'),
  ('Sociales', 'METHOD',        '¿Cómo nos organizamos? ¿Cómo el pasado me ayuda a comprender el presente? ¿De qué manera los cambios impactan al mundo?'),
  ('Sociales', 'PURPOSE',       '¿Para qué me sirve conocer los hechos pasados? ¿Para qué sirven los cambios? ¿Para qué nos sirve estudiar los cambios que se dan en el mundo a lo largo del tiempo?'),
  ('Sociales', 'COMMUNICATION', '¿Cómo se expresan las diferentes sociedades a través del tiempo?'),

  -- Language Arts
  ('Language Arts', 'KNOWLEDGE',     'What do we communicate?'),
  ('Language Arts', 'METHOD',        'How do we communicate correctly?'),
  ('Language Arts', 'PURPOSE',       'Why do we communicate?'),
  ('Language Arts', 'COMMUNICATION', 'How do we become effective communicators?')
) AS v(area_name, dimension, hilo)
  ON public.areas_nombre_normalizado(a.name) = public.areas_nombre_normalizado(v.area_name)
ON CONFLICT (area_id, dimension) DO UPDATE
  SET hilo = EXCLUDED.hilo, updated_at = now();

COMMIT;

-- Verificación: debería listar 4 filas por cada una de las 5 áreas.
-- Si falta alguna área, es que no existe con ese nombre en 'areas'.
SELECT a.name AS area, h.dimension, h.hilo
FROM public.hilos_conductores h
JOIN public.areas a ON a.id = h.area_id
WHERE public.areas_nombre_normalizado(a.name) IN (
  public.areas_nombre_normalizado('Matemática'),
  public.areas_nombre_normalizado('Prácticas del lenguaje'),
  public.areas_nombre_normalizado('Naturales'),
  public.areas_nombre_normalizado('Sociales'),
  public.areas_nombre_normalizado('Language Arts')
)
ORDER BY a.name, array_position(ARRAY['KNOWLEDGE','METHOD','PURPOSE','COMMUNICATION'], h.dimension);
