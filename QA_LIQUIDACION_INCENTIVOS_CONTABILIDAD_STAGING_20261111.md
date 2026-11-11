# AQUABRI — QA de liquidación y conciliación de incentivos (STAGING)
Fecha: 2026-11-11. Rama: `prueba-supabase-auth-20261110`. PR #17.
**SOLO STAGING; NO FUSIONAR A PRODUCCIÓN.**

## Cambios reales instalados
1. `sql/aq_liquidacion_incentivos_auth_v2_staging.sql`: función `aq_liquidar_incentivos_auth_v2`, exige jefe vía Supabase Auth, idempotencia por nonce, pago atómico y trazabilidad privada. Origen caja genera una sola salida con etiqueta `AQ-LIQ-INCENTIVO` y `AQ-MP:EFECTIVO`; origen externo no mueve caja. No añade otro registro a `gastos` (el incentivo ya se devenga en su tabla).
2. `sql/aq_liquidacion_incentivos_caja_saldo_v3_staging.sql`: misma función, revisada para impedir pagar más que el saldo físico efectivo del turno activo. Excluye movimientos etiquetados transferencia/otro, requiere revisión si hay tipos de movimiento desconocidos y **bloquea pagos de incentivos si la caja activa no pertenece al usuario jefe**. Ejecutar **después** del script v2 si se reconstruye staging.
3. `sql/aq_incentivos_auth_nativo_v2_staging.sql`: seis RPC de equipos, incentivo, asignación y movimientos con contexto Auth nativo, sin `contexto_auth_legacy()`.
4. `sql/aq_incentivos_lecturas_auth_nativo_v2_staging.sql`: tres RPC de reporte/lectura nativas, incluyendo detalle de incentivos limitado al empleado vinculado cuando no es jefe.
5. `sql/aq_auditoria_pagos_incentivos_auth_v1_staging.sql`: RPC de conciliación **solo para jefe**, detecta pagos sin devengos, diferencias de importe, caja faltante/alterada, salidas duplicadas y pagos externos con impacto indebido en efectivo. No modifica datos.
6. `index.staging.html`: botón Liquidar conectado a v2/v3 y protegido con confirmación y nonce por reintento. Este archivo está en GitHub y apunta exclusivamente a Supabase staging; **no se ha probado de extremo a extremo en navegador desplegado**.

## Pruebas SQL reales y reversibles
Todas las pruebas financieras se ejecutaron con `BEGIN ... ROLLBACK`; tras cada una se comprobó integridad.
| Escenario | Resultado |
|---|---|
| Vendedor intenta pagar incentivo | Rechazado |
| Jefe registra incentivo de Q2 externo | Paga Q2, cero salidas de caja y cero gastos duplicados |
| Reintento idéntico de nonce | Retorna pago anterior, no genera uno nuevo |
| Reutilización de nonce con parámetros distintos | Rechazado |
| Segundo pago del mismo incentivo con otro nonce | No duplica |
| Crédito pendiente de cobrar | No liquida |
| Crédito saldado | Liquida normalmente |
| Caja sin apertura o cerrada | Rechazado |
| Caja con Q1 de efectivo y pago de Q3 | Rechazado |
| Caja con Q1 efectivo + Q100 transferencia y pago Q3 | Rechazado (transferencia no cuenta como efectivo) |
| Caja con Q3 efectivo y pago Q3 | Una única salida -Q3 |
| Resumen de caja con transferencia + salida efectivo | Resumen calcula correctamente |
| Caja del vendedor abierta, jefe intenta pagar desde esa caja | Rechazado; sin pago ni movimiento |
| Caja propia del jefe abierta tras rechazo anterior | Pago exitoso, debitado solo desde caja propia |
| Equipo autorizado, venta registrada por socio A | Devenga dos mitades, total 100% del incentivo |
| Equipo autorizado, venta registrada por socio B | Mismo reparto 50/50 |
| Venta registrada por el jefe ajeno al equipo | No genera incentivo de equipo |
| Auditoría de pago reconciliado | 0 inconsistencias |
| Manipulación QA de salida -Q3 -> -Q4 | Detecta anomalía de importe |
| Vendedor intenta ejecutar auditoría | Rechazado |
| Vendedor intenta crear equipo/asignar cliente/autorizar incentivo | Rechazado |
| Jefe crea equipo, autoriza, finaliza y consulta | Permitido; revertido |
| Nuevas RPC de incentivos generan sesiones legadas | No generan |

## Estado comprobado tras ROLLBACK
- Staging: 6 ventas, 11 movimientos caja, 0 empleados QA persistidos, 0 pagos incentivos, 0 devengos y 0 intentos de liquidación.
- 55 tablas `public` con RLS sin políticas (denegadas por defecto) más 1 tabla privada de auditoría protegida sin política directa.
- 37 funciones `SECURITY DEFINER` ejecutables por `authenticated` en `public` (a revisar individualmente); 0 ejecutables por `anon` en `public`.
- Liquidador y auditor solo expuestos a `authenticated` en privilegios SQL; además hacen comprobación de rol en servidor.
- Sin cambios ni ejecuciones DDL sobre `aquabri-sistema` principal en esta etapa.

## Riesgos y pendientes — no publicar todavía
- **Prueba UI real** con inicio de sesión y usuarios ficticios. Las pruebas SQL simulan contexto Auth con reclamaciones locales en la transacción; no sustituyen una conexión real con JWT firmado desde navegador.
- Auditar cada función privilegiada y completar RLS/políticas por módulo y rol (no otorgar SELECT general a las tablas financieras).
- Validar además el reporte financiero general: `aq_pagos_incentivos` es registro de pago, `aq_incentivos_devengados` registro del incentivo ganado y `caja` movimiento efectivo; no debe contarse dos veces en estados de resultados. El auditor no verifica el banco para pagos externos.
- Revisar mecanismos de cierre de caja concurrente y la administración de usuarios/Storage; migrar altas de clientes y todas las escrituras restantes de sesiones legacy.
- Mantener bloqueadas cancelaciones que requieren conciliación avanzada (créditos, puntos, pagos de incentivos, caja cerrada).
- Verificar backup, restore, regresiones de navegador y rollback de despliegue antes de cualquier fusión.
