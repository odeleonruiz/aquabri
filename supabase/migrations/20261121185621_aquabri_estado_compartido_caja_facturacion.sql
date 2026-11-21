create function public.aq_estado_caja_facturacion_v1() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  hoy date := (now() at time zone 'America/Guatemala')::date;
  estado text;
  anterior date;
begin
  if public.aq_sesion_legacy_usuario_actual_v1() is null then
    raise exception 'Se requiere iniciar sesión' using errcode='42501';
  end if;
  select c.tipo into estado from public.caja c where c.fecha=hoy and c.tipo in ('apertura','cierre') order by c.id desc limit 1;
  select c.fecha into anterior from public.caja c where c.tipo='apertura' and c.fecha<hoy order by c.fecha desc,c.id desc limit 1;
  if (select c.tipo from public.caja c where c.fecha=anterior and c.tipo in ('apertura','cierre') order by c.id desc limit 1) is distinct from 'apertura' then
    anterior:=null;
  end if;
  return jsonb_build_object('estado',coalesce(estado,'sin_apertura'),'pendiente',anterior);
end;
$$;
revoke all on function public.aq_estado_caja_facturacion_v1() from public,anon,authenticated,service_role;
grant execute on function public.aq_estado_caja_facturacion_v1() to anon;
