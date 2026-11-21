-- Borrador del corte RLS para Aquabri principal, separado de las migraciones automáticas.
-- Incluye las 24 tablas pendientes y sus políticas para usuarios autenticados.
-- Coordinar con las políticas del resto del esquema, el frontend Auth y el respaldo verificable.

begin;
set local lock_timeout = '2s';
set local statement_timeout = '45s';

do $preflight$
declare
    faltantes text[];
begin
    select array_agg(requerida order by requerida) into faltantes
    from unnest(array[
        'aq_abrir_caja_auth_v2',
        'aq_archivar_cliente_auth_v1',
        'aq_asignar_permiso_auth_v1',
        'aq_borrar_ruta_auth_v1',
        'aq_cancelar_venta_contado_auth_v1',
        'aq_canjear_puntos_auth_v1',
        'aq_cerrar_caja_auth_v2',
        'aq_cobrar_auth_v2',
        'aq_crear_pedido_auth_v1',
        'aq_crear_ruta_auth_v1',
        'aq_desactivar_cliente_puntos_auth_v1',
        'aq_editar_venta_datos_auth_v1',
        'aq_eliminar_movimiento_envase_auth_v1',
        'aq_enlace_puntos_comprobante_v1',
        'aq_enlace_puntos_gestionar_v1',
        'aq_entregar_pedido_auth_v1',
        'aq_estado_pedido_auth_v1',
        'aq_estado_ruta_auth_v1',
        'aq_guardar_cliente_auth_v1',
        'aq_inscribir_cliente_puntos_auth_v1',
        'aq_marcar_parada_auth_v1',
        'aq_marcar_visita_auth_v1',
        'aq_mis_permisos_auth_v1',
        'aq_pagar_proveedor_auth_v1',
        'aq_permisos_administrar_listar_v1',
        'aq_registrar_gasto_auth_v2',
        'aq_registrar_movimiento_envase_auth_v1',
        'aq_reordenar_ruta_auth_v1',
        'aq_restaurar_cliente_auth_v1',
        'aq_reutilizar_ruta_auth_v1',
        'aq_rrhh_abrir_salida_auth_v1',
        'aq_rrhh_anular_salida_auth_v1',
        'aq_rrhh_anular_vale_auth_v1',
        'aq_rrhh_cerrar_salida_auth_v1',
        'aq_rrhh_configurar_comision_auth_v1',
        'aq_rrhh_desactivar_comision_auth_v1',
        'aq_rrhh_desactivar_empleado_auth_v1',
        'aq_rrhh_emitir_vale_auth_v1',
        'aq_rrhh_guardar_empleado_auth_v1',
        'aq_rrhh_meta_empleado_auth_v1',
        'aq_rrhh_pagar_auth_v1',
        'aq_rrhh_pagar_comision_auth_v1',
        'aq_rrhh_pagar_retro_auth_v1',
        'aq_rrhh_quitar_ausencia_auth_v1',
        'aq_rrhh_registrar_ausencia_auth_v1',
        'aq_vender_con_envases_auth_v3'
    ]::text[]) as rpc(requerida)
    where not exists (
        select 1
        from pg_proc f join pg_namespace n on n.oid = f.pronamespace
        where n.nspname = 'public' and f.proname = rpc.requerida
          and has_function_privilege('authenticated', f.oid, 'EXECUTE')
    );
    if faltantes is not null then
        raise exception 'Faltan funciones del frontend Auth: %', array_to_string(faltantes, ', ');
    end if;
    if current_setting('aquabri.rls_cutover_verified', true) is distinct from 'SI_CON_PRUEBAS' then
        raise exception 'El corte requiere que el frontend, el respaldo y las pruebas por rol estén listos';
    end if;
end
$preflight$;

alter table public."activos_items" enable row level security;
revoke all privileges on table public."activos_items" from public, anon, authenticated;
grant select on table public."activos_items" to authenticated;
create policy "aq_activos_items_lectura_auth" on public."activos_items" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('activos'::text) AS tiene_permiso_actual)));

drop policy if exists "acceso_total_activos_prestamos" on public."activos_prestamos";
alter table public."activos_prestamos" enable row level security;
revoke all privileges on table public."activos_prestamos" from public, anon, authenticated;
grant select on table public."activos_prestamos" to authenticated;
create policy "aq_activos_prestamos_lectura_auth" on public."activos_prestamos" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('activos'::text) AS tiene_permiso_actual)));

drop policy if exists "aq_ausencias_rrhh_lectura_auth" on public."ausencias";
drop policy if exists "aq_ausencias_sesion_jefe" on public."ausencias";
drop policy if exists "aq_ausencias_sesion_propia" on public."ausencias";
alter table public."ausencias" enable row level security;
revoke all privileges on table public."ausencias" from public, anon, authenticated;
grant select on table public."ausencias" to authenticated;
create policy "aq_ausencias_rrhh_lectura_auth" on public."ausencias" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM public.empleados e
  WHERE ((e.id = ausencias.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));

alter table public."caja" enable row level security;
revoke all privileges on table public."caja" from public, anon, authenticated;
grant select on table public."caja" to authenticated;
create policy "aq_caja_lectura_auth" on public."caja" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('caja'::text) AS tiene_permiso_actual) AND (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))));

drop policy if exists "acceso_total_clientes" on public."clientes";
drop policy if exists "lectura_publica_clientes" on public."clientes";
alter table public."clientes" enable row level security;
revoke all privileges on table public."clientes" from public, anon, authenticated;
grant select on table public."clientes" to authenticated;
create policy "aq_clientes_lectura_auth" on public."clientes" as permissive
    for select to authenticated
    using (aquabri_private.puede_ver_cliente(id));

alter table public."clientes_eliminados" enable row level security;
revoke all privileges on table public."clientes_eliminados" from public, anon, authenticated;
grant select on table public."clientes_eliminados" to authenticated;
create policy "aq_historial_clientes_solo_jefe_select" on public."clientes_eliminados" as permissive
    for select to authenticated
    using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));

drop policy if exists "acceso_total_creditos" on public."creditos";
alter table public."creditos" enable row level security;
revoke all privileges on table public."creditos" from public, anon, authenticated;
grant select on table public."creditos" to authenticated;
create policy "aq_creditos_lectura_auth" on public."creditos" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('creditos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id))));

drop policy if exists "acceso_total_deudas_proveedores" on public."deudas_proveedores";
alter table public."deudas_proveedores" enable row level security;
revoke all privileges on table public."deudas_proveedores" from public, anon, authenticated;
grant select on table public."deudas_proveedores" to authenticated;
create policy "aq_deudas_proveedores_lectura_jefe" on public."deudas_proveedores" as permissive
    for select to authenticated
    using ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
create policy "aq_deudas_proveedores_lectura_permiso" on public."deudas_proveedores" as permissive
    for select to authenticated
    using (( SELECT aquabri_private.tiene_permiso_actual('proveedores.ver'::text) AS tiene_permiso_actual));

drop policy if exists "acceso_total_envases" on public."envases";
alter table public."envases" enable row level security;
revoke all privileges on table public."envases" from public, anon, authenticated;
grant select on table public."envases" to authenticated;
create policy "aq_envases_lectura_permiso" on public."envases" as permissive
    for select to authenticated
    using ((( SELECT aquabri_private.tiene_permiso_actual('envases'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)));

alter table public."grupos_ruta" enable row level security;
revoke all privileges on table public."grupos_ruta" from public, anon, authenticated;
grant select on table public."grupos_ruta" to authenticated;
create policy "aq_grupos_ruta_lectura_auth" on public."grupos_ruta" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual)));

alter table public."liquidacion_items" enable row level security;
revoke all privileges on table public."liquidacion_items" from public, anon, authenticated;
grant select on table public."liquidacion_items" to authenticated;
create policy "aq_liquidacion_items_lectura_auth" on public."liquidacion_items" as permissive
    for select to authenticated
    using ((EXISTS ( SELECT 1
   FROM public.liquidaciones l
  WHERE (l.id = liquidacion_items.liquidacion_id))));

alter table public."liquidaciones" enable row level security;
revoke all privileges on table public."liquidaciones" from public, anon, authenticated;
grant select on table public."liquidaciones" to authenticated;
create policy "aq_liquidaciones_lectura_auth" on public."liquidaciones" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM public.empleados e
  WHERE ((e.id = liquidaciones.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))))) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));

drop policy if exists "aq_pagos_comision_consulta_jefe_v1" on public."pagos_comisiones";
drop policy if exists "aq_comisiones_sesion_jefe" on public."pagos_comisiones";
alter table public."pagos_comisiones" enable row level security;
revoke all privileges on table public."pagos_comisiones" from public, anon, authenticated;
grant select on table public."pagos_comisiones" to authenticated;
create policy "aq_pagos_comision_consulta_jefe_v1" on public."pagos_comisiones" as permissive
    for select to authenticated
    using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));

alter table public."puntos_canjes_qr" enable row level security;
revoke all privileges on table public."puntos_canjes_qr" from public, anon, authenticated;
grant select on table public."puntos_canjes_qr" to authenticated;
create policy "aq_puntos_qr_lectura_autorizada_v1" on public."puntos_canjes_qr" as permissive
    for select to authenticated
    using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)))));

drop policy if exists "acceso_puntos_clientes" on public."puntos_clientes";
drop policy if exists "lectura_publica_puntos" on public."puntos_clientes";
alter table public."puntos_clientes" enable row level security;
revoke all privileges on table public."puntos_clientes" from public, anon, authenticated;
grant select on table public."puntos_clientes" to authenticated;
create policy "aq_puntos_clientes_lectura_auth" on public."puntos_clientes" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id))));

drop policy if exists "acceso_puntos_historial" on public."puntos_historial";
drop policy if exists "lectura_publica_historial" on public."puntos_historial";
alter table public."puntos_historial" enable row level security;
revoke all privileges on table public."puntos_historial" from public, anon, authenticated;
grant select on table public."puntos_historial" to authenticated;
create policy "aq_puntos_historial_lectura_autorizada_v1" on public."puntos_historial" as permissive
    for select to authenticated
    using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)))));

alter table public."puntos_productos" enable row level security;
revoke all privileges on table public."puntos_productos" from public, anon, authenticated;
grant select on table public."puntos_productos" to authenticated;
create policy "aq_puntos_productos_lectura_auth" on public."puntos_productos" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual)));

alter table public."ruta_clientes" enable row level security;
revoke all privileges on table public."ruta_clientes" from public, anon, authenticated;
grant select on table public."ruta_clientes" to authenticated;
create policy "aq_ruta_clientes_lectura_auth" on public."ruta_clientes" as permissive
    for select to authenticated
    using (aquabri_private.puede_ver_cliente(cliente_id));

drop policy if exists "acceso_total_ruta_paradas" on public."ruta_paradas";
alter table public."ruta_paradas" enable row level security;
revoke all privileges on table public."ruta_paradas" from public, anon, authenticated;
grant select on table public."ruta_paradas" to authenticated;
create policy "aq_ruta_paradas_select_auth_v1" on public."ruta_paradas" as permissive
    for select to authenticated
    using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.rutas r
  WHERE ((r.id = ruta_paradas.ruta_id) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) AND (EXISTS ( SELECT 1
           FROM public.usuarios u
          WHERE ((u.auth_uid = ( SELECT auth.uid() AS uid)) AND (coalesce(u.empleado_id, (select min(e.id) from public.empleados e where e.usuario_id=u.id having count(*)=1)) = r.empleado_id)))))))))));

alter table public."visitas" enable row level security;
revoke all privileges on table public."visitas" from public, anon, authenticated;
grant select on table public."visitas" to authenticated;
create policy "aq_visitas_lectura_auth" on public."visitas" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));

alter table public.mantenimientos enable row level security;
revoke all privileges on table public.mantenimientos from public, anon, authenticated;
grant select on public.mantenimientos to authenticated;
create policy aq_mantenimientos_lectura_auth on public.mantenimientos
    for select to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('vehiculos'::text) AS tiene_permiso_actual)));

alter table public.notificaciones enable row level security;
revoke all privileges on table public.notificaciones from public, anon, authenticated;
grant select on public.notificaciones to authenticated;
grant update (leida) on public.notificaciones to authenticated;
create policy aq_notificaciones_propias_lectura_auth on public.notificaciones
    for select to authenticated using ((usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)));
create policy aq_notificaciones_propias_marcar_auth on public.notificaciones
    for update to authenticated using ((usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))) with check ((usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)));

alter table public.precio_historial enable row level security;
revoke all privileges on table public.precio_historial from public, anon, authenticated;
grant select on public.precio_historial to authenticated;
create policy aq_precio_historial_lectura_auth on public.precio_historial
    for select to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('inventario'::text) AS tiene_permiso_actual)));

alter table public.rutas_personalizadas enable row level security;
revoke all privileges on table public.rutas_personalizadas from public, anon, authenticated;
grant select on public.rutas_personalizadas to authenticated;
create policy aq_rutas_personalizadas_lectura_auth on public.rutas_personalizadas
    for select to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) OR ( SELECT aquabri_private.tiene_permiso_actual('ventas'::text) AS tiene_permiso_actual)));

commit;
