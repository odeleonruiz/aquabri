-- Replica las definiciones ya desplegadas en AQUABRI STAGING.
-- Revisar antes de cualquier despliegue a producción.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_cliente_asignar_responsable_auth_v1(p_cliente bigint, p_usuario bigint, p_nota text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF ctx.rol_usuario<>'jefe' THEN RAISE EXCEPTION 'Solo jefe asigna responsables de clientes' USING ERRCODE='42501'; END IF;
 IF p_cliente IS NULL OR p_cliente<=0 OR length(coalesce(p_nota,''))>250 THEN RAISE EXCEPTION 'Datos de asignacion invalidos'; END IF;
 RETURN public.aq_cliente_asignar_responsable(ctx.sesion_token,ctx.usuario_id,p_cliente,p_usuario,p_nota);
END $function$


CREATE OR REPLACE FUNCTION public.aq_clientes_atribucion_listar_auth_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF ctx.rol_usuario<>'jefe' THEN RAISE EXCEPTION 'Solo jefe consulta asignaciones de clientes' USING ERRCODE='42501'; END IF;
 RETURN public.aq_clientes_atribucion_listar(ctx.sesion_token,ctx.usuario_id);
END $function$


CREATE OR REPLACE FUNCTION public.aq_finalizar_incentivo_auth_v1(p_incentivo bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF ctx.rol_usuario<>'jefe' THEN RAISE EXCEPTION 'Solo jefe puede finalizar incentivos' USING ERRCODE='42501'; END IF;
 IF p_incentivo IS NULL OR p_incentivo<=0 THEN RAISE EXCEPTION 'Incentivo invalido'; END IF;
 RETURN public.aq_finalizar_incentivo(ctx.sesion_token,ctx.usuario_id,p_incentivo);
END $function$


CREATE OR REPLACE FUNCTION public.aq_guardar_equipo_auth_v1(p_nombre text, p_empleado_a bigint, p_empleado_b bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF ctx.rol_usuario<>'jefe' THEN RAISE EXCEPTION 'Solo jefe puede crear equipos' USING ERRCODE='42501'; END IF;
 IF length(btrim(coalesce(p_nombre,'')))<2 OR length(p_nombre)>120 THEN RAISE EXCEPTION 'Nombre de equipo invalido'; END IF;
 RETURN public.aq_guardar_equipo(ctx.sesion_token,ctx.usuario_id,p_nombre,p_empleado_a,p_empleado_b);
END $function$


CREATE OR REPLACE FUNCTION public.aq_guardar_incentivo_auth_v1(p_cliente bigint, p_producto bigint, p_captador bigint, p_equipo bigint, p_modalidad text, p_beneficiario bigint, p_importe numeric, p_confirmado boolean)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF ctx.rol_usuario<>'jefe' THEN RAISE EXCEPTION 'Solo jefe puede autorizar incentivos' USING ERRCODE='42501'; END IF;
 RETURN public.aq_guardar_incentivo(ctx.sesion_token,ctx.usuario_id,p_cliente,p_producto,
 p_captador,p_equipo,p_modalidad,p_beneficiario,p_importe,p_confirmado);
END $function$


CREATE OR REPLACE FUNCTION public.aq_movimientos_incentivos_auth_v1(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record; emp integer;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT (aquabri_private.tiene_permiso_actual('comisiones')
      OR aquabri_private.tiene_permiso_actual('reportes')
      OR aquabri_private.tiene_permiso_actual('rrhh')) THEN
   RAISE EXCEPTION 'Sin permiso de comisiones' USING ERRCODE='42501';
 END IF;
 IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta<p_desde OR p_hasta>p_desde+interval '5 years' THEN
  RAISE EXCEPTION 'Rango de fechas invalido';
 END IF;
 SELECT empleado_id INTO emp FROM public.usuarios WHERE id=ctx.usuario_id;
 RETURN coalesce((
  SELECT jsonb_agg(to_jsonb(m) ORDER BY m.fecha DESC,m.id DESC)
  FROM public.aq_incentivos_devengados m
  WHERE m.fecha BETWEEN p_desde AND p_hasta
   AND (ctx.rol_usuario='jefe' OR (emp IS NOT NULL AND m.empleado_id=emp))
 ),'[]'::jsonb);
END $function$

REVOKE ALL ON FUNCTION public.aq_guardar_equipo_auth_v1(text,bigint,bigint),
public.aq_guardar_incentivo_auth_v1(bigint,bigint,bigint,bigint,text,bigint,numeric,boolean),
public.aq_finalizar_incentivo_auth_v1(bigint),
public.aq_clientes_atribucion_listar_auth_v1(),
public.aq_cliente_asignar_responsable_auth_v1(bigint,bigint,text),
public.aq_movimientos_incentivos_auth_v1(date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aq_guardar_equipo_auth_v1(text,bigint,bigint),
public.aq_guardar_incentivo_auth_v1(bigint,bigint,bigint,bigint,text,bigint,numeric,boolean),
public.aq_finalizar_incentivo_auth_v1(bigint),
public.aq_clientes_atribucion_listar_auth_v1(),
public.aq_cliente_asignar_responsable_auth_v1(bigint,bigint,text),
public.aq_movimientos_incentivos_auth_v1(date,date) TO authenticated;
COMMIT;
