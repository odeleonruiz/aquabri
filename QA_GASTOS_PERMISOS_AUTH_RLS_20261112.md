# AQUABRI — QA de gastos Auth/RLS — 12 de noviembre de 2026

**Entornos:** cambios SQL solo en `aquabri-staging` (`xzbawbkstaqvkwtqlqai`). Producción `aquabri-sistema` (`odwccqqvxpsggggehjtt`) no recibió esta migración. Todo ensayo de escritura se ejecutó en una transacción con `ROLLBACK`.

## Error reproducido antes de la corrección

`aq_registrar_gasto_auth_v2` validaba el permiso de rol/empleado (`aquabri_private.tiene_permiso_actual('gastos')`), pero delegaba en `aq_registrar_gasto_seguro`, que exigía el permiso heredado `permisos_custom::jsonb ? 'gastos'`.

En las cuentas de prueba, el vendedor tenía permiso `gastos` **efectivo=true**, pero **legado=false**. La prueba de registro devolvió `42501: Tu sesión no permite registrar gastos`. La función de eliminación tenía el mismo problema.

## Corrección aplicada en STAGING

Se modificaron únicamente las definiciones de:
- `public.aq_registrar_gasto_seguro`
- `public.aq_eliminar_gasto_seguro`

Su comprobación interna ahora consulta `aquabri_private.tiene_permiso_usuario(v_uid::integer,'gastos')` en vez de depender del JSON antiguo. Se conservan las validaciones existentes de sesión, nonce, conciliación y caja. El archivo aplicado está en `sql/aq_gastos_permiso_rol_auth_v3_staging.sql`, con reversión documentada en `sql/rollback/aq_gastos_permiso_rol_auth_v3_rollback.sql`.

## Resultados obtenidos directamente en la base de pruebas

| Ensayo (transacción revertida) | Resultado |
|---|---|
| Lectura de gasto temporal, jefe autenticado | 1 fila visible |
| Lectura de gasto temporal, vendedor autenticado autorizado | 1 fila visible |
| Lectura de gasto temporal, sin sesión | 0 filas |
| Lectura de gasto temporal, vendedor con permiso revocado temporalmente | 0 filas |
| Registro de gasto por vendedor autorizado con `aq_registrar_gasto_auth_v2` | PASÓ |
| Segundo registro con el mismo nonce/payload | PASÓ: `repetida=true`, 1 solo gasto |
| Eliminación con `aq_eliminar_gasto_auth_v2` | PASÓ, gasto retirado |
| Registro tras revocar temporalmente el permiso | Rechazado como correspondía: `42501` |
| Gastos, permisos y operaciones QA persistidos tras los ROLLBACK | 0 |

## Interfaz experimental

En la rama `feature/traslado-auth-seguro-20261112`, `index.html` añade `r_gas` a `fallosCriticos`. Una consulta de gastos fallida ya no se interpreta silenciosamente como lista de cero gastos durante el arranque.

Se creó `index.staging.auth.html` exclusivamente para QA, con URL, publishable key y endpoint de inicio de sesión del proyecto de pruebas. Se confirmó que no contiene la referencia del proyecto productivo. Tiene aviso visible de pruebas y pasaron 15 bloques JavaScript inline compilables de 17 elementos script totales (los restantes son scripts externos/vacíos).

**No publicar ni fusionar con main todavía.** Faltan pruebas E2E de navegador y dispositivos con sesiones reales; hay funciones privilegiadas de compatibilidad legacy pendientes de revisar y 24 tablas productivas sin RLS. La copia de reversión SQL existe, pero no se ha ensayado una restauración integral de datos.

## Verificación de producción posterior a las pruebas

- Ventas oficiales existentes: **5,236**.
- Tablas públicas productivas sin RLS: **24**.
- No se ejecutaron cambios de esquema ni escritura de ventas en producción durante estas pruebas.

### Próxima etapa
Probar `index.staging.auth.html` con jefe/vendedor en navegador y contrastar ingresos/salidas de Caja antes de integrar. Continuar migración de pedidos, rutas, RR. HH., permisos y validación de funciones `SECURITY DEFINER`; preparar respaldo restaurable integral antes del corte productivo.
