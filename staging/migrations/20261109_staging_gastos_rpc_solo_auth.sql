-- Ejecutado y verificado en aquabri-staging el 2026-11-09.
-- Seguridad defensiva solo para el entorno de pruebas.
-- La app principal no se modifica; funciones siguen disponibles para authenticated.
REVOKE EXECUTE ON FUNCTION public.aq_registrar_gasto_seguro(text,bigint,text,jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.aq_eliminar_gasto_seguro(text,bigint,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aq_registrar_gasto_seguro(text,bigint,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aq_eliminar_gasto_seguro(text,bigint,integer) TO authenticated;
