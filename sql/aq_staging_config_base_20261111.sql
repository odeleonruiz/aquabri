-- AQUABRI STAGING ONLY.
-- Restore missing base configuration needed for loadAll(); never copy production records.
BEGIN;
DO $config$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.config) THEN
  INSERT INTO public.config (id,nombre,slogan,telefono,direccion,logo,dia_pago)
  VALUES (1,'AQUABRI PRUEBAS','Entorno exclusivo de pruebas','','','',NULL);
 END IF;
 IF (SELECT count(*) FROM public.config)>1 THEN
   RAISE EXCEPTION 'Se encontraron varias configuraciones: revisión manual requerida';
 END IF;
 IF EXISTS (SELECT 1 FROM public.config WHERE id<>1) THEN
   RAISE EXCEPTION 'La configuración debe tener id=1 para AQUABRI';
 END IF;
 PERFORM setval(pg_get_serial_sequence('public.config','id'), (SELECT max(id) FROM public.config), true);
END $config$;
COMMIT;