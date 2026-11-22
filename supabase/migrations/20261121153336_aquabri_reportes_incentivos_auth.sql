CREATE FUNCTION aquabri_private.aq_contexto_auth_nativo_v2()
 RETURNS TABLE(usuario_id bigint, rol_usuario text, empleado_id integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
$function$;
revoke all on function aquabri_private.aq_contexto_auth_nativo_v2() from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_cliente_asignar_responsable_auth_v1(p_cliente bigint, p_usuario bigint, p_nota text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
$function$;
revoke all on function public.aq_cliente_asignar_responsable_auth_v1(bigint,bigint,text) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_clientes_atribucion_listar_auth_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
$function$;
revoke all on function public.aq_clientes_atribucion_listar_auth_v1() from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_costos_lotes_auth_v1(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE c record;
BEGIN
 SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('reportes') THEN
   RAISE EXCEPTION 'Sin permiso de reportes' USING ERRCODE='42501';
 END IF;
 IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta<p_desde THEN
   RAISE EXCEPTION 'Fechas invalidas';
 END IF;
 RETURN public.aq_costos_lotes_reporte(c.sesion_token,c.usuario_id,p_desde,p_hasta);
END $function$;
revoke all on function public.aq_costos_lotes_auth_v1(date,date) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_eliminar_gasto_auth_v2(p_gasto_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
  SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
  IF NOT aquabri_private.tiene_permiso_actual('gastos') THEN
    RAISE EXCEPTION 'Sin permiso para eliminar gastos' USING ERRCODE='42501';
  END IF;
  RETURN public.aq_eliminar_gasto_seguro(ctx.sesion_token,ctx.usuario_id,p_gasto_id);
END;
$function$;
revoke all on function public.aq_eliminar_gasto_auth_v2(integer) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_estado_incentivos_auth_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe' THEN
  RAISE EXCEPTION 'Solo jefe consulta administración de incentivos' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
  'equipos',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id DESC)
      FROM public.aq_equipos_incentivo t),'[]'::jsonb),
  'incentivos',coalesce((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.id DESC)
      FROM public.aq_incentivos_captacion i),'[]'::jsonb)
 );
END;
$function$;
revoke all on function public.aq_estado_incentivos_auth_v1() from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_facturas_tipos_auth_v1(p_factura_ids bigint[])
 RETURNS TABLE(factura_id bigint, tipo text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE c record;
BEGIN
 SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('facturas') THEN
   RAISE EXCEPTION 'Sin permiso para ver facturas' USING ERRCODE='42501';
 END IF;
 IF p_factura_ids IS NULL OR cardinality(p_factura_ids)>500 THEN
   RAISE EXCEPTION 'Lista de facturas invalida';
 END IF;
 RETURN QUERY SELECT f.factura_id,f.tipo FROM public.aq_facturas_clasificacion f
 WHERE f.factura_id=ANY(p_factura_ids);
END $function$;
revoke all on function public.aq_facturas_tipos_auth_v1(bigint[]) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_finalizar_incentivo_auth_v1(p_incentivo bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
$function$;
revoke all on function public.aq_finalizar_incentivo_auth_v1(bigint) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_guardar_equipo_auth_v1(p_nombre text, p_empleado_a bigint, p_empleado_b bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
$function$;
revoke all on function public.aq_guardar_equipo_auth_v1(text,bigint,bigint) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_guardar_incentivo_auth_v1(p_cliente bigint, p_producto bigint, p_captador bigint, p_equipo bigint, p_modalidad text, p_beneficiario bigint, p_importe numeric, p_confirmado boolean)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
$function$;
revoke all on function public.aq_guardar_incentivo_auth_v1(bigint,bigint,bigint,bigint,text,bigint,numeric,boolean) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_items_incentivados_auth_v1(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe'
 AND NOT (aquabri_private.tiene_permiso_actual('reportes')
       OR aquabri_private.tiene_permiso_actual('comisiones')) THEN
  RAISE EXCEPTION 'Sin permiso de reportes o comisiones' USING ERRCODE='42501';
 END IF;
 IF p_desde IS NULL OR p_hasta IS NULL OR p_desde>p_hasta
  OR p_hasta>p_desde+1826 THEN
  RAISE EXCEPTION 'Rango de fechas inválido' USING ERRCODE='22023';
 END IF;
 RETURN coalesce((
  SELECT jsonb_agg(DISTINCT m.venta_item_id)
  FROM public.aq_incentivos_devengados m
  JOIN public.ventas v ON v.id=m.venta_id
  WHERE m.fecha BETWEEN p_desde AND p_hasta
    AND v.estado NOT IN ('Cancelada','Anulado')
    AND (ctx.rol_usuario='jefe' OR
        (ctx.empleado_id IS NOT NULL AND m.empleado_id=ctx.empleado_id))
 ),'[]'::jsonb);
END;
$function$;
revoke all on function public.aq_items_incentivados_auth_v1(date,date) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_liquidar_incentivos_auth_v2(p_nonce text, p_empleado bigint, p_desde date, p_hasta date, p_origen text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth uuid;
  v_uid integer;
  v_rol text;
  v_hash text;
  v_previo aquabri_private.aq_liquidaciones_incentivos_intentos%ROWTYPE;
  v_ids bigint[];
  v_monto numeric;
  v_pago bigint;
  v_caja integer;
  v_apertura integer;
  v_fecha date;
  v_count integer;
  v_actualizados integer;
  v_saldo_efectivo numeric(14,2);
  v_tipos_desconocidos integer;
  v_usuario_caja integer;
BEGIN
  v_auth := (SELECT auth.uid());
  IF v_auth IS NULL OR coalesce((auth.jwt()->>'is_anonymous')::boolean,false) THEN
    RAISE EXCEPTION 'Inicia sesión con Supabase Auth' USING ERRCODE = '28000';
  END IF;

  SELECT u.id, u.rol INTO v_uid, v_rol
  FROM public.usuarios u JOIN auth.users a ON a.id=u.auth_uid
  WHERE u.auth_uid=v_auth;
  IF v_uid IS NULL OR v_rol <> 'jefe' THEN
    RAISE EXCEPTION 'Solo el jefe puede liquidar incentivos' USING ERRCODE = '42501';
  END IF;

  IF p_nonce IS NULL OR length(p_nonce)<16 OR length(p_nonce)>120
     OR p_empleado IS NULL OR p_empleado<=0
     OR p_desde IS NULL OR p_hasta IS NULL
     OR p_desde>p_hasta OR p_hasta>p_desde+365
     OR p_hasta>(now() AT TIME ZONE 'America/Guatemala')::date
     OR p_origen IS NULL OR p_origen NOT IN ('caja','externo') THEN
    RAISE EXCEPTION 'Parámetros de liquidación inválidos' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.empleados e WHERE e.id=p_empleado) THEN
    RAISE EXCEPTION 'El empleado no existe' USING ERRCODE='22023';
  END IF;

  v_hash := md5(jsonb_build_object('empleado',p_empleado,'desde',p_desde,
                                  'hasta',p_hasta,'origen',p_origen)::text);
  -- Concurrent retries with the same nonce must serialize.
  PERFORM pg_advisory_xact_lock(hashtext('AQ-LIQ-NONCE:'||p_nonce)::bigint);
  SELECT * INTO v_previo
    FROM aquabri_private.aq_liquidaciones_incentivos_intentos
    WHERE nonce=p_nonce FOR UPDATE;
  IF FOUND THEN
    IF v_previo.usuario_id<>v_uid OR v_previo.parametros_hash<>v_hash THEN
      RAISE EXCEPTION 'Identificador de liquidación reutilizado con otros datos' USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('pago_id',v_previo.pago_id,'monto',v_previo.monto,
      'caja_id',v_previo.caja_id,'repetida',true);
  END IF;

  -- Prevent two different nonces settling the same employee concurrently.
  PERFORM pg_advisory_xact_lock(hashtext('AQ-LIQ-EMPLEADO:'||p_empleado::text)::bigint);
  SELECT coalesce(array_agg(q.id),'{}'::bigint[]), coalesce(sum(q.importe_empleado),0), count(*)
  INTO v_ids, v_monto, v_count
  FROM (
    SELECT m.id, m.importe_empleado
    FROM public.aq_incentivos_devengados m
    JOIN public.ventas v ON v.id=m.venta_id
    WHERE m.empleado_id=p_empleado AND m.fecha BETWEEN p_desde AND p_hasta
      AND m.pago_id IS NULL
      AND v.estado IS DISTINCT FROM 'Cancelada'
      AND v.estado IS DISTINCT FROM 'Anulado'
      AND NOT EXISTS (
        SELECT 1 FROM public.creditos c WHERE c.venta_id=m.venta_id
          AND coalesce(c.pagado,0)<coalesce(c.monto,0)
      )
    ORDER BY m.id
    FOR UPDATE OF m
  ) q;

  IF v_monto < 0 OR round(v_monto,2)<>v_monto
     OR v_monto>9999999.99 THEN
    RAISE EXCEPTION 'Importe de incentivo inválido; requiere revisión' USING ERRCODE='22023';
  END IF;

  IF v_count=0 THEN
    INSERT INTO aquabri_private.aq_liquidaciones_incentivos_intentos
      (nonce,usuario_id,parametros_hash,pago_id,monto,caja_id)
    VALUES(p_nonce,v_uid,v_hash,NULL,0,NULL);
    RETURN jsonb_build_object('pago_id',NULL,'monto',0,'caja_id',NULL,'repetida',false);
  END IF;
  IF EXISTS(SELECT 1 FROM public.aq_incentivos_devengados
            WHERE id=ANY(v_ids) AND importe_empleado<=0) OR v_monto<=0 THEN
    RAISE EXCEPTION 'Existe un devengo con importe inválido' USING ERRCODE='22023';
  END IF;
  v_fecha := (now() AT TIME ZONE 'America/Guatemala')::date;

  -- Payout is the settlement of an accrued incentive, not a second operating expense.
  -- 'externo' is recorded only in aq_pagos_incentivos (no cash movement).
  IF p_origen='caja' THEN
    -- Lock cash writes while checking the opening/closing state and inserting.
    LOCK TABLE public.caja IN SHARE ROW EXCLUSIVE MODE;
    SELECT id, usuario_id INTO v_apertura, v_usuario_caja FROM public.caja
    WHERE fecha=v_fecha AND tipo='apertura' ORDER BY id DESC LIMIT 1;
    IF v_apertura IS NULL OR EXISTS(
      SELECT 1 FROM public.caja WHERE fecha=v_fecha AND tipo='cierre' AND id>v_apertura
    ) THEN
      RAISE EXCEPTION 'La caja de hoy no está abierta; liquidación no realizada'
      USING ERRCODE='23514';
    END IF;
    -- Cash payments can only debit the currently opened drawer of this boss.
    -- Never settle out of a seller's cash drawer implicitly.
    IF v_usuario_caja IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'La caja activa pertenece a otro usuario: liquidación de efectivo no permitida'
      USING ERRCODE='23514';
    END IF;

    -- Same accounting convention as aq_caja_resumen_qa_auth_v1:
    -- transfers/other are excluded from physical cash, untagged movements count as cash.
    -- For safety, unknown movement types require manual reconciliation.
    SELECT round(a.monto + coalesce(sum(
      CASE
        WHEN c.id IS NULL THEN 0
        WHEN c.tipo NOT IN ('venta','cobro_credito','ingreso','entrada',
                             'gasto','egreso','salida','pago_proveedor') THEN 0
        WHEN upper(coalesce(c.notas,'')) LIKE '%[AQ-MP:TRANSFERENCIA]%'
          OR upper(coalesce(c.notas,'')) LIKE '%[AQ-MP:OTRO]%' THEN 0
        WHEN c.tipo IN ('venta','cobro_credito','ingreso','entrada') THEN c.monto
        ELSE -abs(c.monto)
      END),0),2),
      count(c.id) FILTER (WHERE c.tipo NOT IN
       ('venta','cobro_credito','ingreso','entrada','gasto','egreso','salida','pago_proveedor'))
    INTO v_saldo_efectivo, v_tipos_desconocidos
    FROM public.caja a
    LEFT JOIN public.caja c ON c.fecha=a.fecha AND c.id>a.id
    WHERE a.id=v_apertura
    GROUP BY a.id,a.monto;

    IF v_tipos_desconocidos>0 THEN
      RAISE EXCEPTION 'Caja contiene movimientos no clasificados: concilia antes de pagar incentivos'
      USING ERRCODE='23514';
    END IF;
    IF v_saldo_efectivo IS NULL OR v_saldo_efectivo < v_monto THEN
      RAISE EXCEPTION 'Saldo en efectivo insuficiente para liquidar: disponible Q%, solicitado Q%',
       coalesce(v_saldo_efectivo,0),v_monto
      USING ERRCODE='23514';
    END IF;
  END IF;

  INSERT INTO public.aq_pagos_incentivos
    (empleado_id,desde,hasta,monto,pagado_por,origen_pago)
  VALUES(p_empleado,p_desde,p_hasta,v_monto,v_uid,p_origen)
  RETURNING id INTO v_pago;

  UPDATE public.aq_incentivos_devengados
     SET pago_id=v_pago
   WHERE id=ANY(v_ids) AND pago_id IS NULL;
  GET DIAGNOSTICS v_actualizados = ROW_COUNT;
  IF v_actualizados<>v_count THEN
    RAISE EXCEPTION 'Conflicto al vincular incentivos: se revierte liquidación';
  END IF;

  IF p_origen='caja' THEN
    INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
    VALUES(v_fecha,'gasto',-v_monto,
       'Liquidación incentivo #'||v_pago::text||
       ' [AQ-LIQ-INCENTIVO:'||v_pago::text||'] [AQ-MP:EFECTIVO]',v_uid)
    RETURNING id INTO v_caja;
  END IF;

  INSERT INTO aquabri_private.aq_liquidaciones_incentivos_intentos
    (nonce,usuario_id,parametros_hash,pago_id,monto,caja_id)
  VALUES(p_nonce,v_uid,v_hash,v_pago,v_monto,v_caja);

  RETURN jsonb_build_object('pago_id',v_pago,'monto',v_monto,
    'caja_id',v_caja,'repetida',false);
END;
$function$;
revoke all on function public.aq_liquidar_incentivos_auth_v2(text,bigint,date,date,text) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_lotes_resumen_auth_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE c record;
BEGIN
 SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
 IF c.rol_usuario<>'jefe' THEN
   RAISE EXCEPTION 'Solo el jefe puede consultar todos los lotes' USING ERRCODE='42501';
 END IF;
 RETURN public.aq_lotes_resumen(c.sesion_token,c.usuario_id);
END $function$;
revoke all on function public.aq_lotes_resumen_auth_v1() from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_movimientos_incentivos_auth_v1(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
$function$;
revoke all on function public.aq_movimientos_incentivos_auth_v1(date,date) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_total_incentivos_auth_v1(p_desde date, p_hasta date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe'
 AND NOT aquabri_private.tiene_permiso_actual('reportes') THEN
  RAISE EXCEPTION 'Sin permiso de reportes' USING ERRCODE='42501';
 END IF;
 IF p_desde IS NULL OR p_hasta IS NULL OR p_desde>p_hasta
 OR p_hasta>p_desde+1826 THEN
  RAISE EXCEPTION 'Rango de fechas inválido' USING ERRCODE='22023';
 END IF;
 RETURN coalesce((
 SELECT sum(m.importe_empleado)
 FROM public.aq_incentivos_devengados m
 JOIN public.ventas v ON v.id=m.venta_id
 WHERE m.fecha BETWEEN p_desde AND p_hasta
 AND v.estado NOT IN ('Cancelada','Anulado')
 AND (ctx.rol_usuario='jefe' OR
      (ctx.empleado_id IS NOT NULL AND m.empleado_id=ctx.empleado_id))
 ),0);
END;
$function$;
revoke all on function public.aq_total_incentivos_auth_v1(date,date) from public,anon,authenticated,service_role;
