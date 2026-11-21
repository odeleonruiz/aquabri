CREATE FUNCTION public.aq_permisos_administrar_listar_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_jefe integer; v_usuarios jsonb; v_catalogo jsonb; v_roles jsonb; v_excepciones jsonb;
BEGIN
 v_jefe := aquabri_private.usuario_id_actual();
 IF v_jefe IS NULL OR aquabri_private.rol_actual() IS DISTINCT FROM 'jefe' THEN
   RAISE EXCEPTION 'Solo el jefe administra permisos' USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',u.id,'nombre',u.nombre,'rol',u.rol) ORDER BY u.nombre),'[]'::jsonb)
 INTO v_usuarios FROM public.usuarios u WHERE u.rol<>'jefe';
 SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',c.codigo,'nombre',c.nombre,'grupo',c.grupo,'delegable',c.delegable) ORDER BY c.grupo,c.codigo),'[]'::jsonb)
 INTO v_catalogo FROM public.aq_permisos_catalogo c WHERE c.activo AND c.delegable;
 SELECT coalesce(jsonb_agg(jsonb_build_object('rol',r.rol,'codigo',r.codigo,'permitido',r.permitido) ORDER BY r.rol,r.codigo),'[]'::jsonb)
 INTO v_roles FROM public.aq_roles_permisos r WHERE r.permitido;
 SELECT coalesce(jsonb_agg(jsonb_build_object('usuario_id',o.usuario_id,'codigo',o.codigo,'permitido',o.permitido) ORDER BY o.usuario_id,o.codigo),'[]'::jsonb)
 INTO v_excepciones FROM public.aq_usuarios_permisos o;
 RETURN jsonb_build_object('usuarios',v_usuarios,'catalogo',v_catalogo,'roles',v_roles,'excepciones',v_excepciones);
END
$function$;

revoke all privileges on function public.aq_permisos_administrar_listar_v1() from public, anon, authenticated, service_role;
grant execute on function public.aq_permisos_administrar_listar_v1() to authenticated;
