-- =========================================================
-- Migración: protección de la tabla resultados (Security Advisor)
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- El Security Advisor marcó "RLS Disabled in Public" en public.resultados
-- (id, user_id, nivel_asignado, created_at). Sin RLS, cualquiera con la
-- clave pública podía leer, modificar o borrar todos los resultados.
-- supabase-migration-endurecimiento-general.sql (2026-09-28) ya la
-- protegía, pero hoy aparece desactivada: esta migración la vuelve a
-- proteger y agrega lectura para administradores (perfiles.rol = 'admin').
--
-- Cada usuario ve y carga solo sus resultados. Nadie puede modificarlos ni
-- borrarlos desde la app (no hay políticas de UPDATE ni DELETE).
-- =========================================================

BEGIN;

ALTER TABLE public.resultados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS resultados_select_own ON public.resultados;
CREATE POLICY resultados_select_own ON public.resultados
  FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS resultados_insert_own ON public.resultados;
CREATE POLICY resultados_insert_own ON public.resultados
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- Lectura para administradores, solo si existe perfiles con la columna rol.
-- es_admin() se crea acá porque la migración del 28/09 no llegó a crearla.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'perfiles' AND column_name = 'rol'
  ) THEN
    EXECUTE $f$
      CREATE OR REPLACE FUNCTION public.es_admin()
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path TO 'public'
      AS $body$
        SELECT EXISTS (SELECT 1 FROM public.perfiles WHERE id = auth.uid() AND rol = 'admin');
      $body$
    $f$;
    REVOKE EXECUTE ON FUNCTION public.es_admin() FROM public, anon;
    GRANT EXECUTE ON FUNCTION public.es_admin() TO authenticated;

    DROP POLICY IF EXISTS resultados_select_admin ON public.resultados;
    CREATE POLICY resultados_select_admin ON public.resultados
      FOR SELECT TO authenticated USING (public.es_admin());
    RAISE NOTICE 'Lectura para administradores creada.';
  ELSE
    RAISE NOTICE 'No existe perfiles.rol: no se crea la lectura para administradores.';
  END IF;
END $$;

COMMIT;

-- Verificación: debería decir rls_activado = true y listar 2 o 3 políticas.
SELECT relrowsecurity AS rls_activado FROM pg_class WHERE oid = 'public.resultados'::regclass;
SELECT policyname, cmd FROM pg_policies WHERE schemaname = 'public' AND tablename = 'resultados';
