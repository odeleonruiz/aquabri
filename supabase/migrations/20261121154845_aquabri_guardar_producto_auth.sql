create function public.aq_guardar_producto_auth_v1(p_producto jsonb, p_insumos jsonb, p_id integer default null)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
  producto public.productos;
  id_guardado integer;
begin
  if aquabri_private.rol_actual() is distinct from 'jefe' then
    raise exception 'Solo el jefe puede guardar productos' using errcode='42501';
  end if;
  if jsonb_typeof(p_producto) is distinct from 'object'
     or jsonb_typeof(p_insumos) is distinct from 'array'
     or not (p_producto ?& array['nombre', 'cat', 'precio', 'costo', 'stock', 'minstock', 'retornable', 'oferta_precio', 'oferta_desc', 'bonif_desc', 'bonif_prod', 'bonif_cant', 'uds_paquete']) then
    raise exception 'Datos de producto incompletos';
  end if;
  producto := jsonb_populate_record(null::public.productos,p_producto);
  if nullif(trim(producto.nombre),'') is null or producto.uds_paquete < 1 then
    raise exception 'Nombre o unidades por paquete inválidos';
  end if;
  if exists (select 1 from jsonb_to_recordset(p_insumos) as i(insumo_id integer,cant numeric)
    left join public.insumos s on s.id=i.insumo_id where s.id is null or coalesce(i.cant,0)<=0) then
    raise exception 'Insumo o cantidad inválidos';
  end if;
  if p_id is null then
    insert into public.productos (nombre, cat, precio, costo, stock, minstock, retornable, oferta_precio, oferta_desc, bonif_desc, bonif_prod, bonif_cant, uds_paquete)
    values (producto.nombre, producto.cat, producto.precio, producto.costo, producto.stock, producto.minstock, producto.retornable, producto.oferta_precio, producto.oferta_desc, producto.bonif_desc, producto.bonif_prod, producto.bonif_cant, producto.uds_paquete) returning id into id_guardado;
  else
    update public.productos set
      nombre=producto.nombre,
      cat=producto.cat,
      precio=producto.precio,
      costo=producto.costo,
      stock=producto.stock,
      minstock=producto.minstock,
      retornable=producto.retornable,
      oferta_precio=producto.oferta_precio,
      oferta_desc=producto.oferta_desc,
      bonif_desc=producto.bonif_desc,
      bonif_prod=producto.bonif_prod,
      bonif_cant=producto.bonif_cant,
      uds_paquete=producto.uds_paquete
    where id=p_id returning id into strict id_guardado;
    delete from public.producto_insumos where producto_id=id_guardado;
  end if;
  insert into public.producto_insumos(producto_id,insumo_id,cant)
    select id_guardado,i.insumo_id,i.cant from jsonb_to_recordset(p_insumos) as i(insumo_id integer,cant numeric);
  return jsonb_build_object('ok',true,'id',id_guardado);
end $fn$;
revoke all on function public.aq_guardar_producto_auth_v1(jsonb,jsonb,integer) from public,anon,authenticated,service_role;
