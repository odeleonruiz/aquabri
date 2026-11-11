# AQUABRI — QA de arranque y módulos (solo STAGING)
Fecha: 2026-11-11. Rama: `prueba-supabase-auth-20261110`, PR #17 (BORRADOR / NO FUSIONAR).

## Alcance realmente comprobado
**Inspección de código, pruebas JS aisladas con dobles de prueba y pruebas SQL con identidad/RLS simuladas. NO es todavía una prueba visual end-to-end en navegador con credenciales reales.** No hubo publicación de staging ni modificaciones en la rama principal.

### Correcciones en `index.staging.html`
1. Inicio por celular: número local guatemalteco de 8 dígitos, `502XXXXXXXX` o `+502XXXXXXXX`; los tres se transforman al número Auth `+502XXXXXXXX`. Inicio por nombre de usuario conserva su ruta por Edge Function.
2. Eliminado segundo botón duplicado `btn-limpiar-ruta` (las funciones que buscan este id toman un solo elemento).
3. Separado `liq-notas-salida` del campo `liq-notas` de liquidación de carga: formularios diferentes no compartirán el mismo id.
4. Restablecimiento correcto de campos ocultos exhibidor: `.value='0'` en vez de `.checked=false`.
5. Añadidos manejadores de botones de exhibidor de cliente y mapa, y compatibilidad de funciones de recordatorio usadas en modal legado.
6. Función `aq_usuarios_resumen_auth_v1()` creada en staging y `loadAll()` actualizado para usarla en lugar de SELECT directo de `usuarios`, que se encontraba bloqueado.

### Nueva RPC `aq_usuarios_resumen_auth_v1`
Archivo: `sql/aq_usuarios_resumen_auth_v1_staging.sql`. Jefe obtiene el resumen de las cuentas de staging; vendedor solo su propia cuenta. No devuelve `pass`, tokens ni sesiones; `anon` no tiene EXECUTE; `authenticated` no obtiene SELECT directo a `public.usuarios`.

### Pruebas ejecutadas
| Prueba | Resultado |
|---|---|
| Validación de sintaxis de los 15 bloques JS internos de HTML corregido | Correcto |
| Duplicación de atributos `id` HTML estáticos tras reparación | Ninguna |
| Referencias Supabase principal dentro de `index.staging.html` | Ninguna detectada |
| Ruta login número de 8 dígitos | Correcta (doble de prueba JS) |
| Ruta login con 502 | Correcta (doble de prueba JS) |
| Ruta login con +502 | Correcta (doble de prueba JS) |
| Ruta login nombre de usuario | Correcta (doble de prueba JS) |
| Botón exhibidor cliente (activar/desactivar) | Correcto (doble de prueba JS) |
| Botón exhibidor en mapa (activar/desactivar) | Correcto (doble de prueba JS) |
| `loadAll` invoca RPC Auth en vez de leer `usuarios` | Correcto |
| RPC usuarios con rol jefe simulado | Dos cuentas en staging |
| RPC usuarios con rol vendedor simulado | Solo su cuenta |
| SELECT directo `usuarios` con rol SQL authenticated | Privilegio no concedido |
| RLS sobre ventas: jefe simulado | Lee 6 ventas QA |
| RLS sobre ventas: vendedor simulado | No lee ventas ajenas; clientes y productos sí disponibles |
| Verificación post-QA de staging | 6 ventas, 11 caja, 2 usuarios; 0 empleados devengos/pagos/intentos adicionales |

## Bloqueadores del navegador real
1. El origen del login por usuario de la Edge Function `aq-auth-usuario-v2` está limitado a `https://odeleonruiz.github.io`. La versión `index.staging.html` de la rama experimental **no está desplegada** en GitHub Pages. Abrir el archivo localmente o en un visor HTML de otro dominio no prueba correctamente ese login por CORS.
2. No se dispone aquí de una sesión autenticada real de usuario ficticio en navegador ni de un origen de preview independiente. Las simulaciones SQL con `SET LOCAL ROLE authenticated` y JWT GUC no sustituyen la validación criptográfica del JWT por PostgREST/Auth en HTTP.
3. `loadAll` aún consulta tablas con RLS sin políticas/SELECT para authenticated. Ejemplos: `liquidaciones`, `pagos`, `vales`, `ruta_clientes`, `producto_insumos`, `vehiculos`, `puntos_clientes`, `visitas`, `activos_cat`. Por seguridad el cliente obtiene un error o datos vacíos. **No ampliar SELECT indiscriminadamente.** Implementar RPC lecturas limitadas por rol o políticas RLS específicas después de auditar la necesidad real de cada módulo.
4. Faltan pruebas de manejo de errores, operaciones comerciales con credenciales ficticias, flujos completos y regresiones móviles.

## Siguientes comprobaciones necesarias
- Publicar **una preview aislada** de la rama staging bajo el origen permitido sin modificar la publicación de producción y sin exponer datos reales.
- Abrir en navegador desde esa URL con cuentas Auth de staging, comprobar jefe y vendedor, sesión persistente, acceso a clientes y POS, ventas, cobros, caja, incentivos y permisos.
- Completar la matriz de lectura RLS por módulo y rol. Mantener escrituras sensibles por RPC con validación en servidor.
- Verificar respaldos/restauración, log de errores de navegador, sincronización y pruebas móviles.
- Conservar PR #17 en borrador sin fusionar.

**Estado: etapa 1 parcialmente ejecutada; NO lista para producción.**
