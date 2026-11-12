# Migración de seguridad AQUABRI — estado al 12 nov 2026

**NO fusionar a `main` ni ejecutar políticas de staging en producción todavía.**

## Preparado en esta rama
- Se conservó el index.html vigente (comprobantes y cuadre).
- El acceso local por comparación `usuarios.pass` fue reemplazado por Supabase Auth.
- Usuario + contraseña se envía al puente servidor `aq-auth-usuario-v2`; teléfono + contraseña usa `signInWithPassword`.
- Se corrigieron expresiones regulares de número celular previamente escapadas de forma incorrecta.
- `loadAll` y lectura de perfil solicitan columnas sin `pass`.
- Comprobación sintáctica: 14/14 scripts inline válidos.

## Verificaciones read-only realizadas
- Supabase staging: RLS en 75/75 tablas de `public`.
- Los 31 recursos consultados en `loadAll()` tienen políticas SELECT y acceso de lectura como usuario Auth, incluyendo permisos de columnas específicas en `usuarios`.
- `authenticated` **no tiene SELECT sobre `usuarios.pass`** en staging.
- Producción: aún tiene 26 tablas públicas sin RLS y login de sesión personalizada; NO activar las políticas de staging directamente.

## Bloqueo de publicación
- El cliente vigente todavía contiene muchas operaciones directas de INSERT/UPDATE/DELETE/UPSERT (aproximadamente 220 apariciones estáticas; no equivalen a 220 endpoints únicos).
- Staging prohíbe esas escrituras directas, por lo que el POS debe adaptarse a RPC/Edge Functions autenticadas para operaciones de caja, ventas, clientes, inventario, créditos, proveedores y demás.
- Comprobar autenticación end-to-end y permisos por rol con identidades de prueba: jefe, vendedor, sesión revocada, invitado anónimo.
- Revisar el puente `aq-auth-usuario-v2` de producción (no es idéntico al de staging), la gestión y cambio de contraseñas, y migración de contraseñas legadas almacenadas en `public.usuarios.pass`.
- Verificar permisos y validaciones de funciones `SECURITY DEFINER` antes de cambiar políticas.
- Preparar respaldo completo/restauración de datos de negocio y ensayo de reversión; el snapshot de RLS creado en producción NO es un backup completo de datos.

## Secuencia de promoción segura
1. Integrar las operaciones de escritura críticas en staging y ejecutar pruebas reales de registro/cobro/cancelación sin datos de producción.
2. Validar bloqueo de operaciones no autorizadas desde API; documentar resultados.
3. Guardar backup completo verificado y probar reversión; asegurar ventanas de corte.
4. Promocionar primero puente Auth y código, con controles verificables; después RLS/grants necesarios, preferentemente dentro de una ventana coordinada para evitar carreras.
5. Probar dispositivos en producción con ventas reales sin exponer a pérdida de datos, ejecutar Supabase Security Advisor, verificar errores y tener reversión preparada.

**Esta rama es desarrollo/prototipo, NO una versión liberada o validada para venta.**


## QA adicional tras correcciones
- [x] Archivo y restauración seguros de clientes, sin eliminar historial financiero.
- [x] RPC de RRHH, ausencias, metas y configuración porcentual de comisiones.
- [x] Nómina y pagos de comisiones idempotentes; pruebas transaccionales reversibles.
- [x] Pedidos programados: reserva sin stock, entrega atómica de caja/crédito y stock.
- [x] Revisión sintáctica de 14 scripts de interfaz.
- [ ] Migrar al 100% las escrituras heredadas restantes de otros módulos.
- [ ] Auditoría individual de funciones SECURITY DEFINER y detección de contraseñas filtradas.
- [ ] Pruebas end-to-end con usuarios reales en móviles y sesión revocada.
- [ ] Verificar backup completo de producción y restaurarlo en entorno aislado.
- [ ] Ventana de cambio, reversión verificada y promoción autorizada: **pendiente**.
