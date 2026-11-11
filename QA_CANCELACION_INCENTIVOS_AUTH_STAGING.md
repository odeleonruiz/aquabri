# AQUABRI — Etapa de edición/cancelación e incentivos sobre Supabase Auth (STAGING)

Fecha 2026-11-10/11. Branch `prueba-supabase-auth-20261110`, PR #17.
**Ningún cambio aplicado a Supabase principal. NO FUSIONAR ESTA PR.**

## Edición de ventas
SQL `sql/aq_edicion_cancelacion_contado_auth_staging.sql`:
- `aq_editar_venta_datos_auth_v1(venta,entrega,notas)` permite editar SOLO entrega y notas.
- Confirma identidad Auth, rol/permiso real y propiedad/fecha para vendedores; rechaza venta anulada y venta con incentivo pagado.
- El frontend comprueba cambios financieros, estado, fecha, cliente, total, pagado e ítems y rechaza la operación si se intentan modificar. El servidor nunca acepta esos campos como parámetros de edición.

## Cancelación de ventas
- `aq_cancelar_venta_contado_auth_v1(venta)` exige identidad Auth, permiso ventas y, para vendedor, venta propia del día.
- Solo permite contado entregado, íntegramente pagado, un único movimiento `caja` coherente con nonce integral V2, caja no cerrada, sin créditos, sin puntos contabilizados ni incentivos pagados.
- Bloquea y valida registros con `FOR UPDATE`; repone stock de productos e insumos (y bonificaciones), marca la venta como cancelada, dispara reversión FIFO e incentivos devengados desde triggers existentes y elimina solo el movimiento de caja de esa venta. Si cualquier paso falla, toda la operación se revierte atómicamente.
- Ventas con cobros posteriores, crédito, caja cerrada, puntos o incentivos ya pagados continúan bloqueadas: requieren ajuste contable supervisado, no una eliminación simple.

## Pruebas transaccionales reales en staging
- Venta ficticia Q10 seguida de cancelación: estado `Cancelada`, movimiento de caja revertido, stock antes/después 51, sin descuadre.
- Venta ficticia con bonificación del mismo producto: stock final 51, revertido correctamente.
- Vendedor: rechazado al cancelar y editar venta ajena.
- Jefe: edición de entrega/notas aceptada; cancelación de crédito rechazó por pago no conciliado.
- Cada prueba se ejecutó dentro de `BEGIN ... ROLLBACK`, no dejó registros persistentes.

## Incentivos y asignaciones de clientes
SQL `sql/aq_incentivos_atribucion_auth_staging.sql`:
- `aq_guardar_equipo_auth_v1`, `aq_guardar_incentivo_auth_v1`, `aq_finalizar_incentivo_auth_v1`: solo jefe, con contexto Auth dentro del servidor y reglas del motor existente.
- `aq_clientes_atribucion_listar_auth_v1`, `aq_cliente_asignar_responsable_auth_v1`: solo jefe, con permisos de asignación en servidor.
- `aq_movimientos_incentivos_auth_v1`: jefe ve todos; otros usuarios con permiso `comisiones`, `reportes` o `rrhh` solo ven movimientos de su empleado vinculado.
- Simulaciones: vendedor rechazado al crear equipo, finalizar incentivo y asignar cliente. Jefe llegó a validaciones de negocio.
- La liquidación de incentivos queda bloqueada en la rama de pruebas: el motor actual intenta insertar `gastos.usuario_id`, columna inexistente en staging, y exige reconciliación de gastos, caja y planilla para habilitarse con seguridad.

## Aislamiento del frontend de pruebas
- `index.staging.html` es copia en GitHub de la rama, dirigida SOLAMENTE a `https://xzbawbkstaqvkwtqlqai.supabase.co` con la clave publishable de staging. No apunta al proyecto principal.
- `index.html` de la rama aún apunta a producción y no debe desplegarse; la versión aislada es `index.staging.html`.
- Se eliminaron funciones del navegador para crear sesiones legadas y llamadas legadas del flujo de incentivos.
- Subida de fotos no migrada queda bloqueada para evitar enviar token/anon-key como credenciales del cliente.
- Captación automática de cliente no migrada queda bloqueada. El proyecto staging no tiene la RPC legacy requerida y no se permite un INSERT directo alternativo.
- Administración de usuarios, documentos sin artículos, liquidación de incentivos y otros módulos de escritura no migrados siguen protegidos/bloqueados en rama experimental.

## Integridad y auditoría
- Staging: **6 ventas, 11 caja, 1 crédito, stock QA 51, 0 tablas sin RLS**.
- Producción: **5,203 ventas, 3 empleados, 26 tablas sin RLS**. No se han modificado.
- Advisors staging: 55 tablas con RLS sin políticas (denegadas por defecto), 35 funciones SECURITY DEFINER ejecutables por authenticated; esas funciones requieren auditoría individual antes de producción. El número sube al crear wrappers Auth legítimos, no significa 35 vulnerabilidades confirmadas.

## Pendientes antes de publicación
1. Revisar funciones SECURITY DEFINER una por una y funciones legacy con posible exposición.
2. Migrar liquidaciones y las variantes de edición/cancelación con movimientos financieros mediante operaciones auditadas y reversibles.
3. Resolver alta/captación de clientes y carga de imágenes en Storage mediante Supabase Auth.
4. Completar RLS de las 55 tablas sin políticas según módulo, con tests de cada rol.
5. Probar `index.staging.html` en navegador real usando cuentas de test; aún NO se ha probado su experiencia end-to-end en UI.
6. Preparar backup verificable, ventana de mantenimiento y rollback antes de cualquier cambio coordinado a producción.

**Estado de versión: BORRADOR no publicable.**
