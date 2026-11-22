-- Solo lectura: el servidor calcula cuánto se podría liquidar a un empleado.
CREATE OR REPLACE FUNCTION public.aq_previa_liquidacion_incentivos_v1(
 p_token text, p_uid bigint, p_empleado bigint, p_desde date, p_hasta date
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public,pg_temp
AS $function$
DECLARE v_monto numeric;v_movimientos integer;v_retenido numeric;v_fecha date;
BEGIN
 IF p_token IS NULL OR p_uid IS NULL OR NOT public.aq_es_jefe(p_token,p_uid) THEN
   RAISE EXCEPTION 'Solo el jefe puede consultar liquidaciones' USING ERRCODE='42501';
 END IF;
 v_fecha:=(now() AT TIME ZONE 'America/Guatemala')::date;
 IF p_empleado IS NULL OR p_empleado<=0 OR p_desde IS NULL OR p_hasta IS NULL OR
 p_desde>p_hasta OR p_hasta>v_fecha OR p_hasta>p_desde+365 THEN
   RAISE EXCEPTION 'Período inválido' USING ERRCODE='22023';
 END IF;
 SELECT coalesce(sum(m.importe_empleado),0),count(*)
 INTO v_monto,v_movimientos
 FROM public.aq_incentivos_devengados m
 JOIN public.ventas v ON v.id=m.venta_id
 WHERE m.empleado_id=p_empleado AND m.fecha BETWEEN p_desde AND p_hasta
 AND m.pago_id IS NULL
 AND v.estado IS DISTINCT FROM 'Cancelada'
 AND v.estado IS DISTINCT FROM 'Anulado'
 AND NOT EXISTS(SELECT 1 FROM public.creditos c WHERE c.venta_id=m.venta_id
   AND coalesce(c.pagado,0)<coalesce(c.monto,0));
 SELECT coalesce(sum(m.importe_empleado),0) INTO v_retenido
 FROM public.aq_incentivos_devengados m JOIN public.ventas v ON v.id=m.venta_id
 WHERE m.empleado_id=p_empleado AND m.fecha BETWEEN p_desde AND p_hasta
 AND m.pago_id IS NULL
 AND v.estado IS DISTINCT FROM 'Cancelada'
 AND v.estado IS DISTINCT FROM 'Anulado'
 AND EXISTS(SELECT 1 FROM public.creditos c WHERE c.venta_id=m.venta_id
  AND coalesce(c.pagado,0)<coalesce(c.monto,0));
 RETURN jsonb_build_object('monto',round(v_monto,2),'movimientos',v_movimientos,
   'retenido_credito',round(v_retenido,2),'empleado_id',p_empleado,
   'desde',p_desde,'hasta',p_hasta);
END
$function$;
REVOKE ALL ON FUNCTION public.aq_previa_liquidacion_incentivos_v1(text,bigint,bigint,date,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aq_previa_liquidacion_incentivos_v1(text,bigint,bigint,date,date) TO anon,authenticated;
