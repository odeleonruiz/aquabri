-- AQUABRI: funciones nuevas. Ya preparadas en Supabase oficial, SIN EXECUTE público.
-- NO publicar mientras el frontend oficial use sesiones/usuarios con accesos abiertos.
-- Versión para revisión y reproducibilidad; no contiene datos reales de clientes.
-- Se necesita habilitar los ocho RPC durante el cambio coordinado, después de
-- probar el frontend contra staging y aplicar las nuevas reglas RLS.
BEGIN;

CREATE OR REPLACE FUNCTION public.aq_cerrar_sesion_segura_v1()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_token text; v_id integer;
BEGIN
  v_id := public.aq_sesion_legacy_usuario_actual_v1();
  IF v_id IS NULL THEN RETURN false; END IF;
  v_token := (pg_catalog.current_setting('request.headers',true)::jsonb)->>'x-aquabri-session';
  DELETE FROM public.sesiones
    WHERE usuario_id=v_id AND token=v_token;
  RETURN FOUND;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aq_desactivar_usuario_seguro_v1(p_id integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor integer;
BEGIN
 v_actor:=public.aq_sesion_legacy_usuario_actual_v1();
 IF v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios WHERE id=v_actor AND rol='jefe')
 THEN RAISE EXCEPTION 'Solo el jefe desactiva usuarios' USING ERRCODE='42501';END IF;
 UPDATE public.usuarios SET rol='bloqueado'
 WHERE id=p_id AND rol<>'jefe';
 IF NOT FOUND THEN RETURN false;END IF;
 DELETE FROM public.sesiones WHERE usuario_id=p_id;
 RETURN true;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aq_guardar_usuario_seguro_v1(p_id integer, p_nombre text, p_usuario text, p_password text, p_rol text, p_foto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_actor integer; v_destino public.usuarios%ROWTYPE;
 v_nombre text:=pg_catalog.btrim(p_nombre);
 v_username text:=pg_catalog.btrim(p_usuario);
 v_hash text; v_id integer;
BEGIN
 v_actor:=public.aq_sesion_legacy_usuario_actual_v1();
 IF v_actor IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.usuarios WHERE id=v_actor AND rol='jefe'
 ) THEN RAISE EXCEPTION 'Solo el jefe puede administrar usuarios' USING ERRCODE='42501'; END IF;

 IF v_nombre IS NULL OR length(v_nombre) NOT BETWEEN 2 AND 100
    OR v_username IS NULL OR length(v_username) NOT BETWEEN 2 AND 80
    OR v_username !~ '^[a-zA-Z0-9._-]+$'
    OR p_rol NOT IN ('jefe','vendedor','vendedor_editor','inventario')
    OR length(coalesce(p_password,''))>72
    OR length(coalesce(p_foto,''))>2000000
 THEN RAISE EXCEPTION 'Datos de usuario inválidos' USING ERRCODE='22023'; END IF;
 IF coalesce(p_foto,'')<>'' AND p_foto !~ '^data:image/(png|jpeg|webp);base64,' THEN
   RAISE EXCEPTION 'Formato de foto inválido' USING ERRCODE='22023';
 END IF;

 IF p_id IS NULL THEN
   IF p_rol='jefe' OR length(coalesce(p_password,''))<6 THEN
     RAISE EXCEPTION 'No puedes crear otra cuenta de jefe ni una clave insegura' USING ERRCODE='42501';
   END IF;
   v_hash:=extensions.crypt(p_password,extensions.gen_salt('bf',10));
   INSERT INTO public.usuarios(nombre,usuario,pass,rol,foto)
     VALUES(v_nombre,v_username,v_hash,p_rol,coalesce(p_foto,''))
   RETURNING id INTO v_id;
 ELSE
   SELECT * INTO v_destino FROM public.usuarios WHERE id=p_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Usuario inexistente' USING ERRCODE='22023'; END IF;
   IF v_destino.rol='jefe' AND v_destino.id<>v_actor THEN
     RAISE EXCEPTION 'No puedes modificar otra cuenta de jefe' USING ERRCODE='42501';
   END IF;
   IF v_destino.rol<>'jefe' AND p_rol='jefe' THEN
     RAISE EXCEPTION 'No puedes crear otra cuenta de jefe' USING ERRCODE='42501';
   END IF;
   IF coalesce(p_password,'')<>'' THEN
     IF length(p_password)<6 THEN RAISE EXCEPTION 'La clave debe tener al menos seis caracteres'; END IF;
     v_hash:=extensions.crypt(p_password,extensions.gen_salt('bf',10));
   END IF;
   UPDATE public.usuarios SET
     nombre=v_nombre, usuario=v_username,
     rol=CASE WHEN v_destino.rol='jefe' THEN 'jefe' ELSE p_rol END,
     foto=coalesce(p_foto,''),
     pass=coalesce(v_hash,pass)
   WHERE id=p_id;
   v_id:=p_id;
 END IF;
 RETURN (SELECT pg_catalog.jsonb_build_object(
    'id',u.id,'nombre',u.nombre,'usuario',u.usuario,'rol',u.rol
  ) FROM public.usuarios u WHERE u.id=v_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aq_login_usuario_seguro_v1(p_usuario text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_nombre text := pg_catalog.btrim(p_usuario);
  v_clave text;
  v_intentos integer;
  v_usuario public.usuarios%ROWTYPE;
  v_token text;
  v_expira timestamptz;
  v_valido boolean := false;
BEGIN
  IF v_nombre IS NULL OR pg_catalog.length(v_nombre) NOT BETWEEN 1 AND 80
    OR p_password IS NULL OR pg_catalog.length(p_password) NOT BETWEEN 1 AND 256
  THEN
    RETURN pg_catalog.jsonb_build_object('ok',false,'error','Usuario o contraseña incorrectos');
  END IF;

  v_clave := pg_catalog.encode(extensions.digest(pg_catalog.lower(v_nombre),'sha256'),'hex');

  INSERT INTO public.aq_auth_login_freno(clave,ventana,intentos,actualizado)
  VALUES(v_clave,now(),1,now())
  ON CONFLICT (clave) DO UPDATE SET
    ventana=CASE WHEN public.aq_auth_login_freno.ventana < now()-interval '15 minutes'
                 THEN now() ELSE public.aq_auth_login_freno.ventana END,
    intentos=CASE WHEN public.aq_auth_login_freno.ventana < now()-interval '15 minutes'
                  THEN 1 ELSE public.aq_auth_login_freno.intentos+1 END,
    actualizado=now()
  RETURNING intentos INTO v_intentos;

  IF v_intentos > 8 THEN
    RETURN pg_catalog.jsonb_build_object('ok',false,'error','Demasiados intentos; inténtalo más tarde');
  END IF;

  SELECT * INTO v_usuario
  FROM public.usuarios u
  WHERE u.usuario=v_nombre AND u.rol IN ('jefe','vendedor','vendedor_editor','inventario')
  LIMIT 1;

  IF FOUND THEN
    IF v_usuario.pass ~ '^\$2[aby]\$' THEN
      v_valido := (extensions.crypt(p_password,v_usuario.pass)=v_usuario.pass);
    ELSE
      v_valido := (v_usuario.pass=p_password);
    END IF;
  END IF;

  IF NOT v_valido THEN
    RETURN pg_catalog.jsonb_build_object('ok',false,'error','Usuario o contraseña incorrectos');
  END IF;

  v_token := pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
  v_expira := now()+interval '12 hours';
  INSERT INTO public.sesiones(usuario_id,token,expira_en)
    VALUES(v_usuario.id,v_token,v_expira);

  DELETE FROM public.aq_auth_login_freno WHERE clave=v_clave;

  RETURN pg_catalog.jsonb_build_object(
    'ok',true,
    'token',v_token,
    'expira_en',v_expira,
    'usuario',pg_catalog.jsonb_build_object(
      'id',v_usuario.id,'usuario',v_usuario.usuario,
      'nombre',v_usuario.nombre,'rol',v_usuario.rol,
      'empleado_id',v_usuario.empleado_id
    )
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aq_permisos_usuario_guardar_seguro_v1(p_id integer, p_permisos_custom text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor integer;v_json jsonb;
BEGIN
 v_actor:=public.aq_sesion_legacy_usuario_actual_v1();
 IF v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios WHERE id=v_actor AND rol='jefe')
 THEN RAISE EXCEPTION 'Solo el jefe administra permisos' USING ERRCODE='42501';END IF;
 IF length(coalesce(p_permisos_custom,''))>10000 THEN RAISE EXCEPTION 'Permisos fuera de rango';END IF;
 v_json:=p_permisos_custom::jsonb;
 IF jsonb_typeof(v_json)<>'array' OR jsonb_array_length(v_json)>100 THEN
   RAISE EXCEPTION 'Formato de permisos inválido';
 END IF;
 UPDATE public.usuarios SET permisos_custom=p_permisos_custom
   WHERE id=p_id AND rol<>'jefe';
 RETURN FOUND;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aq_sesion_legacy_usuario_actual_v1()
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_raw text;
  v_token text;
  v_uid integer;
BEGIN
  v_raw := pg_catalog.current_setting('request.headers',true);
  IF v_raw IS NULL OR v_raw='' THEN RETURN NULL; END IF;
  v_token := (v_raw::jsonb)->>'x-aquabri-session';
  IF v_token IS NULL OR v_token !~ '^[0-9a-f]{64}$' THEN RETURN NULL; END IF;
  SELECT s.usuario_id INTO v_uid
  FROM public.sesiones s JOIN public.usuarios u ON u.id=s.usuario_id
  WHERE s.token=v_token
    AND s.expira_en > now()
    AND u.rol IN ('jefe','vendedor','vendedor_editor','inventario')
  LIMIT 1;
  RETURN v_uid;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aq_sesion_perfil_seguro_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_usuario public.usuarios%ROWTYPE; v_id integer;
BEGIN
  v_id := public.aq_sesion_legacy_usuario_actual_v1();
  IF v_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_usuario FROM public.usuarios WHERE id=v_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN pg_catalog.jsonb_build_object('id',v_usuario.id,
    'nombre',v_usuario.nombre,'usuario',v_usuario.usuario,
    'rol',v_usuario.rol,'foto',v_usuario.foto,
    'permisos_custom',v_usuario.permisos_custom,'empleado_id',v_usuario.empleado_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aq_usuarios_listar_seguro_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_id integer; v_rol text;
BEGIN
  v_id := public.aq_sesion_legacy_usuario_actual_v1();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Sesión no autorizada' USING ERRCODE='42501';
  END IF;
  SELECT rol INTO v_rol FROM public.usuarios WHERE id=v_id;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id',u.id,'nombre',u.nombre,'usuario',u.usuario,
      'rol',u.rol,'foto',u.foto,
      'permisos_custom',u.permisos_custom,'empleado_id',u.empleado_id
    ) ORDER BY u.id),'[]'::jsonb)
    FROM public.usuarios u WHERE v_rol='jefe' OR u.id=v_id);
END;
$function$
;

REVOKE ALL ON FUNCTION public.aq_login_usuario_seguro_v1(text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.aq_sesion_legacy_usuario_actual_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.aq_sesion_perfil_seguro_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.aq_cerrar_sesion_segura_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.aq_usuarios_listar_seguro_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.aq_guardar_usuario_seguro_v1(integer,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.aq_permisos_usuario_guardar_seguro_v1(integer,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.aq_desactivar_usuario_seguro_v1(integer) FROM PUBLIC,anon,authenticated;
COMMIT;
