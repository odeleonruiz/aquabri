# AQUABRI — Pruebas de autorización de operaciones críticas (staging)

Fecha: 2026-11-10; proyecto de pruebas `xzbawbkstaqvkwtqlqai`.
**Este documento no autoriza el despliegue en producción.**

## Cambios aplicados
- `aq_abrir_caja_auth_v2` y `aq_cerrar_caja_auth_v2`: además de verificar el permiso específico, exigen `ctx.rol_usuario = 'jefe'`. Evita que la delegación accidental de permisos abra caja global a vendedores.
- Código SQL versionado: `sql/aq_caja_global_jefe_auth_v2_guard_staging.sql`.
- Las operaciones `aq_vender_auth_v2`, `aq_cobrar_auth_v2`, `aq_comprar_auth_v2` se analizaron y probaron sin alterar sus definiciones.

## Pruebas ejecutadas
Transacciones `BEGIN ... ROLLBACK`, `SET LOCAL ROLE authenticated` y UID de prueba vía `request.jwt.claim.sub`. No son sesiones reales de navegador ni pruebas finales end-to-end.

| Caso | Resultado |
| --- | --- |
| Jefe: vender con datos inválidos | Validación de datos de venta (pasó autorización) |
| Jefe: cobrar con cliente inválido | Validación de cliente de cobro (pasó autorización) |
| Jefe: comprar con datos inválidos | Validación de datos de compra (pasó autorización) |
| Jefe: abrir/cerrar caja con datos inválidos | Validación de datos de caja (pasó autorización) |
| Vendedor: vender con datos inválidos | Validación de datos de venta (pasó autorización) |
| Vendedor: cobrar con cliente inválido | Validación de cliente de cobro (pasó autorización) |
| Vendedor: comprar | Denegado por falta de permiso `compras.registrar` |
| Vendedor: abrir/cerrar caja global | Denegado por rol, incluso con posible delegación de permisos |
| UUID inexistente: vender/cobrar/abrir caja | Denegado: identidad no encontrada en Supabase Auth |
| RPC anon | Los RPC revisados no tienen EXECUTE para anon |
| Credenciales antiguas `usuarios.pass` | No hay SELECT autorizado para authenticated en staging |
| Lectura de perfiles | Jefe: ambos; vendedor: su propio perfil |

## Integridad
- Staging: 6 ventas, 11 entradas en `caja`, 0 tablas public sin RLS después de pruebas.
- Producción: 5,203 ventas, 3 empleados, 2 usuarios, **26 tablas public sin RLS**. No se escribió SQL en producción.

## Pendientes críticos
1. Validar ventas, cobros, compras, conciliaciones de caja y su reversión end-to-end desde la UI de staging, con credenciales Auth y datos ficticios.
2. Revisar **20 funciones SECURITY DEFINER ejecutables por authenticated**; mantener únicamente las RPC justificadas y asegurar validación de identidad y permiso en cada una. No hacer revocaciones masivas sin dependencias.
3. Staging tiene 60 tablas con RLS y ninguna política (denegadas por defecto). Completar permisos de lectura y RPC por módulo.
4. El `index.html` experimental aún contiene llamadas históricas a tablas y RPC; adaptar el conjunto antes de publicarlo.
5. Probar seguridad de roles, errores de conexión, idempotencia, límites de caja, ventas canceladas, créditos ajenos y precio manual sin pérdida de integridad.
6. Revisar flujo de alta/cambio de usuarios con Supabase Auth; actualmente deshabilitado en la rama experimental.
7. Revalidar en ambiente seguro y preparar despliegue coordinado de nuevas políticas y frontend.

Hallazgos de Supabase:
- [RLS enabled no policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
- [Authenticated security definer executable](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
