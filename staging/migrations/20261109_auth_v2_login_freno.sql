-- Entorno de PRUEBAS. Protección del puente de inicio de sesión con usuario.
-- No modifica el inicio de sesión actual en producción.
CREATE TABLE IF NOT EXISTS public.aq_auth_login_freno (
  clave text PRIMARY KEY,
  ventana timestamptz NOT NULL DEFAULT now(),
  intentos integer NOT NULL DEFAULT 0,
  actualizado timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT aq_login_clave_sha256 CHECK (clave ~ '^[0-9a-f]{64}$'),
  CONSTRAINT aq_login_intentos_nopos CHECK (intentos >= 0)
);
ALTER TABLE public.aq_auth_login_freno ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.aq_auth_login_freno FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.aq_auth_login_freno TO service_role;

CREATE OR REPLACE FUNCTION public.aq_auth_login_admitir_intento(p_clave text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_intentos integer;
BEGIN
 IF p_clave IS NULL OR p_clave !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'Clave inválida' USING ERRCODE='22023';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(hashtext(p_clave)::bigint);
 INSERT INTO public.aq_auth_login_freno(clave,ventana,intentos,actualizado)
 VALUES (p_clave,now(),1,now())
 ON CONFLICT(clave) DO UPDATE SET
  intentos=CASE WHEN public.aq_auth_login_freno.ventana < now()-interval '15 minutes'
                THEN 1 ELSE public.aq_auth_login_freno.intentos+1 END,
  ventana=CASE WHEN public.aq_auth_login_freno.ventana < now()-interval '15 minutes'
               THEN now() ELSE public.aq_auth_login_freno.ventana END,
  actualizado=now()
 RETURNING intentos INTO v_intentos;
 RETURN v_intentos<=10;
END;
$fn$;
REVOKE ALL ON FUNCTION public.aq_auth_login_admitir_intento(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aq_auth_login_admitir_intento(text) TO service_role;
