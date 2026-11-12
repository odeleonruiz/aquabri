# AQUABRI: publicación de la autenticación y RLS (NO ejecutar todavía)
Fecha: 12 de noviembre de 2026.

## Estado comprobado
- Base oficial: 24 tablas `public` todavía sin RLS; 5,236 ventas, 6,428 líneas de venta, 212 clientes, 760 créditos y 4,866 movimientos de caja.
- Otras tablas (p. ej. `usuarios`, `sesiones`, `ventas`, `venta_items`) tienen RLS, pero políticas antiguas `USING (true)` con permisos anónimos; eso tampoco constituye autorización segura.
- Las ocho funciones nuevas se instalaron en la base oficial con `EXECUTE` revocado a `PUBLIC`, `anon` y `authenticated`; la aplicación oficial no las usa.
- En laboratorio: inicio servidor, lectura de clientes/créditos con token válido, no lectura sin token y funciones de administración fueron probadas con transacciones reversibles.
- La rama `security/auth-server-bridge-20261112` usa RPC para inicio, perfil y administración, sin leer `usuarios.pass` ni crear sesiones directas.
- GitHub Actions valida la sintaxis del JavaScript y verifica CORS del encabezado de sesión en Staging. Esto NO prueba ventas end-to-end.

## Secuencia necesaria para eliminar las 24 exposiciones, preservando continuidad
1. Confirmar respaldo completo restaurable de PostgreSQL y, de forma separada, objetos de Supabase Storage. Registrar recuentos de todas las tablas financieras y un punto de restauración.
2. Desplegar una vista previa aislada de esta rama que apunte EXCLUSIVAMENTE a Staging; nunca publicar el token `service_role`.
3. En Staging crear políticas RLS de menor privilegio y RPC para escrituras de clientes, ventas, créditos, caja, envases, rutas, activos y RRHH; validar permisos por rol.
4. Ejecutar pruebas reales de inicio de sesión por usuario+contraseña y por teléfono OTP; ventas al contado/crédito, cobros a clientes ajenos, caja por empleado, envases, comisiones, inventario y facturas. Probar también iPhone/Android/PC.
5. Preparar la transición coordinada del frontend y políticas en la base oficial. **La aplicación debe enviar una sesión de servidor válida antes de que las consultas protegidas dependan de RLS.**
6. Cerrar políticas amplias `USING true` no solo de las 24 tablas apagadas, sino también de `usuarios`, `sesiones`, `ventas`, `venta_items` y cualquier otra tabla expuesta. RLS encendido con política `true` NO soluciona el problema.
7. Habilitar los RPC comprobados solo al pasar a la versión nueva; impedir acceso directo al password, emisión de sesiones y operaciones delicadas para el rol anónimo sin sesión válida.
8. Habilitar RLS para las 24 tablas restantes con predicados correctos de propietario/empleado/rol, en lotes verificables, con plan de reversión. Recontar datos de producción y revisar Security Advisors.
9. Cambiar contraseñas antiguas si fueron accesibles; usar el flujo seguro del servidor y almacenar nuevos secretos con hashes. Considerar revocar sesiones antiguas tras un cambio coordinado, evitando bloquear a los empleados inesperadamente.

## Criterios mínimos de aprobación
- Anónimo sin sesión: no puede leer datos personales, créditos, salarios, usuarios, sesiones ni modificar caja/ventas.
- Jefe: acceso completo autorizado y conservado, sin eliminar historial.
- Vendedor: puede registrar ventas y cobros autorizados, incluidos cobros de crédito a otro cliente conforme a reglas del negocio; no puede gestionar permisos ni modificar datos ajenos sin autorización.
- Reintentos con mismo nonce: no duplican ventas, caja o movimientos.
- Reportes y conciliación no arrojan faltantes al comparar con los registros anteriores.
- El flujo de recuperación desde un respaldo se ha probado fuera del proyecto oficial.

**No fusionar el PR ni ejecutar el SQL de corte final sin estas comprobaciones.**
