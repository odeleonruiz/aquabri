# AQUABRI staging — Corrección del inicio de sesión y preview web (2026-11-11)

## Hallazgo real
En `index.staging.html`, `aqPerfilAutenticado()` autenticaba al usuario con `sb.auth.getUser()` pero luego intentaba `sb.from('usuarios').select(...).eq('auth_uid',user.id).maybeSingle()`. `public.usuarios` no tiene concesión SELECT para authenticated. Este es un error de autorización en la segunda fase del login, aunque la contraseña sea correcta. Logs de Auth de staging reportaron un POST contraseña con respuesta 200, seguido de una petición de salida de sesión 204; no prueban que la falla posterior sea exclusiva, pero concuerdan con ella.

## Corrección aplicada
El perfil se lee mediante `sb.rpc('aq_usuarios_resumen_auth_v1')`, ya instalada en STAGING; el frontend elige la entrada cuyo `auth_uid` coincide con `sb.auth.getUser().data.user.id`. No se abre SELECT a `public.usuarios`. La pantalla distingue errores de credenciales, carga de perfil y carga de datos. Las comprobaciones JS aisladas validan perfil vinculado, cuenta sin vínculo y falta de sesión; los 17 bloques script se analizaron por sintaxis sin error.

## Despliegue
- Vercel: proyecto separado `aquabri-staging-preview`, ID `prj_i16KWJZ1fYHPjtTIxQsdRNXI5Ed4` en equipo `odeleonruiz-5993`.
- URL estable: https://aquabri-staging-preview.vercel.app/
- Nuevo deployment `dpl_At6TppnHEMniiwM6ZoSsoPfXBWdZ` estado READY; alias estable asignado a ese despliegue.
- Fuente: `index.staging.html` en rama `prueba-supabase-auth-20261110`, SHA de archivo `adfc0bf9dadc1d74e4f3d3a2abd36c167eed15fa`.
- El HTML incluye URL de Supabase `xzbawbkstaqvkwtqlqai.supabase.co`, no la de producción `odwccqqvxpsggggehjtt.supabase.co`.
- La función Auth `aq-auth-usuario-v2` de staging se desplegó como versión 6 ACTIVE, con origen permitido `https://aquabri-staging-preview.vercel.app` y orígenes anteriores.
- El proyecto Vercel reporta protección Vercel Authentication activa. Puede requerir sesión de Vercel del usuario.

## Confirmación pendiente
No se ha realizado login real en navegador con credenciales del usuario ni pruebas E2E del POS. El servidor web externo no estuvo accesible desde la herramienta HTTP de este entorno; Vercel informa READY y alias asignado. Pedir al usuario que abra la URL estable, recargue y pruebe la cuenta de staging. No solicitar contraseña.

## Protección
Sin cambios a Supabase producción, GitHub Pages principal o `main`. PR #17 permanece en borrador y no fusionado.
