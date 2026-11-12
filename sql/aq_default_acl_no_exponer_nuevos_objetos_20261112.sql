-- AQUABRI: impedir acceso automático a nuevos objetos de public.
-- CAMBIO NO DESTRUCTIVO: solo altera DEFAULT PRIVILEGES.
-- No modifica datos, RLS, grants de objetos existentes, contraseñas ni sesiones.
-- Basado en https://supabase.com/docs/guides/api/securing-your-api
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;
-- El default GLOBAL PUBLIC de Postgres prevalece si solo hacemos REVOKE en esquema.
-- Por eso este último REVOKE evita que futuras funciones sean ejecutables por PUBLIC.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
