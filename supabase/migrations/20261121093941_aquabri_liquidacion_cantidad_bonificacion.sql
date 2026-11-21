set local lock_timeout = '2s';
set local statement_timeout = '25s';
alter table public.liquidacion_items add column cantidad_bonificacion integer not null default 0;
