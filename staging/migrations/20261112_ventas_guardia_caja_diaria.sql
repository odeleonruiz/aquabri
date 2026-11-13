-- AQUABRI | 2026-11-12 | Prevención de ventas fuera de fecha/caja.
-- Solo crea función y trigger; NO modifica ventas, caja, créditos ni inventario históricos.
-- Revertir si fuese necesario: DROP TRIGGER IF EXISTS aq_ventas_guardia_caja_diaria ON public.ventas;
-- DROP FUNCTION IF EXISTS aquabri_private.aq_ventas_guardia_caja_diaria();
CREATE OR REPLACE FUNCTION aquabri_private.aq_ventas_guardia_caja_diaria()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $aq_guard$
DECLARE
  v_hoy date := (transaction_timestamp() AT TIME ZONE 'America/Guatemala')::date;
  v_fecha_pendiente date;
  v_ultimo_control text;
BEGIN
  -- Nunca confiar en fechas antiguas de pantallas que permanecen abiertas toda la noche.
  IF NEW.fecha IS DISTINCT FROM v_hoy THEN
    RAISE EXCEPTION 'Venta rechazada: la fecha debe ser la de hoy (%) en Guatemala, no (%). Actualiza Ventas.', v_hoy, NEW.fecha
      USING ERRCODE = 'P0001';
  END IF;

  -- No basta con revisar el cierre de ayer: verificar cualquier fecha anterior aún abierta.
  SELECT pendientes.fecha INTO v_fecha_pendiente
  FROM (
    SELECT DISTINCT ON (c.fecha) c.fecha, c.tipo
    FROM public.caja AS c
    WHERE c.fecha < v_hoy AND c.tipo IN ('apertura', 'cierre')
    ORDER BY c.fecha DESC, c.id DESC
  ) AS pendientes
  WHERE pendientes.tipo = 'apertura'
  ORDER BY pendientes.fecha DESC
  LIMIT 1;

  IF v_fecha_pendiente IS NOT NULL THEN
    RAISE EXCEPTION 'Venta bloqueada: hay caja pendiente de cierre del %. El jefe debe cerrarla antes de vender.', v_fecha_pendiente
      USING ERRCODE = 'P0001';
  END IF;

  -- La última operación de control del día debe ser una apertura.
  SELECT c.tipo INTO v_ultimo_control
  FROM public.caja AS c
  WHERE c.fecha = v_hoy AND c.tipo IN ('apertura', 'cierre')
  ORDER BY c.id DESC
  LIMIT 1;

  IF v_ultimo_control IS DISTINCT FROM 'apertura' THEN
    RAISE EXCEPTION 'Venta bloqueada: no hay caja abierta hoy (%). Abre Caja antes de vender.', v_hoy
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$aq_guard$;

REVOKE ALL ON FUNCTION aquabri_private.aq_ventas_guardia_caja_diaria() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS aq_ventas_guardia_caja_diaria ON public.ventas;
CREATE TRIGGER aq_ventas_guardia_caja_diaria
BEFORE INSERT ON public.ventas
FOR EACH ROW
EXECUTE FUNCTION aquabri_private.aq_ventas_guardia_caja_diaria();

COMMENT ON FUNCTION aquabri_private.aq_ventas_guardia_caja_diaria()
IS 'Impide vender con fecha diferente al día Guatemala, con días anteriores sin cerrar, o sin caja abierta; no altera datos existentes.';