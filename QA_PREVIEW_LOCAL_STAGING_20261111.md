# AQUABRI — Vista previa local independiente (STAGING)
Fecha: 2026-11-11
Rama: `prueba-supabase-auth-20261110`; PR #17 **BORRADOR**.

## Método seleccionado
La vista previa de navegador funciona **solo en la computadora del usuario**, en `http://127.0.0.1:8765/`. No modifica GitHub Pages de producción y no se ha publicado aún una dirección de pruebas accesible por internet.

Se preparó un ZIP para Windows en esta conversación (`AQUABRI_VISTA_PREVIA_STAGING_WINDOWS.zip`) con:
- `INICIAR_AQUABRI_PRUEBAS.bat`
- `servidor_aquabri_staging.ps1`: descarga `index.staging.html` de la rama experimental a través de HTTPS, comprueba que contiene la referencia `xzbawbkstaqvkwtqlqai.supabase.co` y que NO incluye `odwccqqvxpsggggehjtt.supabase.co`, luego sirve el archivo solo en loopback `127.0.0.1:8765` mediante TCP local.
- `LEEME_ANTES_DE_PROBAR.txt` con pasos y advertencias.

El servidor local solo sirve rutas `/`, `/index.html`, `/index.staging.html`, `/manifest.json`, `/icon-192.png` y `/estado`. No solicita ni registra credenciales de usuario; Supabase JS envía las credenciales directamente a Auth del proyecto staging.

## Edge Function de acceso por nombre de usuario
Función de staging: `aq-auth-usuario-v2`.
- Anterior versión 4: únicamente origen `https://odeleonruiz.github.io`.
- Nueva **versión 5 ACTIVE**: allowlist de `https://odeleonruiz.github.io`, `http://127.0.0.1:8765` y `http://localhost:8765`.
- Se mantuvieron los controles de contraseña, verificación de cuenta y límite de intentos existentes.
- Código de la versión desplegada: `staging-edge/aq-auth-usuario-v2/index.ts`.
- **NO se cambió ninguna función de producción** ni el proyecto `aquabri-sistema`.

## Verificaciones ejecutadas
- Revisión de repositorio: `index.staging.html` mantiene solo URL de Supabase staging y está en rama experimental. Repositorio público.
- ZIP generado y verificado integralmente (`ZipFile.testzip` correcto).
- Archivo launcher revisado para servir solo 127.0.0.1 y descargar desde el repositorio y rama esperados.
- Supabase `get_edge_function`: versión 5 `ACTIVE`, contiene las tres cadenas de origen y la condición de allowlist.
- PR #17 sigue `draft=true`, `merged=false`.

## Limitaciones / pruebas NO realizadas
- No se ha ejecutado el `.bat` / `.ps1` en Windows real desde esta sesión. Se requiere que el usuario ejecute el ZIP y compruebe la URL local.
- No se ha realizado un login real con usuario/contraseña de staging en navegador ni un E2E de ventas, caja o incentivos.
- Google Maps puede requerir autorizar el referer del origen local.
- Otras operaciones siguen bloqueadas hasta completar migración y auditoría. No utilizar información real.
- Para una URL pública independiente se necesita conectar un alojamiento (p. ej., Vercel) y permitir explícitamente el origen asignado en la Edge Function staging.

**NO PUBLICAR/NO FUSIONAR todavía.**
