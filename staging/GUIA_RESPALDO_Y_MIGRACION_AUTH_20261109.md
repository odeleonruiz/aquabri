# AQUABRI — preparación de autenticación y recuperación (9-nov-2026)

## Estado verificado
- Código maestro principal: `main/index.html` sin cambios funcionales por esta preparación.
- Respaldo exacto del código anterior: `backup/antes-auth-v2-20261109`, commit `0c6c82de51f9aae32b3a3b1dee8c0603e1b7c47e`.
- Respaldo privado de datos dentro de la base `aquabri-sistema`: esquema `aquabri_backup_auth_20261109`.
- Verificado: 67 tablas copiadas, 18,219 registros, 0 diferencias de conteos durante captura. Incluye usuarios, empleados, comisiones, Caja y ventas.
- Se conservaron en producción IDs de usuario 1 (jefe) y 9 (vendedor), permisos y claves de acceso actuales; empleados y comisiones sin cambios.
- Se guardaron funciones, vistas, índices, restricciones, triggers, políticas y permisos para asistir la recuperación.
- La copia privada NO es un archivo `pg_dump` independiente y los metadatos de Storage no incluyen el contenido binario de los seis archivos de imágenes.
- Proyecto Supabase de plan Pro: confirmar la copia diaria más reciente en la sección **Database → Backups** antes del corte de autenticación. No se ha verificado su fecha exacta con las herramientas disponibles.

## Lo que se preparó
- Columna `public.usuarios.auth_uid` opcional, sin renumerar cuentas.
- Índice único de identidad Auth.
- Trigger que prohíbe vincular o cambiar `auth_uid` desde los roles cliente `anon` y `authenticated`.
- Esquema no expuesto `aquabri_private` con funciones de consulta de identidad y rol ligadas a `auth.uid()`.
- No se cambiaron las políticas RLS existentes, no se creó ningún usuario nuevo y **no se desactivó el inicio de sesión anterior**.

## Condición de salida: NO ACTIVAR AÚN
Supabase Auth tiene **cero cuentas vinculadas** en producción. Para sustituir el inicio de sesión antiguo falta registrar y verificar identidades, vincularlas de forma administrada a IDs 1 y 9, realizar una prueba de entrada con jefe y vendedor y luego migrar el `index.html` y permisos/RLS en una liberación coordinada. Actualmente `usuarios.pass` y las políticas anteriores continúan siendo un riesgo para publicación comercial. NO revocar indiscriminadamente accesos actuales ni activar RLS de staging en producción de golpe.

## Plan de recuperación ante fallos
1. **Si falla solo el nuevo frontend**: volver a la versión de la rama `backup/antes-auth-v2-20261109`. No borrar usuarios, empleados ni comisiones.
2. **Si falla la nueva autenticación**: no retirar el acceso anterior hasta verificar que las cuentas estén vinculadas y que la ruta nueva esté operativa. Usar las comprobaciones de acceso en pruebas primero.
3. **Si un cambio altera registros**: detener escrituras afectadas y comparar con `aquabri_backup_auth_20261109._manifest`; restaurar únicamente tablas/registros afectados tras revisar movimientos legítimos recientes. Evitar restauraciones masivas que eliminen nuevas ventas.
4. **Si se pierde la instancia**: utilizar respaldo externo/automático de Supabase; el esquema privado en la misma base no sustituye un backup externo.
5. **Las imágenes Storage** deben descargarse como objetos, de forma independiente; el esquema privado solo conserva metadatos.

## Auditoría de comprobación (sin datos sensibles)
```sql
SELECT count(*) AS tablas, sum(snapshot_rows) AS registros
FROM aquabri_backup_auth_20261109._manifest;
SELECT id,rol,(auth_uid IS NOT NULL) AS vinculado FROM public.usuarios ORDER BY id;
SELECT count(*) FROM auth.users;
```

Este archivo es un registro operativo, no contiene contraseñas, tokens ni datos de clientes.
