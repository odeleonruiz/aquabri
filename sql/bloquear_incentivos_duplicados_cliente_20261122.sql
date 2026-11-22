-- AQUABRI | No repetir la autorización de incentivos de un mismo cliente.
-- Se conserva TODO el historial anterior. Nuevos registros se bloquean si
-- el cliente ya tuvo una autorización (activa o finalizada).
-- Reactivaciones futuras deben usar un flujo explícito distinto de "Autorizar".
CREATE OR REPLACE FUNCTION aquabri_private.aq_bloquear_incentivo_duplicado_cliente()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public,aquabri_private,pg_temp
AS $function$
DECLARE v_existente bigint; v_activo boolean;
BEGIN
  IF NEW.cliente_id IS NULL THEN
    RAISE EXCEPTION 'Selecciona un cliente válido para el incentivo'
      USING ERRCODE='22023';
  END IF;
  -- Serializar autorizaciones concurrentes desde distintas computadoras.
  PERFORM 1 FROM public.clientes WHERE id=NEW.cliente_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El cliente ya no existe' USING ERRCODE='23503';
  END IF;
  SELECT id,activo INTO v_existente,v_activo
  FROM public.aq_incentivos_captacion WHERE cliente_id=NEW.cliente_id
  ORDER BY activo DESC,id DESC LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Este cliente ya fue agregado a incentivos (registro #%: %). No se creó otra comisión.',
      v_existente, CASE WHEN v_activo THEN 'ACTIVO' ELSE 'FINALIZADO' END
      USING ERRCODE='23505', CONSTRAINT='aq_cliente_ya_incentivado';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS aq_prevenir_duplicado_incentivo_cliente ON public.aq_incentivos_captacion;
CREATE TRIGGER aq_prevenir_duplicado_incentivo_cliente
BEFORE INSERT ON public.aq_incentivos_captacion
FOR EACH ROW
EXECUTE FUNCTION aquabri_private.aq_bloquear_incentivo_duplicado_cliente();

-- Protección adicional para no tener dos incentivos activos del mismo cliente,
-- aunque correspondieran a productos distintos. No modifica registros anteriores.
CREATE UNIQUE INDEX IF NOT EXISTS aq_un_cliente_incentivado_activo
ON public.aq_incentivos_captacion(cliente_id) WHERE activo;

-- Ningún cliente puede aparecer dos veces activo en el futuro por UPDATE tampoco.
-- Los registros finalizados históricos se mantienen sin modificaciones.
