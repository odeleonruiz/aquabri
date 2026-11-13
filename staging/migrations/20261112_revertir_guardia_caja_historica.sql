-- Retirar únicamente el control adicional instalado hoy: encontró aperturas históricas no cerradas que no deben detener la operación vigente.
-- Se conserva el trigger existente aq_guard_fecha_y_caja_venta_trg y todos los registros de negocio.
DROP TRIGGER IF EXISTS aq_ventas_guardia_caja_diaria ON public.ventas;
DROP FUNCTION IF EXISTS aquabri_private.aq_ventas_guardia_caja_diaria();