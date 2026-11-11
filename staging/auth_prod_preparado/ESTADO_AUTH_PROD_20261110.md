# AQUABRI — Auth v2: backend preparado en producción

**Aplicado** en Supabase proyecto `odwccqqvxpsggggehjtt` y verificado el 10 de noviembre de 2026.

- Edge Function `aq-auth-usuario-v2`, versión 1, estado ACTIVE. Acepta `usuario + contraseña`, obtiene el teléfono +502 **verificado** asociado a `public.usuarios.auth_uid` y lo autentica con Supabase Auth. No acepta email como alternativa en producción. Devuelve tokens solamente si Supabase verifica contraseña y Auth UUID coincide.
- Tabla `public.aq_auth_login_freno` con RLS habilitada y acceso de servicio; función `aq_auth_login_admitir_intento` con límite de 10 intentos/15 minutos por usuario. Roles anon y authenticated no pueden leer contadores ni ejecutar esta función.
- La función `aq_mi_perfil_seguro` permanece restringida a usuarios autenticados.
- Usuarios originales jefe ID 1, vendedor ID 9, empleados y comisiones no alterados. Actualmente **cero identidades Supabase Auth en producción**; por ello no se ha probado login real ni activado el frontend.
- Respaldo privado previo `aquabri_backup_auth_20261109` (67 tablas); respaldo código `backup/antes-auth-v2-20261109`.
- **No hacer corte:** el `index.html` de AQUABRI todavía usa autenticación legada; las políticas RLS antiguas siguen pendientes. Crear/verificar identidades *en el proyecto de producción*, vincular UUID a usuarios existentes sin renumerar, comprobar jefe/vendedor y después migrar frontend y endurecer RLS en despliegue coordinado. No trasladar Auth UUID ni contraseñas de staging por copia SQL.
- La configuración Phone/Twilio fue guardada manualmente por el propietario en el panel de Supabase. No está disponible una lectura de esa configuración mediante las acciones conectadas actuales, de modo que el backend no demuestra por sí solo que el envío de SMS funciona en producción.

**Este directorio documenta código de infraestructura desplegado, no un cambio en la página principal.**
