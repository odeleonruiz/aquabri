# AQUABRI — Facturas e inventario comprado a crédito

## Regla contable
- **Compra de inventario**: se registra factura, artículos, entradas de stock y lote FIFO cuando corresponde. No se registra en **Gastos operativos**. Si es a crédito, se crea deuda con proveedor y **no** salida de Caja. Si se paga desde Caja, genera una única salida etiquetada **EFECTIVO**.
- **Gasto operativo con factura**: factura de servicio o gasto real; se reconoce una vez en **Gastos**. Si es pendiente o a crédito, crea también deuda sin salida de Caja; el responsable queda indicado como *Pendiente de pago*.
- **Deuda previa sin artículos**: registra obligación únicamente; no crea stock ni gasto ficticio.
- **Pago a proveedor**: reduce la deuda, y si proviene de Caja genera salida etiquetada EFECTIVO. No contabiliza otro gasto.
- **Pagos externos ya realizados**: siguen siendo diferentes de deudas pendientes; no se registran como salida de Caja.

## Acceso desde Gastos
- `Gastos → ¿De dónde se pagó?` incluye **Gasto pendiente de pago / crédito de proveedor**. Al seleccionarlo, se requiere proveedor y al pulsar el botón se prepara una factura de tipo **Gasto operativo** y estado **Crédito**. La pantalla **no guarda la deuda automáticamente**: el usuario confirma con **Registrar** en Facturas.
- El botón **Registrar compra de inventario a crédito** abre Facturas en modo compra con artículos y estado Crédito. Deben agregarse los productos antes de confirmar.
- **Sin salida de Caja** ahora significa pago externo **ya realizado**, no una factura pendiente.
- Si no hay permiso de Facturas, se rechaza el traslado sin guardar.
- El formulario original de Gastos conserva los pagos efectivo/transferencia/tarjeta.

## Pruebas realizadas en aquabri-staging (reversibles)
- Compra de producto a crédito: aumentó stock, se creó lote FIFO y una deuda. Sin gasto operativo ni salida de Caja.
- Compra de producto pagada desde Caja: aumentó stock, se creó lote y salida de efectivo etiquetada. Sin gasto operativo duplicado.
- Factura de reparación a crédito: registró gasto y deuda; sin Caja y sin existencias.
- Gasto pagado desde Caja: registró gasto y salida etiquetada; sin deuda.
- Deuda sin artículos: generó solo cuenta por pagar.
- Abono a deuda: redujo saldo y registró salida etiquetada, sin crear otro gasto.
- Pago pendiente indica `pagado_por=Pendiente de pago` y no *Jefe*.
- Prueba de interfaz: prellenado para gasto y compra, sin escribir en BD antes de confirmar y rechazo sin permiso de Facturas.
- Todas las pruebas de BD finalizaron con **ROLLBACK**.

## Migración
`staging/migrations/20261109_facturas_compra_credito_sin_gastos_duplicados.sql`

La migración conserva la validación de roles exacta de producción. No cambia datos históricos.

## Precauciones
- Las facturas antiguas no se recalculan, duplican ni reclasifican.
- No registrar la misma factura en Gastos y en Facturas; se usa un solo flujo.
- El estado financiero del gasto y su pago son acontecimientos distintos.
- Una compra inventariable no se resta directamente de ganancias como gasto corriente; el costo se reconoce al vender/consumir, mediante los registros de costo apropiados.
