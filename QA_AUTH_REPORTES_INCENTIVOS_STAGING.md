# AQUABRI — Migración adicional de reportes, inventario e incentivos a Auth (staging)

Fecha: 2026-11-10/11, proyecto `xzbawbkstaqvkwtqlqai`, rama `prueba-supabase-auth-20261110`.

## Cambios ejecutados SOLO EN STAGING
- Nuevas RPC Auth de solo consulta: `aq_costos_lotes_auth_v1`, `aq_total_incentivos_auth_v1`, `aq_items_incentivados_auth_v1`, `aq_lotes_resumen_auth_v1`, `aq_facturas_tipos_auth_v1`. Son `SECURITY DEFINER`, con comprobación de identidad mediante `aquabri_private.contexto_auth_legacy()` y permiso/rol antes de leer; no reciben token ni ID legado por el navegador.
- Nueva RPC Auth `aq_venta_puede_modificar_auth_v1`: verifica identidad, rol/propiedad y que no existan incentivos liquidados. **Es una consulta, no autoriza UPDATE directo ni cancela una venta.**
- Nueva RPC Auth `aq_estado_incentivos_auth_v1`: solo jefe, lectura de equipos e incentivos. No cambia estado de incentivos.
- `index.html` experimental actualizado para usar las RPC anteriores, no las variantes con `aqb_token`.
- `saveEditVenta` y `delVenta` de la rama experimental ahora bloquean cualquier modificación o cancelación: las mutaciones antiguas no son atómicas y deben reemplazarse con RPC nuevas que concilien inventario, caja, crédito e incentivos. **La producción no ha cambiado.**
- Administración y mutación de incentivos legada bloqueada en la rama experimental, mientras se migran las funciones que escriben datos. Se mantiene lectura de configuración por el jefe.

## Pruebas de autorización SQL con ROLLBACK
- Jefe: resumen de lotes permitido; consulta de posibilidad de modificar venta de QA devolvió `true`.
- Vendedor: resumen de lotes denegado; reporte sin permiso denegado; modificación de venta ajena devolvió `false`.
- Vendedor: lectura de administración de incentivos denegada; jefe permitido.
- No se alteraron filas. Staging sigue con 6 ventas, 11 movimientos de caja, stock ficticio 51; producción con 5,203 ventas, 3 empleados y 26 tablas sin RLS.

## Pendientes y riesgos
- Las RPC nuevas `SECURITY DEFINER` incrementan la advertencia del linter de 20 a **27 funciones** ejecutables por `authenticated`; es esperable para wrappers privilegiados, pero requieren auditoría individual completa.
- Staging tiene 55 tablas con RLS y sin políticas: revisión y pruebas de cada módulo aún pendiente.
- Las funciones de escritura de incentivos, equipos, atribución de clientes y administración de ventas deben migrarse de tokens legados con sus permisos y reglas contables.
- El archivo principal experimental todavía está configurado con **URL de Supabase producción**. No desplegarlo ni probar escrituras desde un navegador hasta generar versión aislada staging y validar todas las consultas y permisos.
- El formulario de login dual todavía necesita prueba en navegador con cuentas de test de staging; el `qa-auth-staging.html` es un diagnóstico de lectura, no certifica flujo completo.
- Se necesita respaldo validado y despliegue coordinado frontend+RLS para producción.

**NO FUSIONAR la PR #17 ni aplicar SQL en producción.**
