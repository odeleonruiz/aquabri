set local lock_timeout='2s';
CREATE OR REPLACE FUNCTION public.aq_enlace_puntos_comprobante_sesion_v1(p_venta_id integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  actor integer := public.aq_sesion_legacy_usuario_actual_v1();
  jefe boolean := coalesce(public.aq_sesion_legacy_rol_v1() = 'jefe', false);
  cliente integer;
  codigo text;
BEGIN
  IF actor IS NULL
     OR (NOT jefe AND NOT coalesce(aquabri_private.tiene_permiso_usuario(actor,'ventas'),false)) THEN
    RETURN NULL;
  END IF;
  SELECT v.cliente_id INTO cliente
  FROM public.ventas v
  WHERE v.id = p_venta_id AND (jefe OR v.usuario_id = actor)
    AND EXISTS (SELECT 1 FROM public.puntos_clientes p WHERE p.cliente_id=v.cliente_id AND p.activo);
  IF cliente IS NULL THEN RETURN NULL; END IF;

  SELECT e.codigo_comprobante INTO codigo FROM aquabri_private.enlaces_puntos e WHERE e.cliente_id=cliente;
  IF codigo IS NOT NULL THEN RETURN codigo; END IF;
  codigo := encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO aquabri_private.enlaces_puntos AS e (cliente_id, huella, codigo_comprobante)
  VALUES (cliente, extensions.digest(codigo, 'sha256'), codigo)
  ON CONFLICT (cliente_id) DO UPDATE SET
    huella = CASE WHEN e.codigo_comprobante IS NULL THEN EXCLUDED.huella ELSE e.huella END,
    codigo_comprobante = coalesce(e.codigo_comprobante, EXCLUDED.codigo_comprobante)
  RETURNING e.codigo_comprobante INTO codigo;
  RETURN codigo;
END;
$function$
;
revoke all on function public.aq_enlace_puntos_comprobante_sesion_v1(integer) from public,anon,authenticated,service_role;
grant execute on function public.aq_enlace_puntos_comprobante_sesion_v1(integer) to anon;
CREATE OR REPLACE FUNCTION public.aq_enlace_puntos_gestionar_sesion_v1(p_cliente_id integer, p_revocar boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE codigo text;
BEGIN
  IF (SELECT public.aq_sesion_legacy_rol_v1()) IS DISTINCT FROM 'jefe' THEN
    RAISE EXCEPTION 'Solo el jefe puede gestionar enlaces' USING ERRCODE = '42501';
  END IF;
  IF p_revocar THEN
    DELETE FROM aquabri_private.enlaces_puntos WHERE cliente_id = p_cliente_id;
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.puntos_clientes WHERE cliente_id=p_cliente_id AND activo) THEN
    RAISE EXCEPTION 'Cliente sin membresía activa' USING ERRCODE = '22023';
  END IF;
  codigo := encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO aquabri_private.enlaces_puntos (cliente_id, huella, codigo_comprobante)
  VALUES (p_cliente_id, extensions.digest(codigo, 'sha256'), codigo)
  ON CONFLICT (cliente_id) DO UPDATE SET huella = EXCLUDED.huella, codigo_comprobante = EXCLUDED.codigo_comprobante;
  RETURN codigo;
END;
$function$
;
revoke all on function public.aq_enlace_puntos_gestionar_sesion_v1(integer,boolean) from public,anon,authenticated,service_role;
grant execute on function public.aq_enlace_puntos_gestionar_sesion_v1(integer,boolean) to anon;
alter table public."clientes" enable row level security;
revoke all on public."clientes" from public, anon, authenticated;
drop policy if exists "acceso_total_clientes" on public."clientes";
drop policy if exists "lectura_publica_clientes" on public."clientes";
create policy "aq_clientes_lectura_auth" on public."clientes" as PERMISSIVE for SELECT to authenticated using (aquabri_private.puede_ver_cliente(id));
grant SELECT on public."clientes" to authenticated;

grant select,insert,update,delete on public."clientes" to anon;
create policy aq_clientes_sesion_negocio on public."clientes" for all to anon using ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null) with check ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null);
alter table public."puntos_clientes" enable row level security;
revoke all on public."puntos_clientes" from public, anon, authenticated;
drop policy if exists "acceso_puntos_clientes" on public."puntos_clientes";
drop policy if exists "lectura_publica_puntos" on public."puntos_clientes";
create policy "aq_puntos_clientes_lectura_auth" on public."puntos_clientes" as PERMISSIVE for SELECT to authenticated using (((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id))));
grant SELECT on public."puntos_clientes" to authenticated;

grant select,insert,update,delete on public."puntos_clientes" to anon;
create policy aq_puntos_clientes_sesion_negocio on public."puntos_clientes" for all to anon using ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null) with check ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null);
alter table public."puntos_historial" enable row level security;
revoke all on public."puntos_historial" from public, anon, authenticated;
drop policy if exists "acceso_puntos_historial" on public."puntos_historial";
drop policy if exists "lectura_publica_historial" on public."puntos_historial";
create policy "aq_puntos_historial_lectura_autorizada_v1" on public."puntos_historial" as PERMISSIVE for SELECT to authenticated using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ((( SELECT aquabri_private.rol_actual() AS rol_actual) = 'jefe'::text) OR (( SELECT aquabri_private.tiene_permiso_actual('puntos'::text) AS tiene_permiso_actual) AND aquabri_private.puede_ver_cliente(cliente_id)))));
grant SELECT on public."puntos_historial" to authenticated;

grant select,insert,update,delete on public."puntos_historial" to anon;
create policy aq_puntos_historial_sesion_negocio on public."puntos_historial" for all to anon using ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null) with check ((select public.aq_sesion_legacy_usuario_actual_v1()) is not null);
