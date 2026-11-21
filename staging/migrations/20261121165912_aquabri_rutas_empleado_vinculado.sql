alter policy "aq_ruta_paradas_select_auth_v1" on public."ruta_paradas" using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM rutas r
  WHERE ((r.id = ruta_paradas.ruta_id) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) AND (EXISTS ( SELECT 1
           FROM usuarios u
          WHERE ((u.auth_uid = ( SELECT auth.uid() AS uid)) AND (coalesce(u.empleado_id, (select min(e.id) from public.empleados e where e.usuario_id=u.id having count(*)=1)) = r.empleado_id)))))))))));
alter policy "aq_rutas_select_auth_v1" on public."rutas" using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('mapa'::text) AS tiene_permiso_actual) AND (EXISTS ( SELECT 1
   FROM usuarios u
  WHERE ((u.auth_uid = ( SELECT auth.uid() AS uid)) AND (coalesce(u.empleado_id, (select min(e.id) from public.empleados e where e.usuario_id=u.id having count(*)=1)) = rutas.empleado_id))))))));
