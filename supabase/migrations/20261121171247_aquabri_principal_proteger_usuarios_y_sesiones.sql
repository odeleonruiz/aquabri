set local lock_timeout='2s';
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
  WHERE u.usuario=v_nombre AND u.rol IN ('jefe','vendedor','vendedor_editor','inventario','reportes')
  LIMIT 1;

  IF FOUND THEN
    IF v_usuario.pass ~ '^\$2[aby]\$' THEN
      v_valido := (extensions.crypt(p_password,v_usuario.pass)=v_usuario.pass);
    ELSE
      v_valido := (v_usuario.pass=p_password);
    END IF;
  END IF;

  IF v_valido IS DISTINCT FROM true THEN
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
    AND u.rol IN ('jefe','vendedor','vendedor_editor','inventario','reportes')
  LIMIT 1;
  RETURN v_uid;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$function$
;
revoke all privileges on public.sesiones,public.usuarios from public,anon,authenticated;
drop policy acceso_total_sesiones on public.sesiones;
drop policy acceso_total_usuarios on public.usuarios;
grant select (id,nombre,usuario,rol,foto,permisos_custom,empleado_id) on public.usuarios to anon,authenticated;
grant insert (nombre,usuario,pass,rol,foto,empleado_id,permisos_custom), update (nombre,usuario,pass,rol,foto,empleado_id,permisos_custom),delete on public.usuarios to anon;
grant select (auth_uid) on public.usuarios to authenticated;
create policy aq_usuarios_perfil_auth on public.usuarios for select to authenticated using (auth_uid=(select auth.uid()) or (select aquabri_private.rol_actual())='jefe');
create policy aq_directorio_sesion on public.usuarios for select to anon using ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null);
create policy aq_usuarios_alta_jefe on public.usuarios for insert to anon with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
create policy aq_usuarios_edicion_jefe on public.usuarios for update to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe') with check ((select public.aq_sesion_legacy_rol_v1())='jefe');
create policy aq_usuarios_baja_jefe on public.usuarios for delete to anon using ((select public.aq_sesion_legacy_rol_v1())='jefe');
