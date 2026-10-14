-- =========================================================
-- Migración: bloqueo de alumnos + hilos de Science + rúbricas guardadas
-- Correr a mano en Supabase SQL Editor, DESPUÉS de
-- supabase-migration-altas-automaticas.sql. Idempotente.
--
-- 1. ALUMNOS: comparten el dominio @austinebs-ah.edu.ar con el staff, pero
--    sus correos empiezan con "st." (st.nombre.apellido@...). Esos correos
--    ya no se autorizan solos. Si algún caso puntual necesitara acceso, se
--    carga a mano en allowed_emails y entra igual.
--
-- 2. CONSULTA DE CORREOS: correo_autorizado() (la puede llamar cualquiera,
--    sin sesión) ya no dice si un correo es de un coordinador o directivo.
--    Antes alcanzaba con probar un correo para saber si esa persona tenía
--    un cargo. Coordinadores y directivos no la necesitan: entran por
--    invitación o se cargan a mano, y el trigger los sigue dejando pasar.
--
-- 3. SCIENCE: recibe los hilos de Naturales traducidos al inglés.
--
-- 4. RÚBRICAS: tabla para guardar la rúbrica de cada PUD (una por PUD y
--    desempeño, por docente). Cada docente ve y edita solo las suyas.
--
-- 5. ALTAS SIN MAILS: se apaga la invitación automática de coordinadores y
--    se confirman las cuentas autorizadas que quedaron pendientes. Va junto
--    con apagar Authentication → Sign In / Providers → Email → "Confirm email".
-- =========================================================

BEGIN;

-- ---------- 1. Quién puede crear una cuenta ----------
CREATE OR REPLACE FUNCTION public.validar_correo_autorizado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text := lower(trim(NEW.email));
BEGIN
  -- Excepciones cargadas a mano, coordinadores invitados y directivos
  IF EXISTS (SELECT 1 FROM public.allowed_emails WHERE lower(email) = v_email)
     OR EXISTS (SELECT 1 FROM public.coordinadores WHERE lower(email) = v_email)
     OR EXISTS (SELECT 1 FROM public.directores WHERE lower(email) = v_email) THEN
    RETURN NEW;
  END IF;

  -- Staff con correo institucional (los de alumnos empiezan con "st.")
  IF split_part(v_email, '@', 2) = 'austinebs-ah.edu.ar' AND v_email NOT LIKE 'st.%' THEN
    INSERT INTO public.allowed_emails (email) VALUES (v_email)
    ON CONFLICT DO NOTHING;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Correo no autorizado por el colegio: %', NEW.email;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.validar_correo_autorizado() FROM public, anon, authenticated;

-- ---------- 2. Chequeo previo del front (solo true/false) ----------
CREATE OR REPLACE FUNCTION public.correo_autorizado(p_email text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (split_part(lower(trim(p_email)), '@', 2) = 'austinebs-ah.edu.ar'
          AND lower(trim(p_email)) NOT LIKE 'st.%')
      OR EXISTS (SELECT 1 FROM public.allowed_emails WHERE lower(email) = lower(trim(p_email)));
$$;
REVOKE ALL ON FUNCTION public.correo_autorizado(text) FROM public;
GRANT EXECUTE ON FUNCTION public.correo_autorizado(text) TO anon, authenticated;

-- Si algún alumno llegó a registrarse mientras estuvo abierto el dominio,
-- se lo saca de la lista del staff. Su cuenta NO se borra acá: revisá la
-- consulta de verificación del final y decidí desde Authentication → Users.
DELETE FROM public.allowed_emails
WHERE lower(email) LIKE 'st.%@austinebs-ah.edu.ar';

-- ---------- 3. Hilos conductores de Science ----------
INSERT INTO public.hilos_conductores (area_id, dimension, hilo)
SELECT a.id, v.dimension, v.hilo
FROM public.areas a
JOIN (VALUES
  ('Science', 'KNOWLEDGE',     'What do changes generate?'),
  ('Science', 'METHOD',        'How are changes produced? How do we get to know the world around us? How do we reason with evidence? How are systems and processes made up?'),
  ('Science', 'PURPOSE',       'What are changes for? What do we use scientific knowledge for?'),
  ('Science', 'COMMUNICATION', 'How do we communicate what we have learned? How do I express scientific knowledge?')
) AS v(area_name, dimension, hilo)
  ON public.areas_nombre_normalizado(a.name) = public.areas_nombre_normalizado(v.area_name)
ON CONFLICT (area_id, dimension) DO UPDATE
  SET hilo = EXCLUDED.hilo, updated_at = now();

-- ---------- 4. Rúbricas guardadas ----------
CREATE TABLE IF NOT EXISTS public.rubricas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  pud_id text NOT NULL,                       -- mismo pudId que usa el contexto del PUD (pud-contexto.js)
  desempeno_id text NOT NULL DEFAULT '',      -- '' si la rúbrica no apunta a un desempeño puntual
  meta_ids text[] NOT NULL DEFAULT '{}',
  escala text NOT NULL DEFAULT 'epc',
  idioma text NOT NULL DEFAULT 'es-en',
  titulo text,
  criterios jsonb NOT NULL DEFAULT '[]',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, pud_id, desempeno_id)
);
CREATE INDEX IF NOT EXISTS idx_rubricas_user_pud ON public.rubricas (user_id, pud_id);

CREATE OR REPLACE FUNCTION public.rubricas_tocar_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_rubricas_updated_at ON public.rubricas;
CREATE TRIGGER trg_rubricas_updated_at
  BEFORE UPDATE ON public.rubricas
  FOR EACH ROW EXECUTE FUNCTION public.rubricas_tocar_updated_at();

ALTER TABLE public.rubricas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rubricas_select_own ON public.rubricas;
CREATE POLICY rubricas_select_own ON public.rubricas
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS rubricas_insert_own ON public.rubricas;
CREATE POLICY rubricas_insert_own ON public.rubricas
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS rubricas_update_own ON public.rubricas;
CREATE POLICY rubricas_update_own ON public.rubricas
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS rubricas_delete_own ON public.rubricas;
CREATE POLICY rubricas_delete_own ON public.rubricas
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- ---------- 5. Altas sin mails (requiere "Confirm email" apagado) ----------
-- Cada persona se registra sola con su correo y entra en el momento; no se
-- manda ningún mail. Por eso:
-- a) Se apaga la invitación automática de coordinadores: sin servidor de
--    mail, podía dejar la cuenta creada pero sin contraseña, y entonces la
--    persona ya no podía registrarse. Ahora Dirección la da de alta en el
--    panel y la persona se registra en Espacio Docente con ese correo.
DROP TRIGGER IF EXISTS trg_invitar_coordinador ON public.coordinadores;

-- b) Se confirman las cuentas autorizadas que quedaron esperando el mail de
--    confirmación (registros de antes de apagar "Confirm email").
UPDATE auth.users u
SET email_confirmed_at = now()
WHERE u.email_confirmed_at IS NULL
  AND (
    (split_part(lower(u.email), '@', 2) = 'austinebs-ah.edu.ar' AND lower(u.email) NOT LIKE 'st.%')
    OR EXISTS (SELECT 1 FROM public.allowed_emails a WHERE lower(a.email) = lower(u.email))
    OR EXISTS (SELECT 1 FROM public.coordinadores c WHERE lower(c.email) = lower(u.email))
    OR EXISTS (SELECT 1 FROM public.directores d WHERE lower(d.email) = lower(u.email))
  );

COMMIT;

-- Verificación 1: cuentas de alumnos que se hayan creado (debería estar vacía).
SELECT email, created_at FROM auth.users
WHERE lower(email) LIKE 'st.%@austinebs-ah.edu.ar'
ORDER BY created_at DESC;

-- Verificación 2: Science con sus 4 hilos.
SELECT a.name, h.dimension, h.hilo
FROM public.hilos_conductores h JOIN public.areas a ON a.id = h.area_id
WHERE public.areas_nombre_normalizado(a.name) = public.areas_nombre_normalizado('Science')
ORDER BY array_position(ARRAY['KNOWLEDGE','METHOD','PURPOSE','COMMUNICATION'], h.dimension);
