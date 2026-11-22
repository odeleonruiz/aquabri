-- Defensa adicional: tabla transaccional privada de autorizaciones de reactivación.
-- Solo los procedimientos controlados del servidor pueden leer/escribir.
ALTER TABLE aquabri_private.aq_incentivo_reactivacion_permiso
ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON aquabri_private.aq_incentivo_reactivacion_permiso FROM PUBLIC,anon,authenticated;