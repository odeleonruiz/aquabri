-- AQUABRI STAGING ONLY — read access by role and existing permission catalog.
-- No INSERT/UPDATE/DELETE grants or policies. Test both jefe and vendedor.
BEGIN;

GRANT SELECT ON TABLE
 public.liquidaciones,public.liquidacion_items,public.pagos,public.vales,
 public.ausencias,public.puntos_clientes,public.puntos_productos,
 public.ruta_clientes,public.vehiculos,public.visitas,public.producto_insumos,
 public.grupos_ruta,public.activos_cat,public.activos_items,
 public.activos_prestamos,public.cargas,public.carga_items
TO authenticated;

CREATE POLICY aq_liquidaciones_lectura_auth ON public.liquidaciones
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR EXISTS (SELECT 1 FROM public.empleados e
   WHERE e.id=liquidaciones.empleado_id
   AND e.usuario_id=(SELECT aquabri_private.usuario_id_actual()))
 OR usuario_id=(SELECT aquabri_private.usuario_id_actual())
);
CREATE POLICY aq_liquidacion_items_lectura_auth ON public.liquidacion_items
FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.liquidaciones l
   WHERE l.id=liquidacion_items.liquidacion_id)
);
CREATE POLICY aq_pagos_rrhh_lectura_auth ON public.pagos
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR EXISTS (SELECT 1 FROM public.empleados e WHERE e.id=pagos.empleado_id
 AND e.usuario_id=(SELECT aquabri_private.usuario_id_actual()))
);
CREATE POLICY aq_vales_rrhh_lectura_auth ON public.vales
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR EXISTS (SELECT 1 FROM public.empleados e WHERE e.id=vales.empleado_id
 AND e.usuario_id=(SELECT aquabri_private.usuario_id_actual()))
);
CREATE POLICY aq_ausencias_rrhh_lectura_auth ON public.ausencias
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR EXISTS (SELECT 1 FROM public.empleados e WHERE e.id=ausencias.empleado_id
 AND e.usuario_id=(SELECT aquabri_private.usuario_id_actual()))
);
CREATE POLICY aq_puntos_clientes_lectura_auth ON public.puntos_clientes
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR (
   (SELECT aquabri_private.tiene_permiso_actual('puntos'))
   AND aquabri_private.puede_ver_cliente(cliente_id)
 )
);
CREATE POLICY aq_puntos_productos_lectura_auth ON public.puntos_productos
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR (SELECT aquabri_private.tiene_permiso_actual('puntos'))
);
CREATE POLICY aq_ruta_clientes_lectura_auth ON public.ruta_clientes
FOR SELECT TO authenticated USING (
 aquabri_private.puede_ver_cliente(cliente_id)
);
CREATE POLICY aq_vehiculos_lectura_auth ON public.vehiculos
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR (SELECT aquabri_private.tiene_permiso_actual('vehiculos'))
);
CREATE POLICY aq_visitas_lectura_auth ON public.visitas
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR usuario_id=(SELECT aquabri_private.usuario_id_actual())
);
CREATE POLICY aq_producto_insumos_lectura_auth ON public.producto_insumos
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR (SELECT aquabri_private.tiene_permiso_actual('inventario'))
);
CREATE POLICY aq_grupos_ruta_lectura_auth ON public.grupos_ruta
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR (SELECT aquabri_private.tiene_permiso_actual('mapa'))
);
CREATE POLICY aq_activos_cat_lectura_auth ON public.activos_cat
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR (SELECT aquabri_private.tiene_permiso_actual('activos'))
);
CREATE POLICY aq_activos_items_lectura_auth ON public.activos_items
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR (SELECT aquabri_private.tiene_permiso_actual('activos'))
);
CREATE POLICY aq_activos_prestamos_lectura_auth ON public.activos_prestamos
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR (SELECT aquabri_private.tiene_permiso_actual('activos'))
);
CREATE POLICY aq_cargas_lectura_auth ON public.cargas
FOR SELECT TO authenticated USING (
 (SELECT aquabri_private.rol_actual())='jefe'
 OR EXISTS (SELECT 1 FROM public.empleados e WHERE e.id=cargas.empleado_id
 AND e.usuario_id=(SELECT aquabri_private.usuario_id_actual()))
);
CREATE POLICY aq_carga_items_lectura_auth ON public.carga_items
FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.cargas c WHERE c.id=carga_items.carga_id)
);

COMMIT;
