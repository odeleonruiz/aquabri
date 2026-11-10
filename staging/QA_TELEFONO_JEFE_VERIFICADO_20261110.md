# AQUABRI — vinculación de celular confirmada en staging (2026-11-10)

**SOLO PRUEBAS** `xzbawbkstaqvkwtqlqai`. No aplicar el vínculo de esta prueba a producción.

## Evidencia de estado
- Tras `signUp({ phone, password })` y `verifyOtp({phone,token,type:'sms'})`, Supabase Auth confirmó una nueva identidad con `phone_confirmed_at`.
- Supabase Auth almacena el teléfono de Guatemala con prefijo `502` sin el carácter `+`. La validación antigua esperaba `+502` y rechazaba identidades correctas.
- Edge Function `aq-auth-usuario-v2`, versión **4**, desplegada y comprobada ACTIVE: acepta `+502XXXXXXXX` o `502XXXXXXXX` para identidad confirmada; convierte a E.164 con `+` antes de `signInWithPassword`.
- El login por **usuario + contraseña no llama a SMS/OTP**; el SMS corresponde a activación o recuperación bajo solicitud explícita.
- Se vinculó la identidad Auth verificada con el usuario **ID 1, rol jefe, de staging**. La fila `public.usuarios` conservó su ID, y se respaldó el UUID antiguo de QA en la tabla privada `aquabri_private.aq_respaldo_vinculos_phone_20261110`.
- El usuario vendedor de QA (ID 2) permanece intacto y sin teléfono confirmado.
- Se probó que la función administrativa `aq_vincular_celular_usuario_admin` no puede ejecutarse con `anon`, `authenticated` o `service_role`, y rechaza una identidad falsa. La actualización especial del jefe de staging se realizó exclusivamente vía migración administrada con respaldo del enlace QA anterior.
- **No se han revelado números telefónicos ni contraseñas en este documento.**

## Límites de la prueba
La recepción de SMS y su confirmación fueron indicadas por la persona usuaria, y la verificación se comprobó en `auth.users.phone_confirmed_at`. Todavía falta una **prueba positiva de inicio de sesión completo** en `staging/PROBAR_LOGIN_SEGURO_USUARIO.html` con el nombre de usuario QA y la contraseña nueva que se estableció al activar el teléfono.

## Producción
El sitio principal todavía mantiene el flujo anterior. NO modificar las contraseñas de `public.usuarios`, no cambiar `index.html` de producción, y no habilitar RLS global de la versión QA hasta validar acceso jefe y vendedor y la autorización por operaciones.
El respaldo previo a Auth sigue en `aquabri_backup_auth_20261109` con 67 tablas y 18,219 filas copiadas, más código anterior `backup/antes-auth-v2-20261109`.

## Prueba siguiente
Abrir `https://odeleonruiz.github.io/aquabri/staging/PROBAR_LOGIN_SEGURO_USUARIO.html` e ingresar el nombre del jefe de **staging** y la **nueva contraseña de pruebas** creada al verificar su celular. No utilizar la contraseña anterior de producción ni compartir credenciales en el chat.
