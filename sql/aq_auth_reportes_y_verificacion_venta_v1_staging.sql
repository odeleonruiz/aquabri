-- Ejecutado solo en staging (xzbawbkstaqvkwtqlqai).
-- Las RPC siguientes generan el token de compatibilidad en el servidor y no lo exponen al navegador.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_costos_lotes_auth_v1(p_desde date,p_hasta date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='public','pg_temp' AS $$
DECLARE c record; BEGIN
SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
IF NOT aquabri_private.tiene_permiso_actual('reportes') THEN RAISE EXCEPTION 'Sin permiso de reportes' USING ERRCODE='42501'; END IF;
IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta<p_desde THEN RAISE EXCEPTION 'Fechas invalidas'; END IF;
RETURN public.aq_costos_lotes_reporte(c.sesion_token,c.usuario_id,p_desde,p_hasta);
END $$;
CREATE OR REPLACE FUNCTION public.aq_total_incentivos_auth_v1(p_desde date,p_hasta date) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path='public','pg_temp' AS $$
DECLARE c record; BEGIN
SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
IF NOT aquabri_private.tiene_permiso_actual('reportes') THEN RAISE EXCEPTION 'Sin permiso de reportes' USING ERRCODE='42501'; END IF;
IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta<p_desde THEN RAISE EXCEPTION 'Fechas invalidas'; END IF;
RETURN public.aq_total_incentivos_reporte(c.sesion_token,c.usuario_id,p_desde,p_hasta);
END $$;
CREATE OR REPLACE FUNCTION public.aq_items_incentivados_auth_v1(p_desde date,p_hasta date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='public','pg_temp' AS $$
DECLARE c record; BEGIN
SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
IF NOT (aquabri_private.tiene_permiso_actual('reportes') OR aquabri_private.tiene_permiso_actual('comisiones')) THEN RAISE EXCEPTION 'Sin permiso de reportes o comisiones' USING ERRCODE='42501'; END IF;
IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta<p_desde THEN RAISE EXCEPTION 'Fechas invalidas'; END IF;
RETURN public.aq_items_incentivados(c.sesion_token,c.usuario_id,p_desde,p_hasta);
END $$;
CREATE OR REPLACE FUNCTION public.aq_lotes_resumen_auth_v1() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='public','pg_temp' AS $$
DECLARE c record; BEGIN
SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
IF c.rol_usuario<>'jefe' THEN RAISE EXCEPTION 'Solo el jefe puede consultar todos los lotes' USING ERRCODE='42501'; END IF;
RETURN public.aq_lotes_resumen(c.sesion_token,c.usuario_id);
END $$;
CREATE OR REPLACE FUNCTION public.aq_facturas_tipos_auth_v1(p_factura_ids bigint[])
RETURNS TABLE(factura_id bigint,tipo text) LANGUAGE plpgsql SECURITY DEFINER SET search_path='public','pg_temp' AS $$
DECLARE c record; BEGIN
SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
IF NOT aquabri_private.tiene_permiso_actual('facturas') THEN RAISE EXCEPTION 'Sin permiso para ver facturas' USING ERRCODE='42501'; END IF;
IF p_factura_ids IS NULL OR cardinality(p_factura_ids)>500 THEN RAISE EXCEPTION 'Lista de facturas invalida'; END IF;
RETURN QUERY SELECT f.factura_id,f.tipo FROM public.aq_facturas_clasificacion f WHERE f.factura_id=ANY(p_factura_ids);
END $$;
CREATE OR REPLACE FUNCTION public.aq_venta_puede_modificar_auth_v1(p_venta bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='public','pg_temp' AS $$
DECLARE c record; BEGIN
SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
IF p_venta IS NULL OR p_venta<=0 OR NOT aquabri_private.tiene_permiso_actual('ventas') THEN RETURN false; END IF;
RETURN EXISTS (SELECT 1 FROM public.ventas v WHERE v.id=p_venta AND (c.rol_usuario='jefe' OR v.usuario_id=c.usuario_id))
 AND NOT EXISTS (SELECT 1 FROM public.aq_incentivos_devengados m WHERE m.venta_id=p_venta AND m.pago_id IS NOT NULL);
END $$;
REVOKE ALL ON FUNCTION public.aq_costos_lotes_auth_v1(date,date),public.aq_total_incentivos_auth_v1(date,date),
 public.aq_items_incentivados_auth_v1(date,date),public.aq_lotes_resumen_auth_v1(),
 public.aq_facturas_tipos_auth_v1(bigint[]),public.aq_venta_puede_modificar_auth_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aq_costos_lotes_auth_v1(date,date),public.aq_total_incentivos_auth_v1(date,date),
 public.aq_items_incentivados_auth_v1(date,date),public.aq_lotes_resumen_auth_v1(),
 public.aq_facturas_tipos_auth_v1(bigint[]),public.aq_venta_puede_modificar_auth_v1(bigint) TO authenticated;
COMMIT;