# AQUABRI — Auditoría de seguridad previa al corte a producción
**Fecha:** 12 de noviembre de 2026  
**Dictamen:** **NO APTO PARA PUBLICAR la migración ni para declarar seguro el sistema principal.**

## Alcance y método
Consultas SQL de lectura, análisis de RLS/grants, inspección estática del `index.html` principal y comparación con Supabase de pruebas. Las consultas con `SET LOCAL ROLE anon` se ejecutaron en transacciones `BEGIN READ ONLY` y `ROLLBACK`. **No se extrajeron contraseñas ni tokens**, ni se alteraron ventas, caja o cuentas de producción.

## Hallazgos críticos — sistema oficial
1. **24/68 tablas públicas sin RLS** y con permisos `anon` de SELECT, INSERT, UPDATE y DELETE. Entre ellas `ventas`, `caja`, `clientes`, `creditos`, `envases` y `ruta_paradas`. Adicionalmente, las políticas `acceso_total_*` de otras tablas tienen `USING true / WITH CHECK true` para `anon,authenticated`.
2. **Exposición real de información sin sesión:** una consulta ejecutada como `anon` contó **5,239 ventas**, **760 créditos**, **213 clientes** y **4,871 movimientos de caja**; también pudo contar **2 usuarios**, **167 sesiones**, **3 empleados**, **24 mensajes** y **71 pagos**. Son conteos, no contenido de registros.
3. **Credenciales/sesiones en riesgo:** `anon` tiene SELECT sobre `public.usuarios.pass` y `public.sesiones.token`, RLS habilitado en ambas pero políticas `ALL USING true`. A la hora de revisar había **14 sesiones vigentes** y 153 vencidas. No se consultaron valores.
4. **Autenticación en el navegador:** `main/index.html` ejecuta `D.usuarios.find(x=>x.usuario===u&&x.pass===p)` (comparación de contraseña en cliente), por lo que restringir `usuarios` ahora, sin reemplazar el login, interrumpiría el acceso.
5. **Funciones privilegiadas:** en `public` existen **34 SECURITY DEFINER** con privilegio `EXECUTE` para `anon` (**6 son funciones de disparador**, no invocables como RPC normal). La mayoría de funciones RPC observadas usan validación de token, pero no se ha certificado cada ruta ni descartado la reutilización de tokens expuestos. Se requiere revisión de grants, `search_path`, autorización y permisos por operación.
6. **Respaldo insuficiente:** `aquabri_private.aq_respaldo_rls_20261112` contiene **1 snapshot de ~41 KB** con claves `funciones, grants, policies, tablas`. **NO es un respaldo integral de ventas, caja, clientes, créditos, inventario o RRHH**, y no se ha demostrado restauración integral externa.

## Estado de pruebas
- **83/83 tablas públicas con RLS activado**. El conteo de políticas indica políticas explícitas en 44 tablas; varias tablas operativas internas están cerradas sin política de lectura.
- Prueba de lectura como `anon` sin sesión en staging: **0 ventas, 0 créditos, 0 clientes y 0 movimientos de caja**. Consulta directa a `usuarios` denegada por permisos. La seguridad depende también de que los RPC legacy que `anon` puede ejecutar validen correctamente credenciales y roles.
- 23 funciones `SECURITY DEFINER` siguen ejecutables por `anon` en staging; no corresponde afirmar que son explotables sin auditar sus guardias, pero es superficie pendiente.
- Pruebas SQL reversibles de gastos por rol, alta y baja, idempotencia de nonce: **PASARON** en staging (ver `QA_GASTOS_PERMISOS_AUTH_RLS_20261112.md`).
- Los PR **#24** y **#25** están sin fusionar, marcados como borrador y requieren resolver integración con el `main` actual. No hay validación completa E2E en iPhone/Android/PC con las operaciones reales.

## Bloqueos para corte seguro (orden obligatorio)
- [ ] **Respaldo completo fuera de producción y restauración probada:** tablas, sequences, funciones, triggers, policies, roles/grants, datos, Auth, Storage relevante. Verificar claves y cantidades; no basta un snapshot de RLS.
- [ ] **Autenticación en servidor/Supabase Auth para jefe y empleados:** usuario+contraseña y número celular según diseño, sesiones persistentes. Nunca descargar `pass` ni tokens de sesiones al navegador. Implementar revocación y manejo de tokens.
- [ ] **Migrar todos los módulos y escrituras directas** a funciones autorizadas por rol, con protecciones de doble registro: ventas, caja, abonos, créditos, envases, bonificaciones, inventario, compras/proveedores, puntos, RRHH, comisiones, rutas y pedidos programados.
- [ ] **Políticas/grants mínimos por rol** para todas las tablas expuestas; retirar `USING true` y `WITH CHECK true` abiertos, bloquear SELECT de `usuarios.pass` y `sesiones.token`; restringir `EXECUTE` de funciones, revisar `SECURITY DEFINER`.
- [ ] **Pruebas E2E en staging:** jefe, vendedor con permiso y sin permiso, anónimo, iPhone/Android/PC; transacciones, caja de empleado y reportes. Verificar que no se duplica crédito, caja, inventario ni comisiones y que no hay fugas entre usuarios.
- [ ] **Plan de corte y rollback conjunto del frontend y DB:** congelar escrituras durante ventana controlada, guardar conteos e integridad, desplegar cliente preparado y cambios RLS/RPC coordinados, probar login/venta/cobro, comparar conteos, restaurar solo ante plan validado.
- [ ] **Rotar credenciales y sesiones legacy después de migrar con éxito**, tratando los tokens existentes como potencialmente expuestos. Evitar el cambio precipitado que bloquee la operación diaria.
- [ ] **Volver a ejecutar Security Advisors y pruebas anon** tras el corte; verificar 0 acceso no autorizado y que la app opere según permisos.

## Estado oficial verificado durante esta auditoría
**5,239 ventas, 2 usuarios enlazados con Auth y 3 empleados.** No se modificaron los datos ni permisos oficiales en la auditoría.

## Dictamen
**Seguridad NO verificada / riesgo crítico en producción actual.** Los cambios preparados en staging mejoran el aislamiento, pero **no autorizan todavía la migración a producción**. El próximo trabajo seguro es terminar el puente de autenticación, las rutas de escritura restantes y el respaldo integral restaurable sin exponer el sistema actual a una interrupción.
