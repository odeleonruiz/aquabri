CREATE OR REPLACE FUNCTION public.aq_devengar_incentivo_item(p_item bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_item public.venta_items%rowtype; v_venta record; v_inc record; v_eq record; v_real numeric; v_monto numeric; v_a numeric;
begin
 select * into v_item from public.venta_items where id=p_item;
 if not found then return; end if;
 if v_item.producto_id is null or v_item.cant is null or v_item.cant<=0 then return; end if;
 select id,cliente_id,fecha,estado,notas,usuario_id into v_venta from public.ventas where id=v_item.venta_id;
 if v_venta.cliente_id is null or v_venta.estado in ('Cancelada','Anulado')
  or (v_venta.estado='Pendiente' and coalesce(v_venta.notas,'') like '📦 PEDIDO:%') then return; end if;
 v_real:=coalesce(v_item.precio,0)-coalesce(v_item.descuento,0);
 select * into v_inc from public.aq_incentivos_captacion
  where cliente_id=v_venta.cliente_id and producto_id=v_item.producto_id and activo=true
  and captacion_confirmada=true and desde<=v_venta.fecha and (hasta is null or hasta>=v_venta.fecha)
  -- Reactivaciones solo generan comisión en ventas creadas DESPUÉS de reactivar;
  -- ventas preexistentes (incluidas las del mismo día) no se recalculan.
  and (reactivacion_origen_id is null or (venta_id_inicio is not null and v_venta.id>venta_id_inicio))
  and precio_minimo<=v_real order by id desc limit 1;
 if not found then return; end if;
 -- Regla esencial: el incentivo NO se hereda por el cliente o la ruta.
 -- Solo se devenga si el usuario que REGISTRÓ la venta pertenece a los beneficiarios.
 -- El jefe o un usuario ajeno no genera incentivo especial, aunque venda a Q9 o más.
 if v_venta.usuario_id is null then return; end if;
 if v_inc.modalidad='individual' then
   if not exists(select 1 from public.empleados e
     where e.id=v_inc.beneficiario_empleado_id and e.usuario_id=v_venta.usuario_id)
   then return; end if;
 else
   select * into v_eq from public.aq_equipos_incentivo where id=v_inc.equipo_id;
   if not found then return; end if;
   if not exists(select 1 from public.empleados e
     where e.id in (v_eq.empleado_a_id,v_eq.empleado_b_id) and e.usuario_id=v_venta.usuario_id)
   then return; end if;
 end if;
 v_monto:=round(v_inc.monto_unitario*v_item.cant,2);
 if v_inc.modalidad='individual' then
  insert into public.aq_incentivos_devengados(incentivo_id,venta_id,venta_item_id,cliente_id,empleado_id,fecha,cantidad,precio_venta,incentivo_por_unidad,importe_empleado,modalidad)
  values(v_inc.id,v_item.venta_id,v_item.id,v_venta.cliente_id,v_inc.beneficiario_empleado_id,v_venta.fecha,v_item.cant,v_real,v_inc.monto_unitario,v_monto,'individual')
  on conflict(venta_item_id,empleado_id) do nothing;
 else
  v_a:=floor(v_monto*100/2)/100.0;
  insert into public.aq_incentivos_devengados(incentivo_id,venta_id,venta_item_id,cliente_id,empleado_id,fecha,cantidad,precio_venta,incentivo_por_unidad,importe_empleado,modalidad)
   values(v_inc.id,v_item.venta_id,v_item.id,v_venta.cliente_id,v_eq.empleado_a_id,v_venta.fecha,v_item.cant,v_real,v_inc.monto_unitario,v_a,'equipo'),
         (v_inc.id,v_item.venta_id,v_item.id,v_venta.cliente_id,v_eq.empleado_b_id,v_venta.fecha,v_item.cant,v_real,v_inc.monto_unitario,v_monto-v_a,'equipo')
   on conflict(venta_item_id,empleado_id) do nothing;
 end if;
 return;
end $function$
