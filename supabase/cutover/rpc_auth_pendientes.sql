-- Activar las RPC previamente instaladas en la misma transacción que el corte RLS.
-- Antes de ejecutar, preparar las escrituras de los módulos pendientes y el frontend de producción.
-- Los permisos SELECT de cuatro módulos se verificaron en staging en la migración 20261121094520.
set local lock_timeout = '2s';
set local statement_timeout = '45s';

do $aquabri_preflight$
begin
    if current_setting('aquabri.rls_cutover_verified', true) is distinct from 'SI_CON_PRUEBAS' then
        raise exception 'El corte de Aquabri requiere un respaldo y pruebas por rol';
    end if;
    if has_any_column_privilege('anon', 'public.sesiones', 'SELECT')
        or has_any_column_privilege('authenticated', 'public.sesiones', 'SELECT')
        or has_any_column_privilege('anon', 'public.sesiones', 'INSERT,UPDATE')
        or has_any_column_privilege('authenticated', 'public.sesiones', 'INSERT,UPDATE') then
        raise exception 'Todavía existe acceso directo a las sesiones legadas';
    end if;
    if exists (
        select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.prokind = 'f'
          and pg_get_function_identity_arguments(p.oid) ~ '(^|, )p_token '
          and (has_function_privilege('anon', p.oid, 'EXECUTE')
               or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    ) then
        raise exception 'Todavía existen RPC legadas accesibles al navegador';
    end if;


end;
$aquabri_preflight$;

grant execute on function public.aq_abrir_caja_auth_v2(p_nonce text, p_fecha date, p_monto numeric, p_usuario_caja integer, p_notas text) to authenticated;
grant execute on function public.aq_archivar_cliente_auth_v1(p_cliente_id integer) to authenticated;
grant execute on function public.aq_asignar_permiso_auth_v1(p_usuario_id integer, p_codigo text, p_permitido boolean, p_motivo text) to authenticated;
grant execute on function public.aq_borrar_ruta_auth_v1(p_ruta_id integer) to authenticated;
grant execute on function public.aq_cancelar_venta_contado_auth_v1(p_venta bigint) to authenticated;
grant execute on function public.aq_canjear_puntos_auth_v1(p_nonce text, p_qr_id integer, p_items jsonb) to authenticated;
grant execute on function public.aq_cerrar_caja_auth_v2(p_nonce text, p_fecha date, p_apertura_id integer, p_contado numeric, p_esperado_cliente numeric, p_num_movimientos integer, p_acepta_sin_clasificar boolean, p_acepta_diferencia boolean, p_notas text) to authenticated;
grant execute on function public.aq_cobrar_auth_v2(p_nonce text, p_cliente_id bigint, p_monto numeric, p_medio text, p_notas text, p_credito_id bigint) to authenticated;
grant execute on function public.aq_crear_pedido_auth_v1(p_nonce text, p_pedido jsonb, p_items jsonb) to authenticated;
grant execute on function public.aq_crear_ruta_auth_v1(p_ruta jsonb, p_clientes jsonb) to authenticated;
grant execute on function public.aq_desactivar_cliente_puntos_auth_v1(p_cliente_id integer) to authenticated;
grant execute on function public.aq_editar_venta_datos_auth_v1(p_venta bigint, p_entrega text, p_notas text) to authenticated;
grant execute on function public.aq_eliminar_movimiento_envase_auth_v1(p_movimiento_id bigint) to authenticated;
grant execute on function public.aq_enlace_puntos_comprobante_v1(p_venta_id integer) to authenticated;
grant execute on function public.aq_enlace_puntos_gestionar_v1(p_cliente_id integer, p_revocar boolean) to authenticated;
grant execute on function public.aq_entregar_pedido_auth_v1(p_nonce text, p_venta_id integer, p_medio text, p_pagado numeric, p_es_credito boolean) to authenticated;
grant execute on function public.aq_estado_pedido_auth_v1(p_venta_id integer, p_estado text, p_empleado_id integer) to authenticated;
grant execute on function public.aq_estado_ruta_auth_v1(p_ruta_id integer, p_estado text) to authenticated;
grant execute on function public.aq_guardar_cliente_auth_v1(p_cliente jsonb, p_cliente_id integer) to authenticated;
grant execute on function public.aq_inscribir_cliente_puntos_auth_v1(p_nonce text, p_cliente_id integer, p_precio numeric, p_notas text, p_medio_pago text) to authenticated;
grant execute on function public.aq_marcar_parada_auth_v1(p_parada_id integer) to authenticated;
grant execute on function public.aq_marcar_visita_auth_v1(p_cliente_id integer, p_sin_compra boolean, p_fecha date, p_venta_id bigint) to authenticated;
grant execute on function public.aq_pagar_proveedor_auth_v1(p_nonce text, p_proveedor text, p_deuda_id bigint, p_monto numeric, p_fecha date, p_notas text, p_origen text) to authenticated;
grant execute on function public.aq_registrar_gasto_auth_v2(p_nonce text, p_gasto jsonb) to authenticated;
grant execute on function public.aq_registrar_movimiento_envase_auth_v1(p_nonce text, p_tipo text, p_cantidad integer, p_cliente_id integer, p_fecha date, p_notas text, p_precio_unitario numeric, p_medio_pago text) to authenticated;
grant execute on function public.aq_reordenar_ruta_auth_v1(p_ruta_id integer, p_paradas jsonb) to authenticated;
grant execute on function public.aq_restaurar_cliente_auth_v1(p_historial_id integer) to authenticated;
grant execute on function public.aq_reutilizar_ruta_auth_v1(p_ruta_id integer, p_fecha date) to authenticated;
grant execute on function public.aq_rrhh_abrir_salida_auth_v1(p_nonce text, p_empleado integer, p_hora_salida time without time zone, p_notas text) to authenticated;
grant execute on function public.aq_rrhh_anular_salida_auth_v1(p_liquidacion integer) to authenticated;
grant execute on function public.aq_rrhh_anular_vale_auth_v1(p_vale_id integer) to authenticated;
grant execute on function public.aq_rrhh_cerrar_salida_auth_v1(p_liquidacion integer, p_hora_regreso time without time zone, p_monto numeric, p_notas text) to authenticated;
grant execute on function public.aq_rrhh_configurar_comision_auth_v1(p_empleado_id integer, p_porcentaje numeric, p_tipo text, p_compartir_empleado_id bigint) to authenticated;
grant execute on function public.aq_rrhh_desactivar_comision_auth_v1(p_comision_id integer) to authenticated;
grant execute on function public.aq_rrhh_desactivar_empleado_auth_v1(p_empleado_id integer) to authenticated;
grant execute on function public.aq_rrhh_emitir_vale_auth_v1(p_nonce text, p_empleado integer, p_tipo text, p_monto numeric, p_fecha date, p_descripcion text) to authenticated;
grant execute on function public.aq_rrhh_guardar_empleado_auth_v1(p_empleado jsonb, p_empleado_id integer) to authenticated;
grant execute on function public.aq_rrhh_meta_empleado_auth_v1(p_empleado_id integer, p_monto numeric, p_periodo text) to authenticated;
grant execute on function public.aq_rrhh_pagar_auth_v1(p_nonce text, p_empleado integer, p_tipo text, p_monto numeric, p_fecha date, p_notas text, p_desc_vales numeric, p_desc_ausencias numeric, p_ausencias jsonb) to authenticated;
grant execute on function public.aq_rrhh_pagar_comision_auth_v1(p_nonce text, p_empleado integer, p_monto numeric, p_fecha date, p_periodo text, p_notas text) to authenticated;
grant execute on function public.aq_rrhh_pagar_retro_auth_v1(p_nonce text, p_empleado integer, p_monto numeric, p_fecha date, p_notas text) to authenticated;
grant execute on function public.aq_rrhh_quitar_ausencia_auth_v1(p_ausencia_id bigint) to authenticated;
grant execute on function public.aq_rrhh_registrar_ausencia_auth_v1(p_empleado_id integer, p_fecha date, p_notas text) to authenticated;
grant execute on function public.aq_vender_con_envases_auth_v3(p_nonce text, p_venta jsonb, p_items jsonb) to authenticated;
grant execute on function public.aq_cliente_asignar_responsable_auth_v1(bigint,bigint,text) to authenticated;
grant execute on function public.aq_clientes_atribucion_listar_auth_v1() to authenticated;
grant execute on function public.aq_costos_lotes_auth_v1(date,date) to authenticated;
grant execute on function public.aq_eliminar_gasto_auth_v2(integer) to authenticated;
grant execute on function public.aq_estado_incentivos_auth_v1() to authenticated;
grant execute on function public.aq_facturas_tipos_auth_v1(bigint[]) to authenticated;
grant execute on function public.aq_finalizar_incentivo_auth_v1(bigint) to authenticated;
grant execute on function public.aq_guardar_equipo_auth_v1(text,bigint,bigint) to authenticated;
grant execute on function public.aq_guardar_incentivo_auth_v1(bigint,bigint,bigint,bigint,text,bigint,numeric,boolean) to authenticated;
grant execute on function public.aq_items_incentivados_auth_v1(date,date) to authenticated;
grant execute on function public.aq_liquidar_incentivos_auth_v2(text,bigint,date,date,text) to authenticated;
grant execute on function public.aq_lotes_resumen_auth_v1() to authenticated;
grant execute on function public.aq_movimientos_incentivos_auth_v1(date,date) to authenticated;
grant execute on function public.aq_total_incentivos_auth_v1(date,date) to authenticated;
grant execute on function public.aq_guardar_producto_auth_v1(jsonb,jsonb,integer) to authenticated;
