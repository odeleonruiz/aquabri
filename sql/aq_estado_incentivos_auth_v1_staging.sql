-- Solo staging: lectura de configuración de incentivos restringida al jefe.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_estado_incentivos_auth_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF ctx.rol_usuario <> 'jefe' THEN
   RAISE EXCEPTION 'Solo el jefe consulta la administración de incentivos' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
  'equipos',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id DESC) FROM public.aq_equipos_incentivo t),'[]'::jsonb),
  'incentivos',coalesce((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.id DESC) FROM public.aq_incentivos_captacion i),'[]'::jsonb)
 );
END $$;
REVOKE ALL ON FUNCTION public.aq_estado_incentivos_auth_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aq_estado_incentivos_auth_v1() TO authenticated;
COMMIT;