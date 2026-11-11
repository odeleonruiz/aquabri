-- AQUABRI STAGING ONLY. Replace Auth v1 bridge implementations without legacy sessions.
BEGIN;
CREATE OR REPLACE FUNCTION aquabri_private.aq_contexto_auth_nativo_v2()
RETURNS TABLE(usuario_id bigint, rol_usuario text, empleado_id integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE v_auth uuid;
BEGIN
 v_auth := (SELECT auth.uid());
 IF v_auth IS NULL OR coalesce((auth.jwt()->>'is_anonymous')::boolean,false) THEN
   RAISE EXCEPTION 'Debes iniciar sesión con Supabase Auth' USING ERRCODE='28000';
 END IF;
 SELECT u.id,u.rol,coalesce(u.empleado_id,(SELECT e.id FROM public.empleados e WHERE e.usuario_id=u.id ORDER BY e.id LIMIT 1)) INTO usuario_id,rol_usuario,empleado_id
 FROM public.usuarios u JOIN auth.users a ON a.id=u.auth_uid
 WHERE u.auth_uid=v_auth
   AND u.rol IN ('jefe','vendedor','vendedor_editor','inventario');
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Usuario de AQUABRI no autorizado' USING ERRCODE='42501';
 END IF;
 RETURN NEXT;
END;
$$;
REVOKE ALL ON FUNCTION aquabri_private.aq_contexto_auth_nativo_v2()
 FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.aq_guardar_equipo_auth_v1(
 p_nombre text,p_empleado_a bigint,p_empleado_b bigint
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record; v_id bigint;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe' THEN RAISE EXCEPTION 'Solo jefe crea equipos' USING ERRCODE='42501'; END IF;
 IF p_nombre IS NULL OR length(btrim(p_nombre))<2 OR length(btrim(p_nombre))>120
    OR p_empleado_a IS NULL OR p_empleado_b IS NULL OR p_empleado_a=p_empleado_b THEN
   RAISE EXCEPTION 'Equipo inválido: nombre y dos empleados diferentes requeridos' USING ERRCODE='22023';
 END IF;
 IF (SELECT count(*) FROM public.empleados WHERE id IN (p_empleado_a,p_empleado_b))<>2 THEN
   RAISE EXCEPTION 'Uno de los empleados no existe' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.aq_equipos_incentivo(nombre,empleado_a_id,empleado_b_id)
 VALUES(btrim(p_nombre),p_empleado_a,p_empleado_b) RETURNING id INTO v_id;
 RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.aq_guardar_incentivo_auth_v1(
 p_cliente bigint,p_producto bigint,p_captador bigint,p_equipo bigint,p_modalidad text,
 p_beneficiario bigint,p_importe numeric,p_confirmado boolean
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record; v_eq public.aq_equipos_incentivo%ROWTYPE; v_id bigint;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe' THEN
   RAISE EXCEPTION 'Solo jefe autoriza incentivos' USING ERRCODE='42501';
 END IF;
 IF p_importe IS NULL OR p_importe<=0 OR p_importe>10000
    OR round(p_importe,2)<>p_importe THEN
   RAISE EXCEPTION 'Monto inválido de incentivo' USING ERRCODE='22023';
 END IF;
 IF NOT coalesce(p_confirmado,false) THEN
   RAISE EXCEPTION 'Debes confirmar que el cliente fue captado' USING ERRCODE='22023';
 END IF;
 IF p_cliente IS NULL OR p_producto IS NULL OR p_captador IS NULL
    OR p_modalidad NOT IN ('individual','equipo') OR p_modalidad IS NULL THEN
   RAISE EXCEPTION 'Datos incompletos de incentivo' USING ERRCODE='22023';
 END IF;
 -- Serialize replacement of incentive configuration for this client.
 PERFORM 1 FROM public.clientes WHERE id=p_cliente FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Cliente inexistente' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.productos WHERE id=p_producto AND lower(nombre) LIKE '%garraf%') THEN
   RAISE EXCEPTION 'Solo aplica a productos garrafón' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.empleados WHERE id=p_captador) THEN
   RAISE EXCEPTION 'Empleado captador inexistente' USING ERRCODE='22023';
 END IF;
 IF p_equipo IS NOT NULL THEN
   SELECT * INTO v_eq FROM public.aq_equipos_incentivo WHERE id=p_equipo AND activo FOR SHARE;
   IF NOT FOUND OR p_captador NOT IN (v_eq.empleado_a_id,v_eq.empleado_b_id) THEN
     RAISE EXCEPTION 'Captador no pertenece al equipo activo' USING ERRCODE='22023';
   END IF;
 END IF;
 IF p_modalidad='equipo' AND p_equipo IS NULL THEN
   RAISE EXCEPTION 'Selecciona un equipo activo' USING ERRCODE='22023';
 END IF;
 IF p_modalidad='individual' AND
   (p_beneficiario IS NULL OR
    (p_equipo IS NOT NULL AND p_beneficiario NOT IN (v_eq.empleado_a_id,v_eq.empleado_b_id)) OR
    (p_equipo IS NULL AND p_beneficiario<>p_captador)) THEN
   RAISE EXCEPTION 'Beneficiario individual no autorizado' USING ERRCODE='22023';
 END IF;
 UPDATE public.aq_incentivos_captacion
 SET activo=false,hasta=(now() AT TIME ZONE 'America/Guatemala')::date,finalizado_en=now()
 WHERE cliente_id=p_cliente AND producto_id=p_producto AND activo;
 INSERT INTO public.aq_incentivos_captacion
   (cliente_id,producto_id,captador_empleado_id,equipo_id,modalidad,
    beneficiario_empleado_id,monto_unitario,precio_minimo,captacion_confirmada,autorizado_usuario_id)
 VALUES(p_cliente,p_producto,p_captador,p_equipo,p_modalidad,p_beneficiario,
        p_importe,9,true,ctx.usuario_id) RETURNING id INTO v_id;
 RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.aq_finalizar_incentivo_auth_v1(p_incentivo bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record; v_actualizados integer;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe' THEN
   RAISE EXCEPTION 'Solo jefe finaliza incentivos' USING ERRCODE='42501';
 END IF;
 IF p_incentivo IS NULL OR p_incentivo<=0 THEN
   RAISE EXCEPTION 'Incentivo inválido' USING ERRCODE='22023';
 END IF;
 UPDATE public.aq_incentivos_captacion
 SET activo=false,hasta=(now() AT TIME ZONE 'America/Guatemala')::date,finalizado_en=now()
 WHERE id=p_incentivo AND activo;
 GET DIAGNOSTICS v_actualizados=ROW_COUNT;
 RETURN v_actualizados=1;
END;
$$;

CREATE OR REPLACE FUNCTION public.aq_clientes_atribucion_listar_auth_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe' THEN
   RAISE EXCEPTION 'Solo jefe consulta asignaciones' USING ERRCODE='42501';
 END IF;
 RETURN coalesce((
 SELECT jsonb_agg(jsonb_build_object(
  'cliente_id',a.cliente_id,'usuario_id',a.usuario_id,
  'usuario_nombre',coalesce(nullif(btrim(u.nombre),''),u.usuario),
  'asignado_por',a.asignado_por,'asignado_en',a.asignado_en,'nota',a.nota
 ) ORDER BY a.cliente_id)
 FROM public.aq_clientes_atribucion_manual a
 JOIN public.usuarios u ON u.id=a.usuario_id
 ),'[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.aq_cliente_asignar_responsable_auth_v1(
 p_cliente bigint,p_usuario bigint,p_nota text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record; v_anterior bigint; v_nombre text;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe' THEN
   RAISE EXCEPTION 'Solo jefe asigna responsables' USING ERRCODE='42501';
 END IF;
 IF p_cliente IS NULL OR p_cliente<=0 OR length(coalesce(p_nota,''))>250 THEN
   RAISE EXCEPTION 'Asignación inválida' USING ERRCODE='22023';
 END IF;
 PERFORM 1 FROM public.clientes WHERE id=p_cliente FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Cliente inexistente' USING ERRCODE='22023'; END IF;
 IF p_usuario IS NOT NULL THEN
   SELECT coalesce(nullif(btrim(nombre),''),usuario) INTO v_nombre
   FROM public.usuarios WHERE id=p_usuario;
   IF NOT FOUND THEN RAISE EXCEPTION 'Usuario inexistente' USING ERRCODE='22023'; END IF;
 END IF;
 SELECT usuario_id INTO v_anterior FROM public.aq_clientes_atribucion_manual
 WHERE cliente_id=p_cliente;
 IF p_usuario IS NULL THEN
   DELETE FROM public.aq_clientes_atribucion_manual WHERE cliente_id=p_cliente;
 ELSE
   INSERT INTO public.aq_clientes_atribucion_manual(cliente_id,usuario_id,asignado_por,asignado_en,nota)
   VALUES(p_cliente,p_usuario,ctx.usuario_id,now(),nullif(btrim(p_nota),''))
   ON CONFLICT(cliente_id) DO UPDATE
   SET usuario_id=excluded.usuario_id,asignado_por=excluded.asignado_por,
       asignado_en=now(),nota=excluded.nota;
 END IF;
 IF v_anterior IS DISTINCT FROM p_usuario THEN
   INSERT INTO public.aq_clientes_atribucion_historial
      (cliente_id,usuario_anterior_id,usuario_nuevo_id,modificado_por,nota)
   VALUES(p_cliente,v_anterior,p_usuario,ctx.usuario_id,nullif(btrim(p_nota),''));
 END IF;
 RETURN jsonb_build_object('ok',true,'cliente_id',p_cliente,'usuario_id',p_usuario,
   'usuario_nombre',v_nombre,'asignacion_manual',p_usuario IS NOT NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.aq_movimientos_incentivos_auth_v1(p_desde date,p_hasta date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record; v_emp integer;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe'
  AND NOT (aquabri_private.tiene_permiso_actual('comisiones') OR
           aquabri_private.tiene_permiso_actual('reportes') OR
           aquabri_private.tiene_permiso_actual('rrhh')) THEN
   RAISE EXCEPTION 'Sin permiso de incentivos' USING ERRCODE='42501';
 END IF;
 IF p_desde IS NULL OR p_hasta IS NULL OR p_desde>p_hasta OR p_hasta>p_desde+1826 THEN
   RAISE EXCEPTION 'Rango inválido' USING ERRCODE='22023';
 END IF;
 v_emp:=ctx.empleado_id;
 RETURN coalesce((
 SELECT jsonb_agg(to_jsonb(m) ORDER BY m.fecha DESC,m.id DESC)
 FROM public.aq_incentivos_devengados m
 WHERE m.fecha BETWEEN p_desde AND p_hasta
 AND (ctx.rol_usuario='jefe' OR (v_emp IS NOT NULL AND m.empleado_id=v_emp))
 ),'[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION
 public.aq_guardar_equipo_auth_v1(text,bigint,bigint),
 public.aq_guardar_incentivo_auth_v1(bigint,bigint,bigint,bigint,text,bigint,numeric,boolean),
 public.aq_finalizar_incentivo_auth_v1(bigint),
 public.aq_clientes_atribucion_listar_auth_v1(),
 public.aq_cliente_asignar_responsable_auth_v1(bigint,bigint,text),
 public.aq_movimientos_incentivos_auth_v1(date,date)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.aq_guardar_equipo_auth_v1(text,bigint,bigint),
 public.aq_guardar_incentivo_auth_v1(bigint,bigint,bigint,bigint,text,bigint,numeric,boolean),
 public.aq_finalizar_incentivo_auth_v1(bigint),
 public.aq_clientes_atribucion_listar_auth_v1(),
 public.aq_cliente_asignar_responsable_auth_v1(bigint,bigint,text),
 public.aq_movimientos_incentivos_auth_v1(date,date)
 TO authenticated;
COMMIT;
