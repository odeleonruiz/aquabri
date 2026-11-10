# AQUABRI — inicio de sesión seguro por usuario (SOLO STAGING)

## Estado aplicado
- Supabase staging: `xzbawbkstaqvkwtqlqai`
- Edge Function activa `aq-auth-usuario-v2` — `verify_jwt=false` porque es el endpoint público de **inicio** de sesión; la contraseña es verificada por Supabase Auth.
- El servicio resuelve internamente el email de Auth a partir del nombre de usuario y `auth_uid`, sin exponer el correo ni la clave administrativa al navegador.
- La petición de inicio admite solo el origen `https://odeleonruiz.github.io`.
- Se instaló el limitador de intentos `aq_auth_login_admitir_intento` con tope de 10 intentos cada 15 minutos por nombre de usuario. Solo `service_role` puede ejecutar la función y la tabla de conteos no es accesible por `anon`.
- Pantalla separada de prueba: `/aquabri/staging/PROBAR_LOGIN_SEGURO_USUARIO.html`. **No forma parte del sistema principal**.
- No se han creado cuentas ni cambiaron credenciales del proyecto de producción.

## Verificación observada
- Función desplegada en staging: ACTIVE (versión 1).
- Permisos SQL verificados: `anon` no puede consultar contador ni ejecutar RPC de limitación; `service_role` sí.
- La base de staging conserva dos identidades QA previamente vinculadas a usuarios ficticios.
- No fue posible completar una petición HTTP de inicio de sesión desde el entorno de herramientas por bloqueo de red; **no debe afirmarse que el login end-to-end está aprobado**.

## Pasos para pasar a producción (solo después de cuentas reales verificadas)
1. Identificar correo REAL de recuperación del jefe y otro distinto para el vendedor. No inventar correos ni reutilizar la contraseña existente en claro.
2. Crear/invitar identidades a Supabase Auth. Cada persona confirma su correo y define una clave nueva; no pedir ni compartir contraseñas en ChatGPT.
3. Vincular cada identidad autenticada a **su usuario existente** en `public.usuarios.auth_uid`. El jefe conserva ID 1, el vendedor ID 9. No crear nuevas filas de empleados/usuarios.
4. Probar `aq_mi_perfil_seguro()` con sesión Auth real, comprobando el ID y rol; comprobar los permisos de negocio de ambos.
5. Portar los accesos, RPC y RLS del frontend anterior a Auth en una versión coordinada. La UI sigue pidiendo usuario y contraseña.
6. Pasar auditorías de RLS; no utilizar nunca permisos universales `USING(true)` en tablas sensibles.
7. Solo después de confirmar la entrada con ambas cuentas y recuperación, desactivar políticas antiguas, borrar claves legadas **mediante un proceso transaccional y auditado**, y retirar sesiones antiguas.

## Respaldos en producción
- Datos previos a la preparación: esquema privado `aquabri_backup_auth_20261109` (67 tablas/18,219 registros) y estructura metadata.
- Copia de código `backup/antes-auth-v2-20261109`.
- La copia interna NO es un dump independiente; verificar backup diario de Supabase Pro y objetos Storage por separado.

Este módulo no debe usarse en producción hasta superar una prueba positiva de sesión real y autorización.
