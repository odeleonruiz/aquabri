-- AQUABRI · Verificación de integridad de historial (solo lectura, NUNCA borra datos).
-- Punto de referencia consultado en producción: 2026-11-12 00:05, hora de Guatemala.
-- La ejecución NO constituye un respaldo y NO protege contra cambios posteriores.
WITH
ventas_antes AS (
 SELECT count(*)::bigint total,
   md5(coalesce(string_agg(id::text,',' ORDER BY id),'')) huella
 FROM public.ventas WHERE id <= 5367
),
items_antes AS (
 SELECT count(*)::bigint total,
   md5(coalesce(string_agg(id::text||':'||coalesce(venta_id,-1)::text,',' ORDER BY id),'')) huella
 FROM public.venta_items WHERE id <= 6623
),
creditos_antes AS (
 SELECT count(*)::bigint total,
   md5(coalesce(string_agg(id::text,',' ORDER BY id),'')) huella
 FROM public.creditos WHERE id <= 853
),
caja_antes AS (
 SELECT count(*)::bigint total,
   md5(coalesce(string_agg(id::text,',' ORDER BY id),'')) huella
 FROM public.caja WHERE id <= 4914
)
SELECT
 now() at time zone 'America/Guatemala' as comprobado_en,
 v.total as ventas_preexistentes,v.huella as huella_ventas,
 (v.total=5236 AND v.huella='90f162b083b7760430e61fa1934c0705') as ventas_conservadas,
 i.total as items_preexistentes,i.huella as huella_items,
 (i.total=6428 AND i.huella='0af9bb4c10ed054aa03a499c931b48bb') as articulos_conservados,
 cr.total as creditos_preexistentes,cr.huella as huella_creditos,
 (cr.total=760 AND cr.huella='c2e995c5a86f5820452cb79878039df8') as creditos_conservados,
 ca.total as caja_preexistente,ca.huella as huella_caja,
 (ca.total=4866 AND ca.huella='1632cd620a88987c9c59242d13f9d2c7') as caja_sin_cambios
FROM ventas_antes v CROSS JOIN items_antes i
CROSS JOIN creditos_antes cr CROSS JOIN caja_antes ca;
-- Interpretación:
-- Un FALSE en ventas_conservadas/articulos_conservados es un BLOQUEO de despliegue.
-- Los abonos/cancelaciones podrían cambiar movimientos de caja incluso legítimamente;
-- un FALSE de caja requiere conciliación, NO restauración automática.
-- No ejecutar restauración sobre el proyecto oficial: sobrescribiría ventas más recientes.
