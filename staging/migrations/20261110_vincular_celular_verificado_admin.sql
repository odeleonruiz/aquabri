-- AQUABRI STAGING: vínculo administrativo de celular Auth verificado con usuario original.
-- Se aplicó en aquabri-staging. No cambia public.usuarios.id, empleados ni comisiones.
-- El acceso al procedimiento está revocado a anon, authenticated y service_role.
-- El administrador lo invoca manualmente desde SQL Editor tras verificar la titularidad.
CREATE OR REPLACE FUNCTION aquabri_private.aq_vincular_celular_usuario_admin(
  p_usuario_id integer, p_auth_uid uuid
) RETURNS integer
LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $link$
DECLARE v_phone text; v_confirmada timestamptz; v_actual uuid;
BEGIN
  IF p_usuario_id IS NULL OR p_auth_uid IS NULL THEN
    RAISE EXCEPTION 'Falta identidad Auth y usuario existente' USING ERRCODE='22023';
  END IF;
  SELECT a.phone,a.phone_confirmed_at INTO v_phone,v_confirmada
    FROM auth.users a WHERE a.id=p_auth_uid;
  IF NOT FOUND OR v_confirmada IS NULL OR v_phone !~ '^[+]502[0-9]{8}$' THEN
    RAISE EXCEPTION 'Se necesita celular guatemalteco verificado'
    USING ERRCODE='42501';
  END IF;
  SELECT u.auth_uid INTO v_actual
    FROM public.usuarios u WHERE u.id=p_usuario_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe usuario original' USING ERRCODE='22023';
  END IF;
  IF v_actual IS NOT NULL AND v_actual<>p_auth_uid THEN
    RAISE EXCEPTION 'Usuario ya vinculado a otra identidad' USING ERRCODE='23505';
  END IF;
  IF EXISTS(SELECT 1 FROM public.usuarios u WHERE u.auth_uid=p_auth_uid AND u.id<>p_usuario_id) THEN
    RAISE EXCEPTION 'Identidad pertenece a otro usuario' USING ERRCODE='23505';
  END IF;
  UPDATE public.usuarios SET auth_uid=p_auth_uid
    WHERE id=p_usuario_id AND auth_uid IS NULL;
  RETURN p_usuario_id;
END
$link$;
REVOKE ALL ON FUNCTION aquabri_private.aq_vincular_celular_usuario_admin(integer,uuid)
FROM PUBLIC, anon, authenticated, service_role;
