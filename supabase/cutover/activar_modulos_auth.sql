grant execute on function public.aq_mantenimiento_auth_v1(text,jsonb,integer),public.aq_notificar_auth_v1(integer,text,text,text,jsonb),public.aq_rutas_guardadas_auth_v1(text,jsonb,integer) to authenticated;
create trigger aq_precio_historial_auth after update of precio on public.productos for each row execute function aquabri_private.aq_precio_historial_auth();
