-- AQUABRI STAGING ONLY: fix app startup without granting direct SELECT to usuarios.
BEGIN;
CREATE OR REPLACE FUNCTION public.aq_usuarios_resumen_auth_v1()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE ctx record;
BEGIN
  SELECT * INTO STRICT ctx FROM aquabri_private.aq_contexto_auth_nativo_v2();
  -- Boss can administer existing users; non-boss sees ONLY their own minimal profile.
  -- Never return password hashes, legacy sessions or another user's Auth UUID.
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',u.id,
      'nombre',u.nombre,
      'usuario',u.usuario,
      'rol',u.rol,
      'foto',u.foto,
      'permisos_custom',u.permisos_custom,
      'empleado_id',u.empleado_id,
      'auth_uid',u.auth_uid
    ) ORDER BY u.id)
    FROM public.usuarios u
    WHERE ctx.rol_usuario='jefe' OR u.id=ctx.usuario_id
  ),'[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.aq_usuarios_resumen_auth_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aq_usuarios_resumen_auth_v1() TO authenticated;
COMMIT;