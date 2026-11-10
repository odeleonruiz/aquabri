-- Preparación compatible y no destructiva de autenticación AQUABRI.
-- Ya aplicada en aquabri-sistema el 2026-11-09, documentada para recuperación.
-- Mantiene las IDs de public.usuarios y el inicio de sesión antiguo.
-- NO habilitar RLS definitiva hasta vincular y probar cuentas Supabase Auth.
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS auth_uid uuid;
CREATE UNIQUE INDEX IF NOT EXISTS aq_usuarios_auth_uid_uq
  ON public.usuarios (auth_uid) WHERE auth_uid IS NOT NULL;
COMMENT ON COLUMN public.usuarios.auth_uid IS
 'Vinculo opcional Supabase Auth; nunca alterar desde cliente. No modifica ID legado.';

CREATE OR REPLACE FUNCTION public.aq_proteger_auth_uid_legacy()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog, public AS $guard$
BEGIN
  IF current_user IN ('anon','authenticated') THEN
    IF TG_OP='INSERT' AND NEW.auth_uid IS NOT NULL THEN
      RAISE EXCEPTION 'Vinculacion Auth debe realizarla una funcion administrativa autorizada' USING ERRCODE='42501';
    ELSIF TG_OP='UPDATE' AND NEW.auth_uid IS DISTINCT FROM OLD.auth_uid THEN
      RAISE EXCEPTION 'No se puede cambiar la identidad Auth desde el cliente' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $guard$;
REVOKE EXECUTE ON FUNCTION public.aq_proteger_auth_uid_legacy() FROM PUBLIC,anon,authenticated;
DO $once$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.usuarios'::regclass
   AND tgname='aq_proteger_auth_uid_legacy_trg') THEN
  CREATE TRIGGER aq_proteger_auth_uid_legacy_trg BEFORE INSERT OR UPDATE
   ON public.usuarios FOR EACH ROW EXECUTE FUNCTION public.aq_proteger_auth_uid_legacy();
 END IF;
END $once$;

CREATE SCHEMA IF NOT EXISTS aquabri_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA aquabri_private FROM PUBLIC,anon;
GRANT USAGE ON SCHEMA aquabri_private TO authenticated;
CREATE OR REPLACE FUNCTION aquabri_private.usuario_id_actual()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$ SELECT u.id FROM public.usuarios u
 WHERE u.auth_uid=(SELECT auth.uid())
 AND EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.auth_uid)
 LIMIT 1 $f$;
CREATE OR REPLACE FUNCTION aquabri_private.rol_actual()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$ SELECT u.rol FROM public.usuarios u
 WHERE u.auth_uid=(SELECT auth.uid())
 AND EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.auth_uid)
 LIMIT 1 $f$;
REVOKE ALL ON FUNCTION aquabri_private.usuario_id_actual() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION aquabri_private.rol_actual() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION aquabri_private.usuario_id_actual() TO authenticated;
GRANT EXECUTE ON FUNCTION aquabri_private.rol_actual() TO authenticated;
