set local lock_timeout='1500ms';
set local statement_timeout='30s';

create function aquabri_private.permiso_sesion_principal(codigo text) returns boolean language sql stable security definer set search_path='' as $$
select aquabri_private.tiene_permiso_usuario(public.aq_sesion_legacy_usuario_actual_v1(),codigo);
$$;
create function aquabri_private.clientes_de_sesion_principal() returns setof integer language sql stable security definer set search_path='' as $$
with actor as materialized (select public.aq_sesion_legacy_usuario_actual_v1() as id)
select c.id from public.clientes c,actor where c.creado_por=actor.id::text
union select a.cliente_id from public.aq_clientes_atribucion_manual a,actor where a.usuario_id=actor.id
union select v.cliente_id from public.ventas v,actor where v.usuario_id=actor.id and v.cliente_id is not null;
$$;
create function aquabri_private.empleado_de_sesion_principal() returns integer language sql stable security definer set search_path='' as $$
select coalesce(u.empleado_id,(select min(e.id) from public.empleados e where e.usuario_id=u.id having count(*)=1)) from public.usuarios u where u.id=public.aq_sesion_legacy_usuario_actual_v1();
$$;
revoke all on function aquabri_private.permiso_sesion_principal(text), aquabri_private.clientes_de_sesion_principal(), aquabri_private.empleado_de_sesion_principal() from public,anon,authenticated,service_role;
grant execute on function aquabri_private.permiso_sesion_principal(text), aquabri_private.clientes_de_sesion_principal(), aquabri_private.empleado_de_sesion_principal() to anon;

alter table public."activos_items" enable row level security;
revoke all on public."activos_items" from public, anon, authenticated;
create policy "aq_activos_items_lectura_auth" on public."activos_items" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('activos'::text) AS tiene_permiso_actual)));
grant SELECT on public."activos_items" to authenticated;
grant select on public.activos_items to anon;
create policy aq_principal_select on public.activos_items for select to anon using ((select aquabri_private.permiso_sesion_principal('activos')));
grant insert on public.activos_items to anon;
create policy aq_principal_insert on public.activos_items for insert to anon with check ((select aquabri_private.permiso_sesion_principal('activos')));
grant update on public.activos_items to anon;
create policy aq_principal_update on public.activos_items for update to anon using ((select aquabri_private.permiso_sesion_principal('activos'))) with check ((select aquabri_private.permiso_sesion_principal('activos')));
grant delete on public.activos_items to anon;
create policy aq_principal_delete on public.activos_items for delete to anon using ((select aquabri_private.permiso_sesion_principal('activos')));

alter table public."activos_prestamos" enable row level security;
revoke all on public."activos_prestamos" from public, anon, authenticated;
drop policy if exists "acceso_total_activos_prestamos" on public."activos_prestamos";
create policy "aq_activos_prestamos_lectura_auth" on public."activos_prestamos" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('activos'::text) AS tiene_permiso_actual)));
grant SELECT on public."activos_prestamos" to authenticated;
grant select on public.activos_prestamos to anon;
create policy aq_principal_select on public.activos_prestamos for select to anon using ((select aquabri_private.permiso_sesion_principal('activos')));
grant insert on public.activos_prestamos to anon;
create policy aq_principal_insert on public.activos_prestamos for insert to anon with check ((select aquabri_private.permiso_sesion_principal('activos')));
grant update on public.activos_prestamos to anon;
create policy aq_principal_update on public.activos_prestamos for update to anon using ((select aquabri_private.permiso_sesion_principal('activos'))) with check ((select aquabri_private.permiso_sesion_principal('activos')));
grant delete on public.activos_prestamos to anon;
create policy aq_principal_delete on public.activos_prestamos for delete to anon using ((select aquabri_private.permiso_sesion_principal('activos')));

alter table public."caja" enable row level security;
revoke all on public."caja" from public, anon, authenticated;
create policy "aq_caja_lectura_auth" on public."caja" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('caja'::text) AS tiene_permiso_actual) AND (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))));
grant SELECT on public."caja" to authenticated;
grant select on public.caja to anon;
create policy aq_principal_select on public.caja for select to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('caja')) and usuario_id = (select public.aq_sesion_legacy_usuario_actual_v1()))));
grant insert on public.caja to anon;
create policy aq_principal_insert on public.caja for insert to anon with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('caja')) and usuario_id = (select public.aq_sesion_legacy_usuario_actual_v1()))));

alter table public."clientes_eliminados" enable row level security;
revoke all on public."clientes_eliminados" from public, anon, authenticated;
create policy "aq_historial_clientes_solo_jefe_select" on public."clientes_eliminados" as PERMISSIVE for SELECT to authenticated using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));
grant SELECT on public."clientes_eliminados" to authenticated;
grant select on public.clientes_eliminados to anon;
create policy aq_principal_select on public.clientes_eliminados for select to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');
grant insert on public.clientes_eliminados to anon;
create policy aq_principal_insert on public.clientes_eliminados for insert to anon with check ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');
grant delete on public.clientes_eliminados to anon;
create policy aq_principal_delete on public.clientes_eliminados for delete to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."creditos" enable row level security;
revoke all on public."creditos" from public, anon, authenticated;
drop policy if exists "acceso_total_creditos" on public."creditos";
create policy "aq_creditos_lectura_auth" on public."creditos" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('creditos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id))));
grant SELECT on public."creditos" to authenticated;
grant select on public.creditos to anon;
create policy aq_principal_select on public.creditos for select to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('creditos')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));
grant insert on public.creditos to anon;
create policy aq_principal_insert on public.creditos for insert to anon with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('creditos')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));
grant update on public.creditos to anon;
create policy aq_principal_update on public.creditos for update to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('creditos')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal())))) with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('creditos')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));
grant delete on public.creditos to anon;
create policy aq_principal_delete on public.creditos for delete to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."deudas_proveedores" enable row level security;
revoke all on public."deudas_proveedores" from public, anon, authenticated;
drop policy if exists "acceso_total_deudas_proveedores" on public."deudas_proveedores";
create policy "aq_deudas_proveedores_lectura_jefe" on public."deudas_proveedores" as PERMISSIVE for SELECT to authenticated using ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
create policy "aq_deudas_proveedores_lectura_permiso" on public."deudas_proveedores" as PERMISSIVE for SELECT to authenticated using (( SELECT aquabri_private.tiene_permiso_actual('proveedores.ver'::text) AS tiene_permiso_actual));
grant SELECT on public."deudas_proveedores" to authenticated;
grant select on public.deudas_proveedores to anon;
create policy aq_principal_select on public.deudas_proveedores for select to anon using ((select aquabri_private.permiso_sesion_principal('proveedores.ver')));
grant insert on public.deudas_proveedores to anon;
create policy aq_principal_insert on public.deudas_proveedores for insert to anon with check ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');
grant delete on public.deudas_proveedores to anon;
create policy aq_principal_delete on public.deudas_proveedores for delete to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."envases" enable row level security;
revoke all on public."envases" from public, anon, authenticated;
drop policy if exists "acceso_total_envases" on public."envases";
create policy "aq_envases_lectura_permiso" on public."envases" as PERMISSIVE for SELECT to authenticated using ((( SELECT aquabri_private.tiene_permiso_actual('envases'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)));
grant SELECT on public."envases" to authenticated;
grant select on public.envases to anon;
create policy aq_principal_select on public.envases for select to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('envases')) and (cliente_id in (select aquabri_private.clientes_de_sesion_principal()) or cliente_id is null))));
grant insert on public.envases to anon;
create policy aq_principal_insert on public.envases for insert to anon with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('envases')) and (cliente_id in (select aquabri_private.clientes_de_sesion_principal()) or cliente_id is null))));
grant delete on public.envases to anon;
create policy aq_principal_delete on public.envases for delete to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."grupos_ruta" enable row level security;
revoke all on public."grupos_ruta" from public, anon, authenticated;
create policy "aq_grupos_ruta_lectura_auth" on public."grupos_ruta" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual)));
grant SELECT on public."grupos_ruta" to authenticated;
grant select on public.grupos_ruta to anon;
create policy aq_principal_select on public.grupos_ruta for select to anon using ((select aquabri_private.permiso_sesion_principal('mapa')));
grant insert on public.grupos_ruta to anon;
create policy aq_principal_insert on public.grupos_ruta for insert to anon with check ((select aquabri_private.permiso_sesion_principal('mapa')));
grant update on public.grupos_ruta to anon;
create policy aq_principal_update on public.grupos_ruta for update to anon using ((select aquabri_private.permiso_sesion_principal('mapa'))) with check ((select aquabri_private.permiso_sesion_principal('mapa')));
grant delete on public.grupos_ruta to anon;
create policy aq_principal_delete on public.grupos_ruta for delete to anon using ((select aquabri_private.permiso_sesion_principal('mapa')));

alter table public."liquidacion_items" enable row level security;
revoke all on public."liquidacion_items" from public, anon, authenticated;
create policy "aq_liquidacion_items_lectura_auth" on public."liquidacion_items" as PERMISSIVE for SELECT to authenticated using ((EXISTS ( SELECT 1
   FROM liquidaciones l
  WHERE (l.id = liquidacion_items.liquidacion_id))));
grant SELECT on public."liquidacion_items" to authenticated;
grant select on public.liquidacion_items to anon;
create policy aq_principal_select on public.liquidacion_items for select to anon using (exists (select 1 from public.liquidaciones l where l.id=liquidacion_items.liquidacion_id));
grant insert on public.liquidacion_items to anon;
create policy aq_principal_insert on public.liquidacion_items for insert to anon with check ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."liquidaciones" enable row level security;
revoke all on public."liquidaciones" from public, anon, authenticated;
create policy "aq_liquidaciones_lectura_auth" on public."liquidaciones" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = liquidaciones.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))))) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));
grant SELECT on public."liquidaciones" to authenticated;
grant select on public.liquidaciones to anon;
create policy aq_principal_select on public.liquidaciones for select to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or usuario_id = (select public.aq_sesion_legacy_usuario_actual_v1()) or empleado_id=(select aquabri_private.empleado_de_sesion_principal())));
grant insert on public.liquidaciones to anon;
create policy aq_principal_insert on public.liquidaciones for insert to anon with check ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');
grant update on public.liquidaciones to anon;
create policy aq_principal_update on public.liquidaciones for update to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe') with check ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');
grant delete on public.liquidaciones to anon;
create policy aq_principal_delete on public.liquidaciones for delete to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."mantenimientos" enable row level security;
revoke all on public."mantenimientos" from public, anon, authenticated;
create policy "aq_mantenimientos_lectura_auth" on public."mantenimientos" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('vehiculos'::text) AS tiene_permiso_actual)));
grant SELECT on public."mantenimientos" to authenticated;
grant select on public.mantenimientos to anon;
create policy aq_principal_select on public.mantenimientos for select to anon using ((select aquabri_private.permiso_sesion_principal('vehiculos')));
grant insert on public.mantenimientos to anon;
create policy aq_principal_insert on public.mantenimientos for insert to anon with check ((select aquabri_private.permiso_sesion_principal('vehiculos')));
grant update on public.mantenimientos to anon;
create policy aq_principal_update on public.mantenimientos for update to anon using ((select aquabri_private.permiso_sesion_principal('vehiculos'))) with check ((select aquabri_private.permiso_sesion_principal('vehiculos')));
grant delete on public.mantenimientos to anon;
create policy aq_principal_delete on public.mantenimientos for delete to anon using ((select aquabri_private.permiso_sesion_principal('vehiculos')));

alter table public."notificaciones" enable row level security;
revoke all on public."notificaciones" from public, anon, authenticated;
create policy "aq_notificaciones_propias_lectura_auth" on public."notificaciones" as PERMISSIVE for SELECT to authenticated using ((usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)));
create policy "aq_notificaciones_propias_marcar_auth" on public."notificaciones" as PERMISSIVE for UPDATE to authenticated using ((usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))) with check ((usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)));
grant SELECT on public."notificaciones" to authenticated;
grant UPDATE ("leida") on public."notificaciones" to authenticated;
grant select on public.notificaciones to anon;
create policy aq_principal_select on public.notificaciones for select to anon using (usuario_id = (select public.aq_sesion_legacy_usuario_actual_v1()));
grant insert on public.notificaciones to anon;
create policy aq_principal_insert on public.notificaciones for insert to anon with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('ventas')) and exists (select 1 from public.usuarios u where u.id=notificaciones.usuario_id and u.rol='jefe'))));
grant update (leida) on public.notificaciones to anon;
create policy aq_principal_update on public.notificaciones for update to anon using (usuario_id = (select public.aq_sesion_legacy_usuario_actual_v1())) with check (usuario_id = (select public.aq_sesion_legacy_usuario_actual_v1()));

alter table public."precio_historial" enable row level security;
revoke all on public."precio_historial" from public, anon, authenticated;
create policy "aq_precio_historial_lectura_auth" on public."precio_historial" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('inventario'::text) AS tiene_permiso_actual)));
grant SELECT on public."precio_historial" to authenticated;
grant select on public.precio_historial to anon;
create policy aq_principal_select on public.precio_historial for select to anon using ((select aquabri_private.permiso_sesion_principal('inventario')));
grant insert on public.precio_historial to anon;
create policy aq_principal_insert on public.precio_historial for insert to anon with check ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."puntos_canjes_qr" enable row level security;
revoke all on public."puntos_canjes_qr" from public, anon, authenticated;
create policy "aq_puntos_qr_lectura_autorizada_v1" on public."puntos_canjes_qr" as PERMISSIVE for SELECT to authenticated using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)))));
grant SELECT on public."puntos_canjes_qr" to authenticated;
grant select on public.puntos_canjes_qr to anon;
create policy aq_principal_select on public.puntos_canjes_qr for select to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('puntos')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));
grant update (usado) on public.puntos_canjes_qr to anon;
create policy aq_principal_update on public.puntos_canjes_qr for update to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('puntos')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal())))) with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('puntos')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));
grant delete on public.puntos_canjes_qr to anon;
create policy aq_principal_delete on public.puntos_canjes_qr for delete to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."puntos_productos" enable row level security;
revoke all on public."puntos_productos" from public, anon, authenticated;
create policy "aq_puntos_productos_lectura_auth" on public."puntos_productos" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual)));
grant SELECT on public."puntos_productos" to authenticated;
grant select on public.puntos_productos to anon;
create policy aq_principal_select on public.puntos_productos for select to anon using (((select aquabri_private.permiso_sesion_principal('puntos')) or (select aquabri_private.permiso_sesion_principal('ventas'))));
grant insert on public.puntos_productos to anon;
create policy aq_principal_insert on public.puntos_productos for insert to anon with check ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');
grant update on public.puntos_productos to anon;
create policy aq_principal_update on public.puntos_productos for update to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe') with check ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');

alter table public."ruta_clientes" enable row level security;
revoke all on public."ruta_clientes" from public, anon, authenticated;
create policy "aq_ruta_clientes_lectura_auth" on public."ruta_clientes" as PERMISSIVE for SELECT to authenticated using (aquabri_private.puede_ver_cliente(cliente_id));
grant SELECT on public."ruta_clientes" to authenticated;
grant select on public.ruta_clientes to anon;
create policy aq_principal_select on public.ruta_clientes for select to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));
grant insert on public.ruta_clientes to anon;
create policy aq_principal_insert on public.ruta_clientes for insert to anon with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));
grant update on public.ruta_clientes to anon;
create policy aq_principal_update on public.ruta_clientes for update to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal())))) with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));
grant delete on public.ruta_clientes to anon;
create policy aq_principal_delete on public.ruta_clientes for delete to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and cliente_id in (select aquabri_private.clientes_de_sesion_principal()))));

alter table public."ruta_paradas" enable row level security;
revoke all on public."ruta_paradas" from public, anon, authenticated;
drop policy if exists "acceso_total_ruta_paradas" on public."ruta_paradas";
create policy "aq_ruta_paradas_select_auth_v1" on public."ruta_paradas" as PERMISSIVE for SELECT to authenticated using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM rutas r
  WHERE ((r.id = ruta_paradas.ruta_id) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) AND (EXISTS ( SELECT 1
           FROM usuarios u
          WHERE ((u.auth_uid = ( SELECT auth.uid() AS uid)) AND (coalesce(u.empleado_id, (select min(e.id) from public.empleados e where e.usuario_id=u.id having count(*)=1)) = r.empleado_id)))))))))));
grant SELECT on public."ruta_paradas" to authenticated;
grant select on public.ruta_paradas to anon;
create policy aq_principal_select on public.ruta_paradas for select to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and exists (select 1 from public.rutas r where r.id=ruta_paradas.ruta_id and r.empleado_id=(select aquabri_private.empleado_de_sesion_principal())))));
grant insert on public.ruta_paradas to anon;
create policy aq_principal_insert on public.ruta_paradas for insert to anon with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and exists (select 1 from public.rutas r where r.id=ruta_paradas.ruta_id and r.empleado_id=(select aquabri_private.empleado_de_sesion_principal())))));
grant update on public.ruta_paradas to anon;
create policy aq_principal_update on public.ruta_paradas for update to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and exists (select 1 from public.rutas r where r.id=ruta_paradas.ruta_id and r.empleado_id=(select aquabri_private.empleado_de_sesion_principal()))))) with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and exists (select 1 from public.rutas r where r.id=ruta_paradas.ruta_id and r.empleado_id=(select aquabri_private.empleado_de_sesion_principal())))));
grant delete on public.ruta_paradas to anon;
create policy aq_principal_delete on public.ruta_paradas for delete to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and exists (select 1 from public.rutas r where r.id=ruta_paradas.ruta_id and r.empleado_id=(select aquabri_private.empleado_de_sesion_principal())))));

alter table public."rutas_personalizadas" enable row level security;
revoke all on public."rutas_personalizadas" from public, anon, authenticated;
create policy "aq_rutas_personalizadas_lectura_auth" on public."rutas_personalizadas" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) OR ( SELECT aquabri_private.tiene_permiso_actual('ventas'::text) AS tiene_permiso_actual)));
grant SELECT on public."rutas_personalizadas" to authenticated;
grant select on public.rutas_personalizadas to anon;
create policy aq_principal_select on public.rutas_personalizadas for select to anon using (((select aquabri_private.permiso_sesion_principal('mapa')) or (select aquabri_private.permiso_sesion_principal('ventas'))));
grant insert on public.rutas_personalizadas to anon;
create policy aq_principal_insert on public.rutas_personalizadas for insert to anon with check ((select aquabri_private.permiso_sesion_principal('mapa')));
grant delete on public.rutas_personalizadas to anon;
create policy aq_principal_delete on public.rutas_personalizadas for delete to anon using ((select aquabri_private.permiso_sesion_principal('mapa')));

alter table public."visitas" enable row level security;
revoke all on public."visitas" from public, anon, authenticated;
create policy "aq_visitas_lectura_auth" on public."visitas" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));
grant SELECT on public."visitas" to authenticated;
grant select on public.visitas to anon;
create policy aq_principal_select on public.visitas for select to anon using (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or usuario_id = (select public.aq_sesion_legacy_usuario_actual_v1())));
grant insert on public.visitas to anon;
create policy aq_principal_insert on public.visitas for insert to anon with check (((select public.aq_sesion_legacy_rol_v1()) = 'jefe' or usuario_id = (select public.aq_sesion_legacy_usuario_actual_v1())));
grant delete on public.visitas to anon;
create policy aq_principal_delete on public.visitas for delete to anon using ((select public.aq_sesion_legacy_rol_v1()) = 'jefe');
