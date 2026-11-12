-- SOLO para revertir la migracion de permisos de gastos en STAGING.
-- Definiciones originales capturadas antes del cambio 2026-11-12.

CREATE OR REPLACE FUNCTION public.aq_eliminar_gasto_seguro(p_token text, p_uid bigint, p_gasto_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint;v_rol text;v_permisos text;
  v_reg public.aq_gastos_operacion%ROWTYPE;
  v_gasto public.gastos%ROWTYPE;
  v_caja public.caja%ROWTYPE;
BEGIN
  IF p_token IS NULL OR length(p_token)<12 OR p_uid IS NULL OR p_gasto_id IS NULL THEN
    RAISE EXCEPTION 'Sesión o gasto inválido' USING ERRCODE='42501';
  END IF;
  SELECT u.id,u.rol,u.permisos_custom INTO v_uid,v_rol,v_permisos
  FROM public.sesiones s JOIN public.usuarios u ON u.id=s.usuario_id
  WHERE s.token=p_token AND s.usuario_id=p_uid AND s.expira_en>now() LIMIT 1;
  IF v_uid IS NULL OR
    (v_rol<>'jefe' AND NOT coalesce((v_permisos::jsonb ? 'gastos'),false)) THEN
    RAISE EXCEPTION 'Tu sesión no permite borrar gastos' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_gasto FROM public.gastos WHERE id=p_gasto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'El gasto ya no existe. Actualiza la pantalla.'; END IF;
  SELECT * INTO v_reg FROM public.aq_gastos_operacion
    WHERE gasto_id=p_gasto_id AND estado='registrado' FOR UPDATE;
  IF FOUND AND v_reg.caja_id IS NOT NULL THEN
    SELECT * INTO v_caja FROM public.caja WHERE id=v_reg.caja_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'La salida de Caja vinculada no existe: revisa antes de borrar el gasto';
    END IF;
    IF v_caja.tipo<>'gasto' OR v_caja.fecha IS DISTINCT FROM v_gasto.fecha
      OR v_caja.monto IS DISTINCT FROM -v_gasto.monto THEN
      RAISE EXCEPTION 'El gasto y su salida ya no coinciden: revisa la conciliación';
    END IF;
    IF EXISTS(SELECT 1 FROM public.caja
        WHERE fecha=v_caja.fecha AND tipo='cierre' AND id>v_caja.id) THEN
      RAISE EXCEPTION 'No puedes borrar un gasto cuyo movimiento de Caja ya quedó cerrado. Realiza un ajuste supervisado.';
    END IF;
    DELETE FROM public.caja WHERE id=v_caja.id;
  END IF;
  DELETE FROM public.gastos WHERE id=v_gasto.id;
  IF v_reg.nonce IS NOT NULL THEN
    UPDATE public.aq_gastos_operacion
      SET gasto_id=NULL,caja_id=NULL,estado='anulado',anulado_en=now()
    WHERE nonce=v_reg.nonce;
  END IF;
  RETURN jsonb_build_object('eliminado',true,'id',p_gasto_id,'caja_eliminada',v_reg.caja_id IS NOT NULL);
END;
$function$;

CREATE OR REPLACE FUNCTION public.aq_registrar_gasto_seguro(p_token text, p_uid bigint, p_nonce text, p_gasto jsonb)
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
  IF v_uid IS NULL OR
     (v_rol<>'jefe' AND NOT coalesce((v_permisos::jsonb ? 'gastos'),false)) THEN
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
    VALUES(v_fecha,'gasto',-v_monto,v_nota_caja,v_uid::integer)
    RETURNING id INTO v_caja_id;
  END IF;
  INSERT INTO public.aq_gastos_operacion
    (nonce,usuario_id,payload_hash,gasto_id,caja_id,metodo)
  VALUES(p_nonce,p_uid,v_hash,v_gasto_id,v_caja_id,v_metodo);
  RETURN jsonb_build_object('id',v_gasto_id,'caja_id',v_caja_id,
    'metodo',v_metodo,'repetida',false);
END;
$function$;
