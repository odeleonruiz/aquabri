-- Infraestructura de Auth de Aquabri replicada desde el esquema probado.
-- Las tablas nacen vacías, con RLS activo y permisos reservados al servidor.
-- Se mantienen en una sola transacción con el registro de la migración.

set local lock_timeout = '2s';
set local statement_timeout = '25s';

create table public."aq_caja_operaciones" (
    "nonce" text not null,
    "tipo" text not null,
    "usuario_id" integer not null,
    "movimiento_id" integer not null,
    "payload_hash" text not null,
    "resultado" jsonb not null,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_caja_operaciones_movimiento_id_fkey" FOREIGN KEY (movimiento_id) REFERENCES public.caja(id),
    constraint "aq_caja_operaciones_movimiento_id_key" UNIQUE (movimiento_id),
    constraint "aq_caja_operaciones_pkey" PRIMARY KEY (nonce),
    constraint "aq_caja_operaciones_tipo_check" CHECK (tipo = ANY (ARRAY['apertura'::text, 'cierre'::text])),
    constraint "aq_caja_operaciones_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id)
);
alter table public."aq_caja_operaciones" enable row level security;
revoke all privileges on table public."aq_caja_operaciones" from public, anon, authenticated, service_role;

create table public."aq_creditos_manual_operaciones_auth" (
    "nonce" text not null,
    "usuario_id" integer not null,
    "cliente_id" integer not null,
    "datos" jsonb not null,
    "credito_id" integer not null,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_creditos_manual_operaciones_auth_pkey" PRIMARY KEY (nonce)
);
alter table public."aq_creditos_manual_operaciones_auth" enable row level security;
revoke all privileges on table public."aq_creditos_manual_operaciones_auth" from public, anon, authenticated, service_role;

create table public."aq_envases_operaciones_auth" (
    "nonce" text not null,
    "usuario_id" integer not null,
    "datos" jsonb not null,
    "resultado" jsonb not null,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_envases_operaciones_auth_pkey" PRIMARY KEY (nonce)
);
alter table public."aq_envases_operaciones_auth" enable row level security;
revoke all privileges on table public."aq_envases_operaciones_auth" from public, anon, authenticated, service_role;

create table public."aq_pedidos_operaciones" (
    "nonce" text not null,
    "accion" text not null,
    "usuario_id" integer not null,
    "venta_id" integer not null,
    "datos" jsonb not null,
    "resultado" jsonb not null,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_pedidos_operaciones_accion_check" CHECK (accion = ANY (ARRAY['crear'::text, 'entregar'::text])),
    constraint "aq_pedidos_operaciones_pkey" PRIMARY KEY (nonce)
);
alter table public."aq_pedidos_operaciones" enable row level security;
revoke all privileges on table public."aq_pedidos_operaciones" from public, anon, authenticated, service_role;

create table public."aq_permisos_auditoria" (
    "id" bigint generated always as identity not null,
    "usuario_id" integer not null,
    "codigo" text not null,
    "valor_anterior" boolean,
    "valor_nuevo" boolean,
    "modificado_por" integer not null,
    "motivo" text,
    "fecha" timestamp with time zone default now() not null,
    constraint "aq_permisos_auditoria_codigo_fkey" FOREIGN KEY (codigo) REFERENCES public.aq_permisos_catalogo(codigo),
    constraint "aq_permisos_auditoria_modificado_por_fkey" FOREIGN KEY (modificado_por) REFERENCES public.usuarios(id),
    constraint "aq_permisos_auditoria_pkey" PRIMARY KEY (id),
    constraint "aq_permisos_auditoria_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id)
);
alter table public."aq_permisos_auditoria" enable row level security;
revoke all privileges on table public."aq_permisos_auditoria" from public, anon, authenticated, service_role;
CREATE INDEX aq_permisos_auditoria_usuario_fecha ON public.aq_permisos_auditoria USING btree (usuario_id, fecha DESC);

create table public."aq_puntos_canjes_operaciones_auth" (
    "nonce" text not null,
    "usuario_id" integer not null,
    "qr_id" integer not null,
    "datos" jsonb not null,
    "resultado" jsonb not null,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_puntos_canjes_operaciones_auth_pkey" PRIMARY KEY (nonce)
);
alter table public."aq_puntos_canjes_operaciones_auth" enable row level security;
revoke all privileges on table public."aq_puntos_canjes_operaciones_auth" from public, anon, authenticated, service_role;

create table public."aq_puntos_inscripciones_auth" (
    "nonce" text not null,
    "usuario_id" integer not null,
    "cliente_id" integer not null,
    "datos" jsonb not null,
    "resultado" jsonb not null,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_puntos_inscripciones_auth_pkey" PRIMARY KEY (nonce)
);
alter table public."aq_puntos_inscripciones_auth" enable row level security;
revoke all privileges on table public."aq_puntos_inscripciones_auth" from public, anon, authenticated, service_role;

create table public."aq_rrhh_pago_operaciones" (
    "nonce" text not null,
    "usuario_id" integer not null,
    "empleado_id" integer not null,
    "payload" jsonb not null,
    "pago_id" integer,
    "pago_comision_id" integer,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_rrhh_pago_operaciones_pkey" PRIMARY KEY (nonce)
);
alter table public."aq_rrhh_pago_operaciones" enable row level security;
revoke all privileges on table public."aq_rrhh_pago_operaciones" from public, anon, authenticated, service_role;

create table public."aq_rrhh_salidas_operacion" (
    "nonce" text not null,
    "usuario_id" integer not null,
    "empleado_id" integer not null,
    "liquidacion_id" integer not null,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_rrhh_salidas_operacion_pkey" PRIMARY KEY (nonce)
);
alter table public."aq_rrhh_salidas_operacion" enable row level security;
revoke all privileges on table public."aq_rrhh_salidas_operacion" from public, anon, authenticated, service_role;

create table public."aq_rrhh_vale_operaciones" (
    "nonce" text not null,
    "empleado_id" integer not null,
    "datos" jsonb not null,
    "vale_id" integer not null,
    "registrado_en" timestamp with time zone default now() not null,
    constraint "aq_rrhh_vale_operaciones_pkey" PRIMARY KEY (nonce)
);
alter table public."aq_rrhh_vale_operaciones" enable row level security;
revoke all privileges on table public."aq_rrhh_vale_operaciones" from public, anon, authenticated, service_role;

create table public."aq_ventas_integrales_operacion" (
    "nonce" text not null,
    "usuario_id" integer not null,
    "venta_id" integer not null,
    "payload_hash" text not null,
    "resultado" jsonb not null,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_ventas_integrales_operacion_pkey" PRIMARY KEY (nonce),
    constraint "aq_ventas_integrales_operacion_venta_id_fkey" FOREIGN KEY (venta_id) REFERENCES public.ventas(id),
    constraint "aq_ventas_integrales_operacion_venta_id_key" UNIQUE (venta_id)
);
alter table public."aq_ventas_integrales_operacion" enable row level security;
revoke all privileges on table public."aq_ventas_integrales_operacion" from public, anon, authenticated, service_role;

create table aquabri_private."aq_liquidaciones_incentivos_intentos" (
    "nonce" text not null,
    "usuario_id" integer not null,
    "parametros_hash" text not null,
    "pago_id" bigint,
    "monto" numeric(14,2) not null,
    "caja_id" integer,
    "creado_en" timestamp with time zone default now() not null,
    constraint "aq_liq_intento_consistencia" CHECK (pago_id IS NULL AND monto = 0::numeric AND caja_id IS NULL OR pago_id IS NOT NULL AND monto > 0::numeric),
    constraint "aq_liquidaciones_incentivos_intentos_caja_id_fkey" FOREIGN KEY (caja_id) REFERENCES public.caja(id) ON DELETE RESTRICT,
    constraint "aq_liquidaciones_incentivos_intentos_caja_id_key" UNIQUE (caja_id),
    constraint "aq_liquidaciones_incentivos_intentos_monto_check" CHECK (monto >= 0::numeric),
    constraint "aq_liquidaciones_incentivos_intentos_pago_id_fkey" FOREIGN KEY (pago_id) REFERENCES public.aq_pagos_incentivos(id) ON DELETE RESTRICT,
    constraint "aq_liquidaciones_incentivos_intentos_pago_id_key" UNIQUE (pago_id),
    constraint "aq_liquidaciones_incentivos_intentos_pkey" PRIMARY KEY (nonce),
    constraint "aq_liquidaciones_incentivos_intentos_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id)
);
alter table aquabri_private."aq_liquidaciones_incentivos_intentos" enable row level security;
revoke all privileges on table aquabri_private."aq_liquidaciones_incentivos_intentos" from public, anon, authenticated, service_role;

create table aquabri_private."carga_operaciones" (
    "nonce" uuid not null,
    "usuario_id" integer not null,
    "solicitud" jsonb not null,
    "resultado" jsonb not null,
    constraint "carga_operaciones_pkey" PRIMARY KEY (nonce),
    constraint "carga_operaciones_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id)
);
alter table aquabri_private."carga_operaciones" enable row level security;
revoke all privileges on table aquabri_private."carga_operaciones" from public, anon, authenticated, service_role;
CREATE INDEX carga_operaciones_carga_creada_idx ON aquabri_private.carga_operaciones USING btree (((resultado ->> 'id'::text))) WHERE ((solicitud ->> 0) IS NULL);

create table aquabri_private."enlaces_puntos" (
    "cliente_id" integer not null,
    "huella" bytea not null,
    "codigo_comprobante" text,
    constraint "enlaces_puntos_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE CASCADE,
    constraint "enlaces_puntos_huella_key" UNIQUE (huella),
    constraint "enlaces_puntos_pkey" PRIMARY KEY (cliente_id)
);
alter table aquabri_private."enlaces_puntos" enable row level security;
revoke all privileges on table aquabri_private."enlaces_puntos" from public, anon, authenticated, service_role;

create table aquabri_private."ventas_de_carga" (
    "venta_id" integer not null,
    "carga_id" integer not null,
    constraint "ventas_de_carga_carga_id_fkey" FOREIGN KEY (carga_id) REFERENCES public.cargas(id),
    constraint "ventas_de_carga_pkey" PRIMARY KEY (venta_id),
    constraint "ventas_de_carga_venta_id_fkey" FOREIGN KEY (venta_id) REFERENCES public.ventas(id)
);
alter table aquabri_private."ventas_de_carga" enable row level security;
revoke all privileges on table aquabri_private."ventas_de_carga" from public, anon, authenticated, service_role;
CREATE INDEX ventas_de_carga_carga_idx ON aquabri_private.ventas_de_carga USING btree (carga_id);
