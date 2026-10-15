-- =========================================================
-- Migración: funciones y regla de áreas (Security Advisor, segunda pasada)
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- 1. Funciones que se podían ejecutar sin iniciar sesión. Todas verifican
--    internamente quién las llama (no eran explotables), pero ninguna se usa
--    sin sesión: se cierran para visitantes como defensa adicional.
--      aldia_seguimiento_capsulas   Al Día (coordinación y dirección)
--      completar_paso               Onboarding
--      director_onboarding_overview Panel de Dirección
--      revisar_pud_presentado       Panel de Coordinación
--    crear_perfil_nuevo_usuario es del nivelador de inglés: se cierra para
--    todos (si es un trigger, sigue funcionando igual).
--
-- 2. areas: la regla de alta decía "siempre"; ahora dice "con sesión
--    iniciada", que es lo mismo en la práctica y deja de marcarse.
--
-- Se dejan a propósito:
-- - correo_autorizado ejecutable sin sesión: el registro la consulta antes
--   de crear la cuenta.
-- - Funciones ejecutables con sesión (las del punto 1, crear_coordinador y
--   correo_autorizado): las usan docentes, coordinadores y Dirección, y cada
--   una verifica internamente el rol de quien la llama.
-- - unaccent en public y "Leaked Password Protection" (no disponible en el
--   plan gratis).
-- =========================================================

BEGIN;

DO $$
DECLARE
  f regprocedure;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('aldia_seguimiento_capsulas', 'completar_paso', 'director_onboarding_overview', 'revisar_pud_presentado')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM public, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    RAISE NOTICE 'Solo con sesión: %', f;
  END LOOP;

  FOR f IN
    SELECT p.oid::regprocedure
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'crear_perfil_nuevo_usuario'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM public, anon, authenticated', f);
    RAISE NOTICE 'Cerrada: %', f;
  END LOOP;
END $$;

DROP POLICY IF EXISTS areas_insert_authenticated ON public.areas;
CREATE POLICY areas_insert_authenticated ON public.areas
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

COMMIT;
