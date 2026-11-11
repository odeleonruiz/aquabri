-- AQUABRI STAGING ONLY: complete the Auth-native incentive read path.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_estado_incentivos_auth_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe' THEN
  RAISE EXCEPTION 'Solo jefe consulta administración de incentivos' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
  'equipos',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id DESC)
      FROM public.aq_equipos_incentivo t),'[]'::jsonb),
  'incentivos',coalesce((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.id DESC)
      FROM public.aq_incentivos_captacion i),'[]'::jsonb)
 );
END;
$$;

CREATE OR REPLACE FUNCTION public.aq_items_incentivados_auth_v1(p_desde date,p_hasta date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe'
 AND NOT (aquabri_private.tiene_permiso_actual('reportes')
       OR aquabri_private.tiene_permiso_actual('comisiones')) THEN
  RAISE EXCEPTION 'Sin permiso de reportes o comisiones' USING ERRCODE='42501';
 END IF;
 IF p_desde IS NULL OR p_hasta IS NULL OR p_desde>p_hasta
  OR p_hasta>p_desde+1826 THEN
  RAISE EXCEPTION 'Rango de fechas inválido' USING ERRCODE='22023';
 END IF;
 RETURN coalesce((
  SELECT jsonb_agg(DISTINCT m.venta_item_id)
  FROM public.aq_incentivos_devengados m
  JOIN public.ventas v ON v.id=m.venta_id
  WHERE m.fecha BETWEEN p_desde AND p_hasta
    AND v.estado NOT IN ('Cancelada','Anulado')
    AND (ctx.rol_usuario='jefe' OR
        (ctx.empleado_id IS NOT NULL AND m.empleado_id=ctx.empleado_id))
 ),'[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.aq_total_incentivos_auth_v1(p_desde date,p_hasta date)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
 IF ctx.rol_usuario<>'jefe'
 AND NOT aquabri_private.tiene_permiso_actual('reportes') THEN
  RAISE EXCEPTION 'Sin permiso de reportes' USING ERRCODE='42501';
 END IF;
 IF p_desde IS NULL OR p_hasta IS NULL OR p_desde>p_hasta
 OR p_hasta>p_desde+1826 THEN
  RAISE EXCEPTION 'Rango de fechas inválido' USING ERRCODE='22023';
 END IF;
 RETURN coalesce((
 SELECT sum(m.importe_empleado)
 FROM public.aq_incentivos_devengados m
 JOIN public.ventas v ON v.id=m.venta_id
 WHERE m.fecha BETWEEN p_desde AND p_hasta
 AND v.estado NOT IN ('Cancelada','Anulado')
 AND (ctx.rol_usuario='jefe' OR
      (ctx.empleado_id IS NOT NULL AND m.empleado_id=ctx.empleado_id))
 ),0);
END;
$$;

REVOKE ALL ON FUNCTION
 public.aq_estado_incentivos_auth_v1(),
 public.aq_items_incentivados_auth_v1(date,date),
 public.aq_total_incentivos_auth_v1(date,date)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.aq_estado_incentivos_auth_v1(),
 public.aq_items_incentivados_auth_v1(date,date),
 public.aq_total_incentivos_auth_v1(date,date)
 TO authenticated;
COMMIT;