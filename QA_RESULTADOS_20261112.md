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


## Continuación — clientes, RRHH, comisiones, nómina y pedidos (12 nov. 2026 UTC)
**Únicamente en Supabase staging.** Aplicadas migraciones:
- `aq_staging_clientes_archivo_reversible_sin_borrado_financiero`: columnas de archivado/restauración y RPC `aq_archivar_cliente_auth_v1`, `aq_restaurar_cliente_auth_v1`. No se eliminan ventas, créditos, puntos, envases ni historial. El jefe puede archivar/restaurar, el vendedor no; cliente con crédito pendiente bloqueado. Probado con ROLLBACK.
- `aq_staging_rrhh_config_segura_y_auditoria`: RPC de alta/edición/desactivación de empleados, ausencias, comisiones porcentuales y metas. No se borran pagos ni historial al desactivar un empleado. Jefe autorizado pasó tests reversibles; vendedor fue bloqueado.
- `aq_staging_rrhh_pagos_atomicos_nonce_y_deducciones`, `aq_staging_rrhh_pago_nonce_repetido_corrige_payload`, `aq_staging_rrhh_comision_periodo_regex_corregida`, `aq_staging_rrhh_vales_y_retro_seguro`: nómina + vales + ausencias en una transacción, idempotencia por nonce; pago de comisiones registrado en un solo asiento principal de nómina y un solo detalle de comisión (sin gasto duplicado). Pago de nómina probado con mismo nonce: mismo ID. Comisión probada con 1 pago y 1 registro de comisión. No se insertaron movimientos de caja automáticamente: revisar contabilidad de caja por empleado antes de producción. Eliminación directa de pagos deshabilitada en QA hasta contar con anulación auditable.
- `aq_staging_pedidos_reserva_entrega_atomica_v1`: pedidos programados con creación de cabecera e items en una sola transacción, estados protegidos y entrega que descuenta existencias y registra **caja O crédito**, no ambos. Trigger corregido para NO consumir FIFO ni incentivos en estados Pendiente/Preparando/En Camino; solo al entregar. Test de contado con reintento: stock 51→50, caja 1, crédito 0. Test de crédito: stock 51 al reservar/preparar; stock 50 tras entrega, caja 0, crédito 1. Todos con ROLLBACK.
- Edición de ventas en QA: se permiten notas y entrega por RPC autorizada, pero se impide edición parcial de artículos, montos, créditos o estado por riesgo contable. Historial de clientes archivados se conserva.
- Interfaces de desarrollo y copia aislada `/qa-seguridad/` adaptadas. 14/14 scripts inline con sintaxis válida; copia QA solo referencia a Supabase staging, sin referencia al proyecto oficial, sin desregistro global de service workers.

### Estado posterior a las pruebas
Clientes activos 2, archivados 0, historial de archivos 0, empleados 0, pagos 0, pagos de comisión 0, operaciones RRHH 0, operaciones de pedidos 0, rutas 0, visitas 0. Ninguna tabla pública sin RLS. Todas las altas de prueba se ejecutaron en transacciones con `ROLLBACK`.

### Riesgos restantes **NO RESUELTOS — NO PUBLICAR AUTH/RLS EN PRODUCCIÓN**
- Al menos algunas escrituras directas heredadas permanecen en módulos de envases vendidos fuera del POS, membresías/puntos, liquidación de cargas, inventario auxiliar, configuración, reportes auxiliares y administración de usuarios. Revisar y adaptar cada operación; la versión QA debe rechazar y no mostrar éxito falso cuando no haya RPC.
- El Security Advisor aún informa funciones `SECURITY DEFINER` ejecutables por `authenticated`; muchas son RPC intencionales, pero **falta auditoría de cada función**. Incluye la advertencia de detección de contraseñas filtradas desactivada. Enlace: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- No fue posible probar en iPhone/Android con credenciales reales desde esta herramienta. Las pruebas SQL con contexto JWT simulado no sustituyen pruebas de navegador, sesión revocada y conectividad.
- No existe una copia integral **verificada y restaurada** de producción obtenida en esta sesión: las herramientas conectadas no ofrecen exportación física y restauración probada de la base. Requiere comprobar respaldos de Supabase y restaurar un backup aislado; un backup de políticas o rama GitHub **no** respalda ventas/clientes.
- **No promover a producción, no activar RLS de staging en producción, ni fusionar index de staging a main.**
