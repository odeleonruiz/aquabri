-- AQUABRI STAGING ONLY. Read-only accounting reconciliation, no legacy session.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_auditar_pagos_incentivos_auth_v1(
  p_desde date, p_hasta date
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE
  ctx record;
  v_total integer;
  v_monto numeric;
  v_inconsistencias integer;
  v_detalle jsonb;
BEGIN
  SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
  IF ctx.rol_usuario<>'jefe' THEN
    RAISE EXCEPTION 'Solo jefe puede auditar pagos de incentivos' USING ERRCODE='42501';
  END IF;
  IF p_desde IS NULL OR p_hasta IS NULL OR p_desde>p_hasta
     OR p_hasta>p_desde+365
     OR p_hasta>(now() AT TIME ZONE 'America/Guatemala')::date THEN
    RAISE EXCEPTION 'Período de auditoría inválido' USING ERRCODE='22023';
  END IF;

  WITH pagos AS (
    SELECT p.id, p.empleado_id, p.monto, p.origen_pago, p.pagado_en,
      (SELECT count(*) FROM public.aq_incentivos_devengados d
       WHERE d.pago_id=p.id) AS cantidad_devengos,
      (SELECT coalesce(sum(d.importe_empleado),0)
       FROM public.aq_incentivos_devengados d WHERE d.pago_id=p.id) AS monto_devengado,
      t.caja_id, t.monto AS monto_intento,
      c.tipo AS tipo_caja, c.monto AS monto_caja, c.fecha AS fecha_caja,
      (SELECT count(*) FROM public.caja m
       WHERE m.notas LIKE ('%[AQ-LIQ-INCENTIVO:'||p.id::text||']%')
      ) AS movimientos_identificados
    FROM public.aq_pagos_incentivos p
    LEFT JOIN aquabri_private.aq_liquidaciones_incentivos_intentos t
      ON t.pago_id=p.id
    LEFT JOIN public.caja c ON c.id=t.caja_id
    WHERE (p.pagado_en AT TIME ZONE 'America/Guatemala')::date
      BETWEEN p_desde AND p_hasta
  ),
  revisados AS (
    SELECT pagos.*,
      array_remove(ARRAY[
        CASE WHEN cantidad_devengos=0 THEN 'sin_devengos_vinculados' END,
        CASE WHEN monto <> round(monto_devengado,2) THEN 'monto_no_coincide_con_devengos' END,
        CASE WHEN origen_pago='caja' AND
           (caja_id IS NULL OR tipo_caja IS DISTINCT FROM 'gasto'
            OR monto_caja IS DISTINCT FROM -monto)
          THEN 'salida_efectivo_inexistente_o_incorrecta' END,
        CASE WHEN origen_pago='caja' AND
           (fecha_caja IS DISTINCT FROM (pagado_en AT TIME ZONE 'America/Guatemala')::date)
          THEN 'fecha_caja_no_coincide' END,
        CASE WHEN origen_pago='externo' AND caja_id IS NOT NULL
          THEN 'pago_externo_afecto_caja' END,
        CASE WHEN origen_pago='caja' AND movimientos_identificados<>1
          THEN 'numero_movimientos_caja_incorrecto' END,
        CASE WHEN origen_pago='externo' AND movimientos_identificados<>0
          THEN 'pago_externo_tiene_salida_caja' END,
        CASE WHEN monto_intento IS NOT NULL AND monto_intento<>monto
          THEN 'intento_monto_inconsistente' END
      ]::text[],NULL::text) AS problemas
    FROM pagos
  )
  SELECT count(*)::integer, coalesce(sum(monto),0),
      count(*) FILTER(WHERE cardinality(problemas)>0)::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'pago_id',id,'empleado_id',empleado_id,'monto',monto,
        'monto_devengado',monto_devengado,'origen',origen_pago,
        'caja_id',caja_id,'problemas',to_jsonb(problemas)
      ) ORDER BY id) FILTER(WHERE cardinality(problemas)>0),'[]'::jsonb)
  INTO v_total, v_monto, v_inconsistencias, v_detalle
  FROM revisados;

  RETURN jsonb_build_object('desde',p_desde,'hasta',p_hasta,
     'pagos',v_total,'monto_total',coalesce(v_monto,0),
     'inconsistencias',v_inconsistencias,'detalle',v_detalle,
     'nota','Pago externo se verifica solo contra AQ: comprobar banco/transferencia fuera del sistema');
END;
$$;
REVOKE ALL ON FUNCTION public.aq_auditar_pagos_incentivos_auth_v1(date,date)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aq_auditar_pagos_incentivos_auth_v1(date,date)
 TO authenticated;
COMMIT;
