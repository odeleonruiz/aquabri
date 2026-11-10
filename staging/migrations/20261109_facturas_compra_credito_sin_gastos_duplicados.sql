-- AQ: factura inventario vs gasto vs crédito proveedor; sin costos duplicados.
CREATE OR REPLACE FUNCTION public.aq_registrar_compra_segura(p_token text, p_uid bigint, p_nonce text, p_factura jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rol text;
  v_previa record;
  v_fact public.facturas_proveedores%ROWTYPE;
  v_item jsonb;
  v_tipo text;
  v_prov text;
  v_num text;
  v_fecha date;
  v_estado text;
  v_origen text;
  v_notas text;
  v_nombre text;
  v_id bigint;
  v_cant integer;
  v_costo numeric(14,4);
  v_subtotal numeric(14,2);
  v_total numeric(14,2) := 0;
  v_esperado numeric(14,2);
  v_hash text;
  v_existente bigint;
  v_prod public.productos%ROWTYPE;
  v_ins public.insumos%ROWTYPE;
  v_stock_positivo numeric;
  v_costo_orientativo numeric;
  v_retornable text;
  v_bodega numeric;
BEGIN
  -- Autenticación de la sesión personalizada actual de AQUABRI.
  IF p_token IS NULL OR length(p_token) < 12 OR p_uid IS NULL OR
     p_nonce IS NULL OR length(p_nonce) < 16 OR length(p_nonce) > 120 THEN
    RAISE EXCEPTION 'Sesión o identificador de compra inválido';
  END IF;
  SELECT u.rol INTO v_rol
  FROM public.sesiones s JOIN public.usuarios u ON u.id = s.usuario_id
  WHERE s.token = p_token AND s.usuario_id = p_uid AND s.expira_en > now()
  LIMIT 1;
  IF v_rol IS NULL OR NOT aquabri_private.tiene_permiso_usuario(p_uid::integer,'compras.registrar') THEN
    RAISE EXCEPTION 'Usuario sin autorización para registrar facturas de proveedores';
  END IF;
  IF jsonb_typeof(p_factura) <> 'object' OR jsonb_typeof(p_items) <> 'array' OR
     jsonb_array_length(p_items) = 0 OR jsonb_array_length(p_items) > 150 THEN
    RAISE EXCEPTION 'La factura debe incluir entre 1 y 150 productos/insumos/envases';
  END IF;
  v_prov := btrim(coalesce(p_factura->>'proveedor',''));
  v_num := btrim(coalesce(p_factura->>'numero_factura',''));
  v_notas := nullif(btrim(coalesce(p_factura->>'notas','')), '');
  v_estado := p_factura->>'estado';
  v_origen := coalesce(p_factura->>'origen_pago','externo');
  IF length(v_prov) < 2 OR length(v_prov) > 200 THEN
    RAISE EXCEPTION 'Nombre de proveedor inválido';
  END IF;
  IF length(v_num) > 100 THEN RAISE EXCEPTION 'Número de factura demasiado largo'; END IF;
  IF v_estado IS NULL OR v_estado NOT IN ('Pagado','Pendiente','Crédito') THEN
    RAISE EXCEPTION 'Estado de factura inválido';
  END IF;
  IF v_origen NOT IN ('caja','externo') THEN RAISE EXCEPTION 'Origen de pago inválido'; END IF;
  IF v_estado <> 'Pagado' AND v_origen = 'caja' THEN
    RAISE EXCEPTION 'Una factura no pagada no puede generar salida de caja';
  END IF;
  v_fecha := (p_factura->>'fecha')::date;
  IF v_fecha IS NULL THEN RAISE EXCEPTION 'La fecha de factura es obligatoria'; END IF;

  -- Validación de todos los importes antes de insertar registros.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_tipo := coalesce(v_item->>'tipo','');
    IF v_tipo NOT IN ('producto','insumo','envase') THEN
      RAISE EXCEPTION 'Tipo de artículo no válido: %', v_tipo;
    END IF;
    v_cant := (v_item->>'cantidad')::integer;
    v_costo := (v_item->>'costo')::numeric;
    v_nombre := btrim(coalesce(v_item->>'nombre',''));
    IF v_cant IS NULL OR v_cant < 1 OR v_cant > 100000 OR
       v_costo IS NULL OR v_costo < 0 OR v_costo > 1000000 OR
       round(v_costo,4) <> v_costo OR length(v_nombre) < 1 OR length(v_nombre)>250 THEN
      RAISE EXCEPTION 'Cantidad, descripción o costo inválido';
    END IF;
    IF v_tipo <> 'envase' AND (v_item->>'id') IS NULL THEN
      RAISE EXCEPTION 'Artículo sin identificador';
    END IF;
    v_subtotal := round(v_cant * v_costo,2);
    v_total := v_total + v_subtotal;
  END LOOP;
  v_esperado := (p_factura->>'total')::numeric;
  IF v_esperado IS NULL OR v_total <> round(v_esperado,2) THEN
    RAISE EXCEPTION 'Total inconsistente. Calculado Q %, enviado Q %',v_total,v_esperado;
  END IF;

  -- Una clave por intento evita dobles compras por doble clic o fallos de red.
  PERFORM pg_advisory_xact_lock(hashtext('aq_compra_nonce:' || p_nonce)::bigint);
  v_hash := md5(p_factura::text || ':' || p_items::text);
  SELECT usuario_id, factura_id, payload_hash INTO v_previa
    FROM public.aq_compras_operacion WHERE nonce=p_nonce;
  IF FOUND THEN
    IF v_previa.usuario_id <> p_uid OR v_previa.payload_hash <> v_hash THEN
      RAISE EXCEPTION 'Este identificador de compra ya corresponde a otra factura';
    END IF;
    RETURN jsonb_build_object('id',v_previa.factura_id,'repetida',true,'total',v_total);
  END IF;

  -- Duplicados contra todo el historial existente: mismo proveedor y número.
  -- Sin número, solo se dispone de protección por nonce.
  IF v_num <> '' THEN
    PERFORM pg_advisory_xact_lock(hashtext('aq_compra_numero:'||lower(v_prov)||':'||lower(v_num))::bigint);
    SELECT f.id INTO v_existente FROM public.facturas_proveedores f
     WHERE lower(btrim(f.proveedor))=lower(v_prov)
       AND lower(btrim(coalesce(f.numero_factura,'')))=lower(v_num)
     ORDER BY f.id DESC LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Factura duplicada: % del proveedor % ya está guardada como factura interna #% ',v_num,v_prov,v_existente;
    END IF;
  END IF;

  -- Requerimos el trigger FIFO activo antes de crear nuevos detalles de compra.
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.factura_items'::regclass
      AND t.tgname='trg_aq_lote_factura' AND t.tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Falta el trigger FIFO trg_aq_lote_factura. No se guardó la compra.';
  END IF;

  INSERT INTO public.facturas_proveedores
    (proveedor,numero_factura,fecha,total,estado,notas)
  VALUES (v_prov,nullif(v_num,''),v_fecha,v_total,v_estado,v_notas)
  RETURNING * INTO v_fact;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_tipo := v_item->>'tipo';
    v_cant := (v_item->>'cantidad')::integer;
    v_costo := (v_item->>'costo')::numeric;
    v_subtotal := round(v_cant * v_costo,2);
    v_nombre := btrim(v_item->>'nombre');

    IF v_tipo = 'producto' THEN
      v_id := (v_item->>'id')::bigint;
      SELECT * INTO v_prod FROM public.productos WHERE id=v_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Producto # % no encontrado',v_id; END IF;
      INSERT INTO public.factura_items
        (factura_id,producto_id,nombre_producto,cantidad,costo_unit,subtotal)
      VALUES (v_fact.id,v_id,v_nombre,v_cant,v_costo,v_subtotal);
      -- El trigger de factura_items creó el lote FIFO de este producto,
      -- excepto si es retornable (su entrada se registra en bodega de envases).
      v_retornable := lower(btrim(coalesce(v_prod.retornable::text,'')));
      IF v_retornable IN ('si','sí','true','1') THEN
        UPDATE public.envases_bodega SET cantidad=coalesce(cantidad,0)+v_cant
         WHERE id=1 RETURNING cantidad INTO v_bodega;
        IF NOT FOUND THEN RAISE EXCEPTION 'Falta la fila #1 de envases_bodega'; END IF;
        INSERT INTO public.envases(fecha,cliente_id,cant,tipo,notas,precio)
        VALUES(v_fecha,NULL,v_cant,'Entrada',
          'Factura #'||v_fact.id||' — '||v_prov||' ('||v_nombre||')',v_subtotal);
      ELSE
        -- Costo promedio únicamente orientativo en Inventario.
        -- El costo histórico REAL está en aq_lotes_inventario.
        v_stock_positivo := greatest(coalesce(v_prod.stock,0),0);
        v_costo_orientativo := round(
          (v_stock_positivo*greatest(coalesce(v_prod.costo,0),0)+v_cant*v_costo)
          / (v_stock_positivo+v_cant),4);
        UPDATE public.productos
          SET stock=coalesce(stock,0)+v_cant, costo=v_costo_orientativo
          WHERE id=v_id;
      END IF;

    ELSIF v_tipo = 'insumo' THEN
      v_id := (v_item->>'id')::bigint;
      SELECT * INTO v_ins FROM public.insumos WHERE id=v_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Insumo # % no encontrado',v_id; END IF;
      INSERT INTO public.factura_items
        (factura_id,producto_id,nombre_producto,cantidad,costo_unit,subtotal)
      VALUES (v_fact.id,NULL,v_nombre,v_cant,v_costo,v_subtotal);
      UPDATE public.insumos SET stock=coalesce(stock,0)+v_cant, costo=v_costo
       WHERE id=v_id;

    ELSIF v_tipo = 'envase' THEN
      INSERT INTO public.factura_items
        (factura_id,producto_id,nombre_producto,cantidad,costo_unit,subtotal)
      VALUES (v_fact.id,NULL,v_nombre,v_cant,v_costo,v_subtotal);
      UPDATE public.envases_bodega SET cantidad=coalesce(cantidad,0)+v_cant
        WHERE id=1 RETURNING cantidad INTO v_bodega;
      IF NOT FOUND THEN RAISE EXCEPTION 'Falta la fila #1 de envases_bodega'; END IF;
      INSERT INTO public.envases(fecha,cliente_id,cant,tipo,notas,precio)
      VALUES(v_fecha,NULL,v_cant,'Entrada',
        'Factura #'||v_fact.id||' — '||v_prov||' ('||v_nombre||')',v_subtotal);
    END IF;
  END LOOP;

  IF v_estado IN ('Crédito','Pendiente') THEN
    INSERT INTO public.deudas_proveedores
      (proveedor,concepto,monto,pagado,fecha,estado,notas)
    VALUES (v_prov,'Factura #'||v_fact.id,v_total,0,v_fecha,'Pendiente','Auto desde factura');
  ELSIF v_estado = 'Pagado' AND v_origen = 'caja' THEN
    -- Compra de existencias = activo y no gasto operativo; Caja registra solo el pago.
    INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
    VALUES (v_fecha,'gasto',-v_total,
      'Compra inventario Factura #'||v_fact.id||' — '||v_prov||
      ' [AQ-MP:EFECTIVO] [AQ-INVENTARIO:COMPRA]',p_uid);
  END IF;

  INSERT INTO public.aq_compras_operacion(nonce,usuario_id,factura_id,payload_hash)
  VALUES(p_nonce,p_uid,v_fact.id,v_hash);

  RETURN jsonb_build_object('id',v_fact.id,'total',v_total,
    'estado',v_estado,'origen_pago',v_origen,'repetida',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.aq_registrar_documento_sin_items(p_token text, p_uid bigint, p_nonce text, p_tipo text, p_documento jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
 v_rol text; v_proveedor text; v_num text; v_concepto text;
 v_fecha date; v_estado text; v_origen text; v_categoria text;
 v_monto numeric(14,2); v_bruto numeric; v_hash text;
 v_prev record; v_id bigint; v_fact public.facturas_proveedores%ROWTYPE;
BEGIN
 IF p_token IS NULL OR length(p_token)<12 OR p_uid IS NULL OR p_nonce IS NULL
    OR length(p_nonce)<16 OR length(p_nonce)>120 THEN
    RAISE EXCEPTION 'Sesion o identificador de documento invalido';
 END IF;
 SELECT u.rol INTO v_rol FROM public.sesiones s JOIN public.usuarios u ON u.id=s.usuario_id
  WHERE s.token=p_token AND s.usuario_id=p_uid AND s.expira_en>now() LIMIT 1;
 IF v_rol NOT IN ('jefe','inventario') OR v_rol IS NULL THEN
   RAISE EXCEPTION 'Sin permiso para registrar documentos de proveedor';
 END IF;
 IF p_tipo IS NULL OR p_tipo NOT IN ('gasto','deuda') OR jsonb_typeof(p_documento)<>'object' THEN
   RAISE EXCEPTION 'Tipo de registro invalido';
 END IF;
 v_proveedor:=btrim(coalesce(p_documento->>'proveedor',''));
 v_num:=btrim(coalesce(p_documento->>'numero_factura',''));
 v_concepto:=btrim(coalesce(p_documento->>'concepto',''));
 v_categoria:=btrim(coalesce(p_documento->>'categoria','Otros gastos'));
 v_estado:=coalesce(p_documento->>'estado','Pendiente');
 v_origen:=coalesce(p_documento->>'origen_pago','externo');
 IF length(v_proveedor)<2 OR length(v_proveedor)>200 OR length(v_num)>100
    OR length(v_concepto)<3 OR length(v_concepto)>250 OR length(v_categoria)>100 THEN
    RAISE EXCEPTION 'Proveedor o concepto invalido';
 END IF;
 IF v_estado NOT IN ('Pagado','Pendiente','Crédito') OR v_origen NOT IN ('caja','externo') THEN
    RAISE EXCEPTION 'Estado u origen de pago invalido';
 END IF;
 IF p_tipo='deuda' AND v_estado='Pagado' THEN
    RAISE EXCEPTION 'La obligacion sin detalle debe ser Pendiente o Credito';
 END IF;
 IF v_estado<>'Pagado' AND v_origen='caja' THEN
    RAISE EXCEPTION 'No se puede sacar efectivo por una obligacion aun no pagada';
 END IF;
 v_fecha:=(p_documento->>'fecha')::date;
 IF v_fecha IS NULL THEN RAISE EXCEPTION 'Fecha requerida'; END IF;
 v_bruto:=(p_documento->>'total')::numeric;
 IF v_bruto IS NULL OR v_bruto<=0 OR v_bruto>100000000 OR round(v_bruto,2)<>v_bruto THEN
    RAISE EXCEPTION 'Importe invalido (solo dos decimales, positivo)';
 END IF;
 v_monto:=v_bruto;
 v_hash:=md5(p_tipo||':'||p_documento::text);
 PERFORM pg_advisory_xact_lock(hashtext('aq_compra_nonce:'||p_nonce)::bigint);
 SELECT usuario_id,factura_id,payload_hash INTO v_prev FROM public.aq_compras_operacion WHERE nonce=p_nonce;
 IF FOUND THEN
   IF v_prev.usuario_id<>p_uid OR v_prev.payload_hash<>v_hash THEN
     RAISE EXCEPTION 'Identificador reutilizado con datos diferentes';
   END IF;
   RETURN jsonb_build_object('id',v_prev.factura_id,'repetida',true);
 END IF;
 IF v_num<>'' THEN
   PERFORM pg_advisory_xact_lock(hashtext('aq_compra_numero:'||lower(v_proveedor)||':'||lower(v_num))::bigint);
   SELECT id INTO v_id FROM public.facturas_proveedores
     WHERE lower(btrim(proveedor))=lower(v_proveedor)
       AND lower(btrim(coalesce(numero_factura,'')))=lower(v_num)
     LIMIT 1;
   IF FOUND THEN
     RAISE EXCEPTION 'Documento duplicado del proveedor % con numero % (interno #%)',v_proveedor,v_num,v_id;
   END IF;
 END IF;
 INSERT INTO public.facturas_proveedores(proveedor,numero_factura,fecha,total,estado,notas)
 VALUES(v_proveedor,nullif(v_num,''),v_fecha,v_monto,v_estado,
   concat('[',upper(p_tipo),'] ',v_concepto,
     CASE WHEN nullif(btrim(coalesce(p_documento->>'notas','')),'') IS NOT NULL
       THEN ' · '||btrim(p_documento->>'notas') ELSE '' END))
 RETURNING * INTO v_fact;
 INSERT INTO public.aq_facturas_clasificacion(factura_id,tipo,concepto,categoria,registrado_por)
 VALUES(v_fact.id,p_tipo,v_concepto,CASE WHEN p_tipo='gasto' THEN v_categoria ELSE NULL END,p_uid);
 IF p_tipo='gasto' THEN
   -- El gasto se reconoce UNA sola vez al registrar el documento, no al pagarlo.
   INSERT INTO public.gastos(fecha,cat,descripcion,proveedor,monto,notas,pagado_por,empleado_id)
   VALUES(v_fecha,coalesce(nullif(v_categoria,''),'Otros gastos'),v_concepto,
      v_proveedor,v_monto,'Auto: Gasto #'||v_fact.id,'Jefe',NULL);
 END IF;
 IF v_estado IN ('Crédito','Pendiente') THEN
   INSERT INTO public.deudas_proveedores(proveedor,concepto,monto,pagado,fecha,estado,notas)
   VALUES(v_proveedor,'Factura #'||v_fact.id||' — '||v_concepto,v_monto,0,v_fecha,
     'Pendiente','Auto desde documento #'||v_fact.id||' ('||p_tipo||')');
 ELSIF v_origen='caja' THEN
   INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
   VALUES(v_fecha,'gasto',-v_monto,'Pago inicial documento #'||v_fact.id||' — '||v_proveedor||' [AQ-MP:EFECTIVO]',p_uid);
 END IF;
 INSERT INTO public.aq_compras_operacion(nonce,usuario_id,factura_id,payload_hash)
 VALUES(p_nonce,p_uid,v_fact.id,v_hash);
 RETURN jsonb_build_object('id',v_fact.id,'tipo',p_tipo,'total',v_monto,'repetida',false);
END; $function$;

CREATE OR REPLACE FUNCTION public.aq_registrar_pago_proveedor_seguro(p_token text, p_uid bigint, p_nonce text, p_proveedor text, p_deuda_id bigint, p_monto numeric, p_fecha date, p_notas text, p_origen text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
 v_rol text; v_prov text; v_monto numeric(14,2); v_restante numeric(14,2);
 v_hash text; v_prev record; v_deuda record; v_toma numeric(14,2);
 v_pagos integer:=0;
BEGIN
 IF p_token IS NULL OR length(p_token)<12 OR p_uid IS NULL
  OR p_nonce IS NULL OR length(p_nonce)<16 OR length(p_nonce)>120 THEN
   RAISE EXCEPTION 'Sesion invalida';
 END IF;
 SELECT u.rol INTO v_rol FROM public.sesiones s JOIN public.usuarios u ON u.id=s.usuario_id
  WHERE s.token=p_token AND s.usuario_id=p_uid AND s.expira_en>now() LIMIT 1;
 IF v_rol IS NULL OR NOT aquabri_private.tiene_permiso_usuario(p_uid::integer,'proveedores.pagar') THEN
   RAISE EXCEPTION 'Solo el jefe puede registrar pagos a proveedores';
 END IF;
 v_prov:=btrim(coalesce(p_proveedor,''));
 IF length(v_prov)<2 OR length(v_prov)>200 OR p_fecha IS NULL OR p_origen NOT IN ('caja','externo')
   OR p_origen IS NULL OR p_monto IS NULL OR p_monto<=0 OR p_monto>100000000 OR round(p_monto,2)<>p_monto THEN
   RAISE EXCEPTION 'Proveedor, fecha, origen o monto invalido';
 END IF;
 IF p_deuda_id IS NOT NULL AND p_deuda_id<1 THEN RAISE EXCEPTION 'Deuda invalida'; END IF;
 v_monto:=p_monto;v_restante:=v_monto;
 v_hash:=md5(concat_ws('|',v_prov,p_deuda_id::text,v_monto::text,p_fecha::text,
    coalesce(p_notas,''),p_origen));
 PERFORM pg_advisory_xact_lock(hashtext('aq_pago_proveedor:'||lower(v_prov))::bigint);
 SELECT proveedor,monto,usuario_id,payload_hash INTO v_prev
 FROM public.aq_pagos_proveedores WHERE nonce=p_nonce;
 IF FOUND THEN
  IF v_prev.usuario_id<>p_uid OR v_prev.payload_hash<>v_hash THEN
    RAISE EXCEPTION 'Pago duplicado con datos diferentes';
  END IF;
  RETURN jsonb_build_object('repetida',true,'monto',v_prev.monto,'nonce',p_nonce);
 END IF;
 INSERT INTO public.aq_pagos_proveedores(nonce,proveedor,deuda_id,monto,fecha,origen,usuario_id,payload_hash)
 VALUES(p_nonce,v_prov,p_deuda_id,v_monto,p_fecha,p_origen,p_uid,v_hash);
 FOR v_deuda IN
  SELECT id,monto,pagado,estado FROM public.deudas_proveedores
  WHERE lower(btrim(proveedor))=lower(v_prov) AND monto>coalesce(pagado,0)
   AND (p_deuda_id IS NULL OR id=p_deuda_id)
  ORDER BY fecha,id FOR UPDATE
 LOOP
  EXIT WHEN v_restante<=0;
  v_toma:=least(v_restante,round(v_deuda.monto-coalesce(v_deuda.pagado,0),2));
  IF v_toma<=0 THEN CONTINUE; END IF;
  UPDATE public.deudas_proveedores
   SET pagado=coalesce(pagado,0)+v_toma,
       estado=CASE WHEN coalesce(pagado,0)+v_toma>=monto THEN 'Pagado' ELSE 'Pendiente' END
   WHERE id=v_deuda.id;
  INSERT INTO public.aq_pagos_proveedor_detalle(nonce,deuda_id,monto)
  VALUES(p_nonce,v_deuda.id,v_toma);
  v_restante:=v_restante-v_toma;v_pagos:=v_pagos+1;
 END LOOP;
 IF v_restante>0 THEN
  RAISE EXCEPTION 'Pago Q% supera el saldo disponible; operacion revertida por completo',v_monto;
 END IF;
 -- Pagar una deuda NO crea un gasto nuevo. Si sale de caja, una unica salida.
 IF p_origen='caja' THEN
  INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
  VALUES(p_fecha,'gasto',-v_monto,
    'Pago proveedor '||v_prov||' · ref '||p_nonce||
    CASE WHEN length(btrim(coalesce(p_notas,'')))>0 THEN ' — '||left(p_notas,200) ELSE '' END||
    ' [AQ-MP:EFECTIVO]',p_uid);
 END IF;
 RETURN jsonb_build_object('nonce',p_nonce,'monto',v_monto,'deudas_cubiertas',v_pagos,'repetida',false);
END; $function$;