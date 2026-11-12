-- Reversión de permisos, solo para staging si se necesitan ensayos con PR #25.
-- No borra datos ni vuelve a crear contraseñas.
GRANT EXECUTE ON FUNCTION public.aq_login_usuario_seguro_v1(text,text)
  TO anon, authenticated;
