# AQUABRI · Resultado de pruebas reversibles de seguridad (12 de noviembre de 2026)

**Entorno:** Supabase de pruebas, no AQUABRI oficial.

## Resultados verificados dentro de transacciones con ROLLBACK
| Caso | Resultado |
| --- | --- |
| Jefe crea y modifica cliente | PASA |
| Vendedor intenta editar cliente ajeno | BLOQUEADO correctamente |
| Anónimo intenta ejecutar venta | BLOQUEADO correctamente |
| Vendedor intenta abrir caja general | BLOQUEADO correctamente |
| Vendedor intenta cambiar permisos del personal | BLOQUEADO correctamente |
| Vendedor intenta pagar proveedor | BLOQUEADO correctamente |
| Venta contado: inventario -1, caja +1 | PASA |
| Reintento misma venta con mismo nonce | No duplicó venta ni caja |
| Vendedor: venta a crédito, cobro, caja +1 | PASA |
| Compra a crédito: inventario +1, deuda +1, caja sin cambio | PASA |
| Reintento misma compra | No duplicó stock ni factura |
| Jefe: apertura Q100, cierre Q100, reintento | PASA |
| Venta + préstamo de envase: cliente +1, bodega -1, movimiento +1 | PASA, con existencias temporales reversibles |

## Correcciones implementadas
- El payload de ventas ahora incluye medio de pago y condición de crédito requeridos por el servidor.
- La rama Auth ya no vuelve a escribir inventario, caja, créditos o puntos después de una venta integral que los guardó atómicamente. Esto era un riesgo grave de doble registro.
- Alta, edición y GPS de clientes por RPC autorizada; incentivos automáticos de alta de cliente eliminados de este flujo.
- Gestión de permisos del personal usa RPC auditadas.
- Alta/edición/eliminación de usuarios con contraseña heredada se deshabilitó en QA: falta implementar administración segura con Supabase Auth.
- Pedidos programados se detienen expresamente en QA hasta disponer de RPC protegida.
- Vista de prueba `/qa-seguridad/` apunta exclusivamente al Supabase de pruebas y ya no desregistra service workers de producción.
- Se creó fila inicial de bodega de envases de **0** existencias en staging; no se asignó inventario inventado.

## Control posterior
- Conteos en staging tras las pruebas: clientes 2, ventas 6, caja 11, créditos 1, stock producto de prueba 51, bodega de envases 0.
- Funciones públicas `aq_*` ejecutables por rol anónimo: 0.
- RLS habilitada en 75 de 75 tablas públicas de staging, pero hay advertencias de funciones SECURITY DEFINER que requieren auditoría.
- Archivo `index.html` de la aplicación oficial **sin cambios**; todos los cambios del POS están en la rama `feature/traslado-auth-seguro-20261112`, no fusionada.

## BLOQUEOS — no listo para producción
- Numerosas escrituras directas de módulos secundarios continúan sin RPC de autorización, entre ellas rutas, pedidos programados, comisiones antiguas, recursos humanos, usuarios y movimientos auxiliares.
- No hay prueba end-to-end con navegador móvil y credenciales reales para toda la interfaz; los ensayos aquí son pruebas SQL de backend.
- No se ha auditado exhaustivamente cada función SECURITY DEFINER, ni se han habilitado medidas opcionales como detección de contraseñas filtradas.
- Falta backup integral verificado y ensayo de restauración y reversión de producción; el respaldo de políticas no cubre datos.
- No promover ni fusionar a `main` ni aplicar RLS de staging directamente al proyecto oficial hasta cerrar bloqueos.

**Las transacciones de venta/compra/cobro/préstamo de estas pruebas se revirtieron con ROLLBACK, no quedaron registradas permanentemente.**
