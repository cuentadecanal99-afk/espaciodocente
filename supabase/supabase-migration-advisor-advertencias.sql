-- =========================================================
-- Migración: advertencias del Security Advisor (las seguras de corregir)
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- 1. "Function Search Path Mutable" (4): se fija el search_path de las
--    funciones para que no se puedan engañar con objetos de otro esquema.
--    No cambia lo que hacen.
-- 2. "RLS Policy Always True" en planificaciones_pud: cualquiera, sin
--    iniciar sesión, podía cargar filas. Espacio Docente solo la usa con
--    sesión iniciada (registro de cada prompt generado).
-- 3. "Public Can See Object in GraphQL Schema" (unas 60): ninguna
--    aplicación usa GraphQL (todas consultan por la API común), así que se
--    desactiva. Se puede volver a activar en Database → Extensions →
--    pg_graphql. Los datos ya estaban protegidos; esto solo oculta la lista
--    de tablas y columnas.
--
-- Se dejan a propósito:
-- - "Extension in Public" (unaccent): moverla obliga a reescribir la función
--   que normaliza nombres de áreas; el riesgo es bajo.
-- - "RLS Policy Always True" en areas: cualquier docente con sesión puede
--   crear un área nueva desde Planificación; es el comportamiento buscado.
-- - preguntas, historial_tests y preguntas_publicas (prueba de nivel):
--   pendientes hasta confirmar cómo se usa esa aplicación.
-- =========================================================

BEGIN;

-- ---------- 1. search_path fijo ----------
DO $$
DECLARE
  f regprocedure;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('areas_nombre_normalizado', 'get_random_questions', 'evaluar_test', 'evaluar_test_adaptativo')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public', f);
    RAISE NOTICE 'search_path fijado: %', f;
  END LOOP;
END $$;

-- ---------- 2. planificaciones_pud: solo con sesión ----------
DROP POLICY IF EXISTS "Habilitar inserción pública anónima" ON public.planificaciones_pud;
DROP POLICY IF EXISTS planificaciones_pud_insert_con_sesion ON public.planificaciones_pud;
CREATE POLICY planificaciones_pud_insert_con_sesion ON public.planificaciones_pud
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

COMMIT;

-- ---------- 3. GraphQL desactivado (fuera de la transacción) ----------
DROP EXTENSION IF EXISTS pg_graphql;
