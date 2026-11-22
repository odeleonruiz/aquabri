-- Bloqueo de invocaciones directas: la función anti-duplicados solo la ejecuta el trigger.
REVOKE ALL ON FUNCTION aquabri_private.aq_bloquear_incentivo_duplicado_cliente()
FROM PUBLIC,anon,authenticated;