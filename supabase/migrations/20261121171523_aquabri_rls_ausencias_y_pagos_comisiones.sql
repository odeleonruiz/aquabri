set local lock_timeout='2s';
alter table public."ausencias" enable row level security;
revoke all privileges on table public."ausencias" from public, anon, authenticated;
grant select on table public."ausencias" to authenticated;
create policy "aq_ausencias_rrhh_lectura_auth" on public."ausencias" as permissive
    for select to authenticated
    using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (EXISTS ( SELECT 1
   FROM public.empleados e
  WHERE ((e.id = ausencias.empleado_id) AND (e.usuario_id = ( SELECT aquabri_private.usuario_id_actual() AS usuario_id_actual)))))));
alter table public."pagos_comisiones" enable row level security;
revoke all privileges on table public."pagos_comisiones" from public, anon, authenticated;
grant select on table public."pagos_comisiones" to authenticated;
create policy "aq_pagos_comision_consulta_jefe_v1" on public."pagos_comisiones" as permissive
    for select to authenticated
    using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text)));

grant select,insert,update,delete on public.ausencias to anon;
grant select,insert,update(empleado_id) on public.pagos_comisiones to anon;
create policy aq_ausencias_sesion_jefe on public.ausencias for all to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
create policy aq_ausencias_sesion_propia on public.ausencias for select to anon using (exists(select 1 from public.empleados e where e.id=empleado_id and e.usuario_id=(select public.aq_sesion_legacy_usuario_actual_v1())));
create policy aq_comisiones_sesion_jefe on public.pagos_comisiones for all to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
