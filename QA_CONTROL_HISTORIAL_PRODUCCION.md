# AQUABRI · Control de integridad del historial oficial
**Corte consultado:** 12 de noviembre de 2026 a las 00:05 (Guatemala).
**Origen:** proyecto oficial `aquabri-sistema`, lectura SQL sin modificaciones.
**ATENCIÓN:** esta huella de integridad NO es un backup ni una restauración comprobada.

| Recurso | Filas observadas | ID máximo observado | Huella de IDs |
|---|---:|---:|---|
| Ventas | 5,236 | 5,367 | `90f162b083b7760430e61fa1934c0705` |
| Venta_items (ID y venta_id) | 6,428 | 6,623 | `0af9bb4c10ed054aa03a499c931b48bb` |
| Créditos | 760 | 853 | `c2e995c5a86f5820452cb79878039df8` |
| Caja | 4,866 | 4,914 | `1632cd620a88987c9c59242d13f9d2c7` |

Las facturas anuladas **permanecen** como registros, no deben eliminarse: 90 detectadas en el corte.

### Antes de cualquier migración de seguridad a producción
1. Abrir [Supabase · respaldos del proyecto oficial](https://supabase.com/dashboard/project/odwccqqvxpsggggehjtt/database/backups). Verificar que existe una copia actual, retenida y que la restauración a **un proyecto nuevo y aislado** funciona. Nunca restaurar un backup antiguo encima de la base activa como prueba: borraría el trabajo posterior al respaldo. También respaldar objetos de Storage si los hubiera.
2. Consultar `QA_CONTROL_HISTORIAL_VERIFICAR.sql` en producción antes y después de la ventana de cambio. El SQL es **solo lectura**, comprueba IDs anteriores al corte incluso si hubo nuevas ventas posteriormente.
3. Detener la migración si `ventas_conservadas` o `articulos_conservados` es `false`. Si créditos o caja cambian, investigar cancelaciones y otros movimientos legítimos; no sobrescribir la base.
4. Instalar las protecciones `DELETE`/`TRUNCATE` de ventas/venta_items probadas **en staging** después del backup y validación de compatibilidad; NO se aplicaron en producción.
5. Comprobar autenticación real desde móvil, permisos RLS y todas las RPC en staging. Las funciones de cargas/liquidación inventario aún están en modo bloqueado seguro en QA.
6. Desplegar en ventana controlada y preparar reversión de código/políticas que **no restaure una copia antigua encima de nuevas ventas**.

### Alcance del bloqueo de borrado
En `aquabri-staging` existen triggers `aq_historial_ventas_no_delete`,
`aq_historial_ventas_no_truncate`, `aq_historial_venta_items_no_delete`,
`aq_historial_venta_items_no_truncate`. Los bloqueos `DELETE` de ventas e ítems
se probaron y fueron rechazados. La comprobación `TRUNCATE ventas` sin CASCADE
también quedó impedida por llaves foráneas; los triggers de TRUNCATE están instalados.
No se ejecutó TRUNCATE CASCADE por ser destructivo.

**No hay autorización para borrar todo el historial de ventas, reiniciar IDs, truncar tablas ni limpiar ventas antiguas.**
