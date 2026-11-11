# AQUABRI — QA de seguridad RLS por módulo (STAGING)
Fecha: 2026-11-11. PR #17 — RAMA EXPERIMENTAL, NO FUSIONAR.

## Cambios ejecutados en Supabase STAGING
Script reproducible: `sql/aq_rls_lecturas_modulos_auth_v4_staging.sql`.

Se añadieron 17 políticas **solo SELECT** (no autorizan INSERT, UPDATE ni DELETE directos):
1. `liquidaciones`: jefe, propietario de liquidación por `usuario_id` o empleado vinculado.
2. `liquidacion_items`: solo si la liquidación principal resulta visible.
3. `pagos`: jefe o empleado correspondiente.
4. `vales`: jefe o empleado correspondiente.
5. `ausencias`: jefe o empleado correspondiente.
6. `puntos_clientes`: jefe o empleado con permiso de puntos y acceso al cliente.
7. `puntos_productos`: jefe o persona con permiso de puntos.
8. `ruta_clientes`: solo clientes visibles mediante `puede_ver_cliente`.
9. `vehiculos`: jefe o permiso `vehiculos`.
10. `visitas`: jefe o autor de visita.
11. `producto_insumos`: jefe o permiso `inventario`.
12. `grupos_ruta`: jefe o permiso `mapa`.
13. `activos_cat`: jefe o permiso `activos`.
14. `activos_items`: jefe o permiso `activos`.
15. `activos_prestamos`: jefe o permiso `activos`.
16. `cargas`: jefe o empleado vinculado.
17. `carga_items`: solo si puede ver la carga.

Se usa `TO authenticated` y predicados de autorización reales, no solo un rol autenticado. RLS existente se conserva.

## Comprobación SQL transaccional (`BEGIN ... ROLLBACK`)
- Con dos empleados ficticios y dos pagos, vales, ausencias y liquidaciones: el vendedor vio únicamente sus propios registros; jefe vio ambos.
- Con dos clientes ficticios de distintos responsables, puntos, rutas, visitas, activo, vehículo y producto de puntos: vendedor vio su cliente, ruta y visita, sin ver el otro; el acceso a módulos por permiso específico se mantuvo restringido. Jefe vio ambos registros de clientes, puntos, rutas y visitas, además del activo y el vehículo.
- Una prueba auxiliar inicial intentó invocar funciones del esquema privado directamente desde el rol de vendedor: PostgreSQL rechazó ese acceso; la prueba correcta se realizó consultando las tablas públicas bajo RLS, sin abrir el esquema privado.
- Todos los registros QA añadidos en transacciones se revirtieron.

## Estado verificado
- 55 → **38** tablas públicas con RLS sin políticas.
- 6 ventas, 11 movimientos de caja, 2 usuarios, 0 empleados ficticios, 0 liquidaciones/pagos/vales/visitas/puntos QA persistidos, 0 liquidaciones de incentivos registradas.
- PR #17 sigue en borrador y no fusionado; ninguna DDL aplicada a `aquabri-sistema`.

## Limitaciones pendientes
- La primera fase de navegador real no está completada: `index.staging.html` está solo en rama experimental y no está publicado en el origen permitido para el login por nombre.
- El simulador SQL usa `SET LOCAL ROLE authenticated` y reclamaciones `request.jwt.claims`; no valida un JWT firmado ni un flujo HTTP del navegador.
- Las 38 tablas públicas restantes con RLS sin políticas requieren evaluación de negocio y pruebas de usuarios antes de habilitar lecturas/escrituras.
- Las funciones `SECURITY DEFINER` accesibles a `authenticated`, operaciones de escritura de módulos no migrados, permisos Storage y credenciales reales de staging requieren auditoría independiente.
- RLS por sí sola no reemplaza las RPC de ventas/cobros/caja: mantener operaciones de escritura controladas en servidor.
- Falta la prueba de ciclo completo login/ventas/cobros/crédito/caja/incentivos desde una vista previa aislada y el informe de regresiones móvil.

**Estado: implementación parcial probada en staging, NO PUBLICABLE.**
