-- AQUABRI STAGING ONLY - Do not run in production.
-- Auth-native, transactional settlement of accrued incentives.
BEGIN;

CREATE TABLE IF NOT EXISTS aquabri_private.aq_liquidaciones_incentivos_intentos (
  nonce text PRIMARY KEY,
  usuario_id integer NOT NULL REFERENCES public.usuarios(id),
  parametros_hash text NOT NULL,
  pago_id bigint UNIQUE REFERENCES public.aq_pagos_incentivos(id) ON DELETE RESTRICT,
  monto numeric(14,2) NOT NULL CHECK (monto >= 0),
  caja_id integer UNIQUE REFERENCES public.caja(id) ON DELETE RESTRICT,
  creado_en timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT aq_liq_intento_consistencia CHECK (
    (pago_id IS NULL AND monto = 0 AND caja_id IS NULL)
    OR (pago_id IS NOT NULL AND monto > 0)
  )
);
ALTER TABLE aquabri_private.aq_liquidaciones_incentivos_intentos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON aquabri_private.aq_liquidaciones_incentivos_intentos FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.aq_liquidar_incentivos_auth_v2(
  p_nonce text, p_empleado bigint, p_desde date, p_hasta date, p_origen text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_auth uuid;
  v_uid integer;
  v_rol text;
  v_hash text;
  v_previo aquabri_private.aq_liquidaciones_incentivos_intentos%ROWTYPE;
  v_ids bigint[];
  v_monto numeric;
  v_pago bigint;
  v_caja integer;
  v_apertura integer;
  v_fecha date;
  v_count integer;
  v_actualizados integer;
BEGIN
  v_auth := (SELECT auth.uid());
  IF v_auth IS NULL OR coalesce((auth.jwt()->>'is_anonymous')::boolean,false) THEN
    RAISE EXCEPTION 'Inicia sesión con Supabase Auth' USING ERRCODE = '28000';
  END IF;

  SELECT u.id, u.rol INTO v_uid, v_rol
  FROM public.usuarios u JOIN auth.users a ON a.id=u.auth_uid
  WHERE u.auth_uid=v_auth;
  IF v_uid IS NULL OR v_rol <> 'jefe' THEN
    RAISE EXCEPTION 'Solo el jefe puede liquidar incentivos' USING ERRCODE = '42501';
  END IF;

  IF p_nonce IS NULL OR length(p_nonce)<16 OR length(p_nonce)>120
     OR p_empleado IS NULL OR p_empleado<=0
     OR p_desde IS NULL OR p_hasta IS NULL
     OR p_desde>p_hasta OR p_hasta>p_desde+365
     OR p_hasta>(now() AT TIME ZONE 'America/Guatemala')::date
     OR p_origen IS NULL OR p_origen NOT IN ('caja','externo') THEN
    RAISE EXCEPTION 'Parámetros de liquidación inválidos' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.empleados e WHERE e.id=p_empleado) THEN
    RAISE EXCEPTION 'El empleado no existe' USING ERRCODE='22023';
  END IF;

  v_hash := md5(jsonb_build_object('empleado',p_empleado,'desde',p_desde,
                                  'hasta',p_hasta,'origen',p_origen)::text);
  -- Concurrent retries with the same nonce must serialize.
  PERFORM pg_advisory_xact_lock(hashtext('AQ-LIQ-NONCE:'||p_nonce)::bigint);
  SELECT * INTO v_previo
    FROM aquabri_private.aq_liquidaciones_incentivos_intentos
    WHERE nonce=p_nonce FOR UPDATE;
  IF FOUND THEN
    IF v_previo.usuario_id<>v_uid OR v_previo.parametros_hash<>v_hash THEN
      RAISE EXCEPTION 'Identificador de liquidación reutilizado con otros datos' USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('pago_id',v_previo.pago_id,'monto',v_previo.monto,
      'caja_id',v_previo.caja_id,'repetida',true);
  END IF;

  -- Prevent two different nonces settling the same employee concurrently.
  PERFORM pg_advisory_xact_lock(hashtext('AQ-LIQ-EMPLEADO:'||p_empleado::text)::bigint);
  SELECT coalesce(array_agg(q.id),'{}'::bigint[]), coalesce(sum(q.importe_empleado),0), count(*)
  INTO v_ids, v_monto, v_count
  FROM (
    SELECT m.id, m.importe_empleado
    FROM public.aq_incentivos_devengados m
    JOIN public.ventas v ON v.id=m.venta_id
    WHERE m.empleado_id=p_empleado AND m.fecha BETWEEN p_desde AND p_hasta
      AND m.pago_id IS NULL
      AND v.estado IS DISTINCT FROM 'Cancelada'
      AND v.estado IS DISTINCT FROM 'Anulado'
      AND NOT EXISTS (
        SELECT 1 FROM public.creditos c WHERE c.venta_id=m.venta_id
          AND coalesce(c.pagado,0)<coalesce(c.monto,0)
      )
    ORDER BY m.id
    FOR UPDATE OF m
  ) q;

  IF v_monto < 0 OR round(v_monto,2)<>v_monto
     OR v_monto>9999999.99 THEN
    RAISE EXCEPTION 'Importe de incentivo inválido; requiere revisión' USING ERRCODE='22023';
  END IF;

  IF v_count=0 THEN
    INSERT INTO aquabri_private.aq_liquidaciones_incentivos_intentos
      (nonce,usuario_id,parametros_hash,pago_id,monto,caja_id)
    VALUES(p_nonce,v_uid,v_hash,NULL,0,NULL);
    RETURN jsonb_build_object('pago_id',NULL,'monto',0,'caja_id',NULL,'repetida',false);
  END IF;
  IF EXISTS(SELECT 1 FROM public.aq_incentivos_devengados
            WHERE id=ANY(v_ids) AND importe_empleado<=0) OR v_monto<=0 THEN
    RAISE EXCEPTION 'Existe un devengo con importe inválido' USING ERRCODE='22023';
  END IF;
  v_fecha := (now() AT TIME ZONE 'America/Guatemala')::date;

  -- Payout is the settlement of an accrued incentive, not a second operating expense.
  -- 'externo' is recorded only in aq_pagos_incentivos (no cash movement).
  IF p_origen='caja' THEN
    -- Lock cash writes while checking the opening/closing state and inserting.
    LOCK TABLE public.caja IN SHARE ROW EXCLUSIVE MODE;
    SELECT id INTO v_apertura FROM public.caja
    WHERE fecha=v_fecha AND tipo='apertura' ORDER BY id DESC LIMIT 1;
    IF v_apertura IS NULL OR EXISTS(
      SELECT 1 FROM public.caja WHERE fecha=v_fecha AND tipo='cierre' AND id>v_apertura
    ) THEN
      RAISE EXCEPTION 'La caja de hoy no está abierta; liquidación no realizada'
      USING ERRCODE='23514';
    END IF;
  END IF;

  INSERT INTO public.aq_pagos_incentivos
    (empleado_id,desde,hasta,monto,pagado_por,origen_pago)
  VALUES(p_empleado,p_desde,p_hasta,v_monto,v_uid,p_origen)
  RETURNING id INTO v_pago;

  UPDATE public.aq_incentivos_devengados
     SET pago_id=v_pago
   WHERE id=ANY(v_ids) AND pago_id IS NULL;
  GET DIAGNOSTICS v_actualizados = ROW_COUNT;
  IF v_actualizados<>v_count THEN
    RAISE EXCEPTION 'Conflicto al vincular incentivos: se revierte liquidación';
  END IF;

  IF p_origen='caja' THEN
    INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
    VALUES(v_fecha,'gasto',-v_monto,
       'Liquidación incentivo #'||v_pago::text||
       ' [AQ-LIQ-INCENTIVO:'||v_pago::text||'] [AQ-MP:EFECTIVO]',v_uid)
    RETURNING id INTO v_caja;
  END IF;

  INSERT INTO aquabri_private.aq_liquidaciones_incentivos_intentos
    (nonce,usuario_id,parametros_hash,pago_id,monto,caja_id)
  VALUES(p_nonce,v_uid,v_hash,v_pago,v_monto,v_caja);

  RETURN jsonb_build_object('pago_id',v_pago,'monto',v_monto,
    'caja_id',v_caja,'repetida',false);
END;
$$;

REVOKE ALL ON FUNCTION public.aq_liquidar_incentivos_auth_v2(text,bigint,date,date,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aq_liquidar_incentivos_auth_v2(text,bigint,date,date,text)
  TO authenticated;
COMMIT;
