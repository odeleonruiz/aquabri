-- Aquabri: reactivar clientes finalizados por el jefe, conservando historial.
-- Se deja intacto el RPC "Autorizar incentivo": cualquier repetición allí sigue bloqueada.
ALTER TABLE public.aq_incentivos_captacion
 ADD COLUMN IF NOT EXISTS reactivacion_origen_id bigint
 REFERENCES public.aq_incentivos_captacion(id);
ALTER TABLE public.aq_incentivos_captacion
 ADD COLUMN IF NOT EXISTS venta_id_inicio bigint;

CREATE TABLE IF NOT EXISTS aquabri_private.aq_incentivo_reactivacion_permiso (
 tx_id bigint NOT NULL,
 cliente_id bigint NOT NULL,
 origen_id bigint NOT NULL,
 autorizado_usuario_id bigint NOT NULL,
 PRIMARY KEY(tx_id,cliente_id)
);
REVOKE ALL ON aquabri_private.aq_incentivo_reactivacion_permiso FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION aquabri_private.aq_bloquear_incentivo_duplicado_cliente()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public, aquabri_private, pg_temp
AS $fn$
DECLARE
 v_ultimo public.aq_incentivos_captacion%ROWTYPE;
 v_autorizado bigint;
BEGIN
 IF NEW.cliente_id IS NULL THEN
  RAISE EXCEPTION 'Selecciona un cliente válido para el incentivo' USING ERRCODE='22023';
 END IF;
 -- Mismo bloqueo de registro de cliente para autorizar/reactivar simultáneamente.
 PERFORM 1 FROM public.clientes WHERE id=NEW.cliente_id FOR UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'El cliente ya no existe' USING ERRCODE='23503';
 END IF;
 SELECT * INTO v_ultimo FROM public.aq_incentivos_captacion
 WHERE cliente_id=NEW.cliente_id
 ORDER BY id DESC LIMIT 1;
 IF NOT FOUND THEN
   IF NEW.reactivacion_origen_id IS NOT NULL THEN
    RAISE EXCEPTION 'Este cliente no tiene incentivo anterior para reactivar' USING ERRCODE='22023';
   END IF;
   RETURN NEW;
 END IF;
 -- Toda autorización repetida por el formulario viejo se rechaza, aunque esté cerrada.
 IF NEW.reactivacion_origen_id IS NULL THEN
    RAISE EXCEPTION 'Este cliente ya fue agregado a incentivos (registro #%: %). Usa Reactivar incentivo si terminó.',
      v_ultimo.id,CASE WHEN v_ultimo.activo THEN 'ACTIVO' ELSE 'FINALIZADO' END
      USING ERRCODE='23505', CONSTRAINT='aq_cliente_ya_incentivado';
 END IF;
 IF v_ultimo.activo OR EXISTS (
    SELECT 1 FROM public.aq_incentivos_captacion
    WHERE cliente_id=NEW.cliente_id AND activo
 ) THEN
    RAISE EXCEPTION 'El cliente ya tiene un incentivo ACTIVO. No se puede reactivar.'
      USING ERRCODE='23505', CONSTRAINT='aq_un_cliente_incentivado_activo';
 END IF;
 IF NEW.reactivacion_origen_id IS DISTINCT FROM v_ultimo.id
    OR NEW.producto_id IS DISTINCT FROM v_ultimo.producto_id
    OR NEW.captador_empleado_id IS DISTINCT FROM v_ultimo.captador_empleado_id
    OR NEW.equipo_id IS DISTINCT FROM v_ultimo.equipo_id
    OR NEW.modalidad IS DISTINCT FROM v_ultimo.modalidad
    OR NEW.beneficiario_empleado_id IS DISTINCT FROM v_ultimo.beneficiario_empleado_id
    OR NEW.monto_unitario IS DISTINCT FROM v_ultimo.monto_unitario
    OR NEW.precio_minimo IS DISTINCT FROM v_ultimo.precio_minimo
    OR NEW.desde IS DISTINCT FROM (now() AT TIME ZONE 'America/Guatemala')::date
    OR NEW.hasta IS NOT NULL OR NEW.activo IS DISTINCT FROM true
    OR NEW.captacion_confirmada IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Reactivación inválida. Se deben respetar las reglas anteriores y la fecha actual.'
      USING ERRCODE='22023';
 END IF;
 -- Permiso de un solo uso creado dentro de la MISMA transacción por el RPC del jefe.
 DELETE FROM aquabri_private.aq_incentivo_reactivacion_permiso p
 WHERE p.tx_id=txid_current()
   AND p.cliente_id=NEW.cliente_id AND p.origen_id=NEW.reactivacion_origen_id
   AND p.autorizado_usuario_id=NEW.autorizado_usuario_id
 RETURNING autorizado_usuario_id INTO v_autorizado;
 IF v_autorizado IS NULL THEN
  RAISE EXCEPTION 'Solo el jefe puede reactivar un incentivo finalizado desde la opción Reactivar.'
    USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END
$fn$;
REVOKE ALL ON FUNCTION aquabri_private.aq_bloquear_incentivo_duplicado_cliente()
FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.aq_reactivar_incentivo_jefe_v1(
 p_token text, p_uid bigint, p_incentivo bigint, p_confirmado boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public, aquabri_private, pg_temp
AS $fn$
DECLARE
 v_origen public.aq_incentivos_captacion%ROWTYPE;
 v_equipo public.aq_equipos_incentivo%ROWTYPE;
 v_nuevo bigint;
 v_max_venta bigint;
 v_hoy date;
BEGIN
 IF p_token IS NULL OR p_uid IS NULL OR NOT public.aq_es_jefe(p_token,p_uid) THEN
  RAISE EXCEPTION 'Solo el jefe puede reactivar incentivos' USING ERRCODE='42501';
 END IF;
 IF p_confirmado IS DISTINCT FROM true OR p_incentivo IS NULL OR p_incentivo<=0 THEN
  RAISE EXCEPTION 'Debes confirmar el incentivo que quieres reactivar' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_origen FROM public.aq_incentivos_captacion
 WHERE id=p_incentivo;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'No se encontró el incentivo anterior' USING ERRCODE='22023';
 END IF;
 -- Serializa solicitudes concurrentes incluso de otros equipos.
 PERFORM 1 FROM public.clientes WHERE id=v_origen.cliente_id FOR UPDATE;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Cliente no existe' USING ERRCODE='23503';
 END IF;
 SELECT * INTO v_origen
 FROM public.aq_incentivos_captacion WHERE id=p_incentivo FOR UPDATE;
 IF v_origen.activo OR EXISTS(
   SELECT 1 FROM public.aq_incentivos_captacion
   WHERE cliente_id=v_origen.cliente_id AND activo
 ) THEN
   RAISE EXCEPTION 'Este cliente ya tiene incentivo activo. No se creó otro.' USING ERRCODE='23505';
 END IF;
 IF v_origen.id IS DISTINCT FROM (
   SELECT max(id) FROM public.aq_incentivos_captacion
   WHERE cliente_id=v_origen.cliente_id
 ) THEN
   RAISE EXCEPTION 'Selecciona el último incentivo finalizado de este cliente' USING ERRCODE='22023';
 END IF;
 IF v_origen.monto_unitario IS NULL OR v_origen.monto_unitario<=0
  OR v_origen.precio_minimo<9 OR NOT v_origen.captacion_confirmada THEN
   RAISE EXCEPTION 'La configuración anterior no es válida para reactivación' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.productos
  WHERE id=v_origen.producto_id AND lower(nombre) LIKE '%garraf%') THEN
   RAISE EXCEPTION 'El producto anterior ya no es un garrafón válido' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.empleados WHERE id=v_origen.captador_empleado_id) THEN
   RAISE EXCEPTION 'El captador anterior ya no existe' USING ERRCODE='22023';
 END IF;
 IF v_origen.equipo_id IS NOT NULL THEN
   SELECT * INTO v_equipo FROM public.aq_equipos_incentivo
   WHERE id=v_origen.equipo_id AND activo FOR SHARE;
   IF NOT FOUND OR v_origen.captador_empleado_id NOT IN
     (v_equipo.empleado_a_id,v_equipo.empleado_b_id) THEN
     RAISE EXCEPTION 'El equipo ya no está activo o cambió. Revisa la configuración antes de reactivar.'
       USING ERRCODE='22023';
   END IF;
 END IF;
 IF v_origen.modalidad='equipo' AND v_origen.equipo_id IS NULL THEN
   RAISE EXCEPTION 'El incentivo anterior no tiene equipo válido' USING ERRCODE='22023';
 END IF;
 IF v_origen.modalidad='individual' AND
 (v_origen.beneficiario_empleado_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.empleados WHERE id=v_origen.beneficiario_empleado_id)) THEN
   RAISE EXCEPTION 'El beneficiario anterior no está disponible' USING ERRCODE='22023';
 END IF;
 IF v_origen.modalidad NOT IN ('equipo','individual') THEN
   RAISE EXCEPTION 'Modalidad de incentivo anterior desconocida' USING ERRCODE='22023';
 END IF;
 v_hoy:=(now() AT TIME ZONE 'America/Guatemala')::date;
 SELECT coalesce(max(id),0) INTO v_max_venta FROM public.ventas;
 INSERT INTO aquabri_private.aq_incentivo_reactivacion_permiso
   (tx_id,cliente_id,origen_id,autorizado_usuario_id)
 VALUES(txid_current(),v_origen.cliente_id,v_origen.id,p_uid);
 INSERT INTO public.aq_incentivos_captacion (
  cliente_id,producto_id,captador_empleado_id,equipo_id,modalidad,
  beneficiario_empleado_id,monto_unitario,precio_minimo,desde,hasta,
  activo,captacion_confirmada,autorizado_usuario_id,
  reactivacion_origen_id,venta_id_inicio
 ) VALUES(
  v_origen.cliente_id,v_origen.producto_id,v_origen.captador_empleado_id,
  v_origen.equipo_id,v_origen.modalidad,v_origen.beneficiario_empleado_id,
  v_origen.monto_unitario,v_origen.precio_minimo,v_hoy,NULL,
  true,true,p_uid,v_origen.id,v_max_venta
 ) RETURNING id INTO v_nuevo;
 RETURN jsonb_build_object('incentivo_id',v_nuevo,'anterior_id',v_origen.id,
   'cliente_id',v_origen.cliente_id,'desde',v_hoy,'monto_unitario',v_origen.monto_unitario,
   'venta_id_inicio',v_max_venta);
END
$fn$;
REVOKE ALL ON FUNCTION public.aq_reactivar_incentivo_jefe_v1(text,bigint,bigint,boolean)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aq_reactivar_incentivo_jefe_v1(text,bigint,bigint,boolean)
TO anon,authenticated;
