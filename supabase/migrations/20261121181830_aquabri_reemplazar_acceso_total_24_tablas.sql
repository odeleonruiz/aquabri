set local lock_timeout='1500ms';
set local statement_timeout='30s';

revoke all on public.activos_cat from public,anon,authenticated;
drop policy "acceso_total_activos_cat" on public.activos_cat;
create policy "aq_activos_cat_lectura_auth" on public."activos_cat" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('activos'::text) AS tiene_permiso_actual)));
grant SELECT on public."activos_cat" to authenticated;
grant select on public.activos_cat to anon;
create policy aq_principal_select on public.activos_cat for select to anon using ((select aquabri_private.permiso_sesion_principal('activos')));
grant insert on public.activos_cat to anon;
create policy aq_principal_insert on public.activos_cat for insert to anon with check ((select aquabri_private.permiso_sesion_principal('activos')));
grant update on public.activos_cat to anon;
create policy aq_principal_update on public.activos_cat for update to anon using ((select aquabri_private.permiso_sesion_principal('activos'))) with check ((select aquabri_private.permiso_sesion_principal('activos')));
grant delete on public.activos_cat to anon;
create policy aq_principal_delete on public.activos_cat for delete to anon using ((select aquabri_private.permiso_sesion_principal('activos')));

revoke all on public.carga_items from public,anon,authenticated;
drop policy "acceso_total_carga_items" on public.carga_items;
create policy "aq_carga_items_lectura_auth" on public."carga_items" as PERMISSIVE for SELECT to authenticated using ((EXISTS ( SELECT 1
   FROM cargas c
  WHERE (c.id = carga_items.carga_id))));
grant SELECT on public."carga_items" to authenticated;
grant select on public.carga_items to anon;
create policy aq_principal_select on public.carga_items for select to anon using (exists(select 1 from public.cargas p where p.id=carga_items.carga_id));
grant insert on public.carga_items to anon;
create policy aq_principal_insert on public.carga_items for insert to anon with check (exists(select 1 from public.cargas p where p.id=carga_items.carga_id));
grant update on public.carga_items to anon;
create policy aq_principal_update on public.carga_items for update to anon using (exists(select 1 from public.cargas p where p.id=carga_items.carga_id)) with check (exists(select 1 from public.cargas p where p.id=carga_items.carga_id));
grant delete on public.carga_items to anon;
create policy aq_principal_delete on public.carga_items for delete to anon using (exists(select 1 from public.cargas p where p.id=carga_items.carga_id));

revoke all on public.cargas from public,anon,authenticated;
drop policy "acceso_total_cargas" on public.cargas;
create policy "aq_cargas_lectura_auth" on public."cargas" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = cargas.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));
grant SELECT on public."cargas" to authenticated;
grant select on public.cargas to anon;
create policy aq_principal_select on public.cargas for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('vehiculos')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));
grant insert on public.cargas to anon;
create policy aq_principal_insert on public.cargas for insert to anon with check (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('vehiculos')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));
grant update on public.cargas to anon;
create policy aq_principal_update on public.cargas for update to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('vehiculos')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal())))) with check (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('vehiculos')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));
grant delete on public.cargas to anon;
create policy aq_principal_delete on public.cargas for delete to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('vehiculos')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));

revoke all on public.categorias from public,anon,authenticated;
drop policy "acceso_total_categorias" on public.categorias;
create policy "aq_categorias_lectura_auth" on public."categorias" as PERMISSIVE for SELECT to authenticated using ((( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual) IS NOT NULL));
grant SELECT on public."categorias" to authenticated;
grant select on public.categorias to anon;
create policy aq_principal_select on public.categorias for select to anon using ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null);
grant insert on public.categorias to anon;
create policy aq_principal_insert on public.categorias for insert to anon with check ((select aquabri_private.permiso_sesion_principal('inventario')));
grant delete on public.categorias to anon;
create policy aq_principal_delete on public.categorias for delete to anon using ((select aquabri_private.permiso_sesion_principal('inventario')));

revoke all on public.comisiones from public,anon,authenticated;
drop policy "acceso_total_comisiones" on public.comisiones;
create policy "aq_comisiones_lectura_auth" on public."comisiones" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = comisiones.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));
grant SELECT on public."comisiones" to authenticated;
grant select on public.comisiones to anon;
create policy aq_principal_select on public.comisiones for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or empleado_id=(select aquabri_private.empleado_de_sesion_principal())));
grant insert on public.comisiones to anon;
create policy aq_principal_insert on public.comisiones for insert to anon with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant update on public.comisiones to anon;
create policy aq_principal_update on public.comisiones for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant delete on public.comisiones to anon;
create policy aq_principal_delete on public.comisiones for delete to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.config from public,anon,authenticated;
drop policy "acceso_total_config" on public.config;
create policy "aq_config_lectura_auth" on public."config" as PERMISSIVE for SELECT to authenticated using ((( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual) IS NOT NULL));
grant SELECT on public."config" to authenticated;
grant select on public.config to anon;
create policy aq_principal_select on public.config for select to anon using ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null);
grant update on public.config to anon;
create policy aq_principal_update on public.config for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.empleados from public,anon,authenticated;
drop policy "acceso_total_empleados" on public.empleados;
create policy "aq_empleados_lectura_auth" on public."empleados" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual))));
grant SELECT on public."empleados" to authenticated;
grant select on public.empleados to anon;
create policy aq_principal_select on public.empleados for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()) or id=(select aquabri_private.empleado_de_sesion_principal())));
grant insert on public.empleados to anon;
create policy aq_principal_insert on public.empleados for insert to anon with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant update on public.empleados to anon;
create policy aq_principal_update on public.empleados for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant delete on public.empleados to anon;
create policy aq_principal_delete on public.empleados for delete to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.envases_bodega from public,anon,authenticated;
drop policy "acceso_total_envases_bodega" on public.envases_bodega;
create policy "aq_envases_bodega_lectura_permiso" on public."envases_bodega" as PERMISSIVE for SELECT to authenticated using (( SELECT aquabri_private.tiene_permiso_actual('envases'::text) AS tiene_permiso_actual));
grant SELECT on public."envases_bodega" to authenticated;
grant select on public.envases_bodega to anon;
create policy aq_principal_select on public.envases_bodega for select to anon using ((select aquabri_private.permiso_sesion_principal('envases')));
grant update on public.envases_bodega to anon;
create policy aq_principal_update on public.envases_bodega for update to anon using ((select aquabri_private.permiso_sesion_principal('envases'))) with check ((select aquabri_private.permiso_sesion_principal('envases')));

revoke all on public.factura_items from public,anon,authenticated;
drop policy "acceso_total_factura_items" on public.factura_items;
create policy "aq_factura_items_lectura_jefe" on public."factura_items" as PERMISSIVE for SELECT to authenticated using ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
create policy "aq_factura_items_lectura_permiso" on public."factura_items" as PERMISSIVE for SELECT to authenticated using (( SELECT aquabri_private.tiene_permiso_actual('facturas'::text) AS tiene_permiso_actual));
grant SELECT on public."factura_items" to authenticated;
grant select on public.factura_items to anon;
create policy aq_principal_select on public.factura_items for select to anon using ((select aquabri_private.permiso_sesion_principal('facturas')));

revoke all on public.facturas_proveedores from public,anon,authenticated;
drop policy "acceso_total_facturas_proveedores" on public.facturas_proveedores;
create policy "aq_facturas_lectura_jefe" on public."facturas_proveedores" as PERMISSIVE for SELECT to authenticated using ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
create policy "aq_facturas_lectura_permiso" on public."facturas_proveedores" as PERMISSIVE for SELECT to authenticated using (( SELECT aquabri_private.tiene_permiso_actual('facturas'::text) AS tiene_permiso_actual));
grant SELECT on public."facturas_proveedores" to authenticated;
grant select on public.facturas_proveedores to anon;
create policy aq_principal_select on public.facturas_proveedores for select to anon using (((select aquabri_private.permiso_sesion_principal('facturas')) or (select aquabri_private.permiso_sesion_principal('proveedores.ver'))));

revoke all on public.gastos from public,anon,authenticated;
drop policy "acceso_total_gastos" on public.gastos;
create policy "aq_gastos_lectura_jefe" on public."gastos" as PERMISSIVE for SELECT to authenticated using ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
create policy "aq_gastos_lectura_permiso" on public."gastos" as PERMISSIVE for SELECT to authenticated using (( SELECT aquabri_private.tiene_permiso_actual('gastos'::text) AS tiene_permiso_actual));
grant SELECT on public."gastos" to authenticated;
grant select on public.gastos to anon;
create policy aq_principal_select on public.gastos for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('gastos')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));
grant insert on public.gastos to anon;
create policy aq_principal_insert on public.gastos for insert to anon with check (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('gastos')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));
grant update on public.gastos to anon;
create policy aq_principal_update on public.gastos for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.insumos from public,anon,authenticated;
drop policy "acceso_total_insumos" on public.insumos;
create policy "aq_insumos_lectura_autorizada" on public."insumos" as PERMISSIVE for SELECT to authenticated using (( SELECT aquabri_private.tiene_permiso_actual('inventario'::text) AS tiene_permiso_actual));
grant SELECT on public."insumos" to authenticated;
grant select on public.insumos to anon;
create policy aq_principal_select on public.insumos for select to anon using (((select aquabri_private.permiso_sesion_principal('inventario')) or (select aquabri_private.permiso_sesion_principal('ventas.registrar'))));
grant insert on public.insumos to anon;
create policy aq_principal_insert on public.insumos for insert to anon with check ((select aquabri_private.permiso_sesion_principal('inventario')));
grant update on public.insumos to anon;
create policy aq_principal_update on public.insumos for update to anon using (((select aquabri_private.permiso_sesion_principal('inventario')) or (select aquabri_private.permiso_sesion_principal('vehiculos')) or (select aquabri_private.permiso_sesion_principal('ventas.registrar')))) with check (((select aquabri_private.permiso_sesion_principal('inventario')) or (select aquabri_private.permiso_sesion_principal('vehiculos')) or (select aquabri_private.permiso_sesion_principal('ventas.registrar'))));
grant delete on public.insumos to anon;
create policy aq_principal_delete on public.insumos for delete to anon using ((select aquabri_private.permiso_sesion_principal('inventario')));

revoke all on public.mensajes from public,anon,authenticated;
drop policy "acceso_total_mensajes" on public.mensajes;

grant select on public.mensajes to anon;
create policy aq_principal_select on public.mensajes for select to anon using (((select aquabri_private.permiso_sesion_principal('chat')) and ((select public.aq_sesion_legacy_rol_v1())='jefe' or tipo='general' or de_usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()) or para_usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()))));
grant insert on public.mensajes to anon;
create policy aq_principal_insert on public.mensajes for insert to anon with check ((((select aquabri_private.permiso_sesion_principal('chat')) and de_usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1())) and ((tipo='general' and para_usuario_id is null) or (tipo='privado' and para_usuario_id is not null))));
grant update (contenido,editado,leido) on public.mensajes to anon;
create policy aq_principal_update on public.mensajes for update to anon using (((select aquabri_private.permiso_sesion_principal('chat')) and ((select public.aq_sesion_legacy_rol_v1())='jefe' or tipo='general' or de_usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()) or para_usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1())))) with check (((select aquabri_private.permiso_sesion_principal('chat')) and ((select public.aq_sesion_legacy_rol_v1())='jefe' or tipo='general' or de_usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()) or para_usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()))));
grant delete on public.mensajes to anon;
create policy aq_principal_delete on public.mensajes for delete to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('chat')) and de_usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()))));

revoke all on public.metas from public,anon,authenticated;
drop policy "acceso_total_metas" on public.metas;
create policy "aq_metas_lectura_permiso" on public."metas" as PERMISSIVE for SELECT to authenticated using (( SELECT aquabri_private.tiene_permiso_actual('metas'::text) AS tiene_permiso_actual));
grant SELECT on public."metas" to authenticated;
grant select on public.metas to anon;
create policy aq_principal_select on public.metas for select to anon using ((select aquabri_private.permiso_sesion_principal('metas')));
grant insert on public.metas to anon;
create policy aq_principal_insert on public.metas for insert to anon with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant update on public.metas to anon;
create policy aq_principal_update on public.metas for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.metas_empleados from public,anon,authenticated;
drop policy "acceso_total_metas_empleados" on public.metas_empleados;
create policy "aq_meta_empleado_lectura_jefe" on public."metas_empleados" as PERMISSIVE for SELECT to authenticated using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));
grant SELECT on public."metas_empleados" to authenticated;
grant select on public.metas_empleados to anon;
create policy aq_principal_select on public.metas_empleados for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or empleado_id=(select aquabri_private.empleado_de_sesion_principal())));
grant insert on public.metas_empleados to anon;
create policy aq_principal_insert on public.metas_empleados for insert to anon with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant update on public.metas_empleados to anon;
create policy aq_principal_update on public.metas_empleados for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant delete on public.metas_empleados to anon;
create policy aq_principal_delete on public.metas_empleados for delete to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.pagos from public,anon,authenticated;
drop policy "acceso_total_pagos" on public.pagos;
create policy "aq_pagos_rrhh_lectura_auth" on public."pagos" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = pagos.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));
grant SELECT on public."pagos" to authenticated;
grant select on public.pagos to anon;
create policy aq_principal_select on public.pagos for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or empleado_id=(select aquabri_private.empleado_de_sesion_principal())));
grant insert on public.pagos to anon;
create policy aq_principal_insert on public.pagos for insert to anon with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant update on public.pagos to anon;
create policy aq_principal_update on public.pagos for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.producto_insumos from public,anon,authenticated;
drop policy "acceso_total_producto_insumos" on public.producto_insumos;
create policy "aq_producto_insumos_lectura_auth" on public."producto_insumos" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('inventario'::text) AS tiene_permiso_actual)));
grant SELECT on public."producto_insumos" to authenticated;
grant select on public.producto_insumos to anon;
create policy aq_principal_select on public.producto_insumos for select to anon using (((select aquabri_private.permiso_sesion_principal('inventario')) or (select aquabri_private.permiso_sesion_principal('ventas.registrar'))));
grant insert on public.producto_insumos to anon;
create policy aq_principal_insert on public.producto_insumos for insert to anon with check ((select aquabri_private.permiso_sesion_principal('inventario')));
grant delete on public.producto_insumos to anon;
create policy aq_principal_delete on public.producto_insumos for delete to anon using ((select aquabri_private.permiso_sesion_principal('inventario')));

revoke all on public.productos from public,anon,authenticated;
drop policy "acceso_total_productos" on public.productos;
create policy "aq_productos_select_usuario_vinculado" on public."productos" as PERMISSIVE for SELECT to authenticated using ((( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual) IS NOT NULL));
grant SELECT on public."productos" to authenticated;
grant SELECT ("id") on public."productos" to authenticated;
grant SELECT ("nombre") on public."productos" to authenticated;
grant SELECT ("cat") on public."productos" to authenticated;
grant SELECT ("precio") on public."productos" to authenticated;
grant SELECT ("stock") on public."productos" to authenticated;
grant SELECT ("minstock") on public."productos" to authenticated;
grant SELECT ("retornable") on public."productos" to authenticated;
grant SELECT ("oferta_precio") on public."productos" to authenticated;
grant SELECT ("oferta_desc") on public."productos" to authenticated;
grant SELECT ("bonif_desc") on public."productos" to authenticated;
grant SELECT ("bonif_prod") on public."productos" to authenticated;
grant SELECT ("bonif_cant") on public."productos" to authenticated;
grant SELECT ("categoria") on public."productos" to authenticated;
grant SELECT ("activo") on public."productos" to authenticated;
grant SELECT ("uds_paquete") on public."productos" to authenticated;
grant select on public.productos to anon;
create policy aq_principal_select on public.productos for select to anon using ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null);
grant insert on public.productos to anon;
create policy aq_principal_insert on public.productos for insert to anon with check ((select aquabri_private.permiso_sesion_principal('inventario')));
grant update on public.productos to anon;
create policy aq_principal_update on public.productos for update to anon using (((select aquabri_private.permiso_sesion_principal('inventario')) or (select aquabri_private.permiso_sesion_principal('vehiculos')) or (select aquabri_private.permiso_sesion_principal('ventas.registrar')))) with check (((select aquabri_private.permiso_sesion_principal('inventario')) or (select aquabri_private.permiso_sesion_principal('vehiculos')) or (select aquabri_private.permiso_sesion_principal('ventas.registrar'))));
grant delete on public.productos to anon;
create policy aq_principal_delete on public.productos for delete to anon using ((select aquabri_private.permiso_sesion_principal('inventario')));

revoke all on public.puntos_config from public,anon,authenticated;
drop policy "acceso_puntos_config" on public.puntos_config;
create policy "aq_puntos_config_lectura_permiso" on public."puntos_config" as PERMISSIVE for SELECT to authenticated using (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual));
grant SELECT on public."puntos_config" to authenticated;
grant select on public.puntos_config to anon;
create policy aq_principal_select on public.puntos_config for select to anon using (((select aquabri_private.permiso_sesion_principal('puntos')) or (select aquabri_private.permiso_sesion_principal('ventas'))));
grant insert on public.puntos_config to anon;
create policy aq_principal_insert on public.puntos_config for insert to anon with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant update on public.puntos_config to anon;
create policy aq_principal_update on public.puntos_config for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.rutas from public,anon,authenticated;
drop policy "acceso_total_rutas" on public.rutas;
create policy "aq_rutas_select_auth_v1" on public."rutas" as PERMISSIVE for SELECT to authenticated using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) AND (EXISTS ( SELECT 1
   FROM usuarios u
  WHERE ((u.auth_uid = ( SELECT auth.uid() AS uid)) AND (coalesce(u.empleado_id, (select min(e.id) from public.empleados e where e.usuario_id=u.id having count(*)=1)) = rutas.empleado_id))))))));
grant SELECT on public."rutas" to authenticated;
grant select on public.rutas to anon;
create policy aq_principal_select on public.rutas for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));
grant insert on public.rutas to anon;
create policy aq_principal_insert on public.rutas for insert to anon with check (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));
grant update on public.rutas to anon;
create policy aq_principal_update on public.rutas for update to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal())))) with check (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));
grant delete on public.rutas to anon;
create policy aq_principal_delete on public.rutas for delete to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('mapa')) and empleado_id=(select aquabri_private.empleado_de_sesion_principal()))));

revoke all on public.vales from public,anon,authenticated;
drop policy "acceso_total_vales" on public.vales;
create policy "aq_vales_rrhh_lectura_auth" on public."vales" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM empleados e
  WHERE ((e.id = vales.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));
grant SELECT on public."vales" to authenticated;
grant select on public.vales to anon;
create policy aq_principal_select on public.vales for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or empleado_id=(select aquabri_private.empleado_de_sesion_principal())));
grant insert on public.vales to anon;
create policy aq_principal_insert on public.vales for insert to anon with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant update on public.vales to anon;
create policy aq_principal_update on public.vales for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
grant delete on public.vales to anon;
create policy aq_principal_delete on public.vales for delete to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe');

revoke all on public.vehiculos from public,anon,authenticated;
drop policy "acceso_total_vehiculos" on public.vehiculos;
create policy "aq_vehiculos_alta_jefe" on public."vehiculos" as PERMISSIVE for INSERT to authenticated with check ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
create policy "aq_vehiculos_edicion_jefe" on public."vehiculos" as PERMISSIVE for UPDATE to authenticated using ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)) with check ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text));
create policy "aq_vehiculos_lectura_auth" on public."vehiculos" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR ( SELECT aquabri_private.tiene_permiso_actual('vehiculos'::text) AS tiene_permiso_actual)));
grant SELECT on public."vehiculos" to authenticated;
grant INSERT ("nombre") on public."vehiculos" to authenticated;
grant UPDATE ("nombre") on public."vehiculos" to authenticated;
grant INSERT ("placa") on public."vehiculos" to authenticated;
grant UPDATE ("placa") on public."vehiculos" to authenticated;
grant INSERT ("tipo") on public."vehiculos" to authenticated;
grant UPDATE ("tipo") on public."vehiculos" to authenticated;
grant INSERT ("capacidad") on public."vehiculos" to authenticated;
grant UPDATE ("capacidad") on public."vehiculos" to authenticated;
grant INSERT ("estado") on public."vehiculos" to authenticated;
grant UPDATE ("estado") on public."vehiculos" to authenticated;
grant INSERT ("notas") on public."vehiculos" to authenticated;
grant UPDATE ("notas") on public."vehiculos" to authenticated;
grant INSERT ("tarjeta_circulacion") on public."vehiculos" to authenticated;
grant UPDATE ("tarjeta_circulacion") on public."vehiculos" to authenticated;
grant select on public.vehiculos to anon;
create policy aq_principal_select on public.vehiculos for select to anon using (((select aquabri_private.permiso_sesion_principal('vehiculos')) or (select aquabri_private.permiso_sesion_principal('mapa'))));
grant insert on public.vehiculos to anon;
create policy aq_principal_insert on public.vehiculos for insert to anon with check ((select aquabri_private.permiso_sesion_principal('vehiculos')));
grant update on public.vehiculos to anon;
create policy aq_principal_update on public.vehiculos for update to anon using ((select aquabri_private.permiso_sesion_principal('vehiculos'))) with check ((select aquabri_private.permiso_sesion_principal('vehiculos')));
grant delete on public.vehiculos to anon;
create policy aq_principal_delete on public.vehiculos for delete to anon using ((select aquabri_private.permiso_sesion_principal('vehiculos')));

revoke all on public.venta_items from public,anon,authenticated;
drop policy "acceso_total_venta_items" on public.venta_items;
create policy "aq_venta_items_lectura_auth" on public."venta_items" as PERMISSIVE for SELECT to authenticated using ((EXISTS ( SELECT 1
   FROM ventas v
  WHERE (v.id = venta_items.venta_id))));
grant SELECT on public."venta_items" to authenticated;
grant select on public.venta_items to anon;
create policy aq_principal_select on public.venta_items for select to anon using (exists(select 1 from public.ventas p where p.id=venta_items.venta_id));
grant insert on public.venta_items to anon;
create policy aq_principal_insert on public.venta_items for insert to anon with check (exists(select 1 from public.ventas p where p.id=venta_items.venta_id));
grant update on public.venta_items to anon;
create policy aq_principal_update on public.venta_items for update to anon using (exists(select 1 from public.ventas p where p.id=venta_items.venta_id)) with check (exists(select 1 from public.ventas p where p.id=venta_items.venta_id));
grant delete on public.venta_items to anon;
create policy aq_principal_delete on public.venta_items for delete to anon using (exists(select 1 from public.ventas p where p.id=venta_items.venta_id));

revoke all on public.ventas from public,anon,authenticated;
drop policy "acceso_total_ventas" on public.ventas;
create policy "aq_ventas_lectura_auth" on public."ventas" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('ventas'::text) AS tiene_permiso_actual) AND (usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))));
grant SELECT on public."ventas" to authenticated;
grant select on public.ventas to anon;
create policy aq_principal_select on public.ventas for select to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('ventas')) and usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()))));
grant insert on public.ventas to anon;
create policy aq_principal_insert on public.ventas for insert to anon with check (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('ventas')) and usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()))));
grant update on public.ventas to anon;
create policy aq_principal_update on public.ventas for update to anon using (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('ventas')) and usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1())))) with check (((select public.aq_sesion_legacy_rol_v1())='jefe' or ((select aquabri_private.permiso_sesion_principal('ventas')) and usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1()))));

create function aquabri_private.limitar_edicion_principal() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_user <> 'anon' then return new; end if;
  if tg_table_name='mensajes' then
    if old.de_usuario_id is distinct from public.aq_sesion_legacy_usuario_actual_v1()
       and (to_jsonb(new)-'leido') is distinct from (to_jsonb(old)-'leido') then
      raise exception 'Solo el remitente puede editar el mensaje' using errcode='42501';
    end if;
  elsif public.aq_sesion_legacy_rol_v1() not in ('jefe','inventario')
     and (to_jsonb(new)-'stock') is distinct from (to_jsonb(old)-'stock') then
    raise exception 'Solo inventario puede cambiar el catálogo' using errcode='42501';
  end if;
  return new;
end $$;
revoke all on function aquabri_private.limitar_edicion_principal() from public,anon,authenticated,service_role;
create trigger aq_limitar_edicion_principal before update on public.productos for each row execute function aquabri_private.limitar_edicion_principal();
create trigger aq_limitar_edicion_principal before update on public.insumos for each row execute function aquabri_private.limitar_edicion_principal();
create trigger aq_limitar_edicion_principal before update on public.mensajes for each row execute function aquabri_private.limitar_edicion_principal();
create function aquabri_private.atribuir_venta_sesion_principal() returns trigger language plpgsql set search_path='' as $$
begin
  if current_user='anon' and new.usuario_id is null then
    new.usuario_id:=public.aq_sesion_legacy_usuario_actual_v1();
  end if;
  return new;
end $$;
revoke all on function aquabri_private.atribuir_venta_sesion_principal() from public,anon,authenticated,service_role;
create trigger aq_atribuir_venta_sesion_principal before insert on public.ventas for each row execute function aquabri_private.atribuir_venta_sesion_principal();
