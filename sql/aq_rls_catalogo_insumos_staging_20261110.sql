-- Ejecutado en staging exclusivamente el 10-11-2026.
BEGIN;
REVOKE ALL ON TABLE public.categorias,public.insumos FROM anon,authenticated;
DROP POLICY IF EXISTS aq_categorias_lectura_auth ON public.categorias;
CREATE POLICY aq_categorias_lectura_auth ON public.categorias FOR SELECT TO authenticated
USING ((SELECT aquabri_private.usuario_id_actual()) IS NOT NULL);
GRANT SELECT ON public.categorias TO authenticated;
GRANT EXECUTE ON FUNCTION aquabri_private.tiene_permiso_actual(text) TO authenticated;
DROP POLICY IF EXISTS aq_insumos_lectura_autorizada ON public.insumos;
CREATE POLICY aq_insumos_lectura_autorizada ON public.insumos FOR SELECT TO authenticated
USING ((SELECT aquabri_private.tiene_permiso_actual('inventario')));
GRANT SELECT ON public.insumos TO authenticated;
COMMIT;
-- Sin INSERT/UPDATE/DELETE desde navegador.
-- Revalidar frente a datos reales de staging antes del despliegue.
