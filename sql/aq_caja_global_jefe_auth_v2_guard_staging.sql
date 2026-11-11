-- AQUABRI STAGING — reforzar caja global: solo jefe, incluso si se delegara permiso de caja.
-- Aplicado únicamente a xzbawbkstaqvkwtqlqai.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_abrir_caja_auth_v2(
 p_nonce text,p_fecha date,p_monto numeric,
 p_usuario_caja integer DEFAULT NULL,p_notas text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $fn$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF ctx.rol_usuario <> 'jefe'
    OR NOT aquabri_private.tiene_permiso_actual('caja.abrir') THEN
  RAISE EXCEPTION 'Apertura de Caja global reservada al jefe' USING ERRCODE='42501';
 END IF;
 RETURN public.aq_caja_abrir_seguro(
 ctx.sesion_token,ctx.usuario_id,p_nonce,p_fecha,p_monto,
 coalesce(p_usuario_caja,ctx.usuario_id::integer),p_notas);
END;
$fn$;
CREATE OR REPLACE FUNCTION public.aq_cerrar_caja_auth_v2(
 p_nonce text,p_fecha date,p_apertura_id integer,p_contado numeric,
 p_esperado_cliente numeric,p_num_movimientos integer,
 p_acepta_sin_clasificar boolean DEFAULT false,
 p_acepta_diferencia boolean DEFAULT false,p_notas text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $fn$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF ctx.rol_usuario <> 'jefe'
   OR NOT aquabri_private.tiene_permiso_actual('caja.cerrar') THEN
  RAISE EXCEPTION 'Cierre de Caja global reservado al jefe' USING ERRCODE='42501';
 END IF;
 RETURN public.aq_caja_cerrar_seguro(
 ctx.sesion_token,ctx.usuario_id,p_nonce,p_fecha,p_apertura_id,
 p_contado,p_esperado_cliente,p_num_movimientos,
 p_acepta_sin_clasificar,p_acepta_diferencia,p_notas);
END;
$fn$;
COMMIT;
