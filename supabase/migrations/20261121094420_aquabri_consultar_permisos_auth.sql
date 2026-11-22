create function public.aq_mis_permisos_auth_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $func$
declare
    usuario_activo integer := aquabri_private.usuario_id_actual();
    rol_activo text;
    permisos jsonb;
begin
    if usuario_activo is null then
        raise exception 'Debes iniciar sesión como usuario autorizado' using errcode = '42501';
    end if;

    select u.rol into strict rol_activo
    from public.usuarios as u
    where u.id = usuario_activo;

    select coalesce(jsonb_agg(c.codigo order by c.codigo), '[]'::jsonb) into permisos
    from public.aq_permisos_catalogo as c
    where c.activo and aquabri_private.tiene_permiso_usuario(usuario_activo, c.codigo);

    return jsonb_build_object('id', usuario_activo, 'rol', rol_activo, 'permisos', permisos);
end;
$func$;

revoke all privileges on function public.aq_mis_permisos_auth_v1() from public, anon, authenticated, service_role;
grant execute on function public.aq_mis_permisos_auth_v1() to authenticated;
