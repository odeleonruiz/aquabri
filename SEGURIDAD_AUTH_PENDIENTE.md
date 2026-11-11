# AQUABRI — Migración de autenticación, revisión de seguridad (10-11-2026)

## Estado de la propuesta
**NO FUSIONAR A MAIN NI ACTIVAR RLS EN PRODUCCIÓN TODAVÍA.**
La rama contiene una integración de interfaz de inicio de sesión con dos identificadores y una prueba aislada. No está probada con credenciales reales ni con la matriz completa de permisos. Los datos productivos no han sido modificados.

## Ingreso propuesto
- Usuario + contraseña de Supabase Auth: Edge Function existente `aq-auth-usuario-v2`, devuelve tokens Auth sin revelar el número de teléfono.
- Celular + la misma contraseña de Supabase Auth: `signInWithPassword({ phone, password })`.
- Resolver cada identidad a `public.usuarios.auth_uid` para conservar `usuarios.id`, nombre, rol y vínculo de empleado.
- El antiguo `usuarios.pass` **no** debe validar sesiones. No es equivalente a la contraseña de Auth.
- La restauración del navegador debe validar `auth.getUser()` antes de cargar datos.

## Hallazgos en principal
- 5,203 ventas y 3 empleados (lectura, sin mutaciones).
- 2 usuarios originales y 2 cuentas en auth.users, vinculadas por auth_uid.
- **26 tablas public sin RLS:** cargas_vehiculos, ruta_clientes, ubicaciones, clientes, envases, activos_prestamos, creditos, deudas_proveedores, ruta_paradas, puntos_clientes, puntos_historial, caja, liquidaciones, liquidacion_items, notificaciones, puntos_productos, visitas, puntos_canjes_qr, clientes_eliminados, rutas_personalizadas, mantenimientos, activos_items, precio_historial, pagos_comisiones, ausencias, grupos_ruta.
- Otras tablas tienen políticas `acceso_total_*` que autorizan `anon,authenticated` con `USING(true)`. **Activar RLS con esas políticas NO protege datos**.
- Las políticas `acceso_total_usuarios` y `acceso_total_sesiones` permiten a anon leer/escribir filas. `usuarios.pass` almacena credenciales legadas en una columna accesible por la API actual.
- El sitio de producción actualmente hace `loadAll()` antes de autenticar. No restringir estas tablas hasta publicar el cliente que valida Auth previamente.
- El código de gestión de usuarios todavía escribe la columna `pass`: migrar a un flujo administrativo de restablecimiento de contraseña de Auth, sin guardar contraseñas legadas.

## Secuencia segura antes de desplegar
1. Tomar respaldo verificable y registrar conteos y pruebas de lectura/escritura de ventas, créditos, caja, inventario, envases, empleados y comisiones.
2. Inventariar todas las tablas y RPC invocadas desde el cliente, sus permisos de operación y su modelo de pertenencia a empresa, sucursal, usuario y rol.
3. Definir RLS **por tabla y acción**. `anon` no debe consultar datos personales ni tablas operativas. `authenticated` no debe conceder acceso total: debe comprobar `auth.uid()` con usuario activo y permisos asignados en servidor.
4. Para `usuarios`, evitar exponer `pass`. Usar una vista o RPC de perfiles que solo devuelva campos públicos y un RPC privilegiado **limitado** para la administración de personal; no exponer RPC SECURITY DEFINER sin controles.
5. Para `sesiones`, retirar el mecanismo anterior y sus políticas permisivas solo cuando el cliente no dependa de él.
6. Crear migración transaccional con políticas, GRANT/REVOKE y funciones de autorización revisadas. Aplicar primero a staging; probar APIs como anon, jefe y vendedor en cada módulo. Verificar que vendedor no pueda modificar funciones exclusivas del jefe ni operar como otro usuario.
7. Probar ambos accesos para jefe (ID 1) y Melgar (ID 9), cierre de sesión, restauración de sesión, bloqueo por intentos y errores de red.
8. Publicar nueva aplicación junto con la política probada dentro de una ventana controlada, con plan de reversión. No eliminar ventas, empleados ni comisiones.
9. Ejecutar Supabase security advisors, conservar evidencia de pruebas y conteos antes/después.

## Nota técnica
La rama es un cambio de integración propuesto. **No es aún una migración de seguridad completa** y no debe considerarse lista para uso operativo hasta superar las pruebas anteriores.

Referencia: https://supabase.com/docs/guides/database/postgres/row-level-security
