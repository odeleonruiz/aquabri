-- AQUABRI: puente AUTH V2 para gastos (aplicado SOLO a staging).
-- Reutiliza motor de gastos con validación de sesión/token generados en servidor.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_registrar_gasto_auth_v2(
  p_nonce text, p_gasto jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $f$
DECLARE ctx record;
BEGIN
  SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
  IF NOT aquabri_private.tiene_permiso_actual('gastos') THEN
    RAISE EXCEPTION 'Sin permiso para registrar gastos' USING ERRCODE='42501';
  END IF;
  RETURN public.aq_registrar_gasto_seguro(ctx.sesion_token,ctx.usuario_id,p_nonce,p_gasto);
END;
$f$;
CREATE OR REPLACE FUNCTION public.aq_eliminar_gasto_auth_v2(
  p_gasto_id integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $f$
DECLARE ctx record;
BEGIN
  SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
  IF NOT aquabri_private.tiene_permiso_actual('gastos') THEN
    RAISE EXCEPTION 'Sin permiso para eliminar gastos' USING ERRCODE='42501';
  END IF;
  RETURN public.aq_eliminar_gasto_seguro(ctx.sesion_token,ctx.usuario_id,p_gasto_id);
END;
$f$;
REVOKE ALL ON FUNCTION public.aq_registrar_gasto_auth_v2(text,jsonb) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.aq_eliminar_gasto_auth_v2(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aq_registrar_gasto_auth_v2(text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aq_eliminar_gasto_auth_v2(integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.aq_registrar_gasto_seguro(text,bigint,text,jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.aq_eliminar_gasto_seguro(text,bigint,integer) FROM authenticated;
COMMIT;
-- Verificaciones en staging:
-- anon NO ejecuta ni v2 ni legacy.
-- authenticated ejecuta solo wrappers, no legacy.
-- UUID inexistente: rechazado; vendedor sin permiso: rechazado.
-- Jefe con gasto inválido: rechazo de datos (superó autenticación y permiso).
