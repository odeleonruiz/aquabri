set local lock_timeout='2s';
alter table public.sesiones add column auth_session_id uuid references auth.sessions(id) on delete cascade;
create unique index sesiones_auth_session_unica on public.sesiones(auth_session_id) where auth_session_id is not null;
create function public.aq_iniciar_sesion_celular_v1() returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  identidad uuid:=auth.uid();
  sesion uuid:=(auth.jwt()->>'session_id')::uuid;
  perfil integer;
  limite timestamptz;
  token_app text;
begin
  select u.id,least(s.created_at+interval '12 hours',s.not_after)
    into strict perfil,limite
    from auth.sessions s join auth.users a on a.id=s.user_id
    join public.usuarios u on u.auth_uid=a.id
    where s.id=sesion and a.id=identidad and s.oauth_client_id is null
      and u.rol in ('jefe','vendedor','vendedor_editor','inventario','reportes')
      and a.phone_confirmed_at is not null and a.phone ~ '^\+?502[0-9]{8}$'
      and a.deleted_at is null and (a.banned_until is null or a.banned_until<=now())
      and s.created_at between now()-interval '3 minutes' and now()
      and (s.not_after is null or s.not_after>now())
      and exists(select 1 from jsonb_array_elements(auth.jwt()->'amr') m where m->>'method'='password')
      and (auth.jwt()->>'aal'='aal2' or not exists(select 1 from auth.mfa_factors f where f.user_id=a.id and f.status='verified'));
  insert into public.sesiones(usuario_id,token,expira_en,auth_session_id)
    values(perfil,encode(extensions.gen_random_bytes(32),'hex'),limite,sesion)
    on conflict (auth_session_id) where auth_session_id is not null do nothing returning token into token_app;
  if token_app is null then raise exception 'Inicia sesión de nuevo' using errcode='28000';end if;
  return jsonb_build_object('ok',true,'token',token_app,'usuario',jsonb_build_object('id',perfil));
exception when no_data_found or too_many_rows then
  raise exception 'La cuenta o la sesión no está habilitada para este acceso' using errcode='28000';
end $$;
revoke all on function public.aq_iniciar_sesion_celular_v1() from public,anon,authenticated,service_role;
grant execute on function public.aq_iniciar_sesion_celular_v1() to authenticated;
create or replace function public.aq_cerrar_sesion_segura_v1() returns boolean
language plpgsql security definer set search_path='' as $$
declare
  cuenta integer:=public.aq_sesion_legacy_usuario_actual_v1();
  llave text:=current_setting('request.headers',true)::jsonb->>'x-aquabri-session';
begin
  if cuenta is null then return false; end if;
  update public.sesiones set expira_en=now(), token=encode(extensions.gen_random_bytes(32),'hex')
    where usuario_id=cuenta and token=llave and auth_session_id is not null;
  if found then return true;end if;
  delete from public.sesiones where usuario_id=cuenta and token=llave and auth_session_id is null;
  return found;
end $$;
