-- Políticas Auth de las cuatro tablas con acceso legado en staging.
grant select on public.mantenimientos, public.notificaciones, public.precio_historial,
    public.rutas_personalizadas to authenticated;
grant update (leida) on public.notificaciones to authenticated;

create policy aq_mantenimientos_lectura_auth on public.mantenimientos
    for select to authenticated
    using (
        (select aquabri_private.rol_actual()) = 'jefe'
        or (select aquabri_private.tiene_permiso_actual('vehiculos'))
    );

create policy aq_notificaciones_propias_lectura_auth on public.notificaciones
    for select to authenticated
    using (usuario_id = (select aquabri_private.usuario_id_actual()));

create policy aq_notificaciones_propias_marcar_auth on public.notificaciones
    for update to authenticated
    using (usuario_id = (select aquabri_private.usuario_id_actual()))
    with check (usuario_id = (select aquabri_private.usuario_id_actual()));

create policy aq_precio_historial_lectura_auth on public.precio_historial
    for select to authenticated
    using (
        (select aquabri_private.rol_actual()) = 'jefe'
        or (select aquabri_private.tiene_permiso_actual('inventario'))
    );

create policy aq_rutas_personalizadas_lectura_auth on public.rutas_personalizadas
    for select to authenticated
    using (
        (select aquabri_private.rol_actual()) = 'jefe'
        or (select aquabri_private.tiene_permiso_actual('mapa'))
        or (select aquabri_private.tiene_permiso_actual('ventas'))
    );
