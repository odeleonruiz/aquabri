# AQUABRI — Control de cambios no destructivos antes del corte (12/11/2026)

## Acciones efectuadas
1. **Endurecimiento de privilegios por defecto** en ambos proyectos Supabase. Se aplicaron únicamente cuatro instrucciones `ALTER DEFAULT PRIVILEGES FOR ROLE postgres`; se retiraron asignaciones automáticas a `anon`, `authenticated` y `service_role` en objetos públicos nuevos, y el privilegio global implícito `PUBLIC EXECUTE` para funciones futuras. No se modificaron tablas ni permisos de objetos existentes.
2. **Comprobación staging de objeto futuro**: en una transacción revertida, crear tabla, secuencia y función nuevas; `anon` no puede leer tabla ni usar secuencia ni ejecutar función; `authenticated` tampoco puede insertar ni ejecutar función. `ROLLBACK`, por lo que los tres objetos QA no persisten.
3. **Preservación de la corrección de comprobante WhatsApp**: la rama `feature/traslado-auth-seguro-20261112` y `index.staging.auth.html` ya usan el PNG fiel al ticket, sin respaldo distinto de texto; se mantienen los flujos de Supabase Auth de esa rama y el banner inequívoco de pruebas. Comprobación sintáctica: 14 scripts embebidos válidos en `index.html` y 15 en preview; 0 errores.
4. **Prueba de aislamiento RLS staging** usando `SET LOCAL ROLE authenticated` y `request.jwt.claim.sub` de los dos perfiles *sin exponer sus UUID*: jefe ve 6 ventas/11 caja/2 clientes/1 crédito/2 perfiles; vendedor ve 0 ventas/0 caja/1 cliente/0 créditos/1 perfil. Se usó `BEGIN READ ONLY` / `ROLLBACK`, sin alterar registros.
5. Auditoría de producción anterior: no se consultaron contraseñas o tokens; permisos viejos **siguen expuestos**, por lo cual no se puede declarar el sistema seguro.

## Integridad del sistema principal verificada después del cambio
| Entidad | Registros |
|---|---:|
| Ventas | 5,239 |
| Detalle de ventas | 6,431 |
| Caja | 4,871 |
| Clientes | 213 |
| Créditos | 760 |
| Usuarios | 2 |
| Empleados | 3 |

Estos conteos son una instantánea: pueden aumentar con el uso del sistema. Ninguna acción ejecutada alteró, borró, truncó ni reemplazó esos registros.

## Referencias y rollback
- SQL aplicado: `sql/aq_default_acl_no_exponer_nuevos_objetos_20261112.sql`
- Rollback explícito de **default grants** (solo si es necesario): `sql/rollback/aq_default_acl_no_exponer_nuevos_objetos_rollback.sql`.
- Auditoría que bloquea el corte: `AUDITORIA_SEGURIDAD_PRECORTE_20261112.md`.
- PR #24 **permanece en borrador, sin fusionar a main**.
- Correcciones de comprobante ya publicadas en main por PR #26, sincronizadas con rama migratoria.

## Bloqueos pendientes para producción
- **24 tablas principales siguen sin RLS**, y muchas políticas existentes son permisivas. Es crucial cerrar accesos, pero *no de golpe*.
- **Inicio de sesión principal antiguo** descarga las credenciales y valida contraseña en el cliente; nunca cortar `usuarios` o `sesiones` hasta reemplazarlo completamente.
- **No existe un respaldo integral de datos de producción con restauración ensayada** dentro de las herramientas disponibles. El único snapshot interno anterior recopila configuración RLS.
- Revisar y cerrar RPC de sesión heredada en staging una vez concluya el cambio a Auth. Actualmente `aq_login_usuario_seguro_v1` sigue ejecutable por `anon` y contiene compatibilidad con contraseñas legacy; se necesita retirarla antes de afirmar que el entorno es Auth-only.
- Terminar adaptación de módulos de RRHH, rutas, pedidos programados, comisiones, administración y pruebas completas por dispositivo.
- Cotejar integridad, conteos y respaldo restaurable en una ventana de corte coordinada. Sin esos requisitos no fusionar PR ni cambiar RLS en producción.

## Regla permanente
**Nunca utilizar el comando de migración para reemplazar una tabla principal con datos de pruebas. No ejecutar DROP, TRUNCATE, DELETE ni restauraciones de datos sobre producción en un corte incremental.** Las migraciones deben ser de esquema y permisos, revisadas y probadas por etapas.
