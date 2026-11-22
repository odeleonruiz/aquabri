-- Aquabri System - Liquidación de incentivos con control de caja y libro de pagos.
-- No crea filas en gastos: el gasto del incentivo ya se devenga en el reporte
-- de rentabilidad al generarse el movimiento, y el pago NO es un segundo gasto.
-- Pago de caja = movimiento físico de caja; fuera de caja = registro sin tocar caja.
-- Compatible con autenticación por sesión legada de Aquabri, validada en servidor.
CREATE OR REPLACE FUNCTION public.aq_liquidar_incentivos_contable_v3(
  p_token text, p_uid bigint, p_nonce text, p_empleado bigint,
  p_desde date, p_hasta date, p_origen text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public, pg_temp
AS $function$
DECLARE
  v_prev aquabri_private.aq_liquidaciones_incentivos_intentos%ROWTYPE;
  v_ids bigint[];
  v_importe numeric;
  v_count integer;
  v_actualizados integer;
  v_pago bigint;
  v_caja integer;
  v_apertura integer;
  v_usuario_caja integer;
  v_fecha date;
  v_saldo numeric(14,2);
  v_desconocidos integer;
  v_hash text;
BEGIN
  IF p_token IS NULL OR p_uid IS NULL OR NOT public.aq_es_jefe(p_token,p_uid) THEN
    RAISE EXCEPTION 'Solo el jefe puede liquidar incentivos' USING ERRCODE='42501';
  END IF;
  v_fecha := (now() AT TIME ZONE 'America/Guatemala')::date;
  IF p_nonce IS NULL OR length(p_nonce)<16 OR length(p_nonce)>120
     OR p_empleado IS NULL OR p_empleado<=0
     OR p_desde IS NULL OR p_hasta IS NULL
     OR p_desde>p_hasta OR p_hasta>v_fecha OR p_hasta>p_desde+365
     OR p_origen IS NULL OR p_origen NOT IN ('caja','externo') THEN
     RAISE EXCEPTION 'Parámetros de liquidación inválidos' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.empleados WHERE id=p_empleado) THEN
    RAISE EXCEPTION 'Empleado no encontrado' USING ERRCODE='22023';
  END IF;

  v_hash := md5(jsonb_build_object('empleado',p_empleado,'desde',p_desde,
          'hasta',p_hasta,'origen',p_origen)::text);
  PERFORM pg_advisory_xact_lock(hashtext('AQ-LIQ-NONCE:'||p_nonce)::bigint);
  SELECT * INTO v_prev
  FROM aquabri_private.aq_liquidaciones_incentivos_intentos
  WHERE nonce=p_nonce FOR UPDATE;
  IF FOUND THEN
    IF v_prev.usuario_id<>p_uid OR v_prev.parametros_hash<>v_hash THEN
      RAISE EXCEPTION 'Identificador de pago reutilizado con otros datos' USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('pago_id',v_prev.pago_id,'monto',v_prev.monto,
          'caja_id',v_prev.caja_id,'repetida',true);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('AQ-LIQ-EMPLEADO:'||p_empleado::text)::bigint);
  SELECT coalesce(array_agg(q.id),'{}'::bigint[]),
         coalesce(sum(q.importe_empleado),0), count(*)
  INTO v_ids,v_importe,v_count
  FROM (
    SELECT m.id,m.importe_empleado
    FROM public.aq_incentivos_devengados m
    JOIN public.ventas v ON v.id=m.venta_id
    WHERE m.empleado_id=p_empleado
      AND m.fecha BETWEEN p_desde AND p_hasta
      AND m.pago_id IS NULL
      AND v.estado IS DISTINCT FROM 'Cancelada'
      AND v.estado IS DISTINCT FROM 'Anulado'
      AND NOT EXISTS (
        SELECT 1 FROM public.creditos c
        WHERE c.venta_id=m.venta_id
          AND coalesce(c.pagado,0)<coalesce(c.monto,0)
      )
    ORDER BY m.id
    FOR UPDATE OF m
  ) q;
  IF v_count=0 THEN
    INSERT INTO aquabri_private.aq_liquidaciones_incentivos_intentos
      (nonce,usuario_id,parametros_hash,pago_id,monto,caja_id)
    VALUES(p_nonce,p_uid,v_hash,NULL,0,NULL);
    RETURN jsonb_build_object('pago_id',NULL,'monto',0,'caja_id',NULL,'repetida',false);
  END IF;
  IF v_importe<=0 OR v_importe>9999999.99
     OR round(v_importe,2)<>v_importe
     OR EXISTS(SELECT 1 FROM public.aq_incentivos_devengados
       WHERE id=ANY(v_ids) AND importe_empleado<=0) THEN
    RAISE EXCEPTION 'Incentivo con importe inválido; requiere revisión' USING ERRCODE='22023';
  END IF;

  IF p_origen='caja' THEN
    LOCK TABLE public.caja IN SHARE ROW EXCLUSIVE MODE;
    SELECT id,usuario_id INTO v_apertura,v_usuario_caja FROM public.caja
    WHERE fecha=v_fecha AND tipo='apertura' ORDER BY id DESC LIMIT 1;
    IF v_apertura IS NULL OR EXISTS(
      SELECT 1 FROM public.caja
      WHERE fecha=v_fecha AND tipo='cierre' AND id>v_apertura) THEN
      RAISE EXCEPTION 'Abre la caja de hoy antes de pagar incentivos' USING ERRCODE='23514';
    END IF;
    IF v_usuario_caja IS DISTINCT FROM p_uid THEN
      RAISE EXCEPTION 'Caja de otro usuario: no se puede descontar efectivo' USING ERRCODE='23514';
    END IF;
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
      count(c.id) FILTER(WHERE c.tipo NOT IN(
       'venta','cobro_credito','ingreso','entrada',
       'gasto','egreso','salida','pago_proveedor'))
    INTO v_saldo,v_desconocidos
    FROM public.caja a
    LEFT JOIN public.caja c ON c.fecha=a.fecha AND c.id>a.id
    WHERE a.id=v_apertura GROUP BY a.id,a.monto;
    IF v_desconocidos>0 THEN
      RAISE EXCEPTION 'Caja con movimientos sin clasificar: concilia antes de pagar'
      USING ERRCODE='23514';
    END IF;
    IF v_saldo IS NULL OR v_saldo<v_importe THEN
      RAISE EXCEPTION 'Efectivo insuficiente: disponible Q%, solicitado Q%',
        coalesce(v_saldo,0),v_importe USING ERRCODE='23514';
    END IF;
  END IF;

  INSERT INTO public.aq_pagos_incentivos(
    empleado_id,desde,hasta,monto,pagado_por,origen_pago
  ) VALUES(p_empleado,p_desde,p_hasta,v_importe,p_uid,p_origen)
  RETURNING id INTO v_pago;

  UPDATE public.aq_incentivos_devengados
  SET pago_id=v_pago WHERE id=ANY(v_ids) AND pago_id IS NULL;
  GET DIAGNOSTICS v_actualizados=ROW_COUNT;
  IF v_actualizados<>v_count THEN
    RAISE EXCEPTION 'Conflicto de liquidación: pago revertido';
  END IF;

  IF p_origen='caja' THEN
    INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
    VALUES(v_fecha,'gasto',-v_importe,
      'Liquidación incentivo #'||v_pago||' [AQ-LIQ-INCENTIVO:'||v_pago||'] [AQ-MP:EFECTIVO]',p_uid)
    RETURNING id INTO v_caja;
  END IF;
  INSERT INTO aquabri_private.aq_liquidaciones_incentivos_intentos
    (nonce,usuario_id,parametros_hash,pago_id,monto,caja_id)
  VALUES(p_nonce,p_uid,v_hash,v_pago,v_importe,v_caja);

  RETURN jsonb_build_object('pago_id',v_pago,'monto',v_importe,
          'caja_id',v_caja,'repetida',false);
END
$function$;
REVOKE ALL ON FUNCTION public.aq_liquidar_incentivos_contable_v3(
  text,bigint,text,bigint,date,date,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aq_liquidar_incentivos_contable_v3(
  text,bigint,text,bigint,date,date,text) TO anon,authenticated;

-- Tablero contable del módulo: no modifica gastos ni caja ni liquida nada.
CREATE OR REPLACE FUNCTION public.aq_control_incentivos_contable_v1(
  p_token text,p_uid bigint,p_desde date,p_hasta date
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public,pg_temp
AS $function$
DECLARE v_result jsonb;v_fecha date;
BEGIN
 IF p_token IS NULL OR p_uid IS NULL OR NOT public.aq_es_jefe(p_token,p_uid) THEN
   RAISE EXCEPTION 'Sin permisos para consultar control de incentivos' USING ERRCODE='42501';
 END IF;
 v_fecha:=(now() AT TIME ZONE 'America/Guatemala')::date;
 IF p_desde IS NULL OR p_hasta IS NULL OR p_desde>p_hasta OR
    p_hasta>v_fecha OR p_hasta>p_desde+3650 THEN
   RAISE EXCEPTION 'Período inválido' USING ERRCODE='22023';
 END IF;
 SELECT jsonb_build_object(
   'desde',p_desde,'hasta',p_hasta,
   'generado',coalesce((SELECT round(sum(m.importe_empleado),2)
      FROM public.aq_incentivos_devengados m
      JOIN public.ventas v ON v.id=m.venta_id
      WHERE m.fecha BETWEEN p_desde AND p_hasta
        AND v.estado IS DISTINCT FROM 'Cancelada'
        AND v.estado IS DISTINCT FROM 'Anulado'),0),
   'pendiente',coalesce((SELECT round(sum(m.importe_empleado),2)
      FROM public.aq_incentivos_devengados m
      JOIN public.ventas v ON v.id=m.venta_id
      WHERE m.fecha BETWEEN p_desde AND p_hasta AND m.pago_id IS NULL
        AND v.estado IS DISTINCT FROM 'Cancelada'
        AND v.estado IS DISTINCT FROM 'Anulado'
        AND NOT EXISTS(SELECT 1 FROM public.creditos c WHERE c.venta_id=m.venta_id
            AND coalesce(c.pagado,0)<coalesce(c.monto,0))),0),
   'retenido_credito',coalesce((SELECT round(sum(m.importe_empleado),2)
      FROM public.aq_incentivos_devengados m JOIN public.ventas v ON v.id=m.venta_id
      WHERE m.fecha BETWEEN p_desde AND p_hasta AND m.pago_id IS NULL
        AND v.estado IS DISTINCT FROM 'Cancelada'
        AND v.estado IS DISTINCT FROM 'Anulado'
        AND EXISTS(SELECT 1 FROM public.creditos c WHERE c.venta_id=m.venta_id
            AND coalesce(c.pagado,0)<coalesce(c.monto,0))),0),
   'pagos_realizados',coalesce((SELECT round(sum(monto),2)
       FROM public.aq_pagos_incentivos
       WHERE (pagado_en AT TIME ZONE 'America/Guatemala')::date
         BETWEEN p_desde AND p_hasta),0),
   'pagos_caja',coalesce((SELECT round(sum(monto),2)
       FROM public.aq_pagos_incentivos
       WHERE origen_pago='caja' AND (pagado_en AT TIME ZONE 'America/Guatemala')::date
         BETWEEN p_desde AND p_hasta),0),
   'pagos_fuera_caja',coalesce((SELECT round(sum(monto),2)
       FROM public.aq_pagos_incentivos
       WHERE origen_pago<>'caja' AND (pagado_en AT TIME ZONE 'America/Guatemala')::date
         BETWEEN p_desde AND p_hasta),0),
   'ultimos_pagos',coalesce((
     SELECT jsonb_agg(to_jsonb(p) ORDER BY p.pagado_en DESC,p.id DESC)
     FROM (
       SELECT i.id,i.empleado_id,i.monto,i.origen_pago,i.pagado_en,i.desde,i.hasta
       FROM public.aq_pagos_incentivos i
       WHERE (i.pagado_en AT TIME ZONE 'America/Guatemala')::date
         BETWEEN p_desde AND p_hasta
       ORDER BY i.pagado_en DESC,i.id DESC LIMIT 25
     ) p
   ),'[]'::jsonb)
 ) INTO v_result;
 RETURN v_result;
END
$function$;
REVOKE ALL ON FUNCTION public.aq_control_incentivos_contable_v1(
  text,bigint,date,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aq_control_incentivos_contable_v1(
  text,bigint,date,date) TO anon,authenticated;
