# AQUABRI Auth v2 — correcciones de llamadas del frontend y gastos (staging)

Fecha: 2026-11-10. Rama: `prueba-supabase-auth-20261110`. **No fusionar a main**.

## Modificaciones del frontend experimental
- Registro de ventas: `aq_registrar_venta_completa` → `aq_vender_auth_v2`. Conserva nonce, payload de venta e ítems. El servidor fija `usuario_id` desde Auth.
- Cobro de créditos: `aq_cobrar_credito_seguro` → `aq_cobrar_auth_v2`; mantiene nonce, cliente, crédito, medio e importe. Cobros de créditos ajenos continúan permitidos si el usuario tiene `creditos.cobrar`, según la RPC.
- Facturas de inventario: `aq_registrar_compra_segura` → `aq_comprar_auth_v2`.
- Documentos sin inventario: se bloquean explícitamente en esta rama hasta implementar su RPC Auth; no recurren a sesiones antiguas.
- Gastos: `aq_registrar_gasto_seguro` → `aq_registrar_gasto_auth_v2`; `aq_eliminar_gasto_seguro` → `aq_eliminar_gasto_auth_v2`.
- Estas modificaciones **no equivalen** a una integración funcional completa; los otros módulos todavía hacen llamadas con sesiones legadas.

## SQL nuevo aplicado SOLO a Supabase staging
`sql/aq_gastos_auth_v2_secure_bridge_staging.sql`:
- Crea dos wrappers con validación de identidad Auth en servidor, permiso `gastos`, nonce y motor de gastos existente.
- Revoca el acceso RPC directo de `authenticated` a las funciones legadas de registro/eliminación de gastos.
- La función legada sigue existiendo internamente para no cambiar su lógica contable.
- Las funciones nuevas no aceptan identidad ni token legados del navegador.

## Pruebas SQL realizadas (transacciones revertidas)
- UUID inexistente -> rechazo Auth.
- Jefe con gasto inválido -> llegó a validación de importe y fecha.
- Vendedor sin autorización para gastos -> rechazado.
- `anon` no puede ejecutar nuevas ni viejas RPC de gastos.
- `authenticated` puede ejecutar wrappers nuevos, no RPC legadas de gastos.
- Recuento: staging 6 ventas, 11 registros de caja; producción 5,203 ventas, 3 empleados.
- Producción no modificada: 26 tablas sin RLS.

## Bloqueos de salida a producción
- 60 tablas de staging con RLS activado pero sin políticas (deny by default): revisar módulo por módulo.
- 20 RPC `SECURITY DEFINER` siguen ejecutables por authenticated, requieren autorización revisada y pruebas por rol; no se deben revocar todas indiscriminadamente.
- Probar de extremo a extremo ventas, créditos, caja, gastos, documentos y reversión desde una compilación conectada realmente a staging, con credenciales de test.
- Exigir permisos de las RPC y no exponer columnas `usuarios.pass`.
- Migrar y auditar las demás funciones que aún usan `aqb_token` antes de quitar las sesiones legadas.
- Ejecutar plan de despliegue coordinado y backup verificable previo.

Documentación: https://supabase.com/docs/guides/database/postgres/row-level-security
