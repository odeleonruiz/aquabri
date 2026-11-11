# AQUABRI — Bonificaciones únicamente manuales (11 noviembre 2026)

## Solicitud
Vender cinco garrafones **no** debe insertar automáticamente uno o más garrafones gratis en el carrito, ni para clientes recién registrados ni existentes. Las sugerencias de precio deben permanecer; los regalos deben agregarse solo por elección expresa del vendedor/jefe.

## Código de producción
Archivo GitHub `main/index.html`, SHA verificado `be0b19b4df9433e8b17246e136d9b677a673837e`. Durante la revisión se detectó que `main/index.html` cambió de SHA `ce312ff0884d8ed7ce5f1e837e8b3abb32db5d98` a esta versión; **se respetó el cambio concurrente y no se sobrescribió**.

La versión nueva de `main` ya incluye:
- Modal de ventas/POS: control explícito `mcp-bonif-manual`; los botones y cantidad de regalo están deshabilitados por defecto; `confirmarModalConfigProd` guarda `bonifCant=0` si no está marcado.
- Pedido programado: control explícito `np-bonif-manual`, campo de cantidad deshabilitado y limpiado cuando se desmarca; `npOnCantChange` no agrega regalos por cantidad.
- Carrito clásico: `addCart` usa `aplBonif=false` para impedir regalos no aprobados en esa ruta; el modal conserva opción manual.
- Selección de producto sin promociones: `aqAgregarProductoNormal` crea ítems con `bonifCant:0`, `bonifProdId:null` y `bonifNombre:''`.
- `aqPrecioHabitualParaProducto`, `aqOfertaInfo` y edición del precio de venta quedan intactas.
- No se cambiaron datos SQL ni se crearon o revirtieron ventas reales.

## QA ejecutado sin escrituras de BD
Evaluación JS aislada de las funciones **reales del `main` actual**, con dobles locales de DOM y carrito:
1. Venta/POS: cinco garrafones → un ítem de cantidad 5 y `bonifCant=0`.
2. Venta/POS: activar control manual y elegir uno gratis → `bonifCant=1`.
3. Desactivar control manual → cantidad gratis vuelve a 0.
4. Pedido programado: cinco garrafones sin control activado → `bonifCant=0`.
5. Pedido programado: activar control y elegir tres regalos → `bonifCant=3`.
6. Todos los 16 bloques JavaScript inline en producción pasan comprobación de sintaxis (`new Function`).
**No equivale a una prueba de venta completa desde un navegador con sesión real**.

## Staging
- Rama `prueba-supabase-auth-20261110` archivo `index.staging.html`, SHA `6a72ed25f7111e1c4c806c1a82b9c72d126d9228`: controles equivalentes para las tres rutas; 5 casos simulados pasaron.
- Deploy separado en Vercel `dpl_HAXUTC5CXiZamtxyXNw5MUM5JJPX` estado READY, alias estable `https://aquabri-staging-preview.vercel.app` apuntando al nuevo deploy.
- Archivo de respaldo **previo** a la corrección, en rama staging: `backups/index-prod-antes-bonif-manual-20261111.html`. Para cualquier reversión, comparar antes con el estado de `main` pues hubo edición concurrente.

## Limitaciones y verificación para el usuario
- No se pudo validar la versión de GitHub Pages en el navegador con credenciales reales; el `main` del repositorio sí se inspeccionó y pasó las pruebas indicadas.
- Recargar AQUABRI principal y comprobar en el carrito que 5 garrafones no incluyen regalo; verificar en el modal que solo al marcar `Agregar bonificación MANUAL` se habiliten unidades gratis.
- No cambiar contraseñas, clientes, inventario ni ventas registradas para probar esto.
