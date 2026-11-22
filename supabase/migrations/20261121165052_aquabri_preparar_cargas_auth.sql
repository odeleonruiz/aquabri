CREATE FUNCTION aquabri_private.resumen_carga(p_carga integer)
 RETURNS TABLE(producto_id integer, cantidad integer, vendido integer, bonificado integer, importe numeric, incentivo numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  WITH movimientos AS (
    SELECT ci.producto_id, ci.cantidad::integer salida, 0 vendido, 0 bonificado, 0::numeric importe, 0::numeric incentivo
    FROM public.carga_items ci WHERE ci.carga_id = p_carga
    UNION ALL
    SELECT i.producto_id, 0, i.cant::integer, 0, x.neto,
           CASE WHEN EXISTS (SELECT 1 FROM public.aq_incentivos_devengados d WHERE d.venta_item_id = i.id)
                THEN x.neto ELSE 0 END
    FROM aquabri_private.ventas_de_carga l
    JOIN public.ventas v ON v.id = l.venta_id
    JOIN public.venta_items i ON i.venta_id = v.id
    CROSS JOIN LATERAL (
      SELECT greatest(0, i.cant * (i.precio - coalesce(i.descuento, 0))) bruto
    ) b
    CROSS JOIN LATERAL (
      SELECT sum(greatest(0, j.cant * (j.precio - coalesce(j.descuento, 0)))) total
      FROM public.venta_items j WHERE j.venta_id = v.id
    ) t
    CROSS JOIN LATERAL (
      SELECT round(CASE WHEN t.total > 0 THEN b.bruto * v.total / t.total ELSE 0 END, 6) neto
    ) x
    WHERE l.carga_id = p_carga
    UNION ALL
    SELECT coalesce(i.bonif_prod_id, i.producto_id), 0, 0, i.bonif_cant, 0, 0
    FROM aquabri_private.ventas_de_carga l JOIN public.venta_items i ON i.venta_id = l.venta_id
    WHERE l.carga_id = p_carga AND i.bonif_cant > 0
  )
  SELECT m.producto_id, sum(m.salida)::integer, sum(m.vendido)::integer,
         sum(m.bonificado)::integer, sum(m.importe), sum(m.incentivo)
  FROM movimientos m GROUP BY m.producto_id
$function$;
revoke all on function aquabri_private.resumen_carga(integer) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_guardar_carga_auth_v1(p_nonce uuid, p_carga integer, p_vehiculo integer, p_empleado integer, p_fecha date, p_descripcion text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_usuario integer := aquabri_private.usuario_id_actual();
  v_jefe boolean := aquabri_private.rol_actual() = 'jefe';
  v_solicitud jsonb;
  v_previa aquabri_private.carga_operaciones%ROWTYPE;
  v_carga public.cargas%ROWTYPE;
  v_item record;
  v_nombre text;
  v_item_id integer;
  v_numero integer;
  v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_usuario IS NULL
    OR NOT coalesce(v_jefe OR aquabri_private.tiene_permiso_actual('vehiculos'), false) THEN
    RAISE EXCEPTION 'Sin permiso para gestionar cargas' USING ERRCODE = '42501';
  END IF;
  IF p_nonce IS NULL OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Carga o productos inválidos' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Agrega entre 1 y 200 productos' USING ERRCODE = '22023';
  END IF;

  v_solicitud := jsonb_build_array(p_carga, p_vehiculo, p_empleado, p_fecha, p_descripcion, p_items);
  PERFORM pg_advisory_xact_lock(hashtextextended('aquabri-carga:' || p_nonce::text, 0));
  SELECT * INTO v_previa FROM aquabri_private.carga_operaciones WHERE nonce = p_nonce;
  IF FOUND THEN
    IF v_previa.usuario_id <> v_usuario OR v_previa.solicitud <> v_solicitud THEN
      RAISE EXCEPTION 'Identificador de operación reutilizado' USING ERRCODE = '22023';
    END IF;
    RETURN v_previa.resultado;
  END IF;

  IF p_carga IS NULL THEN
    IF p_fecha IS NULL OR NOT EXISTS (SELECT 1 FROM public.empleados WHERE id = p_empleado)
      OR length(coalesce(p_descripcion, '')) > 1500 THEN
      RAISE EXCEPTION 'Verifica el empleado, la fecha y la descripción' USING ERRCODE = '22023';
    END IF;
    v_carga.empleado_id := p_empleado;
  ELSE
    SELECT * INTO v_carga FROM public.cargas WHERE id = p_carga FOR UPDATE;
    IF NOT FOUND OR v_carga.estado IS DISTINCT FROM 'En Ruta' THEN
      RAISE EXCEPTION 'La carga debe estar en ruta' USING ERRCODE = '22023';
    END IF;
  END IF;
  IF NOT coalesce(v_jefe, false) AND NOT EXISTS (
    SELECT 1 FROM public.empleados WHERE id = v_carga.empleado_id AND usuario_id = v_usuario
  ) THEN
    RAISE EXCEPTION 'Solo puedes gestionar tu propia carga' USING ERRCODE = '42501';
  END IF;

  IF p_carga IS NULL THEN
    PERFORM 1 FROM public.vehiculos WHERE id = p_vehiculo FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Selecciona un vehículo válido' USING ERRCODE = '22023';
    END IF;
    SELECT count(*) + 1 INTO v_numero FROM public.cargas WHERE vehiculo_id = p_vehiculo AND fecha = p_fecha;
    INSERT INTO public.cargas(vehiculo_id, empleado_id, fecha, descripcion, estado)
    VALUES (p_vehiculo, p_empleado, p_fecha, coalesce(nullif(trim(p_descripcion), ''), 'Carga ' || v_numero), 'En Ruta')
    RETURNING * INTO v_carga;
  END IF;

  FOR v_item IN
    SELECT producto_id, sum(cantidad) AS cantidad,
      bool_and(coalesce(cantidad BETWEEN 1 AND 10000 AND cantidad = trunc(cantidad), false)) AS valido
    FROM jsonb_to_recordset(p_items) AS item(producto_id integer, cantidad numeric)
    GROUP BY producto_id ORDER BY producto_id
  LOOP
    IF NOT v_item.valido OR v_item.cantidad > 10000 THEN
      RAISE EXCEPTION 'Cantidad inválida en la carga' USING ERRCODE = '22023';
    END IF;
    UPDATE public.productos
    SET stock = stock - v_item.cantidad::integer
    WHERE id = v_item.producto_id AND activo IS DISTINCT FROM false AND stock >= v_item.cantidad
    RETURNING nombre INTO v_nombre;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Producto % sin existencias suficientes o inactivo', v_item.producto_id USING ERRCODE = '22023';
    END IF;

    SELECT id INTO v_item_id FROM public.carga_items
    WHERE carga_id = v_carga.id AND producto_id = v_item.producto_id
    ORDER BY id LIMIT 1;
    IF FOUND THEN
      UPDATE public.carga_items SET cantidad = coalesce(cantidad, 0) + v_item.cantidad WHERE id = v_item_id;
    ELSE
      INSERT INTO public.carga_items(carga_id, producto_id, nombre_producto, cantidad)
      VALUES (v_carga.id, v_item.producto_id, v_nombre, v_item.cantidad);
    END IF;
  END LOOP;

  v_resultado := jsonb_build_object('id', v_carga.id, 'numero', v_numero);
  INSERT INTO aquabri_private.carga_operaciones(nonce, usuario_id, solicitud, resultado)
  VALUES (p_nonce, v_usuario, v_solicitud, v_resultado);
  RETURN v_resultado;
END
$function$;
revoke all on function public.aq_guardar_carga_auth_v1(uuid,integer,integer,integer,date,text,jsonb) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_liquidar_carga_auth_v1(p_carga integer, p_efectivo numeric, p_notas text, p_confirmar boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  carga public.cargas%ROWTYPE;
  usuario integer := aquabri_private.usuario_id_actual();
  items jsonb;
  total numeric;
  esperado numeric;
  excluido numeric;
  comision numeric;
  previa public.liquidaciones%ROWTYPE;
  nueva integer;
  item record;
BEGIN
  IF auth.uid() IS NULL OR usuario IS NULL OR aquabri_private.rol_actual() IS DISTINCT FROM 'jefe' THEN
    RAISE EXCEPTION 'Solo el jefe puede conciliar y liquidar una carga' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO carga FROM public.cargas WHERE id = p_carga FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Carga inexistente' USING ERRCODE = '22023'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM aquabri_private.carga_operaciones
    WHERE solicitud->>0 IS NULL AND resultado->>'id' = p_carga::text
  ) THEN
    RAISE EXCEPTION 'La carga anterior requiere conciliación supervisada' USING ERRCODE = '22023';
  END IF;
  IF carga.estado IS DISTINCT FROM 'En Ruta' THEN
    SELECT * INTO previa FROM public.liquidaciones WHERE carga_id = p_carga AND estado = 'Liquidado' ORDER BY id DESC LIMIT 1;
    IF p_confirmar AND FOUND AND previa.efectivo_entregado = p_efectivo AND previa.notas = coalesce(p_notas, '') THEN
      RETURN jsonb_build_object('id', previa.id, 'comision', previa.comision);
    END IF;
    RAISE EXCEPTION 'La carga ya está cerrada' USING ERRCODE = '22023';
  END IF;
  SELECT jsonb_agg(jsonb_build_object(
    'producto_id', r.producto_id, 'nombre_producto', p.nombre, 'cantidad', r.cantidad,
    'ya_vendido', r.vendido, 'ya_bonificado', r.bonificado, 'ya_vendido_monto', round(r.importe, 2),
    'cantidad_regresa', r.cantidad-r.vendido-r.bonificado, 'precio_venta', p.precio
  ) ORDER BY r.producto_id), round(coalesce(sum(r.importe),0),2), round(coalesce(sum(r.incentivo),0),2)
  INTO items,total,excluido
  FROM aquabri_private.resumen_carga(p_carga) r JOIN public.productos p ON p.id = r.producto_id;
  IF items IS NULL THEN RAISE EXCEPTION 'No hay productos conciliables' USING ERRCODE = '22023'; END IF;
  SELECT coalesce(sum(c.monto),0) INTO esperado
  FROM aquabri_private.ventas_de_carga l
  JOIN public.caja c ON c.venta_id = l.venta_id
  WHERE l.carga_id = p_carga AND c.tipo = 'venta' AND c.notas LIKE '%[AQ-MP:EFECTIVO]%';
  SELECT round(greatest(0,total-excluido)*coalesce(e.comision_pct,0)/100,2)
  INTO comision FROM public.empleados e WHERE e.id = carga.empleado_id;
  IF NOT coalesce(p_confirmar,false) THEN
    RETURN jsonb_build_object('items',items,'total',total,'esperado',esperado,'excluido',excluido,'comision',comision);
  END IF;
  IF p_efectivo IS NULL OR p_efectivo NOT BETWEEN 0 AND 100000000 OR p_efectivo <> round(p_efectivo,2)
     OR length(coalesce(p_notas,'')) > 1500 OR comision IS NULL THEN
    RAISE EXCEPTION 'Efectivo, notas o empleado inválidos' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM aquabri_private.resumen_carga(p_carga) r WHERE r.vendido+r.bonificado > r.cantidad) THEN
    RAISE EXCEPTION 'La carga tiene unidades sin conciliar' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.liquidaciones(carga_id,empleado_id,fecha,total_vendido,total_esperado,efectivo_entregado,
                                   diferencia,comision,notas,estado,usuario_id)
  VALUES(p_carga,carga.empleado_id,(now() AT TIME ZONE 'America/Guatemala')::date,total,esperado,p_efectivo,
         p_efectivo-esperado,comision,coalesce(p_notas,''),'Liquidado',usuario)
  RETURNING id INTO nueva;
  FOR item IN SELECT * FROM jsonb_to_recordset(items) AS i(
    producto_id integer,nombre_producto text,cantidad integer,ya_vendido integer,ya_bonificado integer,
    ya_vendido_monto numeric,cantidad_regresa integer,precio_venta numeric
  ) ORDER BY producto_id
  LOOP
    UPDATE public.productos SET stock=coalesce(stock,0)+item.cantidad_regresa WHERE id=item.producto_id;
    INSERT INTO public.liquidacion_items(liquidacion_id,producto_id,nombre_producto,cantidad_salida,cantidad_vendida,
                                        cantidad_devuelta,cantidad_bonificacion,precio_unitario,subtotal)
    VALUES(nueva,item.producto_id,item.nombre_producto,item.cantidad,item.ya_vendido,
           item.cantidad_regresa,item.ya_bonificado,item.precio_venta,item.ya_vendido_monto);
  END LOOP;
  UPDATE public.cargas SET estado='Finalizado' WHERE id=p_carga;
  RETURN jsonb_build_object('id',nueva,'comision',comision);
END
$function$;
revoke all on function public.aq_liquidar_carga_auth_v1(integer,numeric,text,boolean) from public,anon,authenticated,service_role;

CREATE FUNCTION public.aq_vender_de_carga_auth_v1(p_carga integer, p_nonce text, p_venta jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  carga public.cargas%ROWTYPE;
  usuario integer := aquabri_private.usuario_id_actual();
  resultado jsonb;
  vinculo integer;
  item record;
BEGIN
  IF auth.uid() IS NULL OR usuario IS NULL OR NOT coalesce(
    aquabri_private.tiene_permiso_actual('vehiculos') AND aquabri_private.tiene_permiso_actual('ventas.registrar'), false
  ) THEN
    RAISE EXCEPTION 'Sin permiso para vender desde una carga' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO carga FROM public.cargas WHERE id = p_carga FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM public.empleados e WHERE e.id = carga.empleado_id AND e.usuario_id = usuario
  ) THEN
    RAISE EXCEPTION 'La carga no pertenece a este usuario' USING ERRCODE = '42501';
  END IF;
  IF p_venta->>'estado' IS DISTINCT FROM 'Entregado' OR (p_venta->>'fecha')::date IS DISTINCT FROM carga.fecha THEN
    RAISE EXCEPTION 'La venta debe entregarse en la fecha de la carga' USING ERRCODE = '22023';
  END IF;

  resultado := public.aq_vender_con_envases_auth_v3(p_nonce, p_venta || jsonb_build_object('aq_carga_id', p_carga), p_items);
  SELECT carga_id INTO vinculo FROM aquabri_private.ventas_de_carga WHERE venta_id = (resultado->>'id')::integer;
  IF FOUND THEN
    IF vinculo IS DISTINCT FROM p_carga THEN
      RAISE EXCEPTION 'La venta pertenece a otra carga' USING ERRCODE = '22023';
    END IF;
    RETURN resultado;
  END IF;
  IF carga.estado IS DISTINCT FROM 'En Ruta' OR coalesce((resultado->>'repetida')::boolean, false) THEN
    RAISE EXCEPTION 'La carga ya está cerrada o la venta carece de una carga conciliada' USING ERRCODE = '22023';
  END IF;

  INSERT INTO aquabri_private.ventas_de_carga(venta_id, carga_id)
  VALUES ((resultado->>'id')::integer, p_carga);

  IF EXISTS (SELECT 1 FROM aquabri_private.resumen_carga(p_carga) r WHERE r.vendido + r.bonificado > r.cantidad) THEN
    RAISE EXCEPTION 'La carga no tiene unidades suficientes para la venta y la bonificación' USING ERRCODE = '22023';
  END IF;
  -- La venta normal descuenta productos de almacén. Las unidades de ruta salieron al crear la carga.
  FOR item IN
    SELECT unidades.producto_id, sum(unidades.cantidad)::integer cantidad
    FROM public.venta_items i
    CROSS JOIN LATERAL (VALUES (i.producto_id, i.cant), (coalesce(i.bonif_prod_id, i.producto_id), i.bonif_cant))
      unidades(producto_id, cantidad)
    WHERE i.venta_id = (resultado->>'id')::integer AND unidades.cantidad > 0
    GROUP BY unidades.producto_id ORDER BY unidades.producto_id
  LOOP
    UPDATE public.productos SET stock = coalesce(stock, 0) + item.cantidad WHERE id = item.producto_id;
  END LOOP;
  RETURN resultado;
END
$function$;
revoke all on function public.aq_vender_de_carga_auth_v1(integer,text,jsonb,jsonb) from public,anon,authenticated,service_role;
