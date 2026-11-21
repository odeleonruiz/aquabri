-- Operaciones internas de Auth. Preservan las funciones que todavía usa la app antigua.

CREATE FUNCTION aquabri_private.aq_cobrar_credito_auth_interno(p_token text, p_uid bigint, p_nonce text, p_cliente_id bigint, p_monto numeric, p_medio text, p_notas text DEFAULT ''::text, p_credito_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rol text;
  v_cliente_nombre text;
  v_previa public.aq_cobros_credito_operacion%ROWTYPE;
  v_cred public.creditos%ROWTYPE;
  v_hash text;
  v_monto numeric(14,2);
  v_restante numeric(14,2);
  v_saldo numeric(14,2);
  v_abono numeric(14,2);
  v_pagado numeric(14,2);
  v_fecha date := (now() AT TIME ZONE 'America/Guatemala')::date;
  v_caja_id bigint;
  v_detalle jsonb := '[]'::jsonb;
  v_resultado jsonb;
  v_nota text;
  v_medio_txt text;
BEGIN
  IF coalesce(length(p_token),0) < 12 OR p_uid IS NULL OR
     coalesce(length(p_nonce),0) < 16 OR length(p_nonce) > 120 OR
     p_cliente_id IS NULL OR p_cliente_id <= 0 THEN
    RAISE EXCEPTION 'Sesión, cliente o identificador de cobro inválido';
  END IF;

  SELECT u.rol INTO v_rol
  FROM public.sesiones s
  JOIN public.usuarios u ON u.id=s.usuario_id
  WHERE s.token=p_token AND s.usuario_id=p_uid AND s.expira_en>now()
  LIMIT 1;
  IF v_rol IS NULL OR NOT aquabri_private.tiene_permiso_usuario(p_uid::integer,'creditos.cobrar') THEN
    RAISE EXCEPTION 'La sesión no tiene permiso para cobrar créditos';
  END IF;

  IF p_monto IS NULL OR p_monto <= 0 OR p_monto > 100000000 OR
     p_monto <> round(p_monto,2) THEN
    RAISE EXCEPTION 'El importe debe ser positivo y tener como máximo dos decimales';
  END IF;
  IF p_medio IS NULL OR p_medio NOT IN ('efectivo','transferencia','otro') THEN
    RAISE EXCEPTION 'Medio de pago no válido';
  END IF;
  IF length(coalesce(p_notas,'')) > 500 THEN
    RAISE EXCEPTION 'Las observaciones no pueden superar 500 caracteres';
  END IF;
  IF coalesce(p_notas,'') ~* '\[AQ-(MP|CRED-OP):' THEN
    RAISE EXCEPTION 'Las notas no pueden contener marcas internas de pago';
  END IF;
  IF p_credito_id IS NOT NULL AND p_credito_id <= 0 THEN
    RAISE EXCEPTION 'Crédito individual inválido';
  END IF;

  v_monto := round(p_monto,2);
  v_restante := v_monto;
  v_hash := md5(jsonb_build_object(
    'cliente',p_cliente_id,'monto',v_monto,'medio',p_medio,
    'notas',btrim(coalesce(p_notas,'')),'credito',p_credito_id
  )::text);

  -- Evitar dos peticiones simultáneas con la misma clave de operación.
  PERFORM pg_advisory_xact_lock(hashtext('aq_cobro_nonce:'||p_nonce)::bigint);
  SELECT * INTO v_previa FROM public.aq_cobros_credito_operacion
    WHERE nonce=p_nonce;
  IF FOUND THEN
    IF v_previa.usuario_id<>p_uid OR v_previa.cliente_id<>p_cliente_id OR
       v_previa.payload_hash<>v_hash THEN
      RAISE EXCEPTION 'Esta clave de cobro ya pertenece a otra operación';
    END IF;
    RETURN v_previa.resultado || jsonb_build_object('repetida',true);
  END IF;

  SELECT c.nombre INTO v_cliente_nombre
  FROM public.clientes c WHERE c.id=p_cliente_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cliente # % no encontrado',p_cliente_id;
  END IF;

  -- Un mismo cliente no puede tener dos cobros seguros procesándose a la vez.
  PERFORM pg_advisory_xact_lock(hashtext('aq_cobro_cliente:'||p_cliente_id)::bigint);

  FOR v_cred IN
    SELECT cr.* FROM public.creditos cr
    WHERE cr.cliente_id=p_cliente_id
      AND (p_credito_id IS NULL OR cr.id=p_credito_id)
      AND coalesce(cr.monto,0)>coalesce(cr.pagado,0)
    ORDER BY cr.id ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_restante <= 0;
    v_saldo := round(v_cred.monto-coalesce(v_cred.pagado,0),2);
    IF v_saldo <= 0 THEN CONTINUE; END IF;
    v_abono := least(v_saldo,v_restante);
    v_pagado := round(coalesce(v_cred.pagado,0)+v_abono,2);

    UPDATE public.creditos
      SET pagado=v_pagado,
          estado=CASE WHEN v_pagado>=v_cred.monto THEN 'Pagado' ELSE 'Pendiente' END
      WHERE id=v_cred.id;

    v_detalle := v_detalle || jsonb_build_array(jsonb_build_object(
      'id',v_cred.id,
      'venta_id',v_cred.venta_id,
      'concepto',v_cred.concepto,
      'fecha',v_cred.fecha,
      'monto',v_cred.monto,
      'abonado',v_abono,
      'saldoAntes',v_saldo,
      'saldoDespues',round(v_saldo-v_abono,2)
    ));
    v_restante := round(v_restante-v_abono,2);
  END LOOP;

  -- Si el saldo cambió, si no existe el crédito o si se intenta cobrar más
  -- de lo pendiente, PostgreSQL revierte todas las actualizaciones anteriores.
  IF v_restante > 0 OR jsonb_array_length(v_detalle)=0 THEN
    RAISE EXCEPTION 'El cobro no se registró: el saldo actual es insuficiente o ya fue pagado. Actualiza Créditos e inténtalo de nuevo.';
  END IF;

  v_medio_txt := CASE p_medio WHEN 'efectivo' THEN 'Efectivo'
    WHEN 'transferencia' THEN 'Transferencia / depósito'
    ELSE 'Tarjeta / otro medio' END;
  v_nota := 'Cobro crédito — ' || coalesce(nullif(btrim(v_cliente_nombre),''),'Cliente #'||p_cliente_id)
    || CASE WHEN btrim(coalesce(p_notas,''))<>'' THEN ' · '||btrim(p_notas) ELSE '' END
    || ' · Medio de pago: '||v_medio_txt||' [AQ-MP:'||upper(p_medio)||']'
    || ' [AQ-CRED-OP:'||p_nonce||']';

  INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
  VALUES (v_fecha,'cobro_credito',v_monto,v_nota,p_uid)
  RETURNING id INTO v_caja_id;

  v_resultado := jsonb_build_object(
    'repetida',false,'cliente_id',p_cliente_id,'monto',v_monto,
    'fecha',v_fecha,'medio',p_medio,'caja_id',v_caja_id,
    'creditos',v_detalle
  );
  INSERT INTO public.aq_cobros_credito_operacion
    (nonce,usuario_id,cliente_id,payload_hash,resultado)
  VALUES(p_nonce,p_uid,p_cliente_id,v_hash,v_resultado);
  RETURN v_resultado;
END;
$function$;
revoke all privileges on function aquabri_private.aq_cobrar_credito_auth_interno(p_token text, p_uid bigint, p_nonce text, p_cliente_id bigint, p_monto numeric, p_medio text, p_notas text, p_credito_id bigint) from public, anon, authenticated, service_role;

CREATE FUNCTION aquabri_private.aq_registrar_gasto_auth_interno(p_token text, p_uid bigint, p_nonce text, p_gasto jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid bigint; v_rol text; v_permisos text;
  v_exist public.aq_gastos_operacion%ROWTYPE;
  v_hash text;
  v_fecha date;v_monto numeric(14,2);v_monto_bruto numeric;
  v_cat text;v_desc text;v_proveedor text;v_notas text;
  v_empleado integer;v_pagador text;v_metodo text;
  v_usuario_caja integer;
  v_gasto_id integer;v_caja_id integer;v_apertura integer;
  v_nota_caja text;
BEGIN
  IF p_token IS NULL OR length(p_token)<12 OR p_uid IS NULL OR p_uid<=0
     OR p_nonce IS NULL OR length(p_nonce)<16 OR length(p_nonce)>120 THEN
    RAISE EXCEPTION 'Sesión o identificador de gasto inválido' USING ERRCODE='42501';
  END IF;
  SELECT u.id,u.rol,u.permisos_custom INTO v_uid,v_rol,v_permisos
  FROM public.sesiones s JOIN public.usuarios u ON u.id=s.usuario_id
  WHERE s.token=p_token AND s.usuario_id=p_uid AND s.expira_en>now()
  LIMIT 1;
  IF v_uid IS NULL OR NOT aquabri_private.tiene_permiso_usuario(v_uid::integer,'gastos') THEN
    RAISE EXCEPTION 'Tu sesión no permite registrar gastos' USING ERRCODE='42501';
  END IF;
  IF jsonb_typeof(p_gasto)<>'object' THEN
    RAISE EXCEPTION 'Datos de gasto inválidos';
  END IF;
  v_hash=md5(p_gasto::text);
  PERFORM pg_advisory_xact_lock(hashtext('AQ-GASTO:'||p_nonce)::bigint);
  SELECT * INTO v_exist FROM public.aq_gastos_operacion WHERE nonce=p_nonce;
  IF FOUND THEN
    IF v_exist.usuario_id<>p_uid OR v_exist.payload_hash<>v_hash THEN
      RAISE EXCEPTION 'Este intento de gasto ya se utilizó con otros datos';
    END IF;
    IF v_exist.estado='anulado' THEN
      RAISE EXCEPTION 'El gasto de este intento ya fue anulado; crea un registro nuevo';
    END IF;
    RETURN jsonb_build_object('id',v_exist.gasto_id,'caja_id',v_exist.caja_id,
      'metodo',v_exist.metodo,'repetida',true);
  END IF;
  v_fecha=(p_gasto->>'fecha')::date;
  v_monto_bruto=(p_gasto->>'monto')::numeric;
  IF v_fecha IS NULL OR v_monto_bruto IS NULL
    OR v_monto_bruto<=0 OR v_monto_bruto>9999999.99
    OR round(v_monto_bruto,2)<>v_monto_bruto THEN
    RAISE EXCEPTION 'Fecha o monto del gasto inválidos';
  END IF;
  v_monto=v_monto_bruto;
  v_cat=btrim(coalesce(p_gasto->>'cat',''));
  v_desc=btrim(coalesce(p_gasto->>'descripcion',''));
  v_proveedor=btrim(coalesce(p_gasto->>'proveedor',''));
  v_notas=btrim(coalesce(p_gasto->>'notas',''));
  v_metodo=coalesce(p_gasto->>'metodo','');
  IF v_metodo NOT IN ('sin_caja','efectivo','transferencia','otro') THEN
    RAISE EXCEPTION 'Debes elegir de dónde salió el dinero';
  END IF;
  IF v_cat='' OR v_desc='' OR length(v_cat)>120 OR length(v_desc)>300
    OR length(v_proveedor)>200 OR length(v_notas)>1500 THEN
    RAISE EXCEPTION 'Categoría, descripción o notas de gasto inválidas';
  END IF;
  v_empleado=nullif(p_gasto->>'empleado_id','')::integer;
  IF v_empleado IS NOT NULL THEN
    SELECT e.nombre INTO v_pagador FROM public.empleados e WHERE e.id=v_empleado;
    IF v_pagador IS NULL THEN RAISE EXCEPTION 'Empleado responsable inválido'; END IF;
  ELSE
    v_pagador='Jefe';
  END IF;

  -- El responsable de caja puede ser distinto del usuario que creó el registro.
  -- aq_gastos_operacion.usuario_id conserva quién lo registró.
  v_usuario_caja := v_uid::integer;
  IF v_empleado IS NOT NULL AND v_metodo <> 'sin_caja' THEN
    SELECT e.usuario_id INTO v_usuario_caja FROM public.empleados e WHERE e.id=v_empleado;
    IF v_usuario_caja IS NULL THEN
      RAISE EXCEPTION 'El empleado asignado no tiene usuario vinculado. Vincúlalo antes de cargarle gastos a caja.';
    END IF;
  END IF;

  -- Comprobar cierre antes de afectar efectivo de una fecha.
  IF v_metodo='efectivo' THEN
    SELECT id INTO v_apertura FROM public.caja
      WHERE fecha=v_fecha AND tipo='apertura' ORDER BY id DESC LIMIT 1;
    IF v_apertura IS NULL OR EXISTS(
       SELECT 1 FROM public.caja
       WHERE fecha=v_fecha AND tipo='cierre' AND id>v_apertura
    ) THEN
      RAISE EXCEPTION 'La caja de la fecha indicada no está abierta. No se registró el gasto.';
    END IF;
  END IF;

  INSERT INTO public.gastos(fecha,cat,descripcion,proveedor,monto,notas,pagado_por,empleado_id)
  VALUES(v_fecha,v_cat,v_desc,v_proveedor,v_monto,
      btrim(v_notas||' [AQ-GP:'||upper(v_metodo)||']'),v_pagador,v_empleado)
  RETURNING id INTO v_gasto_id;
  IF v_metodo<>'sin_caja' THEN
    v_nota_caja='Gasto # '||v_gasto_id||' — '||v_desc||
      ' [AQ-GASTO:'||v_gasto_id||'] [AQ-MP:'||upper(v_metodo)||']';
    INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
    VALUES(v_fecha,'gasto',-v_monto,v_nota_caja,v_usuario_caja)
    RETURNING id INTO v_caja_id;
  END IF;
  INSERT INTO public.aq_gastos_operacion
    (nonce,usuario_id,payload_hash,gasto_id,caja_id,metodo)
  VALUES(p_nonce,p_uid,v_hash,v_gasto_id,v_caja_id,v_metodo);
  RETURN jsonb_build_object('id',v_gasto_id,'caja_id',v_caja_id,
    'metodo',v_metodo,'repetida',false);
END;
$function$;
revoke all privileges on function aquabri_private.aq_registrar_gasto_auth_interno(p_token text, p_uid bigint, p_nonce text, p_gasto jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION aquabri_private.aq_pago_proveedor_auth_interno(p_token text, p_uid bigint, p_nonce text, p_proveedor text, p_deuda_id bigint, p_monto numeric, p_fecha date, p_notas text, p_origen text)
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
   RAISE EXCEPTION 'Tu cuenta no tiene permiso para registrar pagos a proveedores';
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
revoke all privileges on function aquabri_private.aq_pago_proveedor_auth_interno(p_token text, p_uid bigint, p_nonce text, p_proveedor text, p_deuda_id bigint, p_monto numeric, p_fecha date, p_notas text, p_origen text) from public, anon, authenticated, service_role;

CREATE FUNCTION aquabri_private.aq_envases_venta_auth_interno(p_token text, p_uid bigint, p_venta_id bigint, p_entregados integer, p_devueltos integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_rol text;
 v_venta record;
 v_actual record;
 v_saldo integer;
 v_neto integer;
 v_cant_bodega integer;
begin
 if p_uid is null or p_token is null or length(p_token)<12
   or p_venta_id is null or p_entregados is null or p_devueltos is null
   or p_entregados<0 or p_devueltos<0 or p_entregados>100000 or p_devueltos>100000 then
   raise exception 'Parámetros de envases o sesión inválidos' using errcode='22023';
 end if;
 select u.rol into v_rol
 from public.sesiones s join public.usuarios u on u.id=s.usuario_id
 where s.token=p_token and s.usuario_id=p_uid and s.expira_en>now()
 and u.rol in ('jefe','vendedor','vendedor_editor')
 limit 1;
 if v_rol is null then raise exception 'Sesión sin permisos para registrar envases' using errcode='42501'; end if;
 select id,cliente_id,usuario_id,estado into v_venta from public.ventas
 where id=p_venta_id for update;
 if not found or v_venta.cliente_id is null then
   raise exception 'Venta o cliente no válido para registrar envases' using errcode='22023';
 end if;
 if v_rol<>'jefe' and v_venta.usuario_id is distinct from p_uid then
   raise exception 'El vendedor solo puede registrar envases de su propia venta' using errcode='42501';
 end if;
 if v_venta.estado in ('Cancelada','Anulado') then
   raise exception 'No se pueden prestar envases en una venta cancelada' using errcode='22023';
 end if;
 select * into v_actual from aquabri_private.aq_envases_ventas where venta_id=p_venta_id;
 if found then
   if v_actual.cliente_id=v_venta.cliente_id and v_actual.entregados=p_entregados
    and v_actual.devueltos=p_devueltos and not v_actual.revertido then
    return pg_catalog.jsonb_build_object('ok',true,'repetida',true,'neto',v_actual.neto);
   end if;
   raise exception 'Los envases de esta venta ya fueron registrados; revisa su historial' using errcode='23505';
 end if;
 v_neto=p_entregados-p_devueltos;
 select coalesce(envases,0) into v_saldo
 from public.clientes where id=v_venta.cliente_id for update;
 if not found or v_saldo+v_neto<0 then
   raise exception 'La devolución supera los envases pendientes del cliente; revisa el saldo' using errcode='22023';
 end if;
 select cantidad into v_cant_bodega from public.envases_bodega where id=1 for update;
 if not found then raise exception 'Bodega de envases no configurada' using errcode='22023'; end if;
 if v_neto>0 and v_cant_bodega<v_neto then
   raise exception 'No hay suficientes envases disponibles en bodega' using errcode='22023';
 end if;
 update public.clientes set envases=v_saldo+v_neto where id=v_venta.cliente_id;
 update public.envases_bodega set cantidad=v_cant_bodega-v_neto where id=1;
 insert into aquabri_private.aq_envases_ventas
  (venta_id,cliente_id,entregados,devueltos,neto,usuario_id)
 values (p_venta_id,v_venta.cliente_id,p_entregados,p_devueltos,v_neto,p_uid);
 if v_neto<>0 then
   insert into public.envases(fecha,cliente_id,cant,tipo,notas,precio,venta_id,anulado)
   values((now() at time zone 'America/Guatemala')::date,v_venta.cliente_id,abs(v_neto),
     case when v_neto>0 then 'Préstamo' else 'Devolución' end,
     'Venta #'||p_venta_id||' · Entregados: '||p_entregados||' · Recibidos: '||p_devueltos||' · Neto: '||v_neto,
     0,p_venta_id,false);
 end if;
 return pg_catalog.jsonb_build_object('ok',true,'repetida',false,
  'neto',v_neto,'entregados',p_entregados,'devueltos',p_devueltos,'saldo_final',v_saldo+v_neto);
end;
$function$;
revoke all privileges on function aquabri_private.aq_envases_venta_auth_interno(p_token text, p_uid bigint, p_venta_id bigint, p_entregados integer, p_devueltos integer) from public, anon, authenticated, service_role;
