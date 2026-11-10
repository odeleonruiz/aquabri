-- AQUABRI | bloqueo prospectivo de ingresos duplicados en Caja
-- Aplicado y validado: aquabri-staging y aquabri-sistema, 2026-11-09.
-- No cambia ni elimina registros históricos; solo protege INSERT nuevos.
-- Identifica por ventas.id, NO por producto, cliente, fecha ni importe.
CREATE OR REPLACE FUNCTION public.aq_caja_evitar_ingreso_venta_duplicado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $fn$
BEGIN
  IF NEW.tipo = 'venta' AND NEW.venta_id IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(20261109, NEW.venta_id);
    IF EXISTS (
      SELECT 1 FROM public.caja c
      WHERE c.tipo='venta' AND c.venta_id=NEW.venta_id
    ) THEN
      RAISE EXCEPTION 'La venta % ya tiene ingreso registrado en Caja; se evitó duplicar el ingreso.', NEW.venta_id
        USING ERRCODE='23505';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION public.aq_caja_evitar_ingreso_venta_duplicado() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER aq_caja_evitar_ingreso_venta_duplicado_trg
BEFORE INSERT ON public.caja FOR EACH ROW
EXECUTE FUNCTION public.aq_caja_evitar_ingreso_venta_duplicado();

-- Prueba realizada con DO + subtransacciones:
-- primera entrada de venta sin caja: permitida y revertida;
-- segundo ingreso de una venta ya registrada: bloqueado SQLSTATE 23505;
-- historial principal antes/después: 101 grupos / 181 movimientos / Q5,661.
