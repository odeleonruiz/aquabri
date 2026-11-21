CREATE OR REPLACE FUNCTION public.aq_enlace_puntos_consultar_v1(p_codigo text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'cliente', jsonb_build_object('nombre', c.nombre),
    'ptos', jsonb_build_object('puntos_totales', p.puntos_totales, 'puntos_canjeados', p.puntos_canjeados),
    'programa', (SELECT jsonb_build_object('nombre_programa', pc.nombre_programa, 'porcentaje', pc.porcentaje) FROM public.puntos_config pc ORDER BY pc.id LIMIT 1),
    'historial', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('tipo', h.tipo, 'puntos', h.puntos, 'fecha', h.fecha) ORDER BY h.id DESC)
      FROM (SELECT id, tipo, puntos, fecha FROM public.puntos_historial WHERE cliente_id=c.id ORDER BY id DESC LIMIT 30) h
    ), '[]'::jsonb))
  FROM aquabri_private.enlaces_puntos e
  JOIN public.clientes c ON c.id=e.cliente_id
  JOIN public.puntos_clientes p ON p.cliente_id=c.id AND p.activo
  WHERE p_codigo ~ '^[0-9a-f]{64}$' AND e.huella=extensions.digest(p_codigo,'sha256')
  LIMIT 1;
$function$
;
revoke all on function public.aq_enlace_puntos_consultar_v1(text) from public,anon,authenticated,service_role;
grant execute on function public.aq_enlace_puntos_consultar_v1(text) to anon,authenticated;
