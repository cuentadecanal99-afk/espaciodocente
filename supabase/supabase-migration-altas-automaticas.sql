-- =========================================================
-- Migración: altas sin pasar por el dashboard de Supabase
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- 1. DOCENTES: cualquier correo @austinebs-ah.edu.ar puede crearse la
--    cuenta solo desde Espacio Docente. Al registrarse, el correo se agrega
--    a allowed_emails, así sigue apareciendo en los reportes del staff
--    (onboarding, cápsulas) que se basan en esa tabla. Los correos de otro
--    dominio que ya están en allowed_emails siguen funcionando igual.
--
-- 2. COORDINADORES Y DIRECTIVOS: su invitación ya no se rechaza. Antes, el
--    trigger antes_de_crear_usuario bloqueaba cualquier usuario nuevo que no
--    estuviera en allowed_emails, incluida la invitación automática de
--    invitar_coordinador(); como esa invitación se manda sin esperar
--    respuesta, el fallo pasaba sin aviso.
--
-- 3. PANEL DE DIRECCIÓN: crear_coordinador() da de alta a un coordinador con
--    sus grados y materias en una sola transacción. Importa que sea atómico:
--    un coordinador sin filas de permisos ve TODO, así que si los permisos
--    fallaran después de crear el coordinador, quedaría con acceso total.
--    Solo la puede usar alguien que esté en la tabla directores.
-- =========================================================

-- ---------- 1 y 2. Quién puede crear una cuenta ----------
CREATE OR REPLACE FUNCTION public.validar_correo_autorizado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text := lower(trim(NEW.email));
BEGIN
  -- Correo institucional: se autoriza y se suma a la lista del staff
  IF split_part(v_email, '@', 2) = 'austinebs-ah.edu.ar' THEN
    INSERT INTO public.allowed_emails (email) VALUES (v_email)
    ON CONFLICT DO NOTHING;
    RETURN NEW;
  END IF;

  -- Excepciones cargadas a mano, coordinadores invitados y directivos
  IF EXISTS (SELECT 1 FROM public.allowed_emails WHERE lower(email) = v_email)
     OR EXISTS (SELECT 1 FROM public.coordinadores WHERE lower(email) = v_email)
     OR EXISTS (SELECT 1 FROM public.directores WHERE lower(email) = v_email) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Correo no autorizado por el colegio: %', NEW.email;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.validar_correo_autorizado() FROM public, anon, authenticated;

-- El trigger ya existe (SETUP-SUPABASE.md); se recrea por si faltara.
DROP TRIGGER IF EXISTS antes_de_crear_usuario ON auth.users;
CREATE TRIGGER antes_de_crear_usuario
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.validar_correo_autorizado();

-- Chequeo previo que hace el front antes de signUp (solo devuelve true/false).
CREATE OR REPLACE FUNCTION public.correo_autorizado(p_email text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT split_part(lower(trim(p_email)), '@', 2) = 'austinebs-ah.edu.ar'
      OR EXISTS (SELECT 1 FROM public.allowed_emails WHERE lower(email) = lower(trim(p_email)))
      OR EXISTS (SELECT 1 FROM public.coordinadores WHERE lower(email) = lower(trim(p_email)))
      OR EXISTS (SELECT 1 FROM public.directores WHERE lower(email) = lower(trim(p_email)));
$$;
REVOKE ALL ON FUNCTION public.correo_autorizado(text) FROM public;
GRANT EXECUTE ON FUNCTION public.correo_autorizado(text) TO anon, authenticated;

-- ---------- 3. Alta de coordinadores desde el Panel de Dirección ----------
CREATE OR REPLACE FUNCTION public.crear_coordinador(
  p_email text,
  p_nombre text,
  p_grados text[] DEFAULT '{}',
  p_materias text[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text := lower(trim(p_email));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.directores d WHERE d.email = lower(auth.jwt() ->> 'email')) THEN
    RAISE EXCEPTION 'Solo Dirección puede dar de alta coordinadores.' USING ERRCODE = '42501';
  END IF;
  IF v_email IS NULL OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RAISE EXCEPTION 'El correo "%" no es válido.', p_email USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.coordinadores WHERE lower(email) = v_email) THEN
    RAISE EXCEPTION 'Ese correo ya está dado de alta como coordinador.' USING ERRCODE = '23505';
  END IF;

  -- El trigger trg_invitar_coordinador manda la invitación por mail al confirmarse la transacción.
  INSERT INTO public.coordinadores (email, nombre) VALUES (v_email, nullif(trim(p_nombre), ''));

  -- Sin filas = ve todos los grados / todas las materias.
  INSERT INTO public.coordinador_permiso_grados (email, grado)
  SELECT DISTINCT v_email, g FROM unnest(coalesce(p_grados, '{}')) AS g;
  INSERT INTO public.coordinador_permiso_materias (email, materia)
  SELECT DISTINCT v_email, m FROM unnest(coalesce(p_materias, '{}')) AS m;
END;
$$;
REVOKE ALL ON FUNCTION public.crear_coordinador(text, text, text[], text[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.crear_coordinador(text, text, text[], text[]) TO authenticated;

-- Lectura para Dirección: el panel lista coordinadores y sus permisos.
-- Las políticas se suman a las existentes (cada coordinador sigue viendo solo lo suyo).
DROP POLICY IF EXISTS coordinadores_select_director ON public.coordinadores;
CREATE POLICY coordinadores_select_director ON public.coordinadores
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.directores d WHERE d.email = lower(auth.jwt() ->> 'email')));

DROP POLICY IF EXISTS coordinador_permiso_grados_select_director ON public.coordinador_permiso_grados;
CREATE POLICY coordinador_permiso_grados_select_director ON public.coordinador_permiso_grados
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.directores d WHERE d.email = lower(auth.jwt() ->> 'email')));

DROP POLICY IF EXISTS coordinador_permiso_materias_select_director ON public.coordinador_permiso_materias;
CREATE POLICY coordinador_permiso_materias_select_director ON public.coordinador_permiso_materias
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.directores d WHERE d.email = lower(auth.jwt() ->> 'email')));
