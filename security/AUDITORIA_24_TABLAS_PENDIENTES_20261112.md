# AQUABRI oficial — 24 tablas pendientes de RLS, 12/11/2026

Informe generado de los metadatos de Supabase producción y el código actual de la rama de seguridad. **No cambia la base oficial.** Todas estas tablas tienen RLS desactivado; activar RLS con políticas `USING (true)` no evita la exposición.

| Tabla | Políticas antiguas | Consultas directas | Escrituras directas | Acción |
|---|---:|---:|---|---|
| `activos_items` | 0 | 1 | insert:1, update:4, delete:1 | Ajustar RPC/permisos |
| `activos_prestamos` | 1 | 1 | insert:1, update:1, delete:1 | Ajustar RPC/permisos |
| `ausencias` | 0 | 1 | insert:1, update:1, delete:1 | Ajustar RPC/permisos |
| `caja` | 0 | 16 | insert:4 | Ajustar RPC/permisos |
| `clientes` | 2 | 5 | No detectadas | Ajustar RPC/permisos |
| `clientes_eliminados` | 0 | 1 | No detectadas | Ajustar RPC/permisos |
| `creditos` | 1 | 7 | insert:3, update:3, delete:1 | Ajustar RPC/permisos |
| `deudas_proveedores` | 1 | 1 | insert:1, delete:1 | Ajustar RPC/permisos |
| `envases` | 1 | 2 | No detectadas | Ajustar RPC/permisos |
| `grupos_ruta` | 0 | 1 | insert:1, update:1, delete:1 | Ajustar RPC/permisos |
| `liquidacion_items` | 0 | 0 | insert:1 | Ajustar RPC/permisos |
| `liquidaciones` | 0 | 4 | insert:2, update:1, delete:1 | Ajustar RPC/permisos |
| `mantenimientos` | 0 | 5 | insert:2, update:2, delete:1 | Ajustar RPC/permisos |
| `notificaciones` | 0 | 1 | insert:1, update:2 | Ajustar RPC/permisos |
| `pagos_comisiones` | 0 | 3 | insert:2 | Ajustar RPC/permisos |
| `precio_historial` | 0 | 1 | insert:1 | Ajustar RPC/permisos |
| `puntos_canjes_qr` | 0 | 1 | update:1 | Ajustar RPC/permisos |
| `puntos_clientes` | 2 | 5 | update:5, delete:1, upsert:2 | Ajustar RPC/permisos |
| `puntos_historial` | 2 | 1 | insert:7, update:1, delete:1 | Ajustar RPC/permisos |
| `puntos_productos` | 0 | 6 | insert:1, update:1 | Ajustar RPC/permisos |
| `ruta_clientes` | 0 | 4 | insert:1, delete:2 | Ajustar RPC/permisos |
| `ruta_paradas` | 1 | 10 | insert:4, update:10, delete:1 | Ajustar RPC/permisos |
| `rutas_personalizadas` | 0 | 2 | insert:1, delete:2 | Ajustar RPC/permisos |
| `visitas` | 0 | 11 | insert:3 | Ajustar RPC/permisos |

## Puertas de seguridad
1. Sustituir toda escritura directa restante por un RPC autorizado por usuario y rol, y comprobar idempotencia.
2. Reemplazar políticas antiguas abiertas y restringir lecturas a quien corresponda.
3. Verificar las operaciones reales de caja, créditos, envases, puntos, proveedores y nómina desde móvil y computadora.
4. Confirmar respaldo integral restaurado en un entorno aislado y mantener rollback de frontend/SQL preparado.
5. Trasladar SQL y frontend coordinadamente, nunca habilitando las 24 tablas en producción a ciegas.

## Migración realizada en laboratorio
Inicio, perfil, clientes, ventas, cobros de crédito, caja, gastos y envases ya cuentan con rutas RPC verificadas y archivado seguro sin borrar historial. **Quedan módulos de gestión con escrituras directas**, por lo que este inventario no autoriza la publicación.
