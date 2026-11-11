-- Definiciones desplegadas y verificadas en staging. NO ejecutar en producción sin backup.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_cancelar_venta_contado_auth_v1(p_venta bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record; v public.ventas%ROWTYPE; i record; c public.caja%ROWTYPE;
  count_caja integer; stock_antes integer;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('ventas') THEN
  RAISE EXCEPTION 'Sin permiso para cancelar ventas' USING ERRCODE='42501';
 END IF;
 IF p_venta IS NULL OR p_venta<1 OR p_venta>2147483647 THEN RAISE EXCEPTION 'Venta invalida'; END IF;
 SELECT * INTO v FROM public.ventas WHERE id=p_venta::integer FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
 IF v.estado IN ('Cancelada','Anulado') THEN RAISE EXCEPTION 'Venta ya cancelada'; END IF;
 IF ctx.rol_usuario <> 'jefe' AND
    (v.usuario_id IS DISTINCT FROM ctx.usuario_id::integer OR
     v.fecha IS DISTINCT FROM (now() AT TIME ZONE 'America/Guatemala')::date) THEN
  RAISE EXCEPTION 'Solo puedes cancelar ventas propias del dia' USING ERRCODE='42501';
 END IF;
 -- No intentar revertir movimientos de credito, abonos ni puntos gastados.
 IF v.estado <> 'Entregado' OR coalesce(v.total,0)<=0 OR
    v.total IS DISTINCT FROM v.pagado THEN
  RAISE EXCEPTION 'Esta venta requiere ajuste supervisado (estado o pago parcial)';
 END IF;
 IF EXISTS(SELECT 1 FROM public.creditos WHERE venta_id=v.id OR concepto='Venta #'||v.id) THEN
  RAISE EXCEPTION 'No puedes cancelar una venta con credito: requiere conciliacion';
 END IF;
 IF EXISTS(SELECT 1 FROM public.puntos_historial WHERE venta_id=v.id) THEN
  RAISE EXCEPTION 'Venta con puntos acumulados: requiere conciliacion';
 END IF;
 IF EXISTS(SELECT 1 FROM public.aq_incentivos_devengados
           WHERE venta_id=v.id AND pago_id IS NOT NULL) THEN
  RAISE EXCEPTION 'Venta con incentivos liquidados: requiere ajuste supervisado';
 END IF;
 SELECT count(*) INTO count_caja FROM public.caja WHERE venta_id=v.id;
 IF count_caja <> 1 THEN
  RAISE EXCEPTION 'La venta no tiene un unico movimiento de caja concilable';
 END IF;
 SELECT * INTO c FROM public.caja WHERE venta_id=v.id FOR UPDATE;
 IF c.tipo<>'venta' OR c.monto IS DISTINCT FROM v.total OR
    c.usuario_id IS DISTINCT FROM v.usuario_id OR
    NOT (coalesce(c.notas,'') LIKE '%[AQ-V2:%') THEN
  RAISE EXCEPTION 'Movimiento de caja de venta no coincide';
 END IF;
 IF EXISTS (SELECT 1 FROM public.caja x
   WHERE x.fecha=c.fecha AND x.tipo='cierre' AND x.id>c.id) THEN
  RAISE EXCEPTION 'La caja de esta venta ya fue cerrada: solicita ajuste supervisado';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.venta_items WHERE venta_id=v.id) THEN
  RAISE EXCEPTION 'Venta sin detalle; requiere revision';
 END IF;
 -- Devolver existencia de producto e insumo por las mismas cantidades descontadas por la venta integral.
 FOR i IN SELECT vi.producto_id,
        SUM(vi.cant + CASE WHEN vi.bonif_prod_id IS NULL THEN coalesce(vi.bonif_cant,0) ELSE 0 END) unidades
       FROM public.venta_items vi WHERE vi.venta_id=v.id AND vi.producto_id IS NOT NULL
       GROUP BY vi.producto_id ORDER BY vi.producto_id LOOP
  IF i.unidades<>trunc(i.unidades) OR i.unidades<0 THEN
   RAISE EXCEPTION 'Cantidad irregular; requiere revision';
  END IF;
  UPDATE public.productos SET stock=coalesce(stock,0)+i.unidades::integer WHERE id=i.producto_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado'; END IF;
  UPDATE public.insumos ins SET stock=coalesce(ins.stock,0)+
      (SELECT coalesce(sum(trunc(pi.cant)::integer * i.unidades::integer),0)
       FROM public.producto_insumos pi WHERE pi.insumo_id=ins.id AND pi.producto_id=i.producto_id)
      WHERE ins.id IN (SELECT pi.insumo_id FROM public.producto_insumos pi WHERE pi.producto_id=i.producto_id);
 END LOOP;
 FOR i IN SELECT vi.bonif_prod_id producto_id,sum(coalesce(vi.bonif_cant,0)) unidades
       FROM public.venta_items vi WHERE vi.venta_id=v.id AND vi.bonif_prod_id IS NOT NULL
       GROUP BY vi.bonif_prod_id ORDER BY vi.bonif_prod_id LOOP
  UPDATE public.productos SET stock=coalesce(stock,0)+i.unidades::integer WHERE id=i.producto_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto bonificado no encontrado'; END IF;
 END LOOP;
 -- El disparador AFTER UPDATE de ventas revierte FIFO e incentivos devengados, no pagados.
 UPDATE public.ventas SET estado='Cancelada',
   cancelado_por=(SELECT nombre FROM public.usuarios WHERE id=ctx.usuario_id),
   fecha_cancelacion=(now() AT TIME ZONE 'America/Guatemala')::date
 WHERE id=v.id;
 -- Eliminar únicamente la entrada exacta y validada, nunca cobros de otros creditos.
 DELETE FROM public.caja WHERE id=c.id;
 RETURN jsonb_build_object('id',v.id,'cancelada',true,'caja_revertida',c.id,'tipo','contado_sin_ajustes');
END;
$function$


CREATE OR REPLACE FUNCTION public.aq_editar_venta_datos_auth_v1(p_venta bigint, p_entrega text, p_notas text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record; v public.ventas%ROWTYPE;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('ventas') THEN
  RAISE EXCEPTION 'Sin permiso para editar ventas' USING ERRCODE='42501';
 END IF;
 IF p_venta IS NULL OR p_venta<1 OR p_venta>2147483647 OR length(coalesce(p_entrega,''))>120 OR length(coalesce(p_notas,''))>1000 THEN
  RAISE EXCEPTION 'Datos de venta invalidos';
 END IF;
 SELECT * INTO v FROM public.ventas WHERE id=p_venta::integer FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
 IF v.estado IN ('Cancelada','Anulado') THEN RAISE EXCEPTION 'No se puede editar una venta cancelada'; END IF;
 IF ctx.rol_usuario <> 'jefe' AND
    (v.usuario_id IS DISTINCT FROM ctx.usuario_id::integer OR
     v.fecha IS DISTINCT FROM (now() AT TIME ZONE 'America/Guatemala')::date) THEN
  RAISE EXCEPTION 'Solo puedes editar tus propias ventas del dia' USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM public.aq_incentivos_devengados
           WHERE venta_id=v.id AND pago_id IS NOT NULL) THEN
  RAISE EXCEPTION 'La venta tiene incentivos liquidados'; END IF;
 UPDATE public.ventas
 SET entrega=p_entrega,notas=p_notas WHERE id=v.id;
 RETURN jsonb_build_object('id',v.id,'editada',true,'tipo','datos_no_financieros');
END;
$function$

REVOKE ALL ON FUNCTION public.aq_editar_venta_datos_auth_v1(bigint,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.aq_cancelar_venta_contado_auth_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aq_editar_venta_datos_auth_v1(bigint,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aq_cancelar_venta_contado_auth_v1(bigint) TO authenticated;
COMMIT;
