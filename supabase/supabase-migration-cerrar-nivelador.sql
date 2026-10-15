-- =========================================================
-- Migración: cerrar el nivelador de inglés (otro sistema en esta base)
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- El nivelador de inglés gamificado es una aplicación aparte que quedó en
-- este proyecto de Supabase. Austin no lo usa. Estaba expuesto: cualquiera,
-- sin iniciar sesión, podía ver las respuestas correctas (preguntas) y los
-- mails y niveles de quienes hicieron el test (historial_tests).
--
-- Se cierra por completo SIN BORRAR DATOS: nadie puede leerlo ni escribirlo
-- desde afuera; desde el dashboard de Supabase se sigue viendo todo. Si en
-- algún momento se quiere recuperar o mudar a otro proyecto, está intacto.
--
-- Del nivelador:   perfiles, resultados, preguntas, historial_tests,
--                  preguntas_publicas (vista), get_random_questions,
--                  evaluar_test, evaluar_test_adaptativo, es_admin.
-- NO se tocan:     perfiles_dislexia y niveles_idioma (son del generador de
--                  Adaptaciones de Austin).
-- =========================================================

BEGIN;

-- Tablas: protección activada, sin reglas de acceso y sin permisos para
-- visitantes ni usuarios con sesión. (perfiles además tenía una regla rota
-- con recursión infinita: se elimina junto con las demás.)
DO $$
DECLARE
  t text;
  p record;
BEGIN
  FOREACH t IN ARRAY ARRAY['perfiles', 'resultados', 'preguntas', 'historial_tests'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      FOR p IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = t LOOP
        EXECUTE format('DROP POLICY %I ON public.%I', p.policyname, t);
      END LOOP;
      EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
      RAISE NOTICE 'Cerrada: %', t;
    END IF;
  END LOOP;
END $$;

-- Vista de preguntas: respeta los permisos de quien consulta (resuelve el
-- error "Security Definer View") y queda cerrada.
DO $$
BEGIN
  IF to_regclass('public.preguntas_publicas') IS NOT NULL THEN
    ALTER VIEW public.preguntas_publicas SET (security_invoker = true);
    REVOKE ALL ON public.preguntas_publicas FROM anon, authenticated;
    RAISE NOTICE 'Cerrada: preguntas_publicas';
  END IF;
END $$;

-- Funciones del nivelador: nadie las puede ejecutar desde afuera.
DO $$
DECLARE
  f regprocedure;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('get_random_questions', 'evaluar_test', 'evaluar_test_adaptativo', 'es_admin')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM public, anon, authenticated', f);
    RAISE NOTICE 'Cerrada: %', f;
  END LOOP;
END $$;

COMMIT;

-- Verificación: las 4 tablas con rls = true y 0 reglas.
SELECT c.relname AS tabla, c.relrowsecurity AS rls,
       (SELECT count(*) FROM pg_policies pp WHERE pp.schemaname = 'public' AND pp.tablename = c.relname) AS reglas
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN ('perfiles', 'resultados', 'preguntas', 'historial_tests')
ORDER BY c.relname;
