# AQUABRI — Hotfix de bonificaciones manuales — 2026-11-11

## Solicitud
Ninguna venta, ni de cliente nuevo ni antiguo, debe agregar unidades de regalo por vender 5, 10 o cualquier cantidad. Los precios habituales y las ofertas de precio se mantienen como sugerencias. Una bonificación requiere acción manual explícita del vendedor.

## Producción
- Archivo `index.html`, rama `main`. Commit de hotfix `32fa3c75b0c4a7fe857634a003ab0996b21365da`.
- Cambio UI: checkbox `Agregar bonificación MANUAL (opcional)` cerrado por defecto en modal de producto; input y botones desactivados sin confirmación.
- `confirmarModalConfigProd` y resumen de carrito ignoran cualquier valor de bonificación si checkbox no está marcado.
- La venta rápida normal no aplica bonificación.
- Pedidos programados: checkbox manual por producto, reinicio al cambiar de producto y al añadirlo, cantidad de compra nunca activa regalos.
- El comportamiento de precio sugerido, edición manual de precio, cálculo de ofertas y facturación no se alteró.
- No se realizó DML/DDL en Supabase producción. No se modificaron transacciones existentes; el cambio afecta nuevas selecciones de carrito.

## QA previo a publicación
Prueba JS aislada de funciones reales extraídas del HTML + verificación sintáctica de 16 bloques JavaScript:
| Caso | Cantidad comprada | Regalo |
|---|---:|---:|
| Venta normal, sin marcar bonificación | 5 | 0 |
| Pedido programado, sin marcar bonificación | 5 | 0 |
| Venta normal, marcando manualmente 1 regalo | 5 | 1 |
| Pedido programado, marcando manualmente 1 regalo | 5 | 1 |
| Cambiar producto con bonificación previa oculta | — | Se limpia |

## Staging
- Archivo `index.staging.html` ya tenía una implementación de opt-in manual con botón `Aplicar bonificación manual` y banderas `_mcpBonifActiva` / `_npBonifManual`.
- QA funcional aislado con escenarios idénticos: cinco pruebas correctas, 17 scripts JavaScript parseados.
- Vercel proyecto `aquabri-staging-preview`: deployment `dpl_BAvqoTeb3UdwyYrNCJ16rAxifyZ8` **READY**, alias asignado: `https://aquabri-staging-preview.vercel.app/`. HTML exclusivamente conectado a `xzbawbkstaqvkwtqlqai.supabase.co`.
- No se fusionó PR #17 a main (la corrección de producción se aplicó como hotfix específico directamente a `index.html`).

## Estado y pendientes
- Se comprobó el commit de GitHub `main` y el alias de Vercel. La lectura HTTP externa de las páginas devolvió error con la herramienta de navegación; **no se puede certificar el despliegue de GitHub Pages ni una prueba end-to-end real en navegador** desde esta sesión.
- La publicación de GitHub Pages puede tardar o requerir recarga de caché. Verificar abriendo `https://odeleonruiz.github.io/aquabri/` y probando una venta ficticia **sin cobrar/guardar**: 5 garrafones, 0 bonos, y sólo 1 bono tras la selección manual.
- El conteo de filas con bonificaciones guardadas en `venta_items` producción antes del hotfix era 164; **no editar ni interpretar como automáticas** las ventas previas.
