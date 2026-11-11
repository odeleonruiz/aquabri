# AQUABRI — Solución de inicio de sesión staging (2026-11-11)

## Hallazgo comprobado
En los registros de Supabase staging, un intento autenticado por contraseña devolvió `/auth/v1/token` **200**, la carga del perfil por `aq_usuarios_resumen_auth_v1` devolvió 200 y la petición `/rest/v1/config` con `.single()` devolvió **406** (ninguna fila). A continuación se produjo cierre de sesión `204` por el manejo de errores del frontend. La contraseña no fue el problema en ese intento.

El conteo SQL confirmó `public.config = 0` y `loadAll()` exige `sb.from('config').select('*').single()`. `r_cfg` figura en `fallosCriticos`, lo que impide iniciar el sistema aun cuando Auth y el perfil funcionen.

## Corrección aplicada (solo staging)
Archivo: `sql/aq_staging_config_base_20261111.sql`, aplicado a proyecto `xzbawbkstaqvkwtqlqai` mediante `apply_migration` con nombre `aq_staging_config_base_20261111`.
- Inserta el único registro `config` id 1 cuando no existe.
- Nombre **AQUABRI PRUEBAS**, sin teléfono, dirección o logotipo reales.
- Mantiene los límites y permisos actuales de lectura RLS.
- Ajusta secuencia serial a id 1.
- No toca cuentas, contraseñas, clientes, ventas, caja ni bases principales.

## Verificaciones realizadas
- Migración exitosa.
- QA SQL en transacción como `authenticated` y JWT GUC jefe/vendedor: ambos ven `config` y perfiles permitidos; jefe también ve productos, clientes, ventas y créditos esperados.
- Post-migración: `config=1`, `ventas=6`, `caja=11`, `usuarios=2`, `clientes=2`, `productos=1`, `pagos_incentivos=0`.
- Vercel apunta a `https://aquabri-staging-preview.vercel.app/`. La actualización es de datos staging; no requiere nuevo despliegue HTML.
- PR #17 permanece borrador.

## Pendiente
El usuario debe recargar `https://aquabri-staging-preview.vercel.app/` e iniciar sesión con la misma contraseña de staging. No compartir contraseñas por chat. No se ha verificado aún un login completo en su navegador tras la migración.

**Seguridad:** producción `odwccqqvxpsggggehjtt` y GitHub Pages `main` no se han modificado.
