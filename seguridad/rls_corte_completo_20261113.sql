-- AQUABRI: propuesta de corte seguro de RLS para 68 tablas públicas.
-- Cubre las 24 tablas con RLS apagado y elimina las 34 políticas antiguas de acceso total.
-- IMPORTANTE: NO EJECUTAR EN PRODUCCIÓN hasta migrar el frontend a sesiones JWT/RPC,
-- portar las funciones y columnas requeridas de staging, probar ventas/caja/créditos,
-- y disponer de un respaldo externo verificable. El HTML actual utiliza SELECT/INSERT
-- directos con el rol anon; ejecutar ahora bloquearía el negocio.
-- Generado de la configuración REAL de aquabri-staging (noviembre de 2026).
-- Respaldo de configuración y filas: aquabri_private.aq_seguridad_*_20261113;
-- copia local de datos: aquabri_respaldo_20261113 (no es backup externo).

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
-- activos_cat: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_activos_cat" ON public."activos_cat";
ALTER TABLE public."activos_cat" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."activos_cat" FROM anon, authenticated;
GRANT SELECT ON public."activos_cat" TO authenticated;
CREATE POLICY "aq_activos_cat_lectura_auth" ON public."activos_cat" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('activos'::text) AS tiene_permiso_actual)));

-- activos_items: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."activos_items" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."activos_items" FROM anon, authenticated;
GRANT SELECT ON public."activos_items" TO authenticated;
CREATE POLICY "aq_activos_items_lectura_auth" ON public."activos_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('activos'::text) AS tiene_permiso_actual)));

-- activos_prestamos: rls_antes=false, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_activos_prestamos" ON public."activos_prestamos";
ALTER TABLE public."activos_prestamos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."activos_prestamos" FROM anon, authenticated;
GRANT SELECT ON public."activos_prestamos" TO authenticated;
CREATE POLICY "aq_activos_prestamos_lectura_auth" ON public."activos_prestamos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('activos'::text) AS tiene_permiso_actual)));

-- aq_auth_login_freno: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_auth_login_freno" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_auth_login_freno" FROM anon, authenticated;

-- aq_clientes_atribucion_historial: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_clientes_atribucion_historial" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_clientes_atribucion_historial" FROM anon, authenticated;

-- aq_clientes_atribucion_manual: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_clientes_atribucion_manual" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_clientes_atribucion_manual" FROM anon, authenticated;

-- aq_cobros_credito_operacion: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_cobros_credito_operacion" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_cobros_credito_operacion" FROM anon, authenticated;

-- aq_compras_operacion: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_compras_operacion" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_compras_operacion" FROM anon, authenticated;

-- aq_consumos_lotes: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_consumos_lotes" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_consumos_lotes" FROM anon, authenticated;

-- aq_equipos_incentivo: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_equipos_incentivo" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_equipos_incentivo" FROM anon, authenticated;

-- aq_facturas_clasificacion: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_facturas_clasificacion" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_facturas_clasificacion" FROM anon, authenticated;

-- aq_gastos_operacion: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_gastos_operacion" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_gastos_operacion" FROM anon, authenticated;

-- aq_incentivos_captacion: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_incentivos_captacion" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_incentivos_captacion" FROM anon, authenticated;

-- aq_incentivos_devengados: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_incentivos_devengados" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_incentivos_devengados" FROM anon, authenticated;

-- aq_lotes_inventario: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_lotes_inventario" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_lotes_inventario" FROM anon, authenticated;

-- aq_pagos_incentivos: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_pagos_incentivos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_pagos_incentivos" FROM anon, authenticated;

-- aq_pagos_proveedor_detalle: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_pagos_proveedor_detalle" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_pagos_proveedor_detalle" FROM anon, authenticated;

-- aq_pagos_proveedores: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_pagos_proveedores" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_pagos_proveedores" FROM anon, authenticated;

-- aq_ventas_operacion: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."aq_ventas_operacion" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."aq_ventas_operacion" FROM anon, authenticated;

-- ausencias: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."ausencias" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."ausencias" FROM anon, authenticated;
GRANT SELECT ON public."ausencias" TO authenticated;
CREATE POLICY "aq_ausencias_rrhh_lectura_auth" ON public."ausencias" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = ausencias.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));

-- caja: rls_antes=false, politicas_antes=0, politicas_despues=2
ALTER TABLE public."caja" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."caja" FROM anon, authenticated;
GRANT SELECT ON public."caja" TO anon;
GRANT SELECT ON public."caja" TO authenticated;
CREATE POLICY "aq_caja_lectura_auth" ON public."caja" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));
CREATE POLICY "aq_caja_lectura_sesion_legacy_v1" ON public."caja" AS PERMISSIVE FOR SELECT TO "anon" USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (usuario_id = ( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1))));

-- carga_items: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_carga_items" ON public."carga_items";
ALTER TABLE public."carga_items" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."carga_items" FROM anon, authenticated;
GRANT SELECT ON public."carga_items" TO authenticated;
CREATE POLICY "aq_carga_items_lectura_auth" ON public."carga_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM cargas c
  WHERE (c.id = carga_items.carga_id))));

-- cargas: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_cargas" ON public."cargas";
ALTER TABLE public."cargas" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."cargas" FROM anon, authenticated;
GRANT SELECT ON public."cargas" TO authenticated;
CREATE POLICY "aq_cargas_lectura_auth" ON public."cargas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = cargas.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));

-- cargas_vehiculos: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."cargas_vehiculos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."cargas_vehiculos" FROM anon, authenticated;

-- categorias: rls_antes=true, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_categorias" ON public."categorias";
ALTER TABLE public."categorias" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."categorias" FROM anon, authenticated;
GRANT SELECT ON public."categorias" TO anon;
GRANT SELECT ON public."categorias" TO authenticated;
CREATE POLICY "aq_categorias_lectura_auth" ON public."categorias" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual) IS NOT NULL));
CREATE POLICY "aq_categorias_lectura_sesion_legacy_v1" ON public."categorias" AS PERMISSIVE FOR SELECT TO "anon" USING ((( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1) IS NOT NULL));

-- clientes: rls_antes=false, politicas_antes=2, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_clientes" ON public."clientes";
DROP POLICY IF EXISTS "lectura_publica_clientes" ON public."clientes";
ALTER TABLE public."clientes" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."clientes" FROM anon, authenticated;
GRANT SELECT ON public."clientes" TO anon;
GRANT SELECT ON public."clientes" TO authenticated;
CREATE POLICY "aq_clientes_lectura_auth" ON public."clientes" AS PERMISSIVE FOR SELECT TO "authenticated" USING (aquabri_private.puede_ver_cliente(id));
CREATE POLICY "aq_clientes_lectura_sesion_legacy_v1" ON public."clientes" AS PERMISSIVE FOR SELECT TO "anon" USING (((archivado_en IS NULL) AND (( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1) IS NOT NULL)));

-- clientes_eliminados: rls_antes=false, politicas_antes=0, politicas_despues=2
ALTER TABLE public."clientes_eliminados" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."clientes_eliminados" FROM anon, authenticated;
GRANT SELECT ON public."clientes_eliminados" TO anon;
GRANT SELECT ON public."clientes_eliminados" TO authenticated;
CREATE POLICY "aq_historial_clientes_archivados_sesion_v1" ON public."clientes_eliminados" AS PERMISSIVE FOR SELECT TO "anon" USING ((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text));
CREATE POLICY "aq_historial_clientes_solo_jefe_select" ON public."clientes_eliminados" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));

-- comisiones: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_comisiones" ON public."comisiones";
ALTER TABLE public."comisiones" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."comisiones" FROM anon, authenticated;
GRANT SELECT ON public."comisiones" TO authenticated;
CREATE POLICY "aq_comisiones_lectura_auth" ON public."comisiones" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = comisiones.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));

-- config: rls_antes=true, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_config" ON public."config";
ALTER TABLE public."config" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."config" FROM anon, authenticated;
GRANT SELECT ON public."config" TO anon;
GRANT SELECT ON public."config" TO authenticated;
CREATE POLICY "aq_config_lectura_auth" ON public."config" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual) IS NOT NULL));
CREATE POLICY "aq_config_lectura_sesion_legacy_v1" ON public."config" AS PERMISSIVE FOR SELECT TO "anon" USING ((( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1) IS NOT NULL));

-- creditos: rls_antes=false, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_creditos" ON public."creditos";
ALTER TABLE public."creditos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."creditos" FROM anon, authenticated;
GRANT SELECT ON public."creditos" TO anon;
GRANT SELECT ON public."creditos" TO authenticated;
CREATE POLICY "aq_creditos_lectura_auth" ON public."creditos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (aquabri_private.puede_ver_cliente(cliente_id));
CREATE POLICY "aq_creditos_lectura_sesion_legacy_v1" ON public."creditos" AS PERMISSIVE FOR SELECT TO "anon" USING (( SELECT aq_sesion_legacy_tiene_permiso_lectura_v2('creditos'::text) AS aq_sesion_legacy_tiene_permiso_lectura_v2));

-- deudas_proveedores: rls_antes=false, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_deudas_proveedores" ON public."deudas_proveedores";
ALTER TABLE public."deudas_proveedores" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."deudas_proveedores" FROM anon, authenticated;
GRANT SELECT ON public."deudas_proveedores" TO authenticated;
CREATE POLICY "aq_deudas_proveedores_lectura_jefe" ON public."deudas_proveedores" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
CREATE POLICY "aq_deudas_proveedores_lectura_permiso" ON public."deudas_proveedores" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT aquabri_private.tiene_permiso_actual('proveedores.ver'::text) AS tiene_permiso_actual));

-- empleados: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_empleados" ON public."empleados";
ALTER TABLE public."empleados" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."empleados" FROM anon, authenticated;
GRANT SELECT ON public."empleados" TO authenticated;
CREATE POLICY "aq_empleados_lectura_auth" ON public."empleados" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));

-- envases: rls_antes=false, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_envases" ON public."envases";
ALTER TABLE public."envases" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."envases" FROM anon, authenticated;
GRANT SELECT ON public."envases" TO anon;
GRANT SELECT ON public."envases" TO authenticated;
CREATE POLICY "aq_envases_lectura_permiso" ON public."envases" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT aquabri_private.tiene_permiso_actual('envases'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)));
CREATE POLICY "aq_envases_lectura_sesion_legacy_v1" ON public."envases" AS PERMISSIVE FOR SELECT TO "anon" USING (( SELECT aq_sesion_legacy_tiene_permiso_lectura_v2('envases'::text) AS aq_sesion_legacy_tiene_permiso_lectura_v2));

-- envases_bodega: rls_antes=true, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_envases_bodega" ON public."envases_bodega";
ALTER TABLE public."envases_bodega" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."envases_bodega" FROM anon, authenticated;
GRANT SELECT ON public."envases_bodega" TO anon;
GRANT SELECT ON public."envases_bodega" TO authenticated;
CREATE POLICY "aq_bodega_envases_lectura_sesion_legacy_v1" ON public."envases_bodega" AS PERMISSIVE FOR SELECT TO "anon" USING ((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = ANY (ARRAY['jefe'::text, 'vendedor'::text, 'vendedor_editor'::text, 'inventario'::text])));
CREATE POLICY "aq_envases_bodega_lectura_permiso" ON public."envases_bodega" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT aquabri_private.tiene_permiso_actual('envases'::text) AS tiene_permiso_actual));

-- factura_items: rls_antes=true, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_factura_items" ON public."factura_items";
ALTER TABLE public."factura_items" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."factura_items" FROM anon, authenticated;
GRANT SELECT ON public."factura_items" TO authenticated;
CREATE POLICY "aq_factura_items_lectura_jefe" ON public."factura_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
CREATE POLICY "aq_factura_items_lectura_permiso" ON public."factura_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT aquabri_private.tiene_permiso_actual('facturas'::text) AS tiene_permiso_actual));

-- facturas_proveedores: rls_antes=true, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_facturas_proveedores" ON public."facturas_proveedores";
ALTER TABLE public."facturas_proveedores" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."facturas_proveedores" FROM anon, authenticated;
GRANT SELECT ON public."facturas_proveedores" TO authenticated;
CREATE POLICY "aq_facturas_lectura_jefe" ON public."facturas_proveedores" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
CREATE POLICY "aq_facturas_lectura_permiso" ON public."facturas_proveedores" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT aquabri_private.tiene_permiso_actual('facturas'::text) AS tiene_permiso_actual));

-- gastos: rls_antes=true, politicas_antes=1, politicas_despues=3
DROP POLICY IF EXISTS "acceso_total_gastos" ON public."gastos";
ALTER TABLE public."gastos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."gastos" FROM anon, authenticated;
GRANT SELECT ON public."gastos" TO anon;
GRANT SELECT ON public."gastos" TO authenticated;
CREATE POLICY "aq_gastos_lectura_jefe" ON public."gastos" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
CREATE POLICY "aq_gastos_lectura_permiso" ON public."gastos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT aquabri_private.tiene_permiso_actual('gastos'::text) AS tiene_permiso_actual));
CREATE POLICY "aq_gastos_lectura_sesion_legacy_v1" ON public."gastos" AS PERMISSIVE FOR SELECT TO "anon" USING ((( SELECT aq_sesion_legacy_tiene_permiso_lectura_v2('gastos'::text) AS aq_sesion_legacy_tiene_permiso_lectura_v2) AND ((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR ((empleado_id IS NOT NULL) AND (empleado_id = ( SELECT aq_sesion_legacy_empleado_v1() AS aq_sesion_legacy_empleado_v1))))));

-- grupos_ruta: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."grupos_ruta" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."grupos_ruta" FROM anon, authenticated;
GRANT SELECT ON public."grupos_ruta" TO authenticated;
CREATE POLICY "aq_grupos_ruta_lectura_auth" ON public."grupos_ruta" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual)));

-- insumos: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_insumos" ON public."insumos";
ALTER TABLE public."insumos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."insumos" FROM anon, authenticated;
GRANT SELECT ON public."insumos" TO authenticated;
CREATE POLICY "aq_insumos_lectura_autorizada" ON public."insumos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT aquabri_private.tiene_permiso_actual('inventario'::text) AS tiene_permiso_actual));

-- liquidacion_items: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."liquidacion_items" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."liquidacion_items" FROM anon, authenticated;
GRANT SELECT ON public."liquidacion_items" TO authenticated;
CREATE POLICY "aq_liquidacion_items_lectura_auth" ON public."liquidacion_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM liquidaciones l
  WHERE (l.id = liquidacion_items.liquidacion_id))));

-- liquidaciones: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."liquidaciones" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."liquidaciones" FROM anon, authenticated;
GRANT SELECT ON public."liquidaciones" TO authenticated;
CREATE POLICY "aq_liquidaciones_lectura_auth" ON public."liquidaciones" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = liquidaciones.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))))) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));

-- mantenimientos: rls_antes=false, politicas_antes=0, politicas_despues=0
ALTER TABLE public."mantenimientos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."mantenimientos" FROM anon, authenticated;

-- mensajes: rls_antes=true, politicas_antes=1, politicas_despues=0
DROP POLICY IF EXISTS "acceso_total_mensajes" ON public."mensajes";
ALTER TABLE public."mensajes" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."mensajes" FROM anon, authenticated;

-- metas: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_metas" ON public."metas";
ALTER TABLE public."metas" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."metas" FROM anon, authenticated;
GRANT SELECT ON public."metas" TO authenticated;
CREATE POLICY "aq_metas_lectura_permiso" ON public."metas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT aquabri_private.tiene_permiso_actual('metas'::text) AS tiene_permiso_actual));

-- metas_empleados: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_metas_empleados" ON public."metas_empleados";
ALTER TABLE public."metas_empleados" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."metas_empleados" FROM anon, authenticated;
GRANT SELECT ON public."metas_empleados" TO authenticated;
CREATE POLICY "aq_meta_empleado_lectura_jefe" ON public."metas_empleados" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));

-- notificaciones: rls_antes=false, politicas_antes=0, politicas_despues=0
ALTER TABLE public."notificaciones" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."notificaciones" FROM anon, authenticated;

-- pagos: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_pagos" ON public."pagos";
ALTER TABLE public."pagos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."pagos" FROM anon, authenticated;
GRANT SELECT ON public."pagos" TO authenticated;
CREATE POLICY "aq_pagos_rrhh_lectura_auth" ON public."pagos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = pagos.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));

-- pagos_comisiones: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."pagos_comisiones" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."pagos_comisiones" FROM anon, authenticated;
GRANT SELECT ON public."pagos_comisiones" TO authenticated;
CREATE POLICY "aq_pagos_comision_consulta_jefe_v1" ON public."pagos_comisiones" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));

-- precio_historial: rls_antes=false, politicas_antes=0, politicas_despues=0
ALTER TABLE public."precio_historial" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."precio_historial" FROM anon, authenticated;

-- producto_insumos: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_producto_insumos" ON public."producto_insumos";
ALTER TABLE public."producto_insumos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."producto_insumos" FROM anon, authenticated;
GRANT SELECT ON public."producto_insumos" TO authenticated;
CREATE POLICY "aq_producto_insumos_lectura_auth" ON public."producto_insumos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('inventario'::text) AS tiene_permiso_actual)));

-- productos: rls_antes=true, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_productos" ON public."productos";
ALTER TABLE public."productos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."productos" FROM anon, authenticated;
GRANT SELECT ON public."productos" TO anon;
GRANT SELECT ON public."productos" TO authenticated;
CREATE POLICY "aq_productos_lectura_sesion_legacy_v1" ON public."productos" AS PERMISSIVE FOR SELECT TO "anon" USING ((( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1) IS NOT NULL));
CREATE POLICY "aq_productos_select_usuario_vinculado" ON public."productos" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual) IS NOT NULL));

-- puntos_canjes_qr: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."puntos_canjes_qr" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."puntos_canjes_qr" FROM anon, authenticated;
GRANT SELECT ON public."puntos_canjes_qr" TO authenticated;
CREATE POLICY "aq_puntos_qr_lectura_autorizada_v1" ON public."puntos_canjes_qr" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)))));

-- puntos_clientes: rls_antes=false, politicas_antes=2, politicas_despues=1
DROP POLICY IF EXISTS "acceso_puntos_clientes" ON public."puntos_clientes";
DROP POLICY IF EXISTS "lectura_publica_puntos" ON public."puntos_clientes";
ALTER TABLE public."puntos_clientes" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."puntos_clientes" FROM anon, authenticated;
GRANT SELECT ON public."puntos_clientes" TO authenticated;
CREATE POLICY "aq_puntos_clientes_lectura_auth" ON public."puntos_clientes" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id))));

-- puntos_config: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_puntos_config" ON public."puntos_config";
ALTER TABLE public."puntos_config" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."puntos_config" FROM anon, authenticated;
GRANT SELECT ON public."puntos_config" TO authenticated;
CREATE POLICY "aq_puntos_config_lectura_permiso" ON public."puntos_config" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual));

-- puntos_historial: rls_antes=false, politicas_antes=2, politicas_despues=1
DROP POLICY IF EXISTS "acceso_puntos_historial" ON public."puntos_historial";
DROP POLICY IF EXISTS "lectura_publica_historial" ON public."puntos_historial";
ALTER TABLE public."puntos_historial" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."puntos_historial" FROM anon, authenticated;
GRANT SELECT ON public."puntos_historial" TO authenticated;
CREATE POLICY "aq_puntos_historial_lectura_autorizada_v1" ON public."puntos_historial" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)))));

-- puntos_productos: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."puntos_productos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."puntos_productos" FROM anon, authenticated;
GRANT SELECT ON public."puntos_productos" TO authenticated;
CREATE POLICY "aq_puntos_productos_lectura_auth" ON public."puntos_productos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual)));

-- ruta_clientes: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."ruta_clientes" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."ruta_clientes" FROM anon, authenticated;
GRANT SELECT ON public."ruta_clientes" TO authenticated;
CREATE POLICY "aq_ruta_clientes_lectura_auth" ON public."ruta_clientes" AS PERMISSIVE FOR SELECT TO "authenticated" USING (aquabri_private.puede_ver_cliente(cliente_id));

-- ruta_paradas: rls_antes=false, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_ruta_paradas" ON public."ruta_paradas";
ALTER TABLE public."ruta_paradas" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."ruta_paradas" FROM anon, authenticated;
GRANT SELECT ON public."ruta_paradas" TO authenticated;
CREATE POLICY "aq_ruta_paradas_select_auth_v1" ON public."ruta_paradas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM rutas r
  WHERE ((r.id = ruta_paradas.ruta_id) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) AND (EXISTS ( SELECT 1
           FROM usuarios u
          WHERE ((u.auth_uid = ( SELECT auth.uid() AS uid)) AND (u.empleado_id IS NOT NULL) AND (u.empleado_id = r.empleado_id)))))))))));

-- rutas: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_rutas" ON public."rutas";
ALTER TABLE public."rutas" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."rutas" FROM anon, authenticated;
GRANT SELECT ON public."rutas" TO authenticated;
CREATE POLICY "aq_rutas_select_auth_v1" ON public."rutas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) AND (EXISTS ( SELECT 1
   FROM usuarios u
  WHERE ((u.auth_uid = ( SELECT auth.uid() AS uid)) AND (u.empleado_id IS NOT NULL) AND (u.empleado_id = rutas.empleado_id))))))));

-- rutas_personalizadas: rls_antes=false, politicas_antes=0, politicas_despues=0
ALTER TABLE public."rutas_personalizadas" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."rutas_personalizadas" FROM anon, authenticated;

-- sesiones: rls_antes=true, politicas_antes=1, politicas_despues=0
DROP POLICY IF EXISTS "acceso_total_sesiones" ON public."sesiones";
ALTER TABLE public."sesiones" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."sesiones" FROM anon, authenticated;

-- ubicaciones: rls_antes=true, politicas_antes=0, politicas_despues=0
ALTER TABLE public."ubicaciones" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."ubicaciones" FROM anon, authenticated;

-- usuarios: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_usuarios" ON public."usuarios";
ALTER TABLE public."usuarios" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."usuarios" FROM anon, authenticated;
CREATE POLICY "aq_usuarios_perfil_auth" ON public."usuarios" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((auth_uid = ( SELECT auth.uid() AS uid)) OR (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));

-- vales: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_vales" ON public."vales";
ALTER TABLE public."vales" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."vales" FROM anon, authenticated;
GRANT SELECT ON public."vales" TO authenticated;
CREATE POLICY "aq_vales_rrhh_lectura_auth" ON public."vales" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = vales.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));

-- vehiculos: rls_antes=true, politicas_antes=1, politicas_despues=1
DROP POLICY IF EXISTS "acceso_total_vehiculos" ON public."vehiculos";
ALTER TABLE public."vehiculos" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."vehiculos" FROM anon, authenticated;
GRANT SELECT ON public."vehiculos" TO authenticated;
CREATE POLICY "aq_vehiculos_lectura_auth" ON public."vehiculos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('vehiculos'::text) AS tiene_permiso_actual)));

-- venta_items: rls_antes=true, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_venta_items" ON public."venta_items";
ALTER TABLE public."venta_items" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."venta_items" FROM anon, authenticated;
GRANT SELECT ON public."venta_items" TO anon;
GRANT SELECT ON public."venta_items" TO authenticated;
CREATE POLICY "aq_items_lectura_sesion_legacy_v1" ON public."venta_items" AS PERMISSIVE FOR SELECT TO "anon" USING ((EXISTS ( SELECT 1
   FROM ventas v
  WHERE (v.id = venta_items.venta_id))));
CREATE POLICY "aq_venta_items_lectura_auth" ON public."venta_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ventas v
  WHERE (v.id = venta_items.venta_id))));

-- ventas: rls_antes=true, politicas_antes=1, politicas_despues=2
DROP POLICY IF EXISTS "acceso_total_ventas" ON public."ventas";
ALTER TABLE public."ventas" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."ventas" FROM anon, authenticated;
GRANT SELECT ON public."ventas" TO anon;
GRANT SELECT ON public."ventas" TO authenticated;
CREATE POLICY "aq_ventas_lectura_auth" ON public."ventas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));
CREATE POLICY "aq_ventas_lectura_sesion_legacy_v1" ON public."ventas" AS PERMISSIVE FOR SELECT TO "anon" USING (((( SELECT aq_sesion_legacy_rol_v1() AS aq_sesion_legacy_rol_v1) = 'jefe'::text) OR (usuario_id = ( SELECT aq_sesion_legacy_usuario_actual_v1() AS aq_sesion_legacy_usuario_actual_v1))));

-- visitas: rls_antes=false, politicas_antes=0, politicas_despues=1
ALTER TABLE public."visitas" ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public."visitas" FROM anon, authenticated;
GRANT SELECT ON public."visitas" TO authenticated;
CREATE POLICY "aq_visitas_lectura_auth" ON public."visitas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));

-- Prueba de estructura/estado después de la transacción en el proyecto de destino:
-- select count(*) filter(where relrowsecurity) rls_on from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p');
COMMIT;