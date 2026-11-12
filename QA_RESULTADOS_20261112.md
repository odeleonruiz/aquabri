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
| Jefe autoriza permiso de clientes y vendedor captura cliente propio | PASA; permiso y cliente revertidos |
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


## Ampliación de QA — rutas, visitas, envases y vista aislada
- En `aquabri-staging` instaladas las migraciones `aq_staging_rutas_visitas_auth_v1`, `aq_staging_rutas_crud_auth_v1` y `aq_staging_envases_auth_eliminacion_y_cierre_legacy`.
- `rutas` y `ruta_paradas`: lectura RLS del jefe o empleado asignado; los RPC para visitas, paradas, creación atómica de rutas, reordenación, cambios de estado, reutilización y eliminación validan contexto Auth y rol.
- `aq_eliminar_movimiento_envase_auth_v1`: nuevo envoltorio para el jefe; las funciones heredadas `aq_eliminar_movimiento_envase`, `aq_cancelar_venta_segura` y `aq_registrar_envases_venta` ya no tienen `EXECUTE` directo para `authenticated`.
- Pruebas transaccionales reversibles: registro de visita como jefe `ok=true`; creación/inicio de ruta como jefe `ok=true`; creación de ruta por vendedor rechazada (`42501`).
- Al finalizar, `rutas=0`, `ruta_paradas=0`, `visitas=0` en staging, sin registros de las pruebas. Las 75 tablas públicas conservan RLS.
- Interfaz: las rutas/visitas y eliminación de movimiento de envases usan nuevas RPC; 14 de 14 scripts inline compilan sintácticamente.
- La copia `/qa-seguridad/` de GitHub Pages usa solo URL/clave publicable de staging; no llama al proyecto oficial ni desregistra service workers; la publicación de GitHub Pages fue exitosa. La raíz `/aquabri/` no fue modificada.
- Código de la rama sincronizado con los últimos cambios de `main` manteniendo `main` sin el nuevo código del POS.
- Existe respaldo de código en `backup/antes-sync-main-staging-rutas-20261112` (NO es respaldo de base de datos).

### Pendientes que impiden activar RLS/Auth en producción
- Adaptar y ensayar las restantes escrituras directas de clientes (incluidas bajas), pedidos programados, RRHH, comisiones antiguas, inventario auxiliar y administración segura de usuarios. No asumir que una respuesta de `update/insert` fallida equivale a operación guardada.
- El vendedor de pruebas no tiene `empleado_id` vinculado: falta prueba de una ruta realmente asignada a empleado, además de la prueba desde navegador móvil.
- No se completó auditoría de todas las funciones `SECURITY DEFINER`, aun cuando `anon` no tiene acceso a ellas; evitar conceder permisos sin revisar validaciones internas.
- **Respaldo integral de datos de producción y ensayo de restauración NO realizados**. Los conectores disponibles no exponen un procedimiento para obtener y verificar la copia física diaria. Confirmarla en Supabase Dashboard > Database > Backups, descargar/exportar copia lógica si corresponde y ensayar en un proyecto aislado antes de cualquier publicación.
- No se verificó inicio de sesión con las contraseñas reales desde iPhone/Android; no interpretar las pruebas SQL como prueba de navegador.
