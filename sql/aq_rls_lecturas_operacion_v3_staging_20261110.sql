-- AQUABRI staging. SOLO LECTURA, respaldada por roles y permisos de Supabase Auth.
-- Aplicada al proyecto xzbawbkstaqvkwtqlqai. NO aplicar a producción sin pruebas de integración.
BEGIN;
DROP POLICY IF EXISTS aq_config_lectura_auth ON public.config;
CREATE POLICY aq_config_lectura_auth ON public.config FOR SELECT TO authenticated
USING ((SELECT aquabri_private.usuario_id_actual()) IS NOT NULL);
GRANT SELECT ON public.config TO authenticated;

DROP POLICY IF EXISTS aq_gastos_lectura_permiso ON public.gastos;
CREATE POLICY aq_gastos_lectura_permiso ON public.gastos FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('gastos')));
GRANT SELECT ON public.gastos TO authenticated;

DROP POLICY IF EXISTS aq_facturas_lectura_permiso ON public.facturas_proveedores;
CREATE POLICY aq_facturas_lectura_permiso ON public.facturas_proveedores FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('facturas')));
GRANT SELECT ON public.facturas_proveedores TO authenticated;

DROP POLICY IF EXISTS aq_factura_items_lectura_permiso ON public.factura_items;
CREATE POLICY aq_factura_items_lectura_permiso ON public.factura_items FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('facturas')));
GRANT SELECT ON public.factura_items TO authenticated;

DROP POLICY IF EXISTS aq_deudas_proveedores_lectura_permiso ON public.deudas_proveedores;
CREATE POLICY aq_deudas_proveedores_lectura_permiso ON public.deudas_proveedores FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('proveedores.ver')));
GRANT SELECT ON public.deudas_proveedores TO authenticated;

DROP POLICY IF EXISTS aq_envases_lectura_permiso ON public.envases;
CREATE POLICY aq_envases_lectura_permiso ON public.envases FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('envases'))
   AND aquabri_private.puede_ver_cliente(cliente_id));
GRANT SELECT ON public.envases TO authenticated;

DROP POLICY IF EXISTS aq_envases_bodega_lectura_permiso ON public.envases_bodega;
CREATE POLICY aq_envases_bodega_lectura_permiso ON public.envases_bodega FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('envases')));
GRANT SELECT ON public.envases_bodega TO authenticated;

DROP POLICY IF EXISTS aq_puntos_config_lectura_permiso ON public.puntos_config;
CREATE POLICY aq_puntos_config_lectura_permiso ON public.puntos_config FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('puntos')));
GRANT SELECT ON public.puntos_config TO authenticated;

DROP POLICY IF EXISTS aq_metas_lectura_permiso ON public.metas;
CREATE POLICY aq_metas_lectura_permiso ON public.metas FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('metas')));
GRANT SELECT ON public.metas TO authenticated;
COMMIT;
