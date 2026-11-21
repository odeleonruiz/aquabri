set local lock_timeout='2s';
create function public.aq_mantenimiento_auth_v1(p_accion text,p_datos jsonb,p_id integer default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare m public.mantenimientos%rowtype; nuevo integer; fecha date:=(now() at time zone 'America/Guatemala')::date;
begin
 if aquabri_private.rol_actual() is distinct from 'jefe' then raise exception 'Solo el jefe administra mantenimiento' using errcode='42501'; end if;
 if p_id is not null then
  select * into m from public.mantenimientos where id=p_id for update;
  if not found then raise exception 'Servicio inexistente'; end if;
 end if;
 if p_accion='completar' and p_id is not null then
  if m.estado='Completado' then return jsonb_build_object('ok',true,'repetida',true); end if;
  update public.mantenimientos set estado='Completado',fecha_ultimo=fecha where id=p_id;
  insert into public.mantenimientos(vehiculo_id,tipo,descripcion,fecha_ultimo,fecha_proximo,intervalo_dias,costo,notas,estado)
  values(m.vehiculo_id,m.tipo,m.descripcion,fecha,fecha+greatest(coalesce(m.intervalo_dias,90),1),m.intervalo_dias,m.costo,m.notas,'Pendiente') returning id into nuevo;
 elsif p_accion='eliminar' and p_id is not null then
  delete from public.mantenimientos where id=p_id;
 elsif p_accion='guardar' then
  if coalesce(trim(p_datos->>'tipo'),'')='' or (p_datos->>'fecha_proximo')::date is null
   or coalesce((p_datos->>'costo')::numeric,0)<0 or coalesce((p_datos->>'intervalo_dias')::integer,90)<1 then raise exception 'Datos de mantenimiento inválidos'; end if;
  if p_id is null then
   insert into public.mantenimientos(vehiculo_id,tipo,descripcion,fecha_ultimo,fecha_proximo,intervalo_dias,costo,notas,estado)
   values((p_datos->>'vehiculo_id')::integer,p_datos->>'tipo',p_datos->>'descripcion',(p_datos->>'fecha_ultimo')::date,(p_datos->>'fecha_proximo')::date,coalesce((p_datos->>'intervalo_dias')::integer,90),coalesce((p_datos->>'costo')::numeric,0),p_datos->>'notas','Pendiente') returning id into nuevo;
  else
   update public.mantenimientos set vehiculo_id=(p_datos->>'vehiculo_id')::integer,tipo=p_datos->>'tipo',descripcion=p_datos->>'descripcion',fecha_ultimo=(p_datos->>'fecha_ultimo')::date,fecha_proximo=(p_datos->>'fecha_proximo')::date,intervalo_dias=coalesce((p_datos->>'intervalo_dias')::integer,90),costo=coalesce((p_datos->>'costo')::numeric,0),notas=p_datos->>'notas' where id=p_id;
   nuevo:=p_id;
  end if;
 else raise exception 'Acción inválida'; end if;
 return jsonb_build_object('ok',true,'id',nuevo);
end $f$;
revoke all on function public.aq_mantenimiento_auth_v1(text,jsonb,integer) from public,anon,authenticated,service_role;

create function public.aq_notificar_auth_v1(p_usuario integer,p_titulo text,p_mensaje text,p_tipo text default 'info',p_datos jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare actor integer:=aquabri_private.usuario_id_actual(); destino text;
begin
 select rol into destino from public.usuarios where id=p_usuario;
 if actor is null or destino is null or (actor<>p_usuario and aquabri_private.rol_actual()<>'jefe' and (destino<>'jefe' or p_tipo<>'pedido')) then raise exception 'Notificación no autorizada' using errcode='42501'; end if;
 if length(p_titulo)>200 or length(p_mensaje)>2000 or octet_length(p_datos::text)>10000 then raise exception 'Notificación demasiado larga'; end if;
 insert into public.notificaciones(usuario_id,titulo,mensaje,tipo,datos,leida) values(p_usuario,p_titulo,p_mensaje,p_tipo,p_datos,false);
 return jsonb_build_object('ok',true);
end $f$;
revoke all on function public.aq_notificar_auth_v1(integer,text,text,text,jsonb) from public,anon,authenticated,service_role;

create function public.aq_rutas_guardadas_auth_v1(p_accion text,p_rutas jsonb default '[]',p_id integer default null)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare r jsonb; cid integer; rid integer; idx integer;
begin
 if aquabri_private.rol_actual() is distinct from 'jefe' then raise exception 'Solo el jefe administra rutas guardadas' using errcode='42501'; end if;
 if p_accion='guardar' then
  if jsonb_typeof(p_rutas)<>'array' or jsonb_array_length(p_rutas)>100 then raise exception 'Rutas inválidas'; end if;
  for r in select value from jsonb_array_elements(p_rutas) loop
   if coalesce(trim(r->>'nombre'),'')='' or jsonb_typeof(r->'clientes')<>'array' then raise exception 'Ruta incompleta'; end if;
   insert into public.rutas_personalizadas(nombre,color,dia_semana,activa) values(r->>'nombre',r->>'color',r->>'dia',true) returning id into rid;
   idx:=0;
   for cid in select value::integer from jsonb_array_elements_text(r->'clientes') loop
    if not exists(select 1 from public.clientes where id=cid) then raise exception 'Cliente inexistente'; end if;
    insert into public.ruta_clientes(ruta_id,cliente_id,orden) values(rid,cid,idx);
    idx:=idx+1;
   end loop;
  end loop;
 elsif p_accion='eliminar' and p_id is not null then
  delete from public.ruta_clientes where ruta_id=p_id;
  delete from public.rutas_personalizadas where id=p_id;
 elsif p_accion='limpiar' then
  delete from public.ruta_clientes where ruta_id in (select id from public.rutas_personalizadas);
  delete from public.rutas_personalizadas;
 else raise exception 'Acción inválida'; end if;
 return jsonb_build_object('ok',true);
end $f$;
revoke all on function public.aq_rutas_guardadas_auth_v1(text,jsonb,integer) from public,anon,authenticated,service_role;

create function aquabri_private.aq_precio_historial_auth()
returns trigger language plpgsql security definer set search_path='' as $f$
declare actor integer:=aquabri_private.usuario_id_actual(); nombre text;
begin
 if actor is not null and old.precio is distinct from new.precio then
  if aquabri_private.rol_actual() is distinct from 'jefe' then raise exception 'Solo el jefe cambia precios de catálogo' using errcode='42501'; end if;
  select u.nombre into nombre from public.usuarios u where id=actor;
  insert into public.precio_historial(producto_id,precio_anterior,precio_nuevo,fecha,usuario)
  values(new.id,old.precio,new.precio,(now() at time zone 'America/Guatemala')::date,nombre);
 end if;
 return new;
end $f$;
revoke all on function aquabri_private.aq_precio_historial_auth() from public,anon,authenticated,service_role;
