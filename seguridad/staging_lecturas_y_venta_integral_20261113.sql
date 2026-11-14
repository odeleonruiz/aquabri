-- AQUABRI STAGING: compatibilidad de lectura, sesión y ventas atómicas.

-- Pruebas verificadas con transacciones ROLLBACK: contado jefe, crédito vendedor y visita del vendedor.

-- REQUIERE las funciones/tables de staging (en especial aq_registrar_venta_integral_v2).

-- NO EJECUTAR este archivo directamente sobre el proyecto oficial sin completar dependencias.

BEGIN;

SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.aq_legacy_empleado_actual_v1()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT u.empleado_id FROM public.usuarios u
  WHERE u.id=(SELECT public.aq_sesion_legacy_usuario_actual_v1()) LIMIT 1
$function$
;

CREATE OR REPLACE FUNCTION public.aq_legacy_permiso_modulo_v1(p_codigo text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT (SELECT public.aq_sesion_legacy_usuario_actual_v1()) IS NOT NULL
 AND coalesce(aquabri_private.tiene_permiso_usuario((SELECT public.aq_sesion_legacy_usuario_actual_v1()),p_codigo),false);
$function$
;

CREATE OR REPLACE FUNCTION public.aq_sesion_legacy_puede_ver_cliente_v1(p_cliente integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid integer; v_rol text;
BEGIN
 v_uid:=public.aq_sesion_legacy_usuario_actual_v1();
 IF v_uid IS NULL OR p_cliente IS NULL THEN RETURN false; END IF;
 SELECT rol INTO v_rol FROM public.usuarios WHERE id=v_uid;
 IF v_rol='jefe' THEN RETURN true; END IF;
 RETURN EXISTS(SELECT 1 FROM public.clientes c WHERE c.id=p_cliente AND c.creado_por=v_uid::text)
   OR EXISTS(SELECT 1 FROM public.aq_clientes_atribucion_manual a
             WHERE a.cliente_id=p_cliente AND a.usuario_id=v_uid)
   OR EXISTS(SELECT 1 FROM public.ventas v WHERE v.cliente_id=p_cliente AND v.usuario_id=v_uid);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aq_vender_con_envases_sesion_v1(p_token text, p_uid bigint, p_nonce text, p_venta jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor integer;
 v_header jsonb;
 v_result jsonb;
 v_envases jsonb:=NULL;
 v_entregados integer;
 v_devueltos integer;
 v_venta bigint;
BEGIN
 v_actor := public.aq_sesion_legacy_usuario_actual_v1();
 IF v_actor IS NULL OR p_uid IS DISTINCT FROM v_actor THEN
   RAISE EXCEPTION 'Sesión inexistente o usuario no autorizado' USING ERRCODE='42501';
 END IF;
 v_header := coalesce(nullif(pg_catalog.current_setting('request.headers',true),'')::jsonb,'{}'::jsonb);
 IF p_token IS NULL OR p_token IS DISTINCT FROM (v_header->>'x-aquabri-session') THEN
   RAISE EXCEPTION 'La sesión no corresponde al acceso actual' USING ERRCODE='42501';
 END IF;
 IF NOT coalesce(aquabri_private.tiene_permiso_usuario(v_actor,'ventas.registrar'),false) THEN
   RAISE EXCEPTION 'Sin permiso para registrar ventas' USING ERRCODE='42501';
 END IF;
 IF p_venta IS NULL OR pg_catalog.jsonb_typeof(p_venta)<>'object'
    OR p_items IS NULL OR pg_catalog.jsonb_typeof(p_items)<>'array' THEN
   RAISE EXCEPTION 'Datos de venta inválidos' USING ERRCODE='22023';
 END IF;
 v_entregados := coalesce((p_venta->>'envases_llevan')::integer,0);
 v_devueltos := coalesce((p_venta->>'envases_devuelven')::integer,0);
 IF v_entregados<0 OR v_devueltos<0 OR v_entregados>100000 OR v_devueltos>100000 THEN
   RAISE EXCEPTION 'Cantidad de envases inválida' USING ERRCODE='22023';
 END IF;
 IF (v_entregados>0 OR v_devueltos>0)
    AND nullif(p_venta->>'cliente_id','') IS NULL THEN
   RAISE EXCEPTION 'Cliente requerido para envases' USING ERRCODE='22023';
 END IF;

 -- Esta función realiza inventario, crédito, caja y puntos en una transacción.
 v_result:=public.aq_registrar_venta_integral_v2(p_token,p_uid,p_nonce,p_venta,p_items);

 -- Una reejecución con el mismo nonce no debe volver a modificar envases.
 IF coalesce((v_result->>'repetida')::boolean,false) THEN
   RETURN v_result;
 END IF;

 v_venta:=(v_result->>'id')::bigint;
 IF (v_entregados>0 OR v_devueltos>0) THEN
   v_envases:=public.aq_registrar_envases_venta(
      p_token,p_uid,v_venta,v_entregados,v_devueltos
   );
   IF coalesce((v_envases->>'ok')::boolean,false) IS NOT TRUE THEN
     RAISE EXCEPTION 'No se confirmaron los envases de la venta';
   END IF;
 END IF;
 RETURN v_result || pg_catalog.jsonb_build_object('envases',v_envases);
END;
$function$
;

REVOKE ALL ON FUNCTION public.aq_legacy_permiso_modulo_v1(text),public.aq_legacy_empleado_actual_v1(),
public.aq_vender_con_envases_sesion_v1(text,bigint,text,jsonb,jsonb),public.aq_sesion_legacy_puede_ver_cliente_v1(integer)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.aq_legacy_permiso_modulo_v1(text),
public.aq_legacy_empleado_actual_v1(),
public.aq_vender_con_envases_sesion_v1(text,bigint,text,jsonb,jsonb),
public.aq_sesion_legacy_puede_ver_cliente_v1(integer),
public.aq_sesion_legacy_usuario_actual_v1(),
public.aq_sesion_legacy_rol_v1(),
public.aq_sesion_legacy_tiene_permiso_lectura_v2(text),
public.aq_login_usuario_seguro_v1(text,text),
public.aq_sesion_perfil_seguro_v1(),
public.aq_usuarios_listar_seguro_v1(),
public.aq_cerrar_sesion_segura_v1() TO anon;

ALTER TABLE public."activos_cat" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."activos_cat" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."activos_cat";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."activos_cat" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('activos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."activos_items" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."activos_items" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."activos_items";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."activos_items" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('activos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."activos_prestamos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."activos_prestamos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."activos_prestamos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."activos_prestamos" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('activos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."ausencias" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."ausencias" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."ausencias";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."ausencias" FOR SELECT TO anon USING ((( SELECT aq_legacy_permiso_modulo_v1('rrhh'::text) AS aq_legacy_permiso_modulo_v1) OR (empleado_id = ( SELECT aq_legacy_empleado_actual_v1() AS aq_legacy_empleado_actual_v1))));

ALTER TABLE public."carga_items" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."carga_items" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."carga_items";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."carga_items" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM cargas c
  WHERE (c.id = carga_items.carga_id)))));

ALTER TABLE public."cargas" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."cargas" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."cargas";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."cargas" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (empleado_id = ( SELECT aq_legacy_empleado_actual_v1() AS aq_legacy_empleado_actual_v1))));

ALTER TABLE public."cargas_vehiculos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."cargas_vehiculos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."cargas_vehiculos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."cargas_vehiculos" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('vehiculos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."clientes_eliminados" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."clientes_eliminados" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."clientes_eliminados";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."clientes_eliminados" FOR SELECT TO anon USING ((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text));

ALTER TABLE public."comisiones" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."comisiones" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."comisiones";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."comisiones" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('comisiones'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."deudas_proveedores" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."deudas_proveedores" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."deudas_proveedores";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."deudas_proveedores" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('proveedores.ver'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."empleados" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."empleados" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."empleados";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."empleados" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('rrhh'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."envases_bodega" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."envases_bodega" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."envases_bodega";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."envases_bodega" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('envases'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."factura_items" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."factura_items" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."factura_items";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."factura_items" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('facturas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."facturas_proveedores" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."facturas_proveedores" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."facturas_proveedores";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."facturas_proveedores" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('facturas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."gastos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."gastos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."gastos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."gastos" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('gastos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."grupos_ruta" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."grupos_ruta" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."grupos_ruta";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."grupos_ruta" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('mapa'::text) AS aq_legacy_permiso_modulo_v1) OR ( SELECT aq_legacy_permiso_modulo_v1('ventas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."insumos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."insumos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."insumos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."insumos" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('inventario'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."liquidacion_items" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."liquidacion_items" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."liquidacion_items";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."liquidacion_items" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM liquidaciones l
  WHERE (l.id = liquidacion_items.liquidacion_id)))));

ALTER TABLE public."liquidaciones" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."liquidaciones" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."liquidaciones";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."liquidaciones" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (usuario_id = ( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1)) OR (empleado_id = ( SELECT aq_legacy_empleado_actual_v1() AS aq_legacy_empleado_actual_v1))));

ALTER TABLE public."mantenimientos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."mantenimientos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."mantenimientos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."mantenimientos" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('vehiculos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."mensajes" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."mensajes" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."mensajes";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."mensajes" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (de_usuario_id = ( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1)) OR (para_usuario_id = ( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1))));

ALTER TABLE public."metas" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."metas" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."metas";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."metas" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('metas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."metas_empleados" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."metas_empleados" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."metas_empleados";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."metas_empleados" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('metas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."notificaciones" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."notificaciones" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."notificaciones";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."notificaciones" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (usuario_id = ( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1))));

ALTER TABLE public."pagos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."pagos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."pagos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."pagos" FOR SELECT TO anon USING ((( SELECT aq_legacy_permiso_modulo_v1('rrhh'::text) AS aq_legacy_permiso_modulo_v1) OR (empleado_id = ( SELECT aq_legacy_empleado_actual_v1() AS aq_legacy_empleado_actual_v1))));

ALTER TABLE public."pagos_comisiones" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."pagos_comisiones" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."pagos_comisiones";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."pagos_comisiones" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('comisiones'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."precio_historial" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."precio_historial" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."precio_historial";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."precio_historial" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('inventario'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."producto_insumos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."producto_insumos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."producto_insumos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."producto_insumos" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('inventario'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."puntos_canjes_qr" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."puntos_canjes_qr" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."puntos_canjes_qr";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."puntos_canjes_qr" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('puntos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."puntos_clientes" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."puntos_clientes" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."puntos_clientes";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."puntos_clientes" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('puntos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."puntos_config" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."puntos_config" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."puntos_config";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."puntos_config" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('puntos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."puntos_historial" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."puntos_historial" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."puntos_historial";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."puntos_historial" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('puntos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."puntos_productos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."puntos_productos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."puntos_productos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."puntos_productos" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('puntos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."ruta_clientes" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."ruta_clientes" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."ruta_clientes";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."ruta_clientes" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('mapa'::text) AS aq_legacy_permiso_modulo_v1) OR ( SELECT aq_legacy_permiso_modulo_v1('ventas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."ruta_paradas" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."ruta_paradas" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."ruta_paradas";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."ruta_paradas" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('mapa'::text) AS aq_legacy_permiso_modulo_v1) OR ( SELECT aq_legacy_permiso_modulo_v1('ventas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."ruta_paradas" ENABLE ROW LEVEL SECURITY;

GRANT UPDATE(estado) ON public."ruta_paradas" TO anon;

DROP POLICY IF EXISTS "aq_legacy_parada_visitada_v1" ON public."ruta_paradas";

CREATE POLICY "aq_legacy_parada_visitada_v1" ON public."ruta_paradas" FOR UPDATE TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (( SELECT aq_legacy_permiso_modulo_v1('mapa'::text) AS aq_legacy_permiso_modulo_v1) AND (EXISTS ( SELECT 1
   FROM rutas r
  WHERE ((r.id = ruta_paradas.ruta_id) AND (r.empleado_id = ( SELECT aq_legacy_empleado_actual_v1() AS aq_legacy_empleado_actual_v1)))))))) WITH CHECK (((estado = 'Visitado'::text) AND ((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (( SELECT aq_legacy_permiso_modulo_v1('mapa'::text) AS aq_legacy_permiso_modulo_v1) AND (EXISTS ( SELECT 1
   FROM rutas r
  WHERE ((r.id = ruta_paradas.ruta_id) AND (r.empleado_id = ( SELECT aq_legacy_empleado_actual_v1() AS aq_legacy_empleado_actual_v1)))))))));

ALTER TABLE public."rutas" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."rutas" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."rutas";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."rutas" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('mapa'::text) AS aq_legacy_permiso_modulo_v1) OR ( SELECT aq_legacy_permiso_modulo_v1('ventas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."rutas_personalizadas" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."rutas_personalizadas" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."rutas_personalizadas";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."rutas_personalizadas" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('mapa'::text) AS aq_legacy_permiso_modulo_v1) OR ( SELECT aq_legacy_permiso_modulo_v1('ventas'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."vales" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."vales" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."vales";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."vales" FOR SELECT TO anon USING ((( SELECT aq_legacy_permiso_modulo_v1('rrhh'::text) AS aq_legacy_permiso_modulo_v1) OR (empleado_id = ( SELECT aq_legacy_empleado_actual_v1() AS aq_legacy_empleado_actual_v1))));

ALTER TABLE public."vehiculos" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."vehiculos" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."vehiculos";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."vehiculos" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ( SELECT aq_legacy_permiso_modulo_v1('vehiculos'::text) AS aq_legacy_permiso_modulo_v1)));

ALTER TABLE public."visitas" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public."visitas" TO anon;

DROP POLICY IF EXISTS "aq_compat_legacy_read_v1" ON public."visitas";

CREATE POLICY "aq_compat_legacy_read_v1" ON public."visitas" FOR SELECT TO anon USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (usuario_id = ( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1)) OR ( SELECT aq_sesion_legacy_puede_ver_cliente_v1(visitas.cliente_id) AS aq_sesion_legacy_puede_ver_cliente_v1)));

ALTER TABLE public."visitas" ENABLE ROW LEVEL SECURITY;

GRANT INSERT(cliente_id,fecha,usuario_id,notas,sin_compra) ON public."visitas" TO anon;GRANT USAGE ON SEQUENCE public.visitas_id_seq TO anon;

DROP POLICY IF EXISTS "aq_legacy_visitas_crear_v1" ON public."visitas";

CREATE POLICY "aq_legacy_visitas_crear_v1" ON public."visitas" FOR INSERT TO anon WITH CHECK (((usuario_id = ( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1)) AND (( SELECT aq_legacy_permiso_modulo_v1('ventas'::text) AS aq_legacy_permiso_modulo_v1) OR ( SELECT aq_legacy_permiso_modulo_v1('mapa'::text) AS aq_legacy_permiso_modulo_v1)) AND aq_sesion_legacy_puede_ver_cliente_v1(cliente_id)));

-- RPC de caja y crédito: sólo su wrapper con sesión puede ejecutarse como anon.
REVOKE ALL ON FUNCTION public.aq_cobrar_credito_sesion_segura_v1(text,bigint,numeric,text,text,bigint),
  public.aq_abrir_caja_sesion_v1(text,date,numeric,integer,text),
  public.aq_cerrar_caja_sesion_v1(text,date,integer,numeric,numeric,integer,boolean,boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aq_cobrar_credito_sesion_segura_v1(text,bigint,numeric,text,text,bigint),
  public.aq_abrir_caja_sesion_v1(text,date,numeric,integer,text),
  public.aq_cerrar_caja_sesion_v1(text,date,integer,numeric,numeric,integer,boolean,boolean,text) TO anon;

COMMIT;