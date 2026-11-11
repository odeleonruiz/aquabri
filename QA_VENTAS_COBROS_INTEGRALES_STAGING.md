# AQUABRI — Pruebas transaccionales de extremo a extremo en Supabase staging

Fecha de ejecución: 2026-11-10 (fecha UTC de base de datos puede ser 2026-11-11).
Proyecto de staging: `xzbawbkstaqvkwtqlqai`.
Rama GitHub: `prueba-supabase-auth-20261110`.

**No publicar, no fusionar este PR.** Pruebas realizadas ejecutando funciones SQL como roles simulados, no desde una sesión real del navegador.

## Cambios entregados en esta etapa
1. La interfaz experimental ahora llama a `aq_pagar_proveedor_auth_v1` al pagar proveedores, eliminando los parámetros `p_token` y `p_uid` enviados por cliente.
2. Archivo `qa-auth-staging.html`: diagnóstico de acceso usuario/celular y lectura RLS. Apunta **solo al proyecto staging** y no contiene operaciones de escritura ni persiste la sesión; actualmente es código de una rama sin despliegue público.
3. Se inventariaron las RPC que siguen utilizando identificadores legados. Requieren migración específica antes de cualquier publicación.

## Pruebas SQL reales, todas dentro de transacciones ROLLBACK
- **Venta integral como vendedor**: `aq_vender_auth_v2` devolvió éxito, ID ficticio, subtotal Q10, registró movimiento de caja y bajó temporalmente stock de 51 a 50.
- **Cobro de crédito ajeno como vendedor**: `aq_cobrar_auth_v2` permitió un abono ficticio Q2 a un crédito de cliente no asignado. En la transacción pasó de saldo 7 a 5, y registró caja. Se deshizo todo por ROLLBACK.
- **Idempotencia de venta**: mismo nonce y mismo payload ejecutados dos veces; primera respuesta `repetida=false`, segunda `repetida=true`. Exactamente **1** venta, **1** movimiento de caja, **1** descuento de stock dentro de la transacción.
- En comprobaciones previas vendedor no puede abrir/cerrar caja global ni registrar compras sin permiso; usuario Auth inexistente no puede efectuar operaciones.

## Integridad verificada después del ROLLBACK
- **Staging**: 6 ventas, 11 movimientos de caja, 1 crédito, stock de producto QA 51.
- **Producción**: 5,203 ventas, 3 empleados, 26 tablas públicas sin RLS. Ningún SQL de modificación aplicado en producción.

## Pendientes antes de integrar
- Aún hay llamadas legadas `aqb_token` a reportes FIFO, incentivos, gestión de equipos, responsabilidad de clientes, consulta de facturas, modificación/cancelación de ventas y otros módulos.
- Las operaciones de edición/cancelación requieren autorización de venta en servidor, validación de incentivos liquidados y mutación vía RPC transaccional. Evitar habilitar UPDATE directo en ventas.
- Realizar pruebas browser con credenciales ficticias de staging para login, lectura RLS, venta, cobro, caja y todas las rutas.
- Staging conserva políticas `deny by default` en tablas no migradas, y advertencias SECURITY DEFINER aún sujetas a revisión.
- Hacer respaldo verificable y plan de reversión antes de una migración coordinada a producción.

Importante: no confundir pruebas SQL transaccionales con pruebas de interfaz desplegada y usuarios reales.
