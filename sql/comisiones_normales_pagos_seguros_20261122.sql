-- Aquabri System · cálculo mensual y pago de comisión normal en una transacción.
-- La comisión ordinaria no se confunde con el incentivo especial por captación.
-- Las unidades con incentivo especial registrado se excluyen de la base normal.
-- Se permite pagar parcialmente; cada pago queda vinculado a Gastos y RRHH.
-- Fuente efectivo: además registra una salida de caja del jefe validada.
-- Fuente externa: no resta efectivo de caja.
CREATE TABLE IF NOT EXISTS aquabri_private.aq_comisiones_intentos (
 nonce text PRIMARY KEY,
 usuario_id bigint NOT NULL,
 parametros_hash text NOT NULL,
 pago_id bigint,
 gasto_id bigint,
 caja_id integer,
 monto numeric(14,2) NOT NULL,
 creado_en timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON aquabri_private.aq_comisiones_intentos FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION aquabri_private.aq_comision_calcular_mes_v1(
 p_empleado bigint,p_mes text
) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public,pg_temp
AS $f$
DECLARE
 v_cfg public.comisiones%ROWTYPE;
 v_emp public.empleados%ROWTYPE;
 v_companero integer;
 v_desde date;
 v_hasta date;
 v_total numeric;
 v_cantidad int;
BEGIN
 IF p_mes IS NULL OR p_mes !~ '^\d{4}-\d{2}$' THEN
  RAISE EXCEPTION 'Usa un mes válido (AAAA-MM)' USING ERRCODE='22023';
 END IF;
 v_desde := (p_mes||'-01')::date;
 v_hasta := (v_desde + INTERVAL '1 month' - INTERVAL '1 day')::date;
 IF to_char(v_desde,'YYYY-MM')<>p_mes OR v_desde>(now() AT TIME ZONE 'America/Guatemala')::date THEN
  RAISE EXCEPTION 'Mes de comisión inválido' USING ERRCODE='22023';
 END IF;
 SELECT COUNT(*) INTO v_cantidad FROM public.comisiones c
 WHERE c.empleado_id=p_empleado AND c.activo=true;
 IF v_cantidad<>1 THEN
  RAISE EXCEPTION 'El empleado necesita exactamente una configuración activa de comisión (hay %)',v_cantidad USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_cfg FROM public.comisiones WHERE empleado_id=p_empleado AND activo=true;
 IF v_cfg.tipo_comision IS DISTINCT FROM 'general' THEN
   RAISE EXCEPTION 'La comisión por clientes asignados requiere auditoría de atribuciones: no se liquidó' USING ERRCODE='22023';
 END IF;
 IF v_cfg.porcentaje<0 OR v_cfg.porcentaje>100 THEN
  RAISE EXCEPTION 'Porcentaje de comisión inválido' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_emp FROM public.empleados WHERE id=p_empleado;
 IF NOT FOUND OR v_emp.usuario_id IS NULL THEN
  RAISE EXCEPTION 'Empleado sin usuario vinculado' USING ERRCODE='22023';
 END IF;
 SELECT usuario_id INTO v_companero FROM public.empleados
 WHERE id=v_cfg.compartir_empleado_id;
 WITH vendidas AS (
   SELECT v.id,v.total,v.desc_gral
   FROM public.ventas v
   WHERE v.fecha BETWEEN v_desde AND v_hasta
   AND v.estado IS DISTINCT FROM 'Cancelada'
   AND v.estado IS DISTINCT FROM 'Anulado'
   AND (v_emp.fecha_ingreso IS NULL OR v.fecha>=v_emp.fecha_ingreso)
   AND (v.usuario_id=v_emp.usuario_id OR
        (v_companero IS NOT NULL AND v.usuario_id=v_companero))
 ), valores AS (
   SELECT v.id, v.total, v.desc_gral,
     coalesce(x.n,0) n,
     coalesce(x.bruto,0) bruto,
     coalesce(x.base,0) base
   FROM vendidas v
   LEFT JOIN LATERAL (
     SELECT count(*) n,
       sum(greatest(0,coalesce(i.precio,0)-coalesce(i.descuento,0))
                    *coalesce(i.cant,0)) bruto,
       sum(greatest(0,coalesce(i.precio,0)-coalesce(i.descuento,0))
                    *coalesce(i.cant,0)) FILTER(WHERE NOT EXISTS(
                      SELECT 1 FROM public.aq_incentivos_devengados dev
                      WHERE dev.venta_item_id=i.id
                    )) base
     FROM public.venta_items i WHERE i.venta_id=v.id
   ) x ON true
 )
 SELECT round(coalesce(sum(
  CASE WHEN n=0 THEN greatest(0,coalesce(total,0))
       ELSE greatest(0,base -
          (CASE WHEN bruto>0 THEN coalesce(desc_gral,0)*(base/bruto) ELSE 0 END))
  END
 ),0)*v_cfg.porcentaje/100,2) INTO v_total FROM valores;
 RETURN greatest(0,coalesce(v_total,0));
END
$f$;
REVOKE ALL ON FUNCTION aquabri_private.aq_comision_calcular_mes_v1(bigint,text)
FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.aq_previa_pago_comision_normal_v1(
 p_token text,p_uid bigint,p_empleado bigint,p_mes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public,pg_temp
AS $f$
DECLARE v_total numeric;v_pagado numeric;v_restante numeric;v_desde date;v_hasta date;
BEGIN
 IF p_token IS NULL OR p_uid IS NULL OR NOT public.aq_es_jefe(p_token,p_uid) THEN
  RAISE EXCEPTION 'Solo el jefe puede consultar pagos de comisiones' USING ERRCODE='42501';
 END IF;
 v_total:=aquabri_private.aq_comision_calcular_mes_v1(p_empleado,p_mes);
 v_desde:=(p_mes||'-01')::date;
 v_hasta:=(v_desde+INTERVAL '1 month'-INTERVAL '1 day')::date;
 -- Rechazar antiguos pagos de rangos cruzados con otro mes, que necesitan conciliación.
 IF EXISTS(
   SELECT 1 FROM public.pagos_comisiones p
   WHERE p.empleado_id=p_empleado AND p.periodo ~ '^\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}$'
   AND (p.periodo !~ ('^'||p_mes||'-01_'||p_mes||'-[0-9]{2}$'))
   AND (split_part(p.periodo,'_',1)::date<=v_hasta AND
        split_part(p.periodo,'_',2)::date>=v_desde)
 ) THEN
   RAISE EXCEPTION 'Existe un pago anterior con fechas cruzadas; concilia antes de pagar de nuevo' USING ERRCODE='22023';
 END IF;
 SELECT coalesce(sum(monto),0) INTO v_pagado
 FROM public.pagos_comisiones
 WHERE empleado_id=p_empleado AND
 (periodo=p_mes OR
  (periodo ~ '^\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}$'
   AND split_part(periodo,'_',1)::date=v_desde
   AND split_part(periodo,'_',2)::date=v_hasta));
 v_restante:=greatest(0,v_total-v_pagado);
 RETURN jsonb_build_object('empleado_id',p_empleado,'mes',p_mes,
   'generado',v_total,'pagado',v_pagado,'pendiente',v_restante);
END
$f$;
REVOKE ALL ON FUNCTION public.aq_previa_pago_comision_normal_v1(text,bigint,bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aq_previa_pago_comision_normal_v1(text,bigint,bigint,text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.aq_pagar_comision_normal_v1(
 p_token text,p_uid bigint,p_nonce text,p_empleado bigint,p_mes text,
 p_monto numeric,p_origen text,p_notas text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public,pg_temp
AS $f$
DECLARE
 v_prev aquabri_private.aq_comisiones_intentos%ROWTYPE;
 v_base jsonb;
 v_restante numeric;
 v_usuario text;
 v_empleado text;
 v_hash text;
 v_pago integer;
 v_gasto integer;
 v_caja integer;
 v_apertura integer;
 v_usuario_caja integer;
 v_fecha date;
 v_saldo numeric(14,2);
 v_desconocidos integer;
BEGIN
 IF p_token IS NULL OR p_uid IS NULL OR NOT public.aq_es_jefe(p_token,p_uid) THEN
  RAISE EXCEPTION 'Solo el jefe puede pagar comisiones' USING ERRCODE='42501';
 END IF;
 v_fecha:=(now() AT TIME ZONE 'America/Guatemala')::date;
 IF p_nonce IS NULL OR length(p_nonce)<16 OR length(p_nonce)>120
 OR p_monto IS NULL OR p_monto<=0 OR p_monto>1000000
 OR round(p_monto,2)<>p_monto
 OR p_origen NOT IN ('caja','externo') OR p_origen IS NULL
 OR length(coalesce(p_notas,''))>250 THEN
   RAISE EXCEPTION 'Parámetros de pago inválidos' USING ERRCODE='22023';
 END IF;
 SELECT nombre INTO v_usuario FROM public.usuarios WHERE id=p_uid;
 SELECT nombre INTO v_empleado FROM public.empleados WHERE id=p_empleado;
 IF v_empleado IS NULL THEN
   RAISE EXCEPTION 'Empleado no encontrado' USING ERRCODE='22023';
 END IF;
 v_hash:=md5(jsonb_build_object('empleado',p_empleado,'mes',p_mes,
   'monto',p_monto,'origen',p_origen,'notas',coalesce(p_notas,''))::text);
 PERFORM pg_advisory_xact_lock(hashtext('AQ-COM-NONCE:'||p_nonce)::bigint);
 SELECT * INTO v_prev FROM aquabri_private.aq_comisiones_intentos WHERE nonce=p_nonce FOR UPDATE;
 IF FOUND THEN
   IF v_prev.usuario_id<>p_uid OR v_prev.parametros_hash<>v_hash THEN
     RAISE EXCEPTION 'Referencia de pago reutilizada con otros datos' USING ERRCODE='23505';
   END IF;
   RETURN jsonb_build_object('pago_id',v_prev.pago_id,'gasto_id',v_prev.gasto_id,
     'caja_id',v_prev.caja_id,'monto',v_prev.monto,'repetida',true);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtext('AQ-COM-EMPLEADO:'||p_empleado::text)::bigint);
 v_base:=public.aq_previa_pago_comision_normal_v1(p_token,p_uid,p_empleado,p_mes);
 v_restante:=(v_base->>'pendiente')::numeric;
 IF v_restante < p_monto THEN
  RAISE EXCEPTION 'Pago supera pendiente del mes: Q% disponible, Q% solicitado',
    v_restante,p_monto USING ERRCODE='22023';
 END IF;
 IF p_origen='caja' THEN
   LOCK TABLE public.caja IN SHARE ROW EXCLUSIVE MODE;
   SELECT id,usuario_id INTO v_apertura,v_usuario_caja
   FROM public.caja WHERE fecha=v_fecha AND tipo='apertura' ORDER BY id DESC LIMIT 1;
   IF v_apertura IS NULL OR EXISTS(SELECT 1 FROM public.caja WHERE
     fecha=v_fecha AND tipo='cierre' AND id>v_apertura) THEN
       RAISE EXCEPTION 'Debes abrir caja antes de pagar comisiones en efectivo' USING ERRCODE='23514';
   END IF;
   IF v_usuario_caja IS DISTINCT FROM p_uid THEN
    RAISE EXCEPTION 'No puedes descontar efectivo de la caja de otro usuario' USING ERRCODE='23514';
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
     count(c.id) FILTER (WHERE c.tipo NOT IN (
       'venta','cobro_credito','ingreso','entrada',
       'gasto','egreso','salida','pago_proveedor'))
   INTO v_saldo,v_desconocidos
   FROM public.caja a LEFT JOIN public.caja c
     ON c.fecha=a.fecha AND c.id>a.id
   WHERE a.id=v_apertura
   GROUP BY a.id,a.monto;
   IF v_desconocidos>0 THEN
    RAISE EXCEPTION 'Caja tiene movimientos sin clasificar; concilia antes de pagar' USING ERRCODE='23514';
   END IF;
   IF v_saldo IS NULL OR v_saldo<p_monto THEN
    RAISE EXCEPTION 'Efectivo insuficiente: disponible Q%, solicitado Q%',coalesce(v_saldo,0),p_monto USING ERRCODE='23514';
   END IF;
 END IF;
 INSERT INTO public.pagos_comisiones(empleado_id,monto,fecha,periodo,notas,pagado_por)
 VALUES(p_empleado,p_monto,v_fecha,p_mes,coalesce(p_notas,'')||' [AQ-COM:N:'||p_nonce||']',
   coalesce(v_usuario,'Jefe')) RETURNING id INTO v_pago;
 INSERT INTO public.pagos(empleado_id,tipo,monto,desc_vales,neto,fecha,notas)
 VALUES(p_empleado,'Comisión mensual',p_monto,0,p_monto,v_fecha,
  'Comisión '||p_mes||' [AQ-COM-PAGO:'||v_pago||']');
 INSERT INTO public.gastos(fecha,cat,descripcion,monto,notas,pagado_por,empleado_id)
 VALUES(v_fecha,'Comisiones',
  'Comisión de '||v_empleado||' · '||p_mes,p_monto,
  'Auto: Comisión #'||v_pago||' [AQ-COM-PAGO:'||v_pago||']',
  CASE WHEN p_origen='caja' THEN 'Efectivo de caja' ELSE 'Fuera de caja' END,
  p_empleado) RETURNING id INTO v_gasto;
 IF p_origen='caja' THEN
   INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
   VALUES(v_fecha,'gasto',-p_monto,
      'Pago comisión #'||v_pago||' [AQ-COM-PAGO:'||v_pago||'] [AQ-MP:EFECTIVO]',p_uid)
   RETURNING id INTO v_caja;
 END IF;
 INSERT INTO aquabri_private.aq_comisiones_intentos
 (nonce,usuario_id,parametros_hash,pago_id,gasto_id,caja_id,monto)
 VALUES(p_nonce,p_uid,v_hash,v_pago,v_gasto,v_caja,p_monto);
 RETURN jsonb_build_object('pago_id',v_pago,'gasto_id',v_gasto,'caja_id',v_caja,
  'monto',p_monto,'repetida',false,'pendiente_despues',v_restante-p_monto);
END
$f$;
REVOKE ALL ON FUNCTION public.aq_pagar_comision_normal_v1(text,bigint,text,bigint,text,numeric,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aq_pagar_comision_normal_v1(text,bigint,text,bigint,text,numeric,text,text) TO anon,authenticated;
