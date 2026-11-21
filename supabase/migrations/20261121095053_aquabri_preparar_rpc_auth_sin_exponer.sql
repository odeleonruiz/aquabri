-- Instala las funciones del acceso seguro sin exponerlas a clientes.
-- No reemplaza funciones del acceso vigente ni ejecuta operaciones comerciales.
set local lock_timeout = '2s';
set local statement_timeout = '75s';

CREATE FUNCTION public.aq_registrar_venta_integral_v2(p_token text, p_uid bigint, p_nonce text, p_venta jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
 urol text; h text; prev public.aq_ventas_integrales_operacion%ROWTYPE;
 result jsonb; vid integer; v public.ventas%ROWTYPE;
 credito boolean; medio text; fecha_pago date; vencimiento date;
 it jsonb; pid integer; qty integer; extra integer; bid integer; qtyprincipal integer;
 cid integer; cash_id integer; credito_id integer; pts numeric(14,2):=0;
 saldo numeric(14,2); punto_id integer; item_pts numeric;
BEGIN
 IF p_token IS NULL OR length(p_token)<12 OR p_uid IS NULL OR p_nonce IS NULL
    OR length(p_nonce)<16 OR length(p_nonce)>120 THEN
    RAISE EXCEPTION 'Autenticacion o identificador de operacion invalidos';
 END IF;
 SELECT u.rol INTO urol
 FROM public.sesiones s JOIN public.usuarios u ON u.id=s.usuario_id
 WHERE s.token=p_token AND s.usuario_id=p_uid AND s.expira_en>now() LIMIT 1;
 IF urol IS NULL OR NOT aquabri_private.tiene_permiso_usuario(p_uid::integer,'ventas.registrar') THEN
    RAISE EXCEPTION 'Usuario no autorizado o sesion vencida';
 END IF;
 IF jsonb_typeof(p_venta)<>'object' OR jsonb_typeof(p_items)<>'array' THEN
    RAISE EXCEPTION 'Payload invalido';
 END IF;
 IF p_venta->>'aq_medio_pago' IS NULL OR
    p_venta->>'aq_medio_pago' NOT IN ('efectivo','transferencia','otro') THEN
    RAISE EXCEPTION 'Medio de pago invalido';
 END IF;
 medio := p_venta->>'aq_medio_pago';
 credito := coalesce((p_venta->>'aq_credito')::boolean,false);
 IF nullif(p_venta->>'aq_fecha_vencimiento','') IS NOT NULL THEN
   vencimiento := (p_venta->>'aq_fecha_vencimiento')::date;
 END IF;
 IF credito AND (nullif(p_venta->>'cliente_id','') IS NULL OR
                  coalesce((p_venta->>'total')::numeric,0)<=0 OR
                  coalesce((p_venta->>'pagado')::numeric,0)<>0) THEN
   RAISE EXCEPTION 'Venta a credito invalida';
 END IF;
 h:=md5(p_venta::text||':'||p_items::text);
 PERFORM pg_advisory_xact_lock(hashtext('AQ-V2:'||p_nonce)::bigint);
 SELECT * INTO prev FROM public.aq_ventas_integrales_operacion WHERE nonce=p_nonce;
 IF FOUND THEN
   IF prev.usuario_id<>p_uid OR prev.payload_hash<>h THEN
     RAISE EXCEPTION 'Identificador reutilizado con datos diferentes';
   END IF;
   RETURN prev.resultado||jsonb_build_object('repetida',true,'integral',true);
 END IF;
 SELECT public.aq_registrar_venta_completa(p_token,p_uid,p_nonce,p_venta,p_items) INTO result;
 IF (result->>'repetida')::boolean THEN
   RAISE EXCEPTION 'Venta V1 preexistente sin V2: conciliar manualmente';
 END IF;
 vid:=(result->>'id')::integer;
 SELECT * INTO STRICT v FROM public.ventas WHERE id=vid;
 IF v.estado IS DISTINCT FROM 'Entregado' AND NOT credito THEN
   RAISE EXCEPTION 'Estado distinto de Entregado requiere flujo de reserva aparte';
 END IF;
 IF NOT credito AND (v.pagado IS DISTINCT FROM v.total) THEN
   RAISE EXCEPTION 'Pago no coincide con el total en venta de contado';
 END IF;
 FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   pid:=(it->>'producto_id')::integer;
   qty:=(it->>'cant')::integer;
   extra:=coalesce((it->>'bonif_cant')::integer,0);
   bid:=(it->>'bonif_prod_id')::integer;
   qtyprincipal:=qty + CASE WHEN bid IS NULL THEN extra ELSE 0 END;
   UPDATE public.productos SET stock=coalesce(stock,0)-qtyprincipal WHERE id=pid;
   IF NOT FOUND THEN RAISE EXCEPTION 'Producto % inexistente',pid; END IF;
   UPDATE public.insumos i SET stock=coalesce(i.stock,0)-(
     SELECT coalesce(sum(trunc(pi.cant)::integer*qtyprincipal),0)
     FROM public.producto_insumos pi WHERE pi.insumo_id=i.id AND pi.producto_id=pid
   ) WHERE i.id IN (SELECT pi.insumo_id FROM public.producto_insumos pi WHERE pi.producto_id=pid);
   IF bid IS NOT NULL AND extra>0 THEN
     UPDATE public.productos SET stock=coalesce(stock,0)-extra WHERE id=bid;
     IF NOT FOUND THEN RAISE EXCEPTION 'Producto bonificado % inexistente',bid; END IF;
   END IF;
 END LOOP;
 IF credito THEN
   INSERT INTO public.creditos(cliente_id,venta_id,concepto,monto,pagado,fecha,fecha_vencimiento,estado,notas)
   VALUES(v.cliente_id,vid,'Venta #'||vid,v.total,0,v.fecha,vencimiento,'Pendiente','Auto V2 QA')
   RETURNING id INTO credito_id;
 ELSIF v.total>0 THEN
   fecha_pago:=(now() AT TIME ZONE 'America/Guatemala')::date;
   INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id,venta_id)
   VALUES(fecha_pago,'venta',v.total,
      'Venta #'||vid||' [AQ-MP:'||upper(medio)||'] [AQ-V2:'||p_nonce||']',p_uid,vid)
   RETURNING id INTO cash_id;
 END IF;
 IF NOT credito AND v.cliente_id IS NOT NULL AND EXISTS
    (SELECT 1 FROM public.puntos_config WHERE activo=true) THEN
   SELECT pc.id INTO punto_id
     FROM public.puntos_clientes pc
     WHERE pc.cliente_id=v.cliente_id AND pc.activo=true
     ORDER BY pc.id LIMIT 1 FOR UPDATE;
   IF FOUND THEN
     SELECT coalesce(round(sum(
       (x.item->>'precio')::numeric * (x.item->>'cant')::numeric * pp.porcentaje/100
     ),2),0) INTO pts
     FROM jsonb_array_elements(p_items) AS x(item)
     JOIN public.puntos_productos pp ON pp.producto_id=(x.item->>'producto_id')::integer
     WHERE pp.activo AND pp.porcentaje>0;
     IF pts>0 THEN
       UPDATE public.puntos_clientes SET puntos_totales=coalesce(puntos_totales,0)+pts
       WHERE id=punto_id
       RETURNING round(coalesce(puntos_totales,0)-coalesce(puntos_canjeados,0),2) INTO saldo;
       INSERT INTO public.puntos_historial(cliente_id,venta_id,tipo,puntos,descripcion)
       VALUES(v.cliente_id,vid,'acumulacion',pts,'Venta QA #'||vid);
     END IF;
   END IF;
 END IF;
 result:=result||jsonb_build_object('integral',true,'credito_id',credito_id,
  'caja_id',cash_id,'puntos_ganados',pts,'saldo_puntos',saldo);
 INSERT INTO public.aq_ventas_integrales_operacion(nonce,usuario_id,venta_id,payload_hash,resultado)
 VALUES(p_nonce,p_uid,vid,h,result);
 RETURN result;
END;
$function$;
revoke all privileges on function public.aq_registrar_venta_integral_v2(p_token text, p_uid bigint, p_nonce text, p_venta jsonb, p_items jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION aquabri_private.contexto_auth_legacy()
 RETURNS TABLE(usuario_id bigint, sesion_token text, rol_usuario text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uuid uuid;
        v_user public.usuarios%ROWTYPE;
        v_token text;
BEGIN
  v_uuid:=auth.uid();
  IF v_uuid IS NULL THEN
    RAISE EXCEPTION 'Debe iniciar sesión en Supabase Auth' USING ERRCODE='28000';
  END IF;
  -- Fail closed: the UUID must exist in Supabase Auth, and be linked by an admin.
  IF NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=v_uuid) THEN
    RAISE EXCEPTION 'La identidad no existe en Supabase Auth' USING ERRCODE='28000';
  END IF;
  SELECT * INTO v_user FROM public.usuarios WHERE auth_uid=v_uuid;
  IF NOT FOUND OR v_user.rol NOT IN ('jefe','vendedor','vendedor_editor','inventario') THEN
    RAISE EXCEPTION 'Esta cuenta no está autorizada en AQUABRI' USING ERRCODE='42501';
  END IF;
  IF has_any_column_privilege('anon', 'public.sesiones', 'SELECT,INSERT,UPDATE')
     OR has_any_column_privilege('authenticated', 'public.sesiones', 'SELECT,INSERT,UPDATE') THEN
    RAISE EXCEPTION 'El puente de sesiones todavía no está habilitado' USING ERRCODE='42501';
  END IF;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  INSERT INTO public.sesiones (usuario_id,token,expira_en)
  VALUES (v_user.id,v_token,now()+interval '3 minutes');
  usuario_id:=v_user.id;
  sesion_token:=v_token;
  rol_usuario:=v_user.rol;
  RETURN NEXT;
END;
$function$;
revoke all privileges on function aquabri_private.contexto_auth_legacy() from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_caja_abrir_seguro(p_token text, p_uid bigint, p_nonce text, p_fecha date, p_monto numeric, p_usuario_caja integer, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE rol text; ultimo text; h text; prev public.aq_caja_operaciones%ROWTYPE;
 idmov integer; resultado jsonb;
BEGIN
 IF coalesce(length(p_token),0)<12 OR coalesce(length(p_nonce),0)<16 OR
    coalesce(length(p_nonce),0)>120 OR p_uid IS NULL OR p_fecha IS NULL OR
    p_monto IS NULL OR p_monto<0 OR p_monto>1000000 OR round(p_monto,2)<>p_monto THEN
    RAISE EXCEPTION 'Datos de apertura invalidos';
 END IF;
 SELECT u.rol INTO rol FROM public.usuarios u JOIN public.sesiones s ON s.usuario_id=u.id
  WHERE s.token=p_token AND u.id=p_uid AND s.expira_en>now() LIMIT 1;
 IF rol IS NULL OR NOT aquabri_private.tiene_permiso_usuario(p_uid::integer,'caja.abrir') THEN
    RAISE EXCEPTION 'Sesion invalida';
 END IF;
 IF coalesce(p_usuario_caja,p_uid::int)<>p_uid AND rol<>'jefe' THEN
    RAISE EXCEPTION 'Solo jefe puede abrir la caja de otra persona';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.usuarios WHERE id=coalesce(p_usuario_caja,p_uid::int)) THEN
    RAISE EXCEPTION 'Responsable inexistente';
 END IF;
 IF p_fecha < (now() AT TIME ZONE 'America/Guatemala')::date AND rol<>'jefe' THEN
    RAISE EXCEPTION 'Solo jefe puede registrar apertura historica';
 END IF;
 h:=md5(concat_ws('|',p_fecha,p_monto,p_usuario_caja,coalesce(p_notas,'')));
 PERFORM pg_advisory_xact_lock(hashtext('AQ-CAJA:'||p_fecha::text)::bigint);
 SELECT * INTO prev FROM public.aq_caja_operaciones WHERE nonce=p_nonce;
 IF FOUND THEN
   IF prev.usuario_id<>p_uid OR prev.tipo<>'apertura' OR prev.payload_hash<>h
     THEN RAISE EXCEPTION 'Operacion repetida con datos distintos'; END IF;
   RETURN prev.resultado||jsonb_build_object('repetida',true);
 END IF;
 SELECT tipo INTO ultimo FROM public.caja
 WHERE fecha=p_fecha AND usuario_id=coalesce(p_usuario_caja,p_uid::integer)
   AND tipo IN ('apertura','cierre')
 ORDER BY id DESC LIMIT 1;
 IF ultimo='apertura' THEN RAISE EXCEPTION 'La caja ya esta abierta'; END IF;
 INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
 VALUES(p_fecha,'apertura',p_monto,
   trim(coalesce(p_notas,'')||' | Apertura SQL QA por usuario #'||p_uid),
   coalesce(p_usuario_caja,p_uid::int)) RETURNING id INTO idmov;
 resultado:=jsonb_build_object('movimiento_id',idmov,'tipo','apertura','monto',p_monto,'repetida',false);
 INSERT INTO public.aq_caja_operaciones(nonce,tipo,usuario_id,movimiento_id,payload_hash,resultado)
 VALUES(p_nonce,'apertura',p_uid,idmov,h,resultado);
 RETURN resultado;
END;$function$;
revoke all privileges on function public.aq_caja_abrir_seguro(p_token text, p_uid bigint, p_nonce text, p_fecha date, p_monto numeric, p_usuario_caja integer, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_caja_cerrar_seguro(p_token text, p_uid bigint, p_nonce text, p_fecha date, p_apertura_id integer, p_contado numeric, p_esperado_cliente numeric, p_num_movimientos integer, p_acepta_sin_clasificar boolean DEFAULT false, p_acepta_diferencia boolean DEFAULT false, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE rol text; idap integer; titular integer; fondo numeric; h text; prev public.aq_caja_operaciones%ROWTYPE;
 rowmov record; total numeric:=0; esperado numeric; qty integer:=0; sin_clasificar integer:=0;
 desconocidos integer:=0; medio text; mov numeric; ingreso boolean;
 idmov integer; resultado jsonb; diferencia numeric;
BEGIN
 IF coalesce(length(p_token),0)<12 OR coalesce(length(p_nonce),0)<16 OR
    coalesce(length(p_nonce),0)>120 OR p_uid IS NULL OR p_fecha IS NULL OR p_apertura_id IS NULL
    OR p_contado IS NULL OR round(p_contado,2)<>p_contado OR p_contado<0
    OR p_esperado_cliente IS NULL OR p_num_movimientos IS NULL THEN
    RAISE EXCEPTION 'Datos de cierre invalidos';
 END IF;
 SELECT u.rol INTO rol FROM public.usuarios u JOIN public.sesiones s ON s.usuario_id=u.id
  WHERE s.token=p_token AND u.id=p_uid AND s.expira_en>now() LIMIT 1;
 IF rol IS NULL OR NOT aquabri_private.tiene_permiso_usuario(p_uid::integer,'caja.cerrar') THEN
    RAISE EXCEPTION 'Sesion invalida';
 END IF;
 h:=md5(concat_ws('|',p_fecha,p_apertura_id,p_contado,p_esperado_cliente,
              p_num_movimientos,p_acepta_sin_clasificar,p_acepta_diferencia,coalesce(p_notas,'')));
 PERFORM pg_advisory_xact_lock(hashtext('AQ-CAJA:'||p_fecha::text)::bigint);
 SELECT * INTO prev FROM public.aq_caja_operaciones WHERE nonce=p_nonce;
 IF FOUND THEN
   IF prev.usuario_id<>p_uid OR prev.tipo<>'cierre' OR prev.payload_hash<>h
      THEN RAISE EXCEPTION 'Operacion repetida con datos distintos'; END IF;
   RETURN prev.resultado||jsonb_build_object('repetida',true);
 END IF;
 SELECT id,monto,usuario_id INTO idap,fondo,titular FROM public.caja
 WHERE id=p_apertura_id AND fecha=p_fecha AND tipo='apertura' FOR UPDATE;
 IF rol<>'jefe' AND titular IS DISTINCT FROM p_uid::integer THEN
   RAISE EXCEPTION 'Solo puedes cerrar tu propia caja' USING ERRCODE='42501';
 END IF;
 IF idap IS NULL OR idap<>p_apertura_id THEN RAISE EXCEPTION 'La apertura cambio o no existe'; END IF;
 IF EXISTS(SELECT 1 FROM public.caja WHERE fecha=p_fecha AND usuario_id IS NOT DISTINCT FROM titular AND tipo IN ('apertura','cierre') AND id>idap) THEN
   RAISE EXCEPTION 'Caja ya cerrada';
 END IF;
 total:=fondo;
 FOR rowmov IN SELECT id,tipo,monto,notas FROM public.caja
     WHERE fecha=p_fecha AND id>idap AND tipo NOT IN ('apertura','cierre')
       AND (titular=p_uid AND rol='jefe' OR usuario_id IS NOT DISTINCT FROM titular)
     ORDER BY id LOOP
   qty:=qty+1;
   IF rowmov.tipo NOT IN ('venta','cobro_credito','ingreso','entrada','gasto','egreso','salida','pago_proveedor') THEN
     desconocidos:=desconocidos+1;
     CONTINUE;
   END IF;
   medio:=substring(coalesce(rowmov.notas,'') from '(?i)\[AQ-MP:(EFECTIVO|TRANSFERENCIA|OTRO)\]');
   IF medio IS NULL THEN sin_clasificar:=sin_clasificar+1; END IF;
   IF upper(coalesce(medio,'')) IN ('TRANSFERENCIA','OTRO') THEN CONTINUE; END IF;
   ingreso:=rowmov.tipo IN ('venta','cobro_credito','ingreso','entrada');
   mov:=CASE WHEN ingreso THEN rowmov.monto ELSE -abs(rowmov.monto) END;
   total:=total+mov;
 END LOOP;
 esperado:=round(total,2);
 IF qty<>p_num_movimientos OR esperado<>round(p_esperado_cliente,2) THEN
   RAISE EXCEPTION 'Cambios en caja: recalcular movimientos antes de cerrar';
 END IF;
 IF desconocidos>0 THEN RAISE EXCEPTION 'Movimientos de tipo desconocido: revisarlos antes de cerrar'; END IF;
 IF sin_clasificar>0 AND NOT p_acepta_sin_clasificar THEN
   RAISE EXCEPTION 'Hay pagos sin medio identificado; requiere aceptacion';
 END IF;
 diferencia:=round(p_contado-esperado,2);
 IF diferencia<>0 AND NOT p_acepta_diferencia THEN
   RAISE EXCEPTION 'Diferencia de efectivo no confirmada';
 END IF;
 INSERT INTO public.caja(fecha,tipo,monto,notas,usuario_id)
 VALUES(p_fecha,'cierre',p_contado,
    trim(coalesce(p_notas,'')||' | Apertura #'||idap||' | Esperado '||esperado||
        ' | Contado '||p_contado||' | Diferencia '||diferencia||
        ' | Cierre SQL QA usuario #'||p_uid),
    titular) RETURNING id INTO idmov;
 resultado:=jsonb_build_object('movimiento_id',idmov,'tipo','cierre',
    'esperado',esperado,'contado',p_contado,'diferencia',diferencia,'repetida',false);
 INSERT INTO public.aq_caja_operaciones(nonce,tipo,usuario_id,movimiento_id,payload_hash,resultado)
 VALUES(p_nonce,'cierre',p_uid,idmov,h,resultado);
 RETURN resultado;
END;$function$;
revoke all privileges on function public.aq_caja_cerrar_seguro(p_token text, p_uid bigint, p_nonce text, p_fecha date, p_apertura_id integer, p_contado numeric, p_esperado_cliente numeric, p_num_movimientos integer, p_acepta_sin_clasificar boolean, p_acepta_diferencia boolean, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_vender_auth_v2(p_nonce text, p_venta jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record; venta_segura jsonb; cliente_id bigint;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('ventas.registrar') THEN RAISE EXCEPTION 'Rol sin permiso para vender'; END IF;
 IF p_venta IS NULL OR jsonb_typeof(p_venta)<>'object' THEN RAISE EXCEPTION 'Datos de venta invalidos'; END IF;
 IF nullif(p_venta->>'cliente_id','') IS NOT NULL THEN
  cliente_id:=(p_venta->>'cliente_id')::bigint;
  IF cliente_id<1 OR cliente_id>2147483647 THEN RAISE EXCEPTION 'Cliente invalido'; END IF;
  IF ctx.rol_usuario<>'jefe' AND NOT aquabri_private.puede_ver_cliente(cliente_id::integer) THEN
    RAISE EXCEPTION 'No puedes registrar ventas a clientes no autorizados' USING ERRCODE='42501';
  END IF;
 END IF;
 venta_segura:=jsonb_set(p_venta,'{usuario_id}',to_jsonb(ctx.usuario_id),true);
 RETURN public.aq_registrar_venta_integral_v2(ctx.sesion_token,ctx.usuario_id,p_nonce,venta_segura,p_items);
END; $function$;
revoke all privileges on function public.aq_vender_auth_v2(p_nonce text, p_venta jsonb, p_items jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_abrir_caja_auth_v2(p_nonce text, p_fecha date, p_monto numeric, p_usuario_caja integer DEFAULT NULL::integer, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('caja')
    OR NOT aquabri_private.tiene_permiso_actual('caja.abrir')
 THEN
   RAISE EXCEPTION 'No tienes permiso para abrir caja' USING ERRCODE='42501';
 END IF;
 IF ctx.rol_usuario <> 'jefe' AND p_usuario_caja IS NOT NULL AND p_usuario_caja <> ctx.usuario_id THEN
   RAISE EXCEPTION 'Solo puedes abrir tu propia caja' USING ERRCODE='42501';
 END IF;
 RETURN public.aq_caja_abrir_seguro(
   ctx.sesion_token,ctx.usuario_id,p_nonce,p_fecha,p_monto,
   coalesce(p_usuario_caja,ctx.usuario_id::integer),p_notas
 );
END;
$function$;
revoke all privileges on function public.aq_abrir_caja_auth_v2(p_nonce text, p_fecha date, p_monto numeric, p_usuario_caja integer, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_archivar_cliente_auth_v1(p_cliente_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record; c public.clientes%rowtype; v_hist integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario <> 'jefe' then
   raise exception 'Solo el jefe puede archivar clientes' using errcode='42501';
 end if;
 if p_cliente_id is null or p_cliente_id < 1 then
   raise exception 'Cliente invalido' using errcode='22023';
 end if;
 select * into c from public.clientes where id=p_cliente_id for update;
 if not found then raise exception 'Cliente no existe' using errcode='22023'; end if;
 if c.archivado_en is not null then
   return pg_catalog.jsonb_build_object('ok',true,'repetida',true,'id',c.id);
 end if;
 if coalesce(c.envases,0)>0
  or exists(select 1 from public.creditos cr where cr.cliente_id=c.id and coalesce(cr.monto,0)>coalesce(cr.pagado,0))
  or exists(select 1 from public.ventas v where v.cliente_id=c.id and v.estado in ('Pendiente','Preparando','En Camino'))
 then
   raise exception 'Hay envases, creditos o pedidos pendientes para este cliente' using errcode='22023';
 end if;
 insert into public.clientes_eliminados(
 nombre,ruta,telefono,direccion,lat,lng,tiene_exhibidor,datos_completos,
 fecha_eliminacion,eliminado_por,cliente_original_id
 )
 values (c.nombre,c.ruta,c.telefono,c.direccion,c.lat,c.lng,c.tiene_exhibidor,
 pg_catalog.to_jsonb(c),(now() at time zone 'America/Guatemala')::date,
 (select nombre from public.usuarios where id=ctx.usuario_id),c.id)
 returning id into v_hist;
 update public.clientes set archivado_en=now(),archivado_por=ctx.usuario_id where id=c.id;
 return pg_catalog.jsonb_build_object('ok',true,'id',c.id,'historial_id',v_hist);
end;$function$;
revoke all privileges on function public.aq_archivar_cliente_auth_v1(p_cliente_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_asignar_permiso_auth_v1(p_usuario_id integer, p_codigo text, p_permitido boolean DEFAULT NULL::boolean, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_jefe integer; v_destino public.usuarios%ROWTYPE; v_anterior boolean; v_existia boolean; v_delegable boolean;
BEGIN
 SELECT id INTO v_jefe FROM public.usuarios
 WHERE auth_uid=(SELECT auth.uid()) AND rol='jefe' LIMIT 1;
 IF v_jefe IS NULL THEN
   RAISE EXCEPTION 'Solo el jefe administra permisos' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_destino FROM public.usuarios WHERE id=p_usuario_id FOR UPDATE;
 IF NOT FOUND OR v_destino.rol='jefe' THEN
   RAISE EXCEPTION 'Solo se pueden modificar permisos de empleados, no los del jefe' USING ERRCODE='42501';
 END IF;
 SELECT c.delegable INTO v_delegable FROM public.aq_permisos_catalogo c WHERE c.codigo=p_codigo AND c.activo;
 IF NOT FOUND OR NOT v_delegable THEN
   RAISE EXCEPTION 'Permiso inexistente o reservado exclusivamente al jefe' USING ERRCODE='42501';
 END IF;
 IF length(coalesce(p_motivo,''))>250 THEN
   RAISE EXCEPTION 'Motivo demasiado largo';
 END IF;
 SELECT o.permitido INTO v_anterior FROM public.aq_usuarios_permisos o
 WHERE o.usuario_id=p_usuario_id AND o.codigo=p_codigo;
 v_existia:=FOUND;
 IF (p_permitido IS NULL AND NOT v_existia)
   OR (p_permitido IS NOT NULL AND v_existia AND p_permitido=v_anterior) THEN
   RETURN jsonb_build_object('sin_cambios',true,'usuario_id',p_usuario_id,
     'codigo',p_codigo,'efectivo',aquabri_private.tiene_permiso_usuario(p_usuario_id,p_codigo));
 END IF;
 IF p_permitido IS NULL THEN
   DELETE FROM public.aq_usuarios_permisos
     WHERE usuario_id=p_usuario_id AND codigo=p_codigo;
 ELSE
   INSERT INTO public.aq_usuarios_permisos
   (usuario_id,codigo,permitido,actualizado_por,motivo,actualizado_en)
   VALUES(p_usuario_id,p_codigo,p_permitido,v_jefe,p_motivo,now())
   ON CONFLICT (usuario_id,codigo) DO UPDATE SET
     permitido=EXCLUDED.permitido,actualizado_por=EXCLUDED.actualizado_por,
     motivo=EXCLUDED.motivo,actualizado_en=EXCLUDED.actualizado_en;
 END IF;
 INSERT INTO public.aq_permisos_auditoria
 (usuario_id,codigo,valor_anterior,valor_nuevo,modificado_por,motivo)
 VALUES(p_usuario_id,p_codigo,v_anterior,p_permitido,v_jefe,p_motivo);
 RETURN jsonb_build_object('sin_cambios',false,'usuario_id',p_usuario_id,
     'codigo',p_codigo,'permitido',p_permitido,
     'efectivo',aquabri_private.tiene_permiso_usuario(p_usuario_id,p_codigo));
END
$function$;
revoke all privileges on function public.aq_asignar_permiso_auth_v1(p_usuario_id integer, p_codigo text, p_permitido boolean, p_motivo text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_borrar_ruta_auth_v1(p_ruta_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_cuantas integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' then raise exception 'Solo jefe puede borrar rutas' using errcode='42501';end if;
 if not exists(select 1 from public.rutas where id=p_ruta_id for update) then
   raise exception 'Ruta inexistente' using errcode='22023';
 end if;
 delete from public.ruta_paradas where ruta_id=p_ruta_id;
 get diagnostics v_cuantas=row_count;
 delete from public.rutas where id=p_ruta_id;
 return pg_catalog.jsonb_build_object('ok',true,'paradas_eliminadas',v_cuantas);
end;
$function$;
revoke all privileges on function public.aq_borrar_ruta_auth_v1(p_ruta_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_cancelar_venta_contado_auth_v1(p_venta bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record; v public.ventas%ROWTYPE; i record; c public.caja%ROWTYPE;
  count_caja integer; stock_antes integer;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('ventas') THEN
  RAISE EXCEPTION 'Sin permiso para cancelar ventas' USING ERRCODE='42501';
 END IF;
 IF p_venta IS NULL OR p_venta<1 OR p_venta>2147483647 THEN RAISE EXCEPTION 'Venta invalida'; END IF;
 SELECT * INTO v FROM public.ventas WHERE id=p_venta::integer FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
 IF v.estado IN ('Cancelada','Anulado') THEN RAISE EXCEPTION 'Venta ya cancelada'; END IF;
 IF ctx.rol_usuario <> 'jefe' AND
    (v.usuario_id IS DISTINCT FROM ctx.usuario_id::integer OR
     v.fecha IS DISTINCT FROM (now() AT TIME ZONE 'America/Guatemala')::date) THEN
  RAISE EXCEPTION 'Solo puedes cancelar ventas propias del dia' USING ERRCODE='42501';
 END IF;
 -- No intentar revertir movimientos de credito, abonos ni puntos gastados.
 IF v.estado <> 'Entregado' OR coalesce(v.total,0)<=0 OR
    v.total IS DISTINCT FROM v.pagado THEN
  RAISE EXCEPTION 'Esta venta requiere ajuste supervisado (estado o pago parcial)';
 END IF;
 IF EXISTS(SELECT 1 FROM public.creditos WHERE venta_id=v.id OR concepto='Venta #'||v.id) THEN
  RAISE EXCEPTION 'No puedes cancelar una venta con credito: requiere conciliacion';
 END IF;
 IF EXISTS(SELECT 1 FROM public.puntos_historial WHERE venta_id=v.id) THEN
  RAISE EXCEPTION 'Venta con puntos acumulados: requiere conciliacion';
 END IF;
 IF EXISTS(SELECT 1 FROM public.aq_incentivos_devengados
           WHERE venta_id=v.id AND pago_id IS NOT NULL) THEN
  RAISE EXCEPTION 'Venta con incentivos liquidados: requiere ajuste supervisado';
 END IF;
 SELECT count(*) INTO count_caja FROM public.caja WHERE venta_id=v.id;
 IF count_caja <> 1 THEN
  RAISE EXCEPTION 'La venta no tiene un unico movimiento de caja concilable';
 END IF;
 SELECT * INTO c FROM public.caja WHERE venta_id=v.id FOR UPDATE;
 IF c.tipo<>'venta' OR c.monto IS DISTINCT FROM v.total OR
    c.usuario_id IS DISTINCT FROM v.usuario_id OR
    NOT (coalesce(c.notas,'') LIKE '%[AQ-V2:%') THEN
  RAISE EXCEPTION 'Movimiento de caja de venta no coincide';
 END IF;
 IF EXISTS (SELECT 1 FROM public.caja x
   WHERE x.fecha=c.fecha AND x.tipo='cierre' AND x.id>c.id) THEN
  RAISE EXCEPTION 'La caja de esta venta ya fue cerrada: solicita ajuste supervisado';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.venta_items WHERE venta_id=v.id) THEN
  RAISE EXCEPTION 'Venta sin detalle; requiere revision';
 END IF;
 -- Devolver existencia de producto e insumo por las mismas cantidades descontadas por la venta integral.
 FOR i IN SELECT vi.producto_id,
        SUM(vi.cant + CASE WHEN vi.bonif_prod_id IS NULL THEN coalesce(vi.bonif_cant,0) ELSE 0 END) unidades
       FROM public.venta_items vi WHERE vi.venta_id=v.id AND vi.producto_id IS NOT NULL
       GROUP BY vi.producto_id ORDER BY vi.producto_id LOOP
  IF i.unidades<>trunc(i.unidades) OR i.unidades<0 THEN
   RAISE EXCEPTION 'Cantidad irregular; requiere revision';
  END IF;
  UPDATE public.productos SET stock=coalesce(stock,0)+i.unidades::integer WHERE id=i.producto_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado'; END IF;
  UPDATE public.insumos ins SET stock=coalesce(ins.stock,0)+
      (SELECT coalesce(sum(trunc(pi.cant)::integer * i.unidades::integer),0)
       FROM public.producto_insumos pi WHERE pi.insumo_id=ins.id AND pi.producto_id=i.producto_id)
      WHERE ins.id IN (SELECT pi.insumo_id FROM public.producto_insumos pi WHERE pi.producto_id=i.producto_id);
 END LOOP;
 FOR i IN SELECT vi.bonif_prod_id producto_id,sum(coalesce(vi.bonif_cant,0)) unidades
       FROM public.venta_items vi WHERE vi.venta_id=v.id AND vi.bonif_prod_id IS NOT NULL
       GROUP BY vi.bonif_prod_id ORDER BY vi.bonif_prod_id LOOP
  UPDATE public.productos SET stock=coalesce(stock,0)+i.unidades::integer WHERE id=i.producto_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto bonificado no encontrado'; END IF;
 END LOOP;
 -- El disparador AFTER UPDATE de ventas revierte FIFO e incentivos devengados, no pagados.
 UPDATE public.ventas SET estado='Cancelada',
   cancelado_por=(SELECT nombre FROM public.usuarios WHERE id=ctx.usuario_id),
   fecha_cancelacion=(now() AT TIME ZONE 'America/Guatemala')::date
 WHERE id=v.id;
 -- Eliminar únicamente la entrada exacta y validada, nunca cobros de otros creditos.
 DELETE FROM public.caja WHERE id=c.id;
 RETURN jsonb_build_object('id',v.id,'cancelada',true,'caja_revertida',c.id,'tipo','contado_sin_ajustes');
END;
$function$;
revoke all privileges on function public.aq_cancelar_venta_contado_auth_v1(p_venta bigint) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_canjear_puntos_auth_v1(p_nonce text, p_qr_id integer, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record;v_prev public.aq_puntos_canjes_operaciones_auth%rowtype;
 v_qr public.puntos_canjes_qr%rowtype;
 v_cuenta public.puntos_clientes%rowtype;
 v_item jsonb;v_prod integer;v_qty integer;v_precio numeric;v_nombre text;
 v_total numeric:=0;v_saldo numeric;v_venta integer;
 v_productos integer[]:='{}';v_descripcion text:='';v_resultado jsonb;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if not aquabri_private.tiene_permiso_actual('puntos') then
  raise exception 'Sin permiso para canjes de puntos' using errcode='42501';end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120 or
    p_qr_id is null or p_qr_id<1 or p_items is null or
    pg_catalog.jsonb_typeof(p_items)<>'array' or
    pg_catalog.jsonb_array_length(p_items) not between 1 and 100 then
  raise exception 'Solicitud de canje inválida' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(20261115,pg_catalog.hashtext(p_nonce));
 select * into v_prev from public.aq_puntos_canjes_operaciones_auth where nonce=p_nonce for update;
 if found then
  if v_prev.usuario_id<>ctx.usuario_id or v_prev.qr_id<>p_qr_id or v_prev.datos<>p_items then
    raise exception 'Nonce de canje reutilizado con otros datos' using errcode='23505';end if;
  return v_prev.resultado||pg_catalog.jsonb_build_object('repetida',true);
 end if;
 select * into v_qr from public.puntos_canjes_qr where id=p_qr_id for update;
 if not found or coalesce(v_qr.usado,false) or v_qr.expira_at is null
   or v_qr.expira_at<=now() then
  raise exception 'Código QR utilizado, expirado o inexistente' using errcode='42501';end if;
 if not exists(select 1 from public.clientes where id=v_qr.cliente_id and archivado_en is null) then
  raise exception 'Cliente inexistente o archivado' using errcode='22023';end if;
 if ctx.rol_usuario<>'jefe' and not aquabri_private.puede_ver_cliente(v_qr.cliente_id) then
  raise exception 'Cliente fuera de cartera autorizada' using errcode='42501';end if;
 select * into v_cuenta from public.puntos_clientes where cliente_id=v_qr.cliente_id for update;
 if not found or not coalesce(v_cuenta.activo,false) then
  raise exception 'Cliente sin membresía activa' using errcode='42501';end if;
 v_saldo:=coalesce(v_cuenta.puntos_totales,0)-coalesce(v_cuenta.puntos_canjeados,0);
 for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
  v_prod:=nullif(v_item->>'producto_id','')::integer;
  v_qty:=coalesce(nullif(v_item->>'cant','')::integer,0);
  if v_prod is null or v_prod<1 or v_prod=any(v_productos) or v_qty not between 1 and 5000 then
     raise exception 'Artículo de canje repetido o cantidad inválida' using errcode='22023';end if;
  select p.precio,p.nombre into v_precio,v_nombre from public.productos p
  where p.id=v_prod and coalesce(p.activo,true) for update;
  if not found or coalesce(v_precio,0)<=0 then
     raise exception 'Producto de canje no disponible' using errcode='22023';end if;
  if not exists(select 1 from public.puntos_productos pp
     where pp.producto_id=v_prod and pp.activo=true and pp.porcentaje>0) then
     raise exception 'Producto no habilitado para puntos' using errcode='42501';end if;
  if (select coalesce(stock,0) from public.productos where id=v_prod)<v_qty then
     raise exception 'No hay stock suficiente para el producto %',v_prod using errcode='22023';end if;
  v_productos:=pg_catalog.array_append(v_productos,v_prod);
  v_total:=v_total+pg_catalog.round(v_precio*v_qty,2);
  v_descripcion:=v_descripcion||case when v_descripcion='' then '' else ', ' end
     ||v_qty::text||'x '||v_nombre;
 end loop;
 if v_total<=0 or v_total>v_saldo then
   raise exception 'Puntos insuficientes para el canje' using errcode='22023';end if;
 update public.puntos_canjes_qr set usado=true where id=p_qr_id;
 insert into public.ventas(cliente_id,fecha,total,pagado,estado,entrega,notas,
   tipo_venta,usuario_id,bonificaciones)
 values(v_qr.cliente_id,(now() at time zone 'America/Guatemala')::date,0,0,'Entregado',
   'Entrega Inmediata','CANJE DE PUNTOS','canje',ctx.usuario_id,'')
 returning id into v_venta;
 for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
  v_prod:=(v_item->>'producto_id')::integer;
  v_qty:=(v_item->>'cant')::integer;
  select nombre into v_nombre from public.productos where id=v_prod;
  insert into public.venta_items(venta_id,producto_id,nombre,cant,precio,descuento,es_canje)
  values(v_venta,v_prod,v_nombre,v_qty,0,0,true);
  update public.productos set stock=stock-v_qty where id=v_prod and stock>=v_qty;
  if not found then raise exception 'Stock modificado simultáneamente: canje revertido' using errcode='40001';end if;
 end loop;
 update public.puntos_clientes set puntos_canjeados=coalesce(puntos_canjeados,0)+v_total
   where id=v_cuenta.id;
 insert into public.puntos_historial(cliente_id,venta_id,tipo,puntos,descripcion)
 values(v_qr.cliente_id,v_venta,'canje',-v_total,'Canje QR — '||v_descripcion);
 v_resultado:=pg_catalog.jsonb_build_object('ok',true,'id',v_venta,'cliente_id',v_qr.cliente_id,
   'puntos',v_total,'saldo_final',v_saldo-v_total,'repetida',false);
 insert into public.aq_puntos_canjes_operaciones_auth(nonce,usuario_id,qr_id,datos,resultado)
 values(p_nonce,ctx.usuario_id,p_qr_id,p_items,v_resultado);
 return v_resultado;
end;$function$;
revoke all privileges on function public.aq_canjear_puntos_auth_v1(p_nonce text, p_qr_id integer, p_items jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_cerrar_caja_auth_v2(p_nonce text, p_fecha date, p_apertura_id integer, p_contado numeric, p_esperado_cliente numeric, p_num_movimientos integer, p_acepta_sin_clasificar boolean DEFAULT false, p_acepta_diferencia boolean DEFAULT false, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('caja')
    OR NOT aquabri_private.tiene_permiso_actual('caja.cerrar')
 THEN
   RAISE EXCEPTION 'No tienes permiso para cerrar caja' USING ERRCODE='42501';
 END IF;
 RETURN public.aq_caja_cerrar_seguro(
   ctx.sesion_token,ctx.usuario_id,p_nonce,p_fecha,p_apertura_id,
   p_contado,p_esperado_cliente,p_num_movimientos,
   p_acepta_sin_clasificar,p_acepta_diferencia,p_notas
 );
END;
$function$;
revoke all privileges on function public.aq_cerrar_caja_auth_v2(p_nonce text, p_fecha date, p_apertura_id integer, p_contado numeric, p_esperado_cliente numeric, p_num_movimientos integer, p_acepta_sin_clasificar boolean, p_acepta_diferencia boolean, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_cobrar_auth_v2(p_nonce text, p_cliente_id bigint, p_monto numeric, p_medio text, p_notas text, p_credito_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  ctx record;
BEGIN
  SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();

  IF NOT aquabri_private.tiene_permiso_actual('creditos.cobrar') THEN
    RAISE EXCEPTION 'Rol sin permiso para cobrar'
      USING ERRCODE='42501';
  END IF;

  IF p_cliente_id IS NULL OR p_cliente_id <= 0 OR p_cliente_id > 2147483647 THEN
    RAISE EXCEPTION 'Cliente de cobro inválido';
  END IF;

  -- Un vendedor autorizado puede cobrar un crédito de cualquier cliente,
  -- incluso si no creó ni tiene asignado al cliente.
  -- Este permiso NO concede lectura o edición general de los datos del cliente.
  IF p_credito_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.creditos cr
    WHERE cr.id=p_credito_id AND cr.cliente_id=p_cliente_id
  ) THEN
    RAISE EXCEPTION 'Crédito no corresponde a cliente indicado';
  END IF;

  -- Mantener validación de sesión, montos, medio de pago,
  -- idempotencia, bloqueo de saldo y registro de Caja del motor seguro.
  RETURN aquabri_private.aq_cobrar_credito_auth_interno(
    ctx.sesion_token, ctx.usuario_id, p_nonce,
    p_cliente_id, p_monto, p_medio, p_notas, p_credito_id
  );
END;
$function$;
revoke all privileges on function public.aq_cobrar_auth_v2(p_nonce text, p_cliente_id bigint, p_monto numeric, p_medio text, p_notas text, p_credito_id bigint) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_crear_pedido_auth_v1(p_nonce text, p_pedido jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record;v_act public.aq_pedidos_operaciones%rowtype;v_id integer;
 v_fecha date;v_cliente integer;v_desc numeric;v_subtotal numeric:=0;v_total numeric;
 v_it jsonb;v_prod integer;v_prod_nombre text;v_precio numeric;v_desc_item numeric;v_cant integer;v_bonif integer;
 v_bonif_producto integer;v_notas text;v_bonifs text;v_usu integer;
 v_payload jsonb;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if not aquabri_private.tiene_permiso_actual('ventas.registrar') then
   raise exception 'Sin permiso para registrar pedidos' using errcode='42501';
 end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120 or
  p_pedido is null or jsonb_typeof(p_pedido)<>'object' or
  p_items is null or jsonb_typeof(p_items)<>'array'
  or jsonb_array_length(p_items) not between 1 and 100 then
   raise exception 'Formato de pedido inválido' using errcode='22023';
 end if;
 v_payload:=jsonb_build_object('pedido',p_pedido,'items',p_items);
 perform pg_advisory_xact_lock(85431,hashtext(p_nonce));
 select * into v_act from public.aq_pedidos_operaciones where nonce=p_nonce for update;
 if found then
  if v_act.usuario_id<>ctx.usuario_id or v_act.accion<>'crear' or v_act.datos<>v_payload then
    raise exception 'Nonce de pedido reutilizado' using errcode='22023';end if;
  return v_act.resultado||jsonb_build_object('repetida',true);
 end if;
 v_fecha:=nullif(p_pedido->>'fecha','')::date;
 v_cliente:=nullif(p_pedido->>'cliente_id','')::integer;
 v_desc:=coalesce(nullif(p_pedido->>'desc_gral','')::numeric,0);
 v_notas:=coalesce(p_pedido->>'notas','');
 v_bonifs:=left(coalesce(p_pedido->>'bonificaciones',''),1000);
 if v_fecha is null or v_fecha < (now() at time zone 'America/Guatemala')::date-interval '30 days'
   or v_fecha > (now() at time zone 'America/Guatemala')::date+interval '1 year'
   or v_desc<0 or v_desc>100000 or length(v_notas)>1500 then
  raise exception 'Datos de pedido fuera de rango' using errcode='22023';end if;
 if v_desc>0 and ctx.rol_usuario<>'jefe' then
  raise exception 'Descuento general solo autorizado al jefe' using errcode='42501';end if;
 if v_cliente is not null then
   if not exists(select 1 from public.clientes c where id=v_cliente and c.archivado_en is null) then
     raise exception 'Cliente no existe o está archivado' using errcode='22023';end if;
   if ctx.rol_usuario<>'jefe' and not aquabri_private.puede_ver_cliente(v_cliente) then
     raise exception 'Cliente sin acceso autorizado' using errcode='42501';end if;
 end if;
 for v_it in select value from jsonb_array_elements(p_items) loop
   v_prod:=nullif(v_it->>'producto_id','')::integer;
   v_cant:=coalesce(nullif(v_it->>'cant','')::integer,0);
   v_precio:=coalesce(nullif(v_it->>'precio','')::numeric,-1);
   v_desc_item:=coalesce(nullif(v_it->>'descuento','')::numeric,0);
   v_bonif:=coalesce(nullif(v_it->>'bonif_cant','')::integer,0);
   v_bonif_producto:=nullif(v_it->>'bonif_prod_id','')::integer;
   if v_cant not between 1 and 10000 or v_bonif not between 0 and 10000
    or v_precio<0 or v_precio>100000 or v_precio<>round(v_precio,2)
    or v_desc_item<0 or v_desc_item>v_precio or v_desc_item<>round(v_desc_item,2)
    or not exists(select 1 from public.productos where id=v_prod)
    or (v_bonif_producto is not null and not exists(select 1 from public.productos where id=v_bonif_producto))
   then raise exception 'Producto, descuento o cantidad inválida' using errcode='22023';end if;
   v_subtotal:=v_subtotal+v_cant*(v_precio-v_desc_item);
 end loop;
 v_total:=round(v_subtotal-v_desc,2);
 if v_total<0 then raise exception 'El descuento supera el subtotal' using errcode='22023';end if;
 insert into public.ventas(fecha,cliente_id,total,pagado,entrega,notas,estado,desc_gral,usuario_id,bonificaciones)
 values(v_fecha,v_cliente,v_total,0,'A Domicilio','📦 PEDIDO: '||v_notas,'Pendiente',v_desc,ctx.usuario_id,
 nullif(v_bonifs,''))
 returning id into v_id;
 for v_it in select value from jsonb_array_elements(p_items) loop
   v_prod:=(v_it->>'producto_id')::integer;
   select nombre into v_prod_nombre from public.productos where id=v_prod;
   insert into public.venta_items(
      venta_id,producto_id,nombre,cant,precio,descuento,bonif_nombre,bonif_cant,bonif_prod_id)
   values(v_id,v_prod,coalesce(v_it->>'nombre',v_prod_nombre),
      (v_it->>'cant')::integer,(v_it->>'precio')::numeric,
      coalesce((v_it->>'descuento')::numeric,0),nullif(v_it->>'bonif_nombre',''),
      coalesce((v_it->>'bonif_cant')::integer,0),nullif(v_it->>'bonif_prod_id','')::integer);
 end loop;
 insert into public.aq_pedidos_operaciones(nonce,accion,usuario_id,venta_id,datos,resultado)
 values(p_nonce,'crear',ctx.usuario_id,v_id,v_payload,
   jsonb_build_object('ok',true,'id',v_id,'total',v_total,'estado','Pendiente'));
 return jsonb_build_object('ok',true,'id',v_id,'total',v_total,'estado','Pendiente','repetida',false);
end;$function$;
revoke all privileges on function public.aq_crear_pedido_auth_v1(p_nonce text, p_pedido jsonb, p_items jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_crear_ruta_auth_v1(p_ruta jsonb, p_clientes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record; v_nombre text; v_fecha date; v_empleado integer; v_vehiculo integer;
 v_ruta integer; v_item text; v_cliente integer; v_vistos integer[]:='{}';
 v_orden integer:=0;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' then
   raise exception 'Solo jefe puede crear rutas' using errcode='42501';
 end if;
 if p_ruta is null or pg_catalog.jsonb_typeof(p_ruta)<>'object'
    or p_clientes is null or pg_catalog.jsonb_typeof(p_clientes)<>'array' then
   raise exception 'Datos de ruta invalidos' using errcode='22023';
 end if;
 if pg_catalog.jsonb_array_length(p_clientes) not between 1 and 500 then
   raise exception 'La ruta requiere de 1 a 500 clientes' using errcode='22023';
 end if;
 v_nombre:=pg_catalog.btrim(p_ruta->>'nombre');
 if v_nombre is null or char_length(v_nombre) not between 1 and 140 then
   raise exception 'Nombre de ruta invalido' using errcode='22023';
 end if;
 v_fecha:=nullif(p_ruta->>'fecha','')::date;
 if v_fecha is null then
   raise exception 'Fecha de ruta obligatoria' using errcode='22023';
 end if;
 v_empleado:=nullif(p_ruta->>'empleado_id','')::integer;
 v_vehiculo:=nullif(p_ruta->>'vehiculo_id','')::integer;
 if v_empleado is not null and not exists (select 1 from public.empleados where id=v_empleado) then
   raise exception 'Empleado inexistente' using errcode='22023';
 end if;
 if v_vehiculo is not null and not exists (select 1 from public.vehiculos where id=v_vehiculo) then
   raise exception 'Vehiculo inexistente' using errcode='22023';
 end if;
 for v_item in select value from pg_catalog.jsonb_array_elements_text(p_clientes) loop
   v_cliente:=v_item::integer;
   if v_cliente<1 or v_cliente=any(v_vistos)
       or not exists(select 1 from public.clientes where id=v_cliente) then
     raise exception 'Cliente repetido o inexistente en ruta' using errcode='22023';
   end if;
   v_vistos:=pg_catalog.array_append(v_vistos,v_cliente);
 end loop;
 insert into public.rutas(nombre,fecha,estado,vehiculo_id,empleado_id,notas)
 values(v_nombre,v_fecha,'Pendiente',v_vehiculo,v_empleado,nullif(p_ruta->>'notas',''))
 returning id into v_ruta;
 foreach v_cliente in array v_vistos loop
   v_orden:=v_orden+1;
   insert into public.ruta_paradas(ruta_id,cliente_id,orden,estado)
   values(v_ruta,v_cliente,v_orden,'Pendiente');
 end loop;
 return pg_catalog.jsonb_build_object('ok',true,'id',v_ruta,'nombre',v_nombre,'fecha',v_fecha,'paradas',v_orden);
end;
$function$;
revoke all privileges on function public.aq_crear_ruta_auth_v1(p_ruta jsonb, p_clientes jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_desactivar_cliente_puntos_auth_v1(p_cliente_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_id integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('puntos') then
  raise exception 'Solo jefe puede desactivar la membresía' using errcode='42501';end if;
 update public.puntos_clientes set activo=false
 where cliente_id=p_cliente_id and activo=true returning id into v_id;
 if v_id is null then
   if exists(select 1 from public.puntos_clientes where cliente_id=p_cliente_id and activo=false) then
     return pg_catalog.jsonb_build_object('ok',true,'repetida',true);
   end if;
   raise exception 'Membresía activa no encontrada' using errcode='22023';
 end if;
 insert into public.puntos_historial(cliente_id,tipo,puntos,descripcion)
 values(p_cliente_id,'ajuste',0,'Membresía desactivada por el jefe. Historial conservado.');
 return pg_catalog.jsonb_build_object('ok',true,'repetida',false);
end;$function$;
revoke all privileges on function public.aq_desactivar_cliente_puntos_auth_v1(p_cliente_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_editar_venta_datos_auth_v1(p_venta bigint, p_entrega text, p_notas text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record; v public.ventas%ROWTYPE;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('ventas') THEN
  RAISE EXCEPTION 'Sin permiso para editar ventas' USING ERRCODE='42501';
 END IF;
 IF p_venta IS NULL OR p_venta<1 OR p_venta>2147483647 OR length(coalesce(p_entrega,''))>120 OR length(coalesce(p_notas,''))>1000 THEN
  RAISE EXCEPTION 'Datos de venta invalidos';
 END IF;
 SELECT * INTO v FROM public.ventas WHERE id=p_venta::integer FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Venta no encontrada'; END IF;
 IF v.estado IN ('Cancelada','Anulado') THEN RAISE EXCEPTION 'No se puede editar una venta cancelada'; END IF;
 IF ctx.rol_usuario <> 'jefe' AND
    (v.usuario_id IS DISTINCT FROM ctx.usuario_id::integer OR
     v.fecha IS DISTINCT FROM (now() AT TIME ZONE 'America/Guatemala')::date) THEN
  RAISE EXCEPTION 'Solo puedes editar tus propias ventas del dia' USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM public.aq_incentivos_devengados
           WHERE venta_id=v.id AND pago_id IS NOT NULL) THEN
  RAISE EXCEPTION 'La venta tiene incentivos liquidados'; END IF;
 UPDATE public.ventas
 SET entrega=p_entrega,notas=p_notas WHERE id=v.id;
 RETURN jsonb_build_object('id',v.id,'editada',true,'tipo','datos_no_financieros');
END;
$function$;
revoke all privileges on function public.aq_editar_venta_datos_auth_v1(p_venta bigint, p_entrega text, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_eliminar_movimiento_envase_auth_v1(p_movimiento_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('envases') then
   raise exception 'Solo jefe autorizado puede eliminar movimientos de envases' using errcode='42501';
 end if;
 if p_movimiento_id is null or p_movimiento_id<1 then
   raise exception 'Movimiento inválido' using errcode='22023';
 end if;
 return public.aq_eliminar_movimiento_envase(ctx.sesion_token,ctx.usuario_id,p_movimiento_id);
end;
$function$;
revoke all privileges on function public.aq_eliminar_movimiento_envase_auth_v1(p_movimiento_id bigint) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_enlace_puntos_comprobante_v1(p_venta_id integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  actor integer := aquabri_private.usuario_id_actual();
  jefe boolean := coalesce(aquabri_private.rol_actual() = 'jefe', false);
  cliente integer;
  codigo text;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR actor IS NULL
     OR (NOT jefe AND NOT aquabri_private.tiene_permiso_actual('ventas')) THEN
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
$function$;
revoke all privileges on function public.aq_enlace_puntos_comprobante_v1(p_venta_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_enlace_puntos_gestionar_v1(p_cliente_id integer, p_revocar boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE codigo text;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR (SELECT aquabri_private.rol_actual()) IS DISTINCT FROM 'jefe' THEN
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
$function$;
revoke all privileges on function public.aq_enlace_puntos_gestionar_v1(p_cliente_id integer, p_revocar boolean) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_entregar_pedido_auth_v1(p_nonce text, p_venta_id integer, p_medio text, p_pagado numeric, p_es_credito boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record;v public.ventas%rowtype;v_op public.aq_pedidos_operaciones%rowtype;
 v_items public.venta_items%rowtype;v_prod integer;v_bonif integer;v_bonif_id integer;
 v_payload jsonb;v_fecha date:=(now() at time zone 'America/Guatemala')::date;
 v_caja integer;v_credito integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if not aquabri_private.tiene_permiso_actual('ventas.registrar') then
   raise exception 'Sin permiso para entregar pedidos' using errcode='42501';end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120
  or p_venta_id is null or p_venta_id<1 or p_medio not in ('efectivo','transferencia','otro')
  or p_pagado is null or p_pagado<0 or p_pagado<>round(p_pagado,2) or p_pagado>10000000
 then raise exception 'Entrega inválida' using errcode='22023';end if;
 v_payload:=jsonb_build_object('venta_id',p_venta_id,'medio',p_medio,'pagado',p_pagado,
   'credito',coalesce(p_es_credito,false));
 perform pg_advisory_xact_lock(85432,p_venta_id);
 select * into v_op from public.aq_pedidos_operaciones where nonce=p_nonce for update;
 if found then
  if v_op.usuario_id<>ctx.usuario_id or v_op.accion<>'entregar' or v_op.datos<>v_payload then
     raise exception 'Identificador de entrega reutilizado' using errcode='22023';end if;
  return v_op.resultado||jsonb_build_object('repetida',true);
 end if;
 select * into v from public.ventas where id=p_venta_id for update;
 if not found or v.estado not in ('Pendiente','Preparando','En Camino')
  or coalesce(v.notas,'') not like '📦 PEDIDO:%' then
   raise exception 'Pedido no disponible para entregar o ya entregado' using errcode='42501';end if;
 if p_es_credito and v.cliente_id is null then
   raise exception 'Pedido a crédito requiere cliente' using errcode='22023';end if;
 if not p_es_credito and p_pagado<>v.total then
   raise exception 'El cobro de contado debe coincidir con el total' using errcode='22023';end if;
 if p_es_credito and p_pagado<>0 then
   raise exception 'Pedido a crédito no puede registrar cobro simultáneo' using errcode='22023';end if;
 if not exists(select 1 from public.venta_items where venta_id=v.id) then
   raise exception 'Pedido sin productos' using errcode='22023';end if;
 if exists(select 1 from public.caja where venta_id=v.id and tipo='venta')
 or exists(select 1 from public.creditos where venta_id=v.id
   or concepto='Venta #'||v.id::text) then
  raise exception 'Pedido tiene cobro o deuda anterior; conciliar antes de entregar' using errcode='23505';end if;
 -- Un solo cambio de estado dispara FIFO e incentivos al entregarse.
 update public.ventas set estado='Entregado',fecha=v_fecha,
   pagado=case when p_es_credito then 0 else v.total end,usuario_id=ctx.usuario_id
 where id=v.id;
 for v_items in select * from public.venta_items where venta_id=v.id order by id loop
   v_prod:=v_items.producto_id;
   v_bonif:=coalesce(v_items.bonif_cant,0);
   v_bonif_id:=v_items.bonif_prod_id;
   if v_prod is null then raise exception 'Producto de pedido inválido' using errcode='22023';end if;
   update public.productos set stock=coalesce(stock,0)-trunc(v_items.cant)::integer-
       case when v_bonif_id is null then v_bonif else 0 end where id=v_prod;
   if not found then raise exception 'Producto de pedido inexistente' using errcode='22023';end if;
   update public.insumos i set stock=coalesce(i.stock,0)-
     (select coalesce(sum(trunc(pi.cant)::integer*(trunc(v_items.cant)::integer+
       case when v_bonif_id is null then v_bonif else 0 end)),0)
       from public.producto_insumos pi where pi.insumo_id=i.id and pi.producto_id=v_prod)
    where i.id in(select pi.insumo_id from public.producto_insumos pi where pi.producto_id=v_prod);
   if v_bonif_id is not null and v_bonif>0 then
      update public.productos set stock=coalesce(stock,0)-v_bonif where id=v_bonif_id;
   end if;
 end loop;
 if p_es_credito then
   insert into public.creditos(cliente_id,venta_id,concepto,monto,pagado,fecha,estado,notas)
   values(v.cliente_id,v.id,'Venta #'||v.id,v.total,0,v_fecha,'Pendiente','Pedido programado entregado')
   returning id into v_credito;
 elsif v.total>0 then
   insert into public.caja(fecha,tipo,monto,notas,usuario_id,venta_id)
   values(v_fecha,'venta',v.total,'Venta #'||v.id||
   ' [AQ-MP:'||upper(p_medio)||'] [AQ-PEDIDO:'||p_nonce||']',ctx.usuario_id,v.id)
   returning id into v_caja;
 end if;
 insert into public.aq_pedidos_operaciones(nonce,accion,usuario_id,venta_id,datos,resultado)
 values(p_nonce,'entregar',ctx.usuario_id,v.id,v_payload,
   jsonb_build_object('ok',true,'id',v.id,'estado','Entregado','caja_id',v_caja,'credito_id',v_credito));
 return jsonb_build_object('ok',true,'repetida',false,'id',v.id,'estado','Entregado',
   'caja_id',v_caja,'credito_id',v_credito);
end;$function$;
revoke all privileges on function public.aq_entregar_pedido_auth_v1(p_nonce text, p_venta_id integer, p_medio text, p_pagado numeric, p_es_credito boolean) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_estado_pedido_auth_v1(p_venta_id integer, p_estado text, p_empleado_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v public.ventas%rowtype;v_nombre text;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if not aquabri_private.tiene_permiso_actual('ventas.registrar') then
   raise exception 'Sin permiso para gestionar pedidos' using errcode='42501';end if;
 if p_estado not in ('Pendiente','Preparando','En Camino') then
   raise exception 'Estado no permitido desde este control' using errcode='22023';end if;
 select * into v from public.ventas where id=p_venta_id for update;
 if not found or coalesce(v.notas,'') not like '📦 PEDIDO:%' or
  v.estado not in ('Pendiente','Preparando','En Camino') then
   raise exception 'Pedido no modificable' using errcode='42501';end if;
 if p_empleado_id is not null then
  select nombre into v_nombre from public.empleados where id=p_empleado_id and estado='Activo';
  if v_nombre is null then raise exception 'Empleado no válido para asignación' using errcode='22023';end if;
 end if;
 update public.ventas set estado=p_estado,aq_pedido_asignado_empleado_id=
  coalesce(p_empleado_id,aq_pedido_asignado_empleado_id)
 where id=p_venta_id;
 return jsonb_build_object('ok',true,'id',p_venta_id,'estado',p_estado);
end;$function$;
revoke all privileges on function public.aq_estado_pedido_auth_v1(p_venta_id integer, p_estado text, p_empleado_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_estado_ruta_auth_v1(p_ruta_id integer, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record; v_empleado integer; v_fecha date; v_actual text; v_empleado_usuario integer; v_pendientes integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 select empleado_id,fecha,estado into v_empleado,v_fecha,v_actual from public.rutas where id=p_ruta_id for update;
 if not found then raise exception 'Ruta inexistente' using errcode='22023'; end if;
 if p_estado not in ('Pendiente','En Ruta','Completada','Finalizado') then
   raise exception 'Estado invalido' using errcode='22023';
 end if;
 select empleado_id into v_empleado_usuario from public.usuarios where id=ctx.usuario_id;
 if ctx.rol_usuario<>'jefe' and (
      not aquabri_private.tiene_permiso_actual('mapa')
      or v_empleado_usuario is null or v_empleado is distinct from v_empleado_usuario
      or v_fecha is distinct from (now() at time zone 'America/Guatemala')::date
      or p_estado not in ('En Ruta','Completada')
   ) then
   raise exception 'No autorizado para modificar esta ruta' using errcode='42501';
 end if;
 select count(*) into v_pendientes from public.ruta_paradas
 where ruta_id=p_ruta_id and estado is distinct from 'Visitado';
 if p_estado='Completada' and v_pendientes>0 then
   raise exception 'Todavia hay paradas pendientes' using errcode='22023';
 end if;
 -- "Finalizado" NO inventa visitas ni marca pendientes como entregados.
 update public.rutas set estado=p_estado where id=p_ruta_id;
 return pg_catalog.jsonb_build_object('ok',true,'estado',p_estado,'pendientes',v_pendientes);
end;
$function$;
revoke all privileges on function public.aq_estado_ruta_auth_v1(p_ruta_id integer, p_estado text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_guardar_cliente_auth_v1(p_cliente jsonb, p_cliente_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 ctx record;
 v_id integer;
 v_nombre text;
 v_telefono text;
 v_lat numeric;
 v_lng numeric;
 v_cliente public.clientes%ROWTYPE;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('clientes') THEN
   RAISE EXCEPTION 'Sin permiso para gestionar clientes' USING ERRCODE='42501';
 END IF;
 IF p_cliente IS NULL OR pg_catalog.jsonb_typeof(p_cliente)<>'object' THEN
   RAISE EXCEPTION 'Datos de cliente inválidos' USING ERRCODE='22023';
 END IF;
 IF p_cliente_id IS NOT NULL AND (p_cliente_id<1 OR p_cliente_id>2147483647) THEN
   RAISE EXCEPTION 'Cliente inválido' USING ERRCODE='22023';
 END IF;
 v_nombre := nullif(pg_catalog.btrim(p_cliente->>'nombre'),'');
 v_telefono:=nullif(pg_catalog.btrim(p_cliente->>'telefono'),'');
 v_lat := nullif(p_cliente->>'lat','')::numeric;
 v_lng := nullif(p_cliente->>'lng','')::numeric;
 IF (v_lat IS NOT NULL AND (v_lat < -90 OR v_lat>90))
   OR (v_lng IS NOT NULL AND (v_lng < -180 OR v_lng>180))
   OR length(coalesce(v_nombre,''))>200 OR length(coalesce(v_telefono,''))>60
   OR length(coalesce(p_cliente->>'ruta',''))>100
   OR length(coalesce(p_cliente->>'direccion',''))>500 THEN
   RAISE EXCEPTION 'Datos de cliente fuera de rango' USING ERRCODE='22023';
 END IF;
 IF p_cliente_id IS NULL THEN
   IF v_nombre IS NULL OR length(v_nombre)<2 THEN
     RAISE EXCEPTION 'Nombre del cliente requerido' USING ERRCODE='22023';
   END IF;
   INSERT INTO public.clientes(nombre,telefono,direccion,ruta,lat,lng,
       tiene_exhibidor,descripcion_exhibidor,exhibidor_capacidad,exhibidor_costo,
       fecha_nacimiento,creado_por)
   VALUES(v_nombre,v_telefono,p_cliente->>'direccion',p_cliente->>'ruta',v_lat,v_lng,
      coalesce((p_cliente->>'tiene_exhibidor')::boolean,false),
      p_cliente->>'descripcion_exhibidor',
      coalesce((p_cliente->>'exhibidor_capacidad')::integer,0),
      coalesce((p_cliente->>'exhibidor_costo')::numeric,0),
      nullif(p_cliente->>'fecha_nacimiento','')::date,
      ctx.usuario_id::text)
   RETURNING id INTO v_id;
 ELSE
   IF ctx.rol_usuario<>'jefe' AND
      NOT aquabri_private.puede_ver_cliente(p_cliente_id) THEN
     RAISE EXCEPTION 'No puedes editar este cliente' USING ERRCODE='42501';
   END IF;
   SELECT * INTO v_cliente FROM public.clientes WHERE id=p_cliente_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Cliente inexistente' USING ERRCODE='22023'; END IF;
   IF p_cliente ? 'nombre' AND (v_nombre IS NULL OR length(v_nombre)<2) THEN
     RAISE EXCEPTION 'Nombre inválido' USING ERRCODE='22023';
   END IF;
   UPDATE public.clientes SET
     nombre=CASE WHEN p_cliente ? 'nombre' THEN v_nombre ELSE nombre END,
     telefono=CASE WHEN p_cliente ? 'telefono' THEN v_telefono ELSE telefono END,
     direccion=CASE WHEN p_cliente ? 'direccion' THEN p_cliente->>'direccion' ELSE direccion END,
     ruta=CASE WHEN p_cliente ? 'ruta' THEN p_cliente->>'ruta' ELSE ruta END,
     lat=CASE WHEN p_cliente ? 'lat' THEN v_lat ELSE lat END,
     lng=CASE WHEN p_cliente ? 'lng' THEN v_lng ELSE lng END,
     tiene_exhibidor=CASE WHEN p_cliente ? 'tiene_exhibidor' THEN (p_cliente->>'tiene_exhibidor')::boolean ELSE tiene_exhibidor END,
     descripcion_exhibidor=CASE WHEN p_cliente ? 'descripcion_exhibidor' THEN p_cliente->>'descripcion_exhibidor' ELSE descripcion_exhibidor END,
     exhibidor_capacidad=CASE WHEN p_cliente ? 'exhibidor_capacidad' THEN (p_cliente->>'exhibidor_capacidad')::integer ELSE exhibidor_capacidad END,
     exhibidor_costo=CASE WHEN p_cliente ? 'exhibidor_costo' THEN (p_cliente->>'exhibidor_costo')::numeric ELSE exhibidor_costo END,
     fecha_nacimiento=CASE WHEN p_cliente ? 'fecha_nacimiento' THEN nullif(p_cliente->>'fecha_nacimiento','')::date ELSE fecha_nacimiento END
   WHERE id=p_cliente_id RETURNING id INTO v_id;
 END IF;
 RETURN pg_catalog.jsonb_build_object('id',v_id,'ok',true);
END;
$function$;
revoke all privileges on function public.aq_guardar_cliente_auth_v1(p_cliente jsonb, p_cliente_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_inscribir_cliente_puntos_auth_v1(p_nonce text, p_cliente_id integer, p_precio numeric, p_notas text DEFAULT ''::text, p_medio_pago text DEFAULT 'efectivo'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_op public.aq_puntos_inscripciones_auth%rowtype;
 v_fila public.puntos_clientes%rowtype;v_resultado jsonb;v_venta integer;
 v_datos jsonb;v_fecha date:=(now() at time zone 'America/Guatemala')::date;v_usuario_id integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if not aquabri_private.tiene_permiso_actual('puntos') then
  raise exception 'Sin permiso para registrar membresías' using errcode='42501';end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120
 or p_cliente_id is null or p_cliente_id<1
 or p_precio is null or p_precio<0 or p_precio>100000 or round(p_precio,2)<>p_precio
 or length(coalesce(p_notas,''))>1500
 or p_medio_pago not in ('efectivo','transferencia','otro') then
  raise exception 'Datos de inscripción inválidos' using errcode='22023';end if;
 v_datos:=pg_catalog.jsonb_build_object('cliente_id',p_cliente_id,'precio',p_precio,
 'notas',coalesce(p_notas,''),'medio_pago',p_medio_pago);
 perform pg_catalog.pg_advisory_xact_lock(20261114,pg_catalog.hashtext(p_nonce));
 select * into v_op from public.aq_puntos_inscripciones_auth where nonce=p_nonce for update;
 if found then
  if v_op.usuario_id<>ctx.usuario_id or v_op.datos<>v_datos then
   raise exception 'Intento de usar identificador previo para otra inscripción' using errcode='23505';end if;
  return v_op.resultado||pg_catalog.jsonb_build_object('repetida',true);
 end if;
 perform 1 from public.clientes where id=p_cliente_id and archivado_en is null for update;
 if not found then raise exception 'Cliente no existe o está archivado' using errcode='22023';end if;
 if ctx.rol_usuario<>'jefe' and not aquabri_private.puede_ver_cliente(p_cliente_id) then
   raise exception 'Cliente no autorizado' using errcode='42501';end if;
 select * into v_fila from public.puntos_clientes where cliente_id=p_cliente_id for update;
 if found and coalesce(v_fila.activo,false) then
    raise exception 'Cliente ya inscrito; no puede cobrarse otra membresía' using errcode='23505';
 end if;
 if p_precio>0 then
   insert into public.ventas(fecha,cliente_id,total,pagado,entrega,notas,estado,usuario_id,bonificaciones)
   values(v_fecha,p_cliente_id,p_precio,p_precio,'Entrega Inmediata',
     'Membresía: '||p_notas,'Entregado',ctx.usuario_id,'')
   returning id into v_venta;
   insert into public.venta_items(venta_id,nombre,producto_id,cant,precio,descuento,bonif_cant)
   values(v_venta,'Inscripción a programa de puntos',null,1,p_precio,0,0);
   insert into public.caja(fecha,tipo,monto,notas,usuario_id,venta_id)
   values(v_fecha,'venta',p_precio,
     'Venta #'||v_venta||' [AQ-MP:'||upper(p_medio_pago)||'] [AQ-PUNTOS:'||p_nonce||']',
     ctx.usuario_id,v_venta);
 end if;
 if v_fila.id is null then
   insert into public.puntos_clientes(cliente_id,puntos_totales,puntos_canjeados,activo,fecha_inscripcion)
   values(p_cliente_id,0,0,true,v_fecha);
 else
   update public.puntos_clientes set activo=true,fecha_inscripcion=v_fecha where id=v_fila.id;
 end if;
 insert into public.puntos_historial(cliente_id,venta_id,tipo,puntos,descripcion)
 values(p_cliente_id,v_venta,'ajuste',0,
   'Inscripción'||case when p_precio>0 then ' de Q'||p_precio::text else ' gratuita' end);
 v_resultado:=pg_catalog.jsonb_build_object('ok',true,'cliente_id',p_cliente_id,'venta_id',v_venta,
   'precio',p_precio,'repetida',false);
 insert into public.aq_puntos_inscripciones_auth(nonce,usuario_id,cliente_id,datos,resultado)
 values(p_nonce,ctx.usuario_id,p_cliente_id,v_datos,v_resultado);
 return v_resultado;
end;$function$;
revoke all privileges on function public.aq_inscribir_cliente_puntos_auth_v1(p_nonce text, p_cliente_id integer, p_precio numeric, p_notas text, p_medio_pago text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_marcar_parada_auth_v1(p_parada_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record;
 v_estado text;
 v_fecha date;
 v_empleado_ruta integer;
 v_empleado_usuario integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario <> 'jefe'
   and not aquabri_private.tiene_permiso_actual('mapa') then
   raise exception 'Sin permiso para gestionar rutas' using errcode='42501';
 end if;
 select p.estado,r.fecha,r.empleado_id
   into v_estado,v_fecha,v_empleado_ruta
   from public.ruta_paradas p
   join public.rutas r on r.id=p.ruta_id
   where p.id=p_parada_id for update of p;
 if not found then
   raise exception 'Parada inexistente' using errcode='22023';
 end if;
 if v_fecha is distinct from (now() at time zone 'America/Guatemala')::date then
   raise exception 'Solo pueden marcarse paradas de la ruta de hoy' using errcode='42501';
 end if;
 select empleado_id into v_empleado_usuario from public.usuarios where id=ctx.usuario_id;
 if ctx.rol_usuario <> 'jefe'
   and (v_empleado_usuario is null
        or v_empleado_ruta is distinct from v_empleado_usuario) then
   raise exception 'Ruta no asignada a este empleado' using errcode='42501';
 end if;
 if v_estado is distinct from 'Visitado' then
   update public.ruta_paradas set estado='Visitado' where id=p_parada_id;
 end if;
 return pg_catalog.jsonb_build_object('ok',true,'repetida',v_estado='Visitado');
end;
$function$;
revoke all privileges on function public.aq_marcar_parada_auth_v1(p_parada_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_marcar_visita_auth_v1(p_cliente_id integer, p_sin_compra boolean DEFAULT false, p_fecha date DEFAULT NULL::date, p_venta_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record;
 v_fecha date := coalesce(p_fecha, (now() at time zone 'America/Guatemala')::date);
 v_hoy date := (now() at time zone 'America/Guatemala')::date;
 v_empleado integer;
 v_ruta_autorizada boolean;
 v_ya_registrada boolean := false;
 v_paradas integer := 0;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario <> 'jefe'
   and not (aquabri_private.tiene_permiso_actual('mapa')
            or aquabri_private.tiene_permiso_actual('ventas.registrar')) then
   raise exception 'Sin permiso para registrar visitas' using errcode='42501';
 end if;
 if p_cliente_id is null or p_cliente_id < 1
   or not exists(select 1 from public.clientes where id=p_cliente_id) then
   raise exception 'Cliente inexistente' using errcode='22023';
 end if;
 if v_fecha > v_hoy then
   raise exception 'No se admiten visitas futuras' using errcode='22023';
 end if;

 select empleado_id into v_empleado from public.usuarios where id=ctx.usuario_id;
 select exists(
   select 1 from public.rutas r
   join public.ruta_paradas rp on rp.ruta_id=r.id
   where rp.cliente_id=p_cliente_id
     and r.fecha=v_fecha
     and v_empleado is not null and r.empleado_id=v_empleado
 ) into v_ruta_autorizada;

 if ctx.rol_usuario <> 'jefe'
   and not aquabri_private.puede_ver_cliente(p_cliente_id)
   and not v_ruta_autorizada then
   raise exception 'Cliente fuera de tu cartera y rutas autorizadas' using errcode='42501';
 end if;

 if p_venta_id is null then
   if v_fecha <> v_hoy then
     raise exception 'Visita histórica requiere una venta confirmada' using errcode='42501';
   end if;
 else
   if not exists (
     select 1 from public.ventas v
     where v.id=p_venta_id and v.cliente_id=p_cliente_id and v.fecha=v_fecha
       and v.estado is distinct from 'Cancelada'
       and (ctx.rol_usuario='jefe' or v.usuario_id=ctx.usuario_id)
   ) then
     raise exception 'La venta no coincide con usuario, fecha y cliente' using errcode='42501';
   end if;
 end if;

 perform pg_catalog.pg_advisory_xact_lock(94751, p_cliente_id);
 select exists (
   select 1 from public.visitas v
   where v.cliente_id=p_cliente_id and v.usuario_id=ctx.usuario_id and v.fecha=v_fecha
 ) into v_ya_registrada;
 if not v_ya_registrada then
   insert into public.visitas(cliente_id, fecha, usuario_id, notas, sin_compra)
   values(
     p_cliente_id, v_fecha, ctx.usuario_id::integer,
     case when p_venta_id is not null then 'Auto desde venta #'||p_venta_id::text
          when p_sin_compra then 'Sin compra'
          else 'Marcado desde mapa' end,
     coalesce(p_sin_compra,false) and p_venta_id is null
   );
 end if;

 update public.ruta_paradas rp set estado='Visitado'
 from public.rutas r
 where rp.ruta_id=r.id and rp.cliente_id=p_cliente_id
   and r.fecha=v_fecha and rp.estado is distinct from 'Visitado'
   and (
     ctx.rol_usuario='jefe'
     or (v_empleado is not null and r.empleado_id=v_empleado)
   );
 get diagnostics v_paradas = row_count;
 return pg_catalog.jsonb_build_object(
   'ok',true,'repetida',v_ya_registrada,'paradas_actualizadas',v_paradas
 );
end;
$function$;
revoke all privileges on function public.aq_marcar_visita_auth_v1(p_cliente_id integer, p_sin_compra boolean, p_fecha date, p_venta_id bigint) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_pagar_proveedor_auth_v1(p_nonce text, p_proveedor text, p_deuda_id bigint, p_monto numeric, p_fecha date, p_notas text, p_origen text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE c record;
BEGIN
  SELECT * INTO STRICT c FROM aquabri_private.contexto_auth_legacy();
  IF NOT aquabri_private.tiene_permiso_actual('proveedores.pagar') THEN RAISE EXCEPTION 'Solo el jefe puede pagar a proveedores'; END IF;
  RETURN aquabri_private.aq_pago_proveedor_auth_interno(c.sesion_token,c.usuario_id,p_nonce,p_proveedor,p_deuda_id,p_monto,p_fecha,p_notas,p_origen);
END;
$function$;
revoke all privileges on function public.aq_pagar_proveedor_auth_v1(p_nonce text, p_proveedor text, p_deuda_id bigint, p_monto numeric, p_fecha date, p_notas text, p_origen text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_registrar_gasto_auth_v2(p_nonce text, p_gasto jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ctx record;
BEGIN
  SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
  IF NOT aquabri_private.tiene_permiso_actual('gastos') THEN
    RAISE EXCEPTION 'Sin permiso para registrar gastos' USING ERRCODE='42501';
  END IF;
  RETURN aquabri_private.aq_registrar_gasto_auth_interno(ctx.sesion_token,ctx.usuario_id,p_nonce,p_gasto);
END;
$function$;
revoke all privileges on function public.aq_registrar_gasto_auth_v2(p_nonce text, p_gasto jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_registrar_movimiento_envase_auth_v1(p_nonce text, p_tipo text, p_cantidad integer, p_cliente_id integer DEFAULT NULL::integer, p_fecha date DEFAULT NULL::date, p_notas text DEFAULT ''::text, p_precio_unitario numeric DEFAULT 0, p_medio_pago text DEFAULT 'efectivo'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record; v_prev public.aq_envases_operaciones_auth%rowtype;
 v_payload jsonb;v_fecha date;v_saldo integer;v_bodega integer;
 v_nuevo integer;v_monto numeric;v_venta integer;v_movimiento integer;
 v_tipo text;v_client_id integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if not aquabri_private.tiene_permiso_actual('envases') then
  raise exception 'Sin permiso para movimientos de envases' using errcode='42501';
 end if;
 if p_tipo not in ('Entrada','Préstamo','Devolución','Venta') then
  raise exception 'Tipo de envases desconocido' using errcode='22023';
 end if;
 if p_tipo in ('Entrada','Venta') and ctx.rol_usuario<>'jefe' then
  raise exception 'Solo jefe puede registrar entradas y ventas de envases desde bodega' using errcode='42501';
 end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120
 or p_cantidad is null or p_cantidad not between 1 and 10000
 or length(coalesce(p_notas,''))>1000
 or p_precio_unitario is null or p_precio_unitario<0 or p_precio_unitario>100000
 or round(p_precio_unitario,2)<>p_precio_unitario
 or p_medio_pago not in ('efectivo','transferencia','otro') then
  raise exception 'Movimiento de envases inválido' using errcode='22023';
 end if;
 v_fecha:=coalesce(p_fecha,(now() at time zone 'America/Guatemala')::date);
 if v_fecha>(now() at time zone 'America/Guatemala')::date
    or v_fecha<(now() at time zone 'America/Guatemala')::date-interval '365 days' then
  raise exception 'Fecha de movimiento inválida' using errcode='22023';
 end if;
 if p_tipo='Venta' and v_fecha<>(now() at time zone 'America/Guatemala')::date then
  raise exception 'Las ventas cobradas se registran con fecha actual de caja' using errcode='22023';
 end if;
 if p_tipo<>'Venta' and p_precio_unitario<>0 then
  raise exception 'El precio solo corresponde a venta de envases' using errcode='22023';
 end if;
 if p_tipo='Venta' and p_precio_unitario<=0 then
  raise exception 'Precio de venta obligatorio' using errcode='22023';
 end if;
 if p_tipo in ('Préstamo','Devolución') and p_cliente_id is null then
  raise exception 'Cliente obligatorio para préstamo o devolución' using errcode='22023';
 end if;
 if p_tipo='Entrada' and p_cliente_id is not null then
  raise exception 'Las entradas se registran sin cliente' using errcode='22023';
 end if;
 v_monto:=p_cantidad*p_precio_unitario;
 v_payload:=pg_catalog.jsonb_build_object('tipo',p_tipo,'cantidad',p_cantidad,
 'cliente_id',p_cliente_id,'fecha',v_fecha,'notas',coalesce(p_notas,''),
 'precio_unitario',p_precio_unitario,'medio_pago',p_medio_pago);
 perform pg_catalog.pg_advisory_xact_lock(20261112,pg_catalog.hashtext(p_nonce));
 select * into v_prev from public.aq_envases_operaciones_auth where nonce=p_nonce for update;
 if found then
   if v_prev.usuario_id<>ctx.usuario_id or v_prev.datos<>v_payload then
     raise exception 'Identificador de operación reutilizado con datos distintos' using errcode='23505';
   end if;
   return v_prev.resultado||pg_catalog.jsonb_build_object('repetida',true);
 end if;
 v_client_id:=p_cliente_id;
 if v_client_id is not null then
    select coalesce(c.envases,0) into v_saldo from public.clientes c
      where c.id=v_client_id and c.archivado_en is null for update;
    if not found then raise exception 'Cliente inactivo o inexistente' using errcode='22023';end if;
    if ctx.rol_usuario<>'jefe' and not aquabri_private.puede_ver_cliente(v_client_id) then
       raise exception 'Cliente no autorizado para este usuario' using errcode='42501';
    end if;
 end if;
 select cantidad into v_bodega from public.envases_bodega where id=1 for update;
 if not found then raise exception 'Bodega de envases no configurada' using errcode='22023';end if;
 if v_bodega is null or v_bodega<0 then raise exception 'Saldo de bodega inválido' using errcode='22023';end if;
 if p_tipo in ('Préstamo','Venta') and v_bodega<p_cantidad then
   raise exception 'Envases insuficientes en bodega: %',v_bodega using errcode='22023';
 end if;
 if p_tipo='Devolución' and coalesce(v_saldo,0)<p_cantidad then
   raise exception 'El cliente no tiene suficientes envases prestados' using errcode='22023';
 end if;
 v_nuevo:=v_bodega+case when p_tipo in ('Entrada','Devolución') then p_cantidad else -p_cantidad end;
 update public.envases_bodega set cantidad=v_nuevo where id=1;
 if p_tipo='Préstamo' then
   update public.clientes set envases=v_saldo+p_cantidad where id=v_client_id;
 elsif p_tipo='Devolución' then
   update public.clientes set envases=v_saldo-p_cantidad where id=v_client_id;
 elsif p_tipo='Venta' then
   insert into public.ventas(fecha,cliente_id,total,pagado,entrega,notas,estado,
     usuario_id,bonificaciones)
   values(v_fecha,v_client_id,v_monto,v_monto,'Entrega Inmediata',
     'Venta de envase vacío ×'||p_cantidad||case when coalesce(p_notas,'')<>'' then ' — '||p_notas else '' end,
     'Entregado',ctx.usuario_id,'')
   returning id into v_venta;
   insert into public.venta_items(venta_id,producto_id,nombre,cant,precio,descuento,bonif_cant)
   values(v_venta,null,'Envase vacío (venta desde bodega)',p_cantidad,p_precio_unitario,0,0);
   insert into public.caja(fecha,tipo,monto,notas,usuario_id,venta_id)
   values(v_fecha,'venta',v_monto,
     'Venta #'||v_venta||' [AQ-MP:'||upper(p_medio_pago)||'] [AQ-ENVASE:'||p_nonce||']',
     ctx.usuario_id,v_venta);
 end if;
 insert into public.envases(fecha,cliente_id,cant,tipo,notas,precio,venta_id,anulado)
 values(v_fecha,v_client_id,p_cantidad,p_tipo,coalesce(p_notas,''),v_monto,v_venta,false)
 returning id into v_movimiento;
 insert into public.aq_envases_operaciones_auth(nonce,usuario_id,datos,resultado)
 values(p_nonce,ctx.usuario_id,v_payload,
   pg_catalog.jsonb_build_object('ok',true,'id',v_movimiento,
    'venta_id',v_venta,'monto',v_monto,'bodega_final',v_nuevo));
 return pg_catalog.jsonb_build_object('ok',true,'repetida',false,'id',v_movimiento,
    'venta_id',v_venta,'monto',v_monto,'bodega_final',v_nuevo);
end;$function$;
revoke all privileges on function public.aq_registrar_movimiento_envase_auth_v1(p_nonce text, p_tipo text, p_cantidad integer, p_cliente_id integer, p_fecha date, p_notas text, p_precio_unitario numeric, p_medio_pago text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_reordenar_ruta_auth_v1(p_ruta_id integer, p_paradas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_empleado integer;v_fecha date;v_empleado_usuario integer;
 v_count integer;v_actual integer;v_item text;v_pid integer;v_vistos integer[]:='{}';v_orden integer:=0;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if not aquabri_private.tiene_permiso_actual('mapa') and ctx.rol_usuario<>'jefe' then
   raise exception 'Sin acceso a rutas' using errcode='42501';
 end if;
 select empleado_id,fecha into v_empleado,v_fecha from public.rutas where id=p_ruta_id for update;
 if not found then raise exception 'Ruta inexistente' using errcode='22023'; end if;
 select empleado_id into v_empleado_usuario from public.usuarios where id=ctx.usuario_id;
 if ctx.rol_usuario<>'jefe' and (
    v_empleado_usuario is null or v_empleado is distinct from v_empleado_usuario
    or v_fecha is distinct from (now() at time zone 'America/Guatemala')::date
 ) then raise exception 'Ruta ajena o fuera de fecha' using errcode='42501';end if;
 if p_paradas is null or pg_catalog.jsonb_typeof(p_paradas)<>'array' then
   raise exception 'Lista de paradas invalida' using errcode='22023';
 end if;
 v_count:=pg_catalog.jsonb_array_length(p_paradas);
 select count(*) into v_actual from public.ruta_paradas where ruta_id=p_ruta_id;
 if v_count<>v_actual or v_count>500 then
   raise exception 'La lista debe incluir todas las paradas existentes' using errcode='22023';
 end if;
 for v_item in select value from pg_catalog.jsonb_array_elements_text(p_paradas) loop
   v_pid:=v_item::integer;
   if v_pid=any(v_vistos) or not exists (
     select 1 from public.ruta_paradas where id=v_pid and ruta_id=p_ruta_id
   ) then raise exception 'Parada duplicada o ajena a la ruta' using errcode='42501';end if;
   v_vistos:=pg_catalog.array_append(v_vistos,v_pid);
 end loop;
 foreach v_pid in array v_vistos loop
   v_orden:=v_orden+1;
   update public.ruta_paradas set orden=v_orden where id=v_pid;
 end loop;
 return pg_catalog.jsonb_build_object('ok',true,'paradas',v_orden);
end;
$function$;
revoke all privileges on function public.aq_reordenar_ruta_auth_v1(p_ruta_id integer, p_paradas jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_restaurar_cliente_auth_v1(p_historial_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record; h public.clientes_eliminados%rowtype; v_id integer; v_original integer; v_json jsonb;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario <> 'jefe' then
   raise exception 'Solo el jefe puede restaurar clientes' using errcode='42501';
 end if;
 select * into h from public.clientes_eliminados where id=p_historial_id for update;
 if not found then raise exception 'Historial inexistente' using errcode='22023'; end if;
 if h.restaurado_en is not null then
   raise exception 'Este cliente ya fue restaurado' using errcode='22023';
 end if;
 v_original:=h.cliente_original_id;
 if v_original is not null and exists(select 1 from public.clientes where id=v_original) then
   update public.clientes set archivado_en=null,archivado_por=null
     where id=v_original and archivado_en is not null returning id into v_id;
   if v_id is null then raise exception 'Cliente ya activo o duplicado' using errcode='22023';end if;
 else
   v_json:=coalesce(h.datos_completos,'{}'::jsonb);
   insert into public.clientes(nombre,telefono,direccion,ruta,lat,lng,
        tiene_exhibidor,descripcion_exhibidor,exhibidor_capacidad,exhibidor_costo,
        fecha_nacimiento,creado_por)
   values(coalesce(nullif(h.nombre,''),'Cliente restaurado'),h.telefono,h.direccion,h.ruta,
       h.lat,h.lng,coalesce(h.tiene_exhibidor,false),v_json->>'descripcion_exhibidor',
       nullif(v_json->>'exhibidor_capacidad','')::integer,
       nullif(v_json->>'exhibidor_costo','')::numeric,
       nullif(v_json->>'fecha_nacimiento','')::date,
       ctx.usuario_id::text) returning id into v_id;
 end if;
 update public.clientes_eliminados set restaurado_en=now() where id=p_historial_id;
 return pg_catalog.jsonb_build_object('ok',true,'id',v_id,'historial_id',p_historial_id);
end;$function$;
revoke all privileges on function public.aq_restaurar_cliente_auth_v1(p_historial_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_reutilizar_ruta_auth_v1(p_ruta_id integer, p_fecha date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_pendientes integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' then raise exception 'Solo jefe puede reutilizar rutas' using errcode='42501';end if;
 if p_fecha is null then raise exception 'Fecha invalida' using errcode='22023';end if;
 if not exists(select 1 from public.rutas where id=p_ruta_id for update) then
   raise exception 'Ruta inexistente' using errcode='22023';
 end if;
 update public.ruta_paradas p
 set estado=case when exists(
      select 1 from public.ventas v where v.cliente_id=p.cliente_id
        and v.fecha=p_fecha and v.estado is distinct from 'Cancelada')
       or exists(select 1 from public.visitas vi where vi.cliente_id=p.cliente_id and vi.fecha=p_fecha)
   then 'Visitado' else 'Pendiente' end
 where p.ruta_id=p_ruta_id;
 select count(*) into v_pendientes from public.ruta_paradas
 where ruta_id=p_ruta_id and estado is distinct from 'Visitado';
 update public.rutas
 set fecha=p_fecha,estado=case when v_pendientes=0 then 'Completada' else 'Pendiente' end
 where id=p_ruta_id;
 return pg_catalog.jsonb_build_object('ok',true,'pendientes',v_pendientes);
end;
$function$;
revoke all privileges on function public.aq_reutilizar_ruta_auth_v1(p_ruta_id integer, p_fecha date) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_abrir_salida_auth_v1(p_nonce text, p_empleado integer, p_hora_salida time without time zone, p_notas text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_id integer;v_prev public.aq_rrhh_salidas_operacion%rowtype;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
   raise exception 'Solo jefe puede registrar salidas de personal' using errcode='42501';end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120
 or p_empleado is null or not exists(select 1 from public.empleados e where e.id=p_empleado and e.estado='Activo')
 or p_hora_salida is null or length(coalesce(p_notas,''))>1000 then
   raise exception 'Datos de salida inválidos' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(20261113,pg_catalog.hashtext(p_nonce));
 select * into v_prev from public.aq_rrhh_salidas_operacion where nonce=p_nonce for update;
 if found then
   if v_prev.usuario_id<>ctx.usuario_id or v_prev.empleado_id<>p_empleado then
     raise exception 'Identificador de salida utilizado por otro empleado' using errcode='23505';end if;
   return pg_catalog.jsonb_build_object('ok',true,'repetida',true,'id',v_prev.liquidacion_id);
 end if;
 insert into public.liquidaciones(empleado_id,fecha,hora_salida,notas,estado,usuario_id)
 values(p_empleado,(now() at time zone 'America/Guatemala')::date,p_hora_salida,p_notas,'abierta',ctx.usuario_id)
 returning id into v_id;
 insert into public.aq_rrhh_salidas_operacion(nonce,usuario_id,empleado_id,liquidacion_id)
 values(p_nonce,ctx.usuario_id,p_empleado,v_id);
 return pg_catalog.jsonb_build_object('ok',true,'repetida',false,'id',v_id);
end;$function$;
revoke all privileges on function public.aq_rrhh_abrir_salida_auth_v1(p_nonce text, p_empleado integer, p_hora_salida time without time zone, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_anular_salida_auth_v1(p_liquidacion integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v public.liquidaciones%rowtype;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
  raise exception 'Solo jefe puede anular salidas' using errcode='42501';end if;
 select * into v from public.liquidaciones where id=p_liquidacion for update;
 if not found then raise exception 'Salida inexistente' using errcode='22023';end if;
 if v.estado='Anulada' then return pg_catalog.jsonb_build_object('ok',true,'repetida',true,'id',v.id);end if;
 if v.estado<>'abierta' or v.carga_id is not null or
    coalesce(v.total_vendido,0)<>0 or coalesce(v.efectivo_entregado,0)<>0
    or coalesce(v.monto_entregado,0)<>0 or
    exists(select 1 from public.liquidacion_items li where li.liquidacion_id=v.id) then
  raise exception 'Salida con historial, pagos o cargas: no puede eliminarse; necesita ajuste supervisado' using errcode='42501';
 end if;
 update public.liquidaciones set estado='Anulada',notas=coalesce(v.notas,'')||' [Anulada por jefe]' where id=v.id;
 return pg_catalog.jsonb_build_object('ok',true,'repetida',false,'id',v.id);
end;$function$;
revoke all privileges on function public.aq_rrhh_anular_salida_auth_v1(p_liquidacion integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_anular_vale_auth_v1(p_vale_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_estado text;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh')
 then raise exception 'Solo jefe puede anular vales' using errcode='42501';end if;
 select estado into v_estado from public.vales where id=p_vale_id for update;
 if not found then raise exception 'Vale no encontrado' using errcode='22023';end if;
 if v_estado='Descontado' then raise exception 'Vale ya descontado; no puede anularse' using errcode='42501';end if;
 if v_estado<>'Anulado' then update public.vales set estado='Anulado' where id=p_vale_id;end if;
 return jsonb_build_object('ok',true,'id',p_vale_id,'repetida',v_estado='Anulado');
end;$function$;
revoke all privileges on function public.aq_rrhh_anular_vale_auth_v1(p_vale_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_cerrar_salida_auth_v1(p_liquidacion integer, p_hora_regreso time without time zone, p_monto numeric, p_notas text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v public.liquidaciones%rowtype;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
   raise exception 'Solo jefe puede cerrar una salida' using errcode='42501';end if;
 if p_liquidacion is null or p_liquidacion<1 or p_hora_regreso is null
    or p_monto is null or p_monto<0 or p_monto>10000000 or p_monto<>pg_catalog.round(p_monto,2)
    or length(coalesce(p_notas,''))>1000 then
   raise exception 'Datos de liquidación inválidos' using errcode='22023';end if;
 select * into v from public.liquidaciones where id=p_liquidacion for update;
 if not found or v.carga_id is not null then raise exception 'Salida independiente inexistente' using errcode='22023';end if;
 if v.estado='cerrada' then
   if v.hora_regreso is not distinct from p_hora_regreso and v.monto_entregado is not distinct from p_monto then
     return pg_catalog.jsonb_build_object('ok',true,'repetida',true,'id',v.id);
   end if;
   raise exception 'Salida ya cerrada con otros valores' using errcode='23505';
 end if;
 if v.estado<>'abierta' then raise exception 'Solo se pueden cerrar salidas abiertas' using errcode='42501';end if;
 update public.liquidaciones set hora_regreso=p_hora_regreso,monto_entregado=p_monto,
   estado='cerrada',notas=p_notas where id=v.id;
 return pg_catalog.jsonb_build_object('ok',true,'repetida',false,'id',v.id);
end;$function$;
revoke all privileges on function public.aq_rrhh_cerrar_salida_auth_v1(p_liquidacion integer, p_hora_regreso time without time zone, p_monto numeric, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_configurar_comision_auth_v1(p_empleado_id integer, p_porcentaje numeric, p_tipo text, p_compartir_empleado_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record; v_id integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('comisiones') then
  raise exception 'No autorizado a configurar comisiones' using errcode='42501';end if;
 if p_porcentaje is null or p_porcentaje<0 or p_porcentaje>100
   or p_tipo not in ('general','clientes')
   or not exists(select 1 from public.empleados where id=p_empleado_id)
   or (p_compartir_empleado_id is not null and (p_compartir_empleado_id=p_empleado_id
   or not exists(select 1 from public.empleados where id=p_compartir_empleado_id)))
 then raise exception 'Configuracion de comision invalida' using errcode='22023';end if;
 perform pg_advisory_xact_lock(85603,p_empleado_id);
 select id into v_id from public.comisiones where empleado_id=p_empleado_id and activo=true order by id desc limit 1 for update;
 if v_id is null then
  insert into public.comisiones(empleado_id,porcentaje,tipo_comision,compartir_empleado_id,activo)
  values(p_empleado_id,p_porcentaje,p_tipo,p_compartir_empleado_id,true) returning id into v_id;
 else
  update public.comisiones set porcentaje=p_porcentaje,tipo_comision=p_tipo,compartir_empleado_id=p_compartir_empleado_id
  where id=v_id;
 end if;
 return jsonb_build_object('ok',true,'id',v_id);
end;$function$;
revoke all privileges on function public.aq_rrhh_configurar_comision_auth_v1(p_empleado_id integer, p_porcentaje numeric, p_tipo text, p_compartir_empleado_id bigint) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_desactivar_comision_auth_v1(p_comision_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_id integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('comisiones') then
  raise exception 'No autorizado a desactivar comisiones' using errcode='42501';end if;
 update public.comisiones set activo=false where id=p_comision_id returning id into v_id;
 if v_id is null then raise exception 'Comision inexistente' using errcode='22023';end if;
 return jsonb_build_object('ok',true,'id',v_id);
end;$function$;
revoke all privileges on function public.aq_rrhh_desactivar_comision_auth_v1(p_comision_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_desactivar_empleado_auth_v1(p_empleado_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_id integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
  raise exception 'Solo jefe puede desactivar empleados' using errcode='42501';end if;
 update public.empleados set estado='Inactivo' where id=p_empleado_id returning id into v_id;
 if v_id is null then raise exception 'Empleado no existe' using errcode='22023';end if;
 return jsonb_build_object('ok',true,'id',v_id,'estado','Inactivo');
end;$function$;
revoke all privileges on function public.aq_rrhh_desactivar_empleado_auth_v1(p_empleado_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_emitir_vale_auth_v1(p_nonce text, p_empleado integer, p_tipo text, p_monto numeric, p_fecha date, p_descripcion text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record; v_id integer;v_op public.aq_rrhh_vale_operaciones%rowtype;v_datos jsonb;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh')
 then raise exception 'Solo jefe puede emitir vales' using errcode='42501';end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120
 or not exists(select 1 from public.empleados where id=p_empleado)
 or p_tipo is null or length(btrim(p_tipo)) not between 1 and 80
 or p_monto is null or p_monto<=0 or p_monto>100000 or p_monto<>round(p_monto,2)
 or p_fecha is null or p_fecha>(now() at time zone 'America/Guatemala')::date
 or length(coalesce(p_descripcion,''))>1000 then
  raise exception 'Vale inválido' using errcode='22023';end if;
 v_datos:=jsonb_build_object('empleado',p_empleado,'tipo',p_tipo,'monto',p_monto,'fecha',p_fecha,'descripcion',coalesce(p_descripcion,''));
 perform pg_advisory_xact_lock(85422,hashtext(p_nonce));
 select * into v_op from public.aq_rrhh_vale_operaciones where nonce=p_nonce for update;
 if found then
  if v_op.datos<>v_datos then raise exception 'Nonce usado con otro vale' using errcode='22023';end if;
  return jsonb_build_object('ok',true,'repetida',true,'id',v_op.vale_id);
 end if;
 insert into public.vales(empleado_id,tipo,monto,fecha,descripcion,autorizado_por,estado)
 values(p_empleado,p_tipo,p_monto,p_fecha,p_descripcion,
 (select nombre from public.usuarios where id=ctx.usuario_id),'Pendiente')
 returning id into v_id;
 insert into public.aq_rrhh_vale_operaciones(nonce,empleado_id,datos,vale_id) values(p_nonce,p_empleado,v_datos,v_id);
 return jsonb_build_object('ok',true,'repetida',false,'id',v_id);
end;$function$;
revoke all privileges on function public.aq_rrhh_emitir_vale_auth_v1(p_nonce text, p_empleado integer, p_tipo text, p_monto numeric, p_fecha date, p_descripcion text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_guardar_empleado_auth_v1(p_empleado jsonb, p_empleado_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record; v_id integer; v_nom text;v_sueldo numeric;v_usr integer;v_freq text;v_estado text;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario <> 'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
  raise exception 'Solo jefe autorizado puede gestionar empleados' using errcode='42501';
 end if;
 if p_empleado is null or jsonb_typeof(p_empleado)<>'object' then
  raise exception 'Empleado invalido' using errcode='22023';
 end if;
 v_nom:=nullif(btrim(p_empleado->>'nombre'),'');
 v_sueldo:=coalesce(nullif(p_empleado->>'sueldo','')::numeric,0);
 v_usr:=nullif(p_empleado->>'usuario_id','')::integer;
 v_freq:=coalesce(nullif(p_empleado->>'frecuencia_pago',''),'mensual');
 v_estado:=coalesce(nullif(p_empleado->>'estado',''),'Activo');
 if v_nom is null or length(v_nom) not between 2 and 160 or v_sueldo<0 or v_sueldo>1000000
 or v_freq not in ('diario','semanal','quincenal','mensual')
 or v_estado not in ('Activo','Inactivo','Suspendido')
 or length(coalesce(p_empleado->>'puesto',''))>160
 or length(coalesce(p_empleado->>'telefono',''))>60 then
   raise exception 'Campos de empleado fuera de rango' using errcode='22023';
 end if;
 if v_usr is not null and (not exists(select 1 from public.usuarios where id=v_usr)
   or exists(select 1 from public.empleados where usuario_id=v_usr and id is distinct from p_empleado_id)) then
  raise exception 'Usuario inexistente o vinculado a otro empleado' using errcode='22023';
 end if;
 if p_empleado_id is null then
  insert into public.empleados(nombre,puesto,sueldo,telefono,fecha_ingreso,estado,usuario_id,frecuencia_pago,fecha_nacimiento)
  values(v_nom,p_empleado->>'puesto',v_sueldo,nullif(p_empleado->>'telefono',''),
    nullif(p_empleado->>'fecha_ingreso','')::date,v_estado,v_usr,v_freq,
    nullif(p_empleado->>'fecha_nacimiento','')::date) returning id into v_id;
 else
  update public.empleados set nombre=v_nom,puesto=p_empleado->>'puesto',sueldo=v_sueldo,
    telefono=nullif(p_empleado->>'telefono',''),fecha_ingreso=nullif(p_empleado->>'fecha_ingreso','')::date,
    estado=v_estado,usuario_id=v_usr,frecuencia_pago=v_freq,
    fecha_nacimiento=nullif(p_empleado->>'fecha_nacimiento','')::date
  where id=p_empleado_id returning id into v_id;
  if v_id is null then raise exception 'Empleado inexistente' using errcode='22023';end if;
 end if;
 return jsonb_build_object('ok',true,'id',v_id);
end;$function$;
revoke all privileges on function public.aq_rrhh_guardar_empleado_auth_v1(p_empleado jsonb, p_empleado_id integer) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_meta_empleado_auth_v1(p_empleado_id integer, p_monto numeric, p_periodo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_id integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('metas') then
  raise exception 'No autorizado a fijar metas' using errcode='42501';end if;
 if p_monto is null or p_monto<=0 or p_monto>100000000 or length(coalesce(p_periodo,'')) not between 1 and 50
   or not exists(select 1 from public.empleados where id=p_empleado_id)
 then raise exception 'Meta invalida' using errcode='22023';end if;
 perform pg_advisory_xact_lock(85604,p_empleado_id);
 select id into v_id from public.metas_empleados where empleado_id=p_empleado_id order by id desc limit 1 for update;
 if v_id is null then
  insert into public.metas_empleados(empleado_id,monto,periodo) values(p_empleado_id,p_monto,p_periodo) returning id into v_id;
 else
  update public.metas_empleados set monto=p_monto,periodo=p_periodo where id=v_id;
 end if;
 return jsonb_build_object('ok',true,'id',v_id);
end;$function$;
revoke all privileges on function public.aq_rrhh_meta_empleado_auth_v1(p_empleado_id integer, p_monto numeric, p_periodo text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_pagar_auth_v1(p_nonce text, p_empleado integer, p_tipo text, p_monto numeric, p_fecha date, p_notas text, p_desc_vales numeric DEFAULT 0, p_desc_ausencias numeric DEFAULT 0, p_ausencias jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 ctx record; v_pago integer;v_op public.aq_rrhh_pago_operaciones%rowtype;
 v_payload jsonb;v_vales numeric:=0; v_neto numeric;
 v_ids bigint[]:='{}';v_item text;v_ausencia bigint;v_count integer;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
  raise exception 'No autorizado para registrar nómina' using errcode='42501';end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120
    or p_empleado is null or p_tipo is null or length(btrim(p_tipo)) not between 2 and 100
    or p_monto is null or p_monto<=0 or p_monto>1000000 or round(p_monto,2)<>p_monto
    or p_fecha is null or p_fecha> (now() at time zone 'America/Guatemala')::date
    or p_fecha < (now() at time zone 'America/Guatemala')::date-interval '5 years'
    or p_desc_vales is null or p_desc_vales<0 or p_desc_ausencias is null or p_desc_ausencias<0
    or length(coalesce(p_notas,''))>2000 or p_ausencias is null
    or jsonb_typeof(p_ausencias)<>'array' or jsonb_array_length(p_ausencias)>100 then
  raise exception 'Pago con datos inválidos' using errcode='22023';
 end if;
 if not exists(select 1 from public.empleados where id=p_empleado) then
  raise exception 'Empleado inexistente' using errcode='22023';end if;
 v_payload:=jsonb_build_object('empleado',p_empleado,'tipo',p_tipo,'monto',p_monto,
     'fecha',p_fecha,'notas',coalesce(p_notas,''),'vales',p_desc_vales,'ausencias_monto',
      p_desc_ausencias,'ausencias_ids',p_ausencias);
 perform pg_advisory_xact_lock(85420,p_empleado);
 select * into v_op from public.aq_rrhh_pago_operaciones where nonce=p_nonce for update;
 if found then
   if (v_op.payload - 'neto')<>v_payload or v_op.empleado_id<>p_empleado then
      raise exception 'Nonce reutilizado con datos distintos' using errcode='22023';end if;
   return jsonb_build_object('ok',true,'repetida',true,'id',v_op.pago_id,'neto',v_op.payload->>'neto');
 end if;

 select coalesce(sum(monto),0) into v_vales from public.vales
  where empleado_id=p_empleado and estado='Pendiente';
 if round(v_vales,2)<>round(p_desc_vales,2) then
  raise exception 'La deducción por vales no coincide con pendientes actuales: %',v_vales using errcode='22023';end if;
 for v_item in select value from jsonb_array_elements_text(p_ausencias) loop
  v_ausencia:=v_item::bigint;
  if v_ausencia<1 or v_ausencia=any(v_ids) then
   raise exception 'Ausencias repetidas o inválidas' using errcode='22023';end if;
  v_ids:=array_append(v_ids,v_ausencia);
 end loop;
 select count(*) into v_count from public.ausencias
 where empleado_id=p_empleado and id=any(v_ids) and coalesce(liquidada,false)=false;
 if v_count<>cardinality(v_ids) then
   raise exception 'Una ausencia ya está liquidada o no corresponde al empleado' using errcode='22023';end if;
 if p_desc_ausencias>0 and cardinality(v_ids)=0 then
   raise exception 'Descuento por ausencia sin registros relacionados' using errcode='22023';end if;
 v_neto:=round(p_monto-p_desc_vales-p_desc_ausencias,2);
 if v_neto<0 then raise exception 'El neto no puede ser negativo' using errcode='22023';end if;
 if p_tipo ilike 'Sueldo%' and exists(
   select 1 from public.pagos where empleado_id=p_empleado and fecha=p_fecha and tipo=p_tipo
 ) then raise exception 'El sueldo de este empleado y fecha ya figura pagado' using errcode='23505';end if;

 insert into public.pagos(empleado_id,tipo,monto,desc_vales,neto,fecha,notas)
 values(p_empleado,p_tipo,p_monto,p_desc_vales+p_desc_ausencias,v_neto,p_fecha,p_notas)
 returning id into v_pago;
 update public.vales set estado='Descontado'
 where empleado_id=p_empleado and estado='Pendiente';
 if cardinality(v_ids)>0 then
   update public.ausencias set liquidada=true where empleado_id=p_empleado and id=any(v_ids);
 end if;
 insert into public.aq_rrhh_pago_operaciones(nonce,usuario_id,empleado_id,payload,pago_id)
 values(p_nonce,ctx.usuario_id,p_empleado,
 v_payload||jsonb_build_object('neto',v_neto),v_pago);
 return jsonb_build_object('ok',true,'repetida',false,'id',v_pago,'neto',v_neto);
end;$function$;
revoke all privileges on function public.aq_rrhh_pagar_auth_v1(p_nonce text, p_empleado integer, p_tipo text, p_monto numeric, p_fecha date, p_notas text, p_desc_vales numeric, p_desc_ausencias numeric, p_ausencias jsonb) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_pagar_comision_auth_v1(p_nonce text, p_empleado integer, p_monto numeric, p_fecha date, p_periodo text, p_notas text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_pago integer;v_com integer;v_op public.aq_rrhh_pago_operaciones%rowtype;v_payload jsonb;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh')
    or not aquabri_private.tiene_permiso_actual('comisiones') then
  raise exception 'No autorizado para liquidar comisiones' using errcode='42501';end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120
    or p_empleado is null or not exists(select 1 from public.empleados where id=p_empleado)
    or p_monto is null or p_monto<=0 or p_monto>1000000 or round(p_monto,2)<>p_monto
    or p_fecha is null or p_fecha>(now() at time zone 'America/Guatemala')::date
    or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
    or length(coalesce(p_notas,''))>1500 then
   raise exception 'Pago de comisión inválido' using errcode='22023';end if;
 v_payload:=jsonb_build_object('empleado',p_empleado,'tipo','Comisión mensual',
 'monto',p_monto,'fecha',p_fecha,'periodo',p_periodo,'notas',coalesce(p_notas,''));
 perform pg_advisory_xact_lock(85421,p_empleado);
 select * into v_op from public.aq_rrhh_pago_operaciones where nonce=p_nonce for update;
 if found then
  if v_op.payload<>v_payload then raise exception 'Nonce reutilizado' using errcode='22023';end if;
  return jsonb_build_object('ok',true,'repetida',true,'id',v_op.pago_comision_id);
 end if;
 insert into public.pagos_comisiones(empleado_id,monto,fecha,periodo,notas,pagado_por)
 values(p_empleado,p_monto,p_fecha,p_periodo,p_notas,
  (select nombre from public.usuarios where id=ctx.usuario_id))
 returning id into v_com;
 insert into public.pagos(empleado_id,tipo,monto,desc_vales,neto,fecha,notas)
 values(p_empleado,'Comisión mensual',p_monto,0,p_monto,p_fecha,
 'Comisión '||p_periodo||coalesce(' — '||nullif(p_notas,''),''))
 returning id into v_pago;
 -- No insertar además un gasto duplicado: el pago es el registro principal.
 insert into public.aq_rrhh_pago_operaciones(nonce,usuario_id,empleado_id,payload,pago_id,pago_comision_id)
 values(p_nonce,ctx.usuario_id,p_empleado,v_payload,v_pago,v_com);
 return jsonb_build_object('ok',true,'repetida',false,'id',v_com,'pago_id',v_pago);
end;$function$;
revoke all privileges on function public.aq_rrhh_pagar_comision_auth_v1(p_nonce text, p_empleado integer, p_monto numeric, p_fecha date, p_periodo text, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_pagar_retro_auth_v1(p_nonce text, p_empleado integer, p_monto numeric, p_fecha date, p_notas text DEFAULT 'Pago retroactivo — puesto al día'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_id integer;v_op public.aq_rrhh_pago_operaciones%rowtype;v_payload jsonb;v_actual public.pagos%rowtype;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
  raise exception 'Solo jefe puede registrar pagos retroactivos' using errcode='42501';end if;
 if p_nonce is null or length(p_nonce) not between 16 and 120
 or p_empleado is null or not exists(select 1 from public.empleados where id=p_empleado)
 or p_monto is null or p_monto<=0 or p_monto>100000 or p_monto<>round(p_monto,2)
 or p_fecha is null or p_fecha>(now() at time zone 'America/Guatemala')::date
 or p_fecha<(now() at time zone 'America/Guatemala')::date-interval '3 years'
 or length(coalesce(p_notas,''))>1000 then raise exception 'Pago retroactivo inválido' using errcode='22023';end if;
 v_payload:=jsonb_build_object('empleado',p_empleado,'monto',p_monto,'fecha',p_fecha,'notas',p_notas,'tipo','Sueldo semanal');
 perform pg_advisory_xact_lock(85423,p_empleado);
 select * into v_op from public.aq_rrhh_pago_operaciones where nonce=p_nonce for update;
 if found then
  if v_op.payload<>v_payload then raise exception 'Nonce reutilizado' using errcode='22023';end if;
  return jsonb_build_object('ok',true,'repetida',true,'id',v_op.pago_id);
 end if;
 select * into v_actual from public.pagos where empleado_id=p_empleado and tipo='Sueldo semanal' and fecha=p_fecha order by id limit 1;
 if found then
  if v_actual.monto=p_monto then
   return jsonb_build_object('ok',true,'repetida',true,'id',v_actual.id,'ya_existia',true);
  end if;
  raise exception 'Ya existe pago semanal distinto en esa fecha' using errcode='23505';
 end if;
 insert into public.pagos(empleado_id,tipo,monto,desc_vales,neto,fecha,notas)
 values(p_empleado,'Sueldo semanal',p_monto,0,p_monto,p_fecha,p_notas)
 returning id into v_id;
 insert into public.aq_rrhh_pago_operaciones(nonce,usuario_id,empleado_id,payload,pago_id)
 values(p_nonce,ctx.usuario_id,p_empleado,v_payload,v_id);
 return jsonb_build_object('ok',true,'repetida',false,'id',v_id);
end;$function$;
revoke all privileges on function public.aq_rrhh_pagar_retro_auth_v1(p_nonce text, p_empleado integer, p_monto numeric, p_fecha date, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_quitar_ausencia_auth_v1(p_ausencia_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_liquidada boolean;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
  raise exception 'No autorizado a retirar ausencias' using errcode='42501';end if;
 select liquidada into v_liquidada from public.ausencias where id=p_ausencia_id for update;
 if not found then raise exception 'Ausencia no encontrada' using errcode='22023';end if;
 if coalesce(v_liquidada,false) then raise exception 'Ausencia ya liquidada; no puede eliminarse' using errcode='42501';end if;
 delete from public.ausencias where id=p_ausencia_id;
 return jsonb_build_object('ok',true,'id',p_ausencia_id);
end;$function$;
revoke all privileges on function public.aq_rrhh_quitar_ausencia_auth_v1(p_ausencia_id bigint) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_rrhh_registrar_ausencia_auth_v1(p_empleado_id integer, p_fecha date, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx record;v_id bigint;
begin
 select * into strict ctx from aquabri_private.contexto_auth_legacy();
 if ctx.rol_usuario<>'jefe' or not aquabri_private.tiene_permiso_actual('rrhh') then
  raise exception 'No autorizado a registrar ausencias' using errcode='42501';end if;
 if p_fecha is null or p_fecha<current_date-interval '3 years' or p_fecha>current_date+interval '1 year'
  or length(coalesce(p_notas,''))>1000 or not exists(select 1 from public.empleados where id=p_empleado_id) then
  raise exception 'Empleado, fecha o nota invalido' using errcode='22023';end if;
 perform pg_advisory_xact_lock(85602,p_empleado_id);
 select id into v_id from public.ausencias where empleado_id=p_empleado_id and fecha=p_fecha order by id limit 1;
 if v_id is not null then return jsonb_build_object('ok',true,'id',v_id,'repetida',true);end if;
 insert into public.ausencias(empleado_id,fecha,notas,liquidada)
 values(p_empleado_id,p_fecha,p_notas,false) returning id into v_id;
 return jsonb_build_object('ok',true,'id',v_id,'repetida',false);
end;$function$;
revoke all privileges on function public.aq_rrhh_registrar_ausencia_auth_v1(p_empleado_id integer, p_fecha date, p_notas text) from public, anon, authenticated, service_role;

CREATE FUNCTION public.aq_vender_con_envases_auth_v3(p_nonce text, p_venta jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 ctx record;
 venta jsonb;
 resultado_envases jsonb := NULL;
 llevados integer;
 devueltos integer;
BEGIN
 SELECT * INTO STRICT ctx FROM aquabri_private.contexto_auth_legacy();
 IF NOT aquabri_private.tiene_permiso_actual('ventas.registrar') THEN
   RAISE EXCEPTION 'No tienes permiso para registrar ventas' USING ERRCODE='42501';
 END IF;
 IF p_nonce IS NULL OR length(p_nonce)<16 OR length(p_nonce)>120
    OR p_venta IS NULL OR pg_catalog.jsonb_typeof(p_venta)<>'object'
    OR p_items IS NULL OR pg_catalog.jsonb_typeof(p_items)<>'array' THEN
   RAISE EXCEPTION 'Formato de venta inválido' USING ERRCODE='22023';
 END IF;
 llevados := coalesce((p_venta->>'envases_llevan')::integer,0);
 devueltos := coalesce((p_venta->>'envases_devuelven')::integer,0);
 IF llevados NOT BETWEEN 0 AND 100000 OR devueltos NOT BETWEEN 0 AND 100000 THEN
   RAISE EXCEPTION 'Cantidad de envases inválida' USING ERRCODE='22023';
 END IF;
 IF (llevados>0 OR devueltos>0) AND nullif(p_venta->>'cliente_id','') IS NULL THEN
   RAISE EXCEPTION 'Debes seleccionar un cliente para registrar envases' USING ERRCODE='22023';
 END IF;
 venta := public.aq_vender_auth_v2(p_nonce,p_venta,p_items);
 IF venta IS NULL OR nullif(venta->>'id','') IS NULL THEN
   RAISE EXCEPTION 'La venta no fue confirmada';
 END IF;
 IF llevados>0 OR devueltos>0 THEN
   resultado_envases := aquabri_private.aq_envases_venta_auth_interno(
     ctx.sesion_token,ctx.usuario_id,(venta->>'id')::bigint,llevados,devueltos
   );
 END IF;
 RETURN venta || pg_catalog.jsonb_build_object('envases',resultado_envases);
END;
$function$;
revoke all privileges on function public.aq_vender_con_envases_auth_v3(p_nonce text, p_venta jsonb, p_items jsonb) from public, anon, authenticated, service_role;
