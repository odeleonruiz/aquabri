-- Operaciones de asistencia sobre las dos tablas ya instaladas.
CREATE SCHEMA aquabri_asistencia_privada;
REVOKE ALL ON SCHEMA aquabri_asistencia_privada FROM PUBLIC;
GRANT USAGE ON SCHEMA aquabri_asistencia_privada TO anon, authenticated;

CREATE FUNCTION aquabri_asistencia_privada.identidad() RETURNS integer
LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT COALESCE(public.aq_sesion_legacy_usuario_actual_v1(), aquabri_private.usuario_id_actual())
$$;

CREATE FUNCTION aquabri_asistencia_privada.estado(p_fecha date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_usuario integer := aquabri_asistencia_privada.identidad();
  v_hoy date := (now() AT TIME ZONE 'America/Guatemala')::date;
  v_jefe boolean;
  v_config public.aq_asistencia_config%ROWTYPE;
  v_resultado jsonb;
BEGIN
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'La sesión de Aquabri ha vencido.' USING ERRCODE = '42501';
  END IF;
  SELECT rol = 'jefe' INTO v_jefe FROM public.usuarios WHERE id = v_usuario;
  SELECT * INTO STRICT v_config FROM public.aq_asistencia_config WHERE id = 1;
  IF p_fecha IS NOT NULL AND v_jefe IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Solo el jefe puede consultar la asistencia del equipo.' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'hoy', v_hoy, 'activo', v_config.activo, 'fecha_inicio', v_config.fecha_inicio,
    'vigente', v_config.activo AND v_hoy >= v_config.fecha_inicio,
    'radio_metros', v_config.radio_metros, 'ubicacion_guardada', v_config.latitud IS NOT NULL,
    'marca', (SELECT jsonb_build_object('entrada', entrada, 'salida', salida)
              FROM public.aq_asistencia WHERE usuario_id = v_usuario AND fecha = v_hoy)
  ) INTO v_resultado;

  IF p_fecha IS NOT NULL THEN
    v_resultado := v_resultado || jsonb_build_object('registros', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('nombre', u.nombre, 'entrada', a.entrada,
                          'salida', a.salida) ORDER BY a.entrada, a.usuario_id), '[]'::jsonb)
      FROM public.aq_asistencia a JOIN public.usuarios u ON u.id = a.usuario_id
      WHERE a.fecha = p_fecha
    ));
  END IF;
  RETURN v_resultado;
END;
$$;

CREATE FUNCTION aquabri_asistencia_privada.configurar(
  p_accion text, p_lat double precision, p_lon double precision, p_precision double precision
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_usuario integer := aquabri_asistencia_privada.identidad();
  v_config public.aq_asistencia_config%ROWTYPE;
BEGIN
  IF v_usuario IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.usuarios WHERE id = v_usuario AND rol = 'jefe'
  ) THEN
    RAISE EXCEPTION 'Solo el jefe puede configurar la asistencia.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO STRICT v_config FROM public.aq_asistencia_config WHERE id = 1 FOR UPDATE;
  CASE p_accion
    WHEN 'ubicacion' THEN
      IF (p_lat BETWEEN -90 AND 90 AND p_lon BETWEEN -180 AND 180
          AND p_precision BETWEEN 0 AND v_config.radio_metros / 2.0) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'La ubicación es imprecisa. Acércate al lugar de marcación y vuelve a intentar.' USING ERRCODE = '22023';
      END IF;
      UPDATE public.aq_asistencia_config SET latitud = p_lat, longitud = p_lon WHERE id = 1;
    WHEN 'activar' THEN
      IF v_config.latitud IS NULL THEN
        RAISE EXCEPTION 'Guarda primero la ubicación del negocio.' USING ERRCODE = '22023';
      END IF;
      UPDATE public.aq_asistencia_config SET activo = true WHERE id = 1;
    WHEN 'desactivar' THEN
      UPDATE public.aq_asistencia_config SET activo = false WHERE id = 1;
    ELSE
      RAISE EXCEPTION 'Selecciona una acción de asistencia válida.' USING ERRCODE = '22023';
  END CASE;
END;
$$;

CREATE FUNCTION aquabri_asistencia_privada.marcar(
  p_tipo text, p_fecha date, p_lat double precision, p_lon double precision, p_precision double precision
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_usuario integer := aquabri_asistencia_privada.identidad();
  v_instante timestamptz := statement_timestamp();
  v_fecha date := (v_instante AT TIME ZONE 'America/Guatemala')::date;
  v_config public.aq_asistencia_config%ROWTYPE;
  v_distancia double precision;
  v_a double precision;
BEGIN
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'La sesión de Aquabri ha vencido.' USING ERRCODE = '42501';
  END IF;
  IF p_fecha IS DISTINCT FROM v_fecha THEN
    RAISE EXCEPTION 'Cambió el día en Guatemala. Actualiza la asistencia y vuelve a intentar.' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO STRICT v_config FROM public.aq_asistencia_config WHERE id = 1 FOR SHARE;
  IF NOT v_config.activo OR v_fecha < v_config.fecha_inicio THEN
    RAISE EXCEPTION 'La marcación de asistencia está desactivada.' USING ERRCODE = '22023';
  END IF;
  IF (p_lat BETWEEN -90 AND 90 AND p_lon BETWEEN -180 AND 180
      AND p_precision BETWEEN 0 AND v_config.radio_metros / 2.0) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'La ubicación es imprecisa. Activa la ubicación precisa y vuelve a intentar.' USING ERRCODE = '22023';
  END IF;
  v_a := sin(radians(p_lat - v_config.latitud) / 2)^2
       + cos(radians(v_config.latitud)) * cos(radians(p_lat))
         * sin(radians(p_lon - v_config.longitud) / 2)^2;
  v_distancia := 2 * 6371000 * asin(sqrt(greatest(0.0, least(1.0, v_a))));
  IF v_distancia > v_config.radio_metros THEN
    RAISE EXCEPTION 'Estás fuera del radio de marcación del negocio.' USING ERRCODE = '22023';
  END IF;

  CASE p_tipo
    WHEN 'entrada' THEN
      INSERT INTO public.aq_asistencia (usuario_id, fecha, entrada, entrada_distancia_m)
      VALUES (v_usuario, v_fecha, v_instante, v_distancia)
      ON CONFLICT (usuario_id, fecha) DO NOTHING;
    WHEN 'salida' THEN
      UPDATE public.aq_asistencia SET salida = greatest(v_instante, entrada), salida_distancia_m = v_distancia
      WHERE usuario_id = v_usuario AND fecha = v_fecha AND salida IS NULL;
      IF NOT FOUND AND NOT EXISTS (
        SELECT 1 FROM public.aq_asistencia WHERE usuario_id = v_usuario AND fecha = v_fecha AND salida IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'Debes registrar la entrada antes de marcar la salida.' USING ERRCODE = '22023';
      END IF;
    ELSE
      RAISE EXCEPTION 'Selecciona entrada o salida.' USING ERRCODE = '22023';
  END CASE;
END;
$$;

CREATE FUNCTION public.aq_asistencia_estado_v1(p_fecha date DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT aquabri_asistencia_privada.estado(p_fecha)
$$;
CREATE FUNCTION public.aq_asistencia_configurar_v1(
  p_accion text, p_lat double precision DEFAULT NULL, p_lon double precision DEFAULT NULL,
  p_precision double precision DEFAULT NULL
) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT aquabri_asistencia_privada.configurar(p_accion, p_lat, p_lon, p_precision)
$$;
CREATE FUNCTION public.aq_asistencia_marcar_v1(
  p_tipo text, p_fecha date, p_lat double precision, p_lon double precision, p_precision double precision
) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT aquabri_asistencia_privada.marcar(p_tipo, p_fecha, p_lat, p_lon, p_precision)
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA aquabri_asistencia_privada FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION aquabri_asistencia_privada.estado(date),
  aquabri_asistencia_privada.configurar(text, double precision, double precision, double precision),
  aquabri_asistencia_privada.marcar(text, date, double precision, double precision, double precision)
TO anon, authenticated;
REVOKE ALL ON FUNCTION public.aq_asistencia_estado_v1(date),
  public.aq_asistencia_configurar_v1(text, double precision, double precision, double precision),
  public.aq_asistencia_marcar_v1(text, date, double precision, double precision, double precision)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aq_asistencia_estado_v1(date),
  public.aq_asistencia_configurar_v1(text, double precision, double precision, double precision),
  public.aq_asistencia_marcar_v1(text, date, double precision, double precision, double precision)
TO anon, authenticated;
