# AQUABRI — un SMS al activar celular; ingreso cotidiano sin SMS

## Estado
- Supabase de pruebas: `aquabri-staging` (`xzbawbkstaqvkwtqlqai`).
- Servicio de ingreso `aq-auth-usuario-v2`, versión 3, desplegado y en estado ACTIVE.
- Admite `username + password` que se valida internamente contra la identidad Auth **de celular +502 ya verificado**. Las cuentas antiguas de prueba que usan correo verificado siguen admitidas como compatibilidad.
- La función **no llama a OTP ni envía SMS para ingresos normales**.
- Pantalla independiente `staging/ACTIVAR_CELULAR_SMS_PRIMERA_VEZ.html`: registrar una identidad Auth con teléfono y contraseña, verificar SMS durante la activación, recuperar contraseña por SMS solo a demanda. Conecta solamente a staging.
- Función `aquabri_private.aq_vincular_celular_usuario_admin(integer,uuid)` en staging para vinculación exclusiva desde el SQL Editor: exige `auth.users.phone_confirmed_at` válido, teléfono `+502` de 8 dígitos y preserva el `usuarios.id` legado. Rechaza intentos anónimos y usuarios ya vinculados a otra identidad. Validación negativa aprobada.
- No se crearon usuarios ni se alteraron datos de producción.
- Respaldo de producción: esquema privado `aquabri_backup_auth_20261109` (67 tablas y 18,219 filas); respaldo del código `backup/antes-auth-v2-20261109`.

## Paso del dueño en Supabase (obligatorio y no automatizado todavía)
1. Abre `https://supabase.com/dashboard/project/xzbawbkstaqvkwtqlqai/auth/providers` (proyecto de pruebas, **no** `aquabri-sistema`).
2. En **Authentication → Providers → Phone**, habilitar Phone.
3. Elegir **Twilio Verify** si aparece. Copiar allí los datos **de forma privada** desde Twilio:
   - **Twilio Account SID**: empieza `AC`.
   - **Twilio Auth Token**: secreto. No compartir por chat, capturas o GitHub.
   - **Twilio Verify Service SID**: empieza `VA`, no confundir con un Messaging Service SID `MG`.
4. Guardar y comprobar entrega de un SMS de activación únicamente en staging. Cuenta Twilio de prueba limita destinatarios a números verificados; no se ha confirmado disponibilidad general.
5. Si Supabase ofrece solo la integración **Twilio SMS normal** con requisito `MG`, **no** pegar el `VA` allí. Revisar la opción específica Twilio Verify o adaptar el proveedor. No modificar Phone de producción en este paso.

## Prueba de alta y recuperación
- Visita `staging/ACTIVAR_CELULAR_SMS_PRIMERA_VEZ.html` desde GitHub Pages cuando esté publicado.
- Selecciona **Verificar celular por primera vez** y coloca solo 8 dígitos después del +502.
- Elige una contraseña **nueva**, no la contraseña actual de AQUABRI.
- Pulsar **Enviar código** origina una solicitud de SMS vía Supabase Auth y el proveedor habilitado.
- Introducir el código en la propia pantalla; `verifyOtp({phone,token,type:'sms'})` confirma el teléfono.
- La verificación de SMS **no autoriza** al nuevo `auth.users.id` a acceder a los datos de AQUABRI. La vinculación sigue restringida al administrador y se hará únicamente tras cotejar la identidad con la cuenta original.
- Recuperación **solo cuando la pida**: `signInWithOtp({phone,options:{shouldCreateUser:false}})` + `verifyOtp` + `updateUser({password})`.
- Inicio habitual: la Edge Function verifica contraseña con `signInWithPassword({phone,password})`. No solicita SMS.
- Limitador de intentos en el login existente, no expone identidad ni password por navegador.

## Aún pendiente / NO PUBLICAR EN PRODUCCIÓN
- El código de activación se guardó en GitHub, **no está enlazado desde la app principal**.
- No se ha confirmado la conexión real Supabase Phone con Twilio Verify ni una prueba end-to-end con SMS real y una identidad vinculada.
- Falta vincular de manera supervisada las cuentas ID 1 jefe e ID 9 vendedor en la base principal y actualizar el `index.html` completo para usar tokens Auth y políticas RLS. **No usar el SMS como sustituto de autorización del jefe.**
- No desactivar el ingreso antiguo ni modificar RLS de producción hasta pruebas por ambos roles.
- La política de seguridad actual de producción todavía tiene tablas públicas sin RLS efectivo; esta integración parcial no remedia eso.
- Las contraseñas legadas deben retirarse de lectura pública durante el corte, con respaldo y mecanismo de recuperación. No reutilizar las existentes en Auth.
- Considerar riesgo de reciclaje de teléfonos; mantener recuperación administrativa adicional y contraseña robusta.
