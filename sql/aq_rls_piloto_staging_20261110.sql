-- MIGRACIÓN REPRODUCIBLE — aplicada únicamente a AQUABRI staging
-- Proyecto: xzbawbkstaqvkwtqlqai, fecha 2026-11-10
-- NO EJECUTAR EN PRODUCCIÓN SIN REVISIÓN Y PRUEBAS DE INTEGRACIÓN.
BEGIN;
REVOKE ALL ON TABLE public.usuarios FROM anon, authenticated;
DROP POLICY IF EXISTS aq_usuarios_perfil_auth ON public.usuarios;
CREATE POLICY aq_usuarios_perfil_auth ON public.usuarios FOR SELECT TO authenticated
USING (auth_uid=(SELECT auth.uid()) OR (SELECT aquabri_private.rol_actual())='jefe');
GRANT SELECT (id,nombre,usuario,rol,foto,permisos_custom,empleado_id,auth_uid)
ON public.usuarios TO authenticated;

GRANT SELECT ON public.productos TO authenticated;

REVOKE ALL ON public.empleados FROM anon,authenticated;
DROP POLICY IF EXISTS aq_empleados_lectura_auth ON public.empleados;
CREATE POLICY aq_empleados_lectura_auth ON public.empleados FOR SELECT TO authenticated
USING ((SELECT aquabri_private.rol_actual())='jefe'
       OR usuario_id=(SELECT aquabri_private.usuario_id_actual()));
GRANT SELECT ON public.empleados TO authenticated;

REVOKE ALL ON public.comisiones FROM anon,authenticated;
DROP POLICY IF EXISTS aq_comisiones_lectura_auth ON public.comisiones;
CREATE POLICY aq_comisiones_lectura_auth ON public.comisiones FOR SELECT TO authenticated
USING ((SELECT aquabri_private.rol_actual())='jefe'
   OR EXISTS (SELECT 1 FROM public.empleados e WHERE e.id=empleado_id
      AND e.usuario_id=(SELECT aquabri_private.usuario_id_actual())));
GRANT SELECT ON public.comisiones TO authenticated;
COMMIT;

-- CONSULTAS DE VERIFICACIÓN (solo lectura):
-- SELECT has_column_privilege('authenticated','public.usuarios','pass','SELECT');
-- Debe retornar false.
-- SELECT c.relname,c.relrowsecurity FROM pg_class c
-- JOIN pg_namespace n ON n.oid=c.relnamespace
-- WHERE n.nspname='public' AND c.relkind='r';
-- No hacer GRANT ALL/USING(true) ni reemplazar reglas por "TO authenticated" solamente.
