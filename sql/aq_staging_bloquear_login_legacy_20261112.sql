-- STAGING ÚNICAMENTE. NO EJECUTAR SOBRE PRODUCCIÓN.
-- La preview Auth usa Supabase Auth y Edge Function aq-auth-usuario-v2.
-- Prohibir que clientes públicos sigan generando sesiones legacy.
-- No elimina ni edita tablas, ventas, sesiones o usuarios.
REVOKE EXECUTE ON FUNCTION public.aq_login_usuario_seguro_v1(text,text)
  FROM anon, authenticated, PUBLIC;
