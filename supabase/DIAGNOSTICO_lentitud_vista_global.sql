-- ===========================================================================
-- DIAGNÓSTICO — por qué tarda en cargar la Vista Global
--
-- No cambia nada: solo mide y reporta. Se corre entero en el SQL Editor de
-- Supabase y se pegan los cuatro resultados.
--
-- Qué se está buscando: `get_platform_overview()` (el RPC que llena la
-- pantalla principal) arma diez subconsultas. Ocho están acotadas a hoy o a
-- las últimas 24 horas, pero dos recorren TODA la historia cada vez que se
-- abre la pantalla:
--
--   last_payment      -> max(created_at) de todos los pagos completados
--   last_open_session -> max(opened_at) de todas las sesiones de caja
--
-- Esas dos crecen con el uso: cada mes de operación las hace más lentas,
-- aunque la app esté rápida. Los bloques 3 y 4 confirman si son ellas.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- BLOQUE 1 — tamaño de las tablas que se recorren
-- ---------------------------------------------------------------------------
select relname                                   as tabla,
       n_live_tup                                as filas_aprox,
       pg_size_pretty(pg_total_relation_size(relid)) as tamano
  from pg_stat_user_tables
 where schemaname = 'public'
   and relname in ('payments', 'cash_register_sessions', 'cash_registers',
                   'print_jobs', 'fiscal_documents', 'table_sessions',
                   'agent_nodes', 'ncf_sequences', 'memberships', 'businesses')
 order by n_live_tup desc;

-- ---------------------------------------------------------------------------
-- BLOQUE 2 — índices que existen hoy en esas tablas
-- ---------------------------------------------------------------------------
select tablename as tabla,
       indexname as indice,
       indexdef  as definicion
  from pg_indexes
 where schemaname = 'public'
   and tablename in ('payments', 'cash_register_sessions', 'cash_registers',
                     'print_jobs', 'fiscal_documents', 'table_sessions',
                     'agent_nodes', 'ncf_sequences', 'memberships')
 order by tablename, indexname;

-- ---------------------------------------------------------------------------
-- BLOQUE 3 — cuánto tarda cada pedazo del RPC, por separado
--
-- El RPC no se puede llamar desde el editor (exige sesión de operador), así
-- que se miden sus subconsultas una por una.
-- ---------------------------------------------------------------------------
drop table if exists _diag;
create temporary table _diag (paso text, ms numeric, filas bigint);

do $$
declare
  t0 timestamptz;
  n  bigint;
  v_hoy      timestamptz := (date_trunc('day', (now() at time zone 'America/Santo_Domingo'))) at time zone 'America/Santo_Domingo';
  v_24h      timestamptz := now() - interval '24 hours';
begin
  t0 := clock_timestamp();
  select count(*) into n from (
    select pp.business_id, max(pp.created_at) as ts
      from public.payments pp
     where pp.status = 'completed'
     group by pp.business_id) x;
  insert into _diag values ('last_payment — TODA la historia de pagos',
    round(extract(epoch from clock_timestamp() - t0) * 1000), n);

  t0 := clock_timestamp();
  select count(*) into n from (
    select cr.business_id, max(crs.opened_at) as ts
      from public.cash_register_sessions crs
      join public.cash_registers cr on cr.id = crs.cash_register_id
     group by cr.business_id) x;
  insert into _diag values ('last_open_session — TODA la historia de cajas',
    round(extract(epoch from clock_timestamp() - t0) * 1000), n);

  t0 := clock_timestamp();
  select count(*) into n from (
    select p.business_id, sum(p.amount) as revenue, count(*) as sales
      from public.payments p
     where p.status = 'completed' and p.created_at >= v_hoy
     group by p.business_id) x;
  insert into _diag values ('rev_today — pagos de hoy',
    round(extract(epoch from clock_timestamp() - t0) * 1000), n);

  t0 := clock_timestamp();
  select count(*) into n from (
    select pj.business_id, count(*) as jobs
      from public.print_jobs pj
     where pj.created_at >= v_24h
     group by pj.business_id) x;
  insert into _diag values ('print_agg — impresiones 24h',
    round(extract(epoch from clock_timestamp() - t0) * 1000), n);

  t0 := clock_timestamp();
  select count(*) into n from (
    select fd.business_id, count(*) as cnt
      from public.fiscal_documents fd
     where fd.issued_at >= v_hoy and fd.status = 'active'
     group by fd.business_id) x;
  insert into _diag values ('fd_today — comprobantes de hoy',
    round(extract(epoch from clock_timestamp() - t0) * 1000), n);

  t0 := clock_timestamp();
  select count(*) into n from (
    select ts.business_id, count(*) as cnt
      from public.table_sessions ts
     where ts.closed_at is null and ts.business_id is not null
     group by ts.business_id) x;
  insert into _diag values ('open_tables_agg — mesas abiertas',
    round(extract(epoch from clock_timestamp() - t0) * 1000), n);

  t0 := clock_timestamp();
  select count(*) into n from (
    select m.business_id, max(u.last_sign_in_at) as ts
      from public.memberships m
      join auth.users u on u.id = m.user_id
     where m.status = 'active'
     group by m.business_id) x;
  insert into _diag values ('last_login — último ingreso por negocio',
    round(extract(epoch from clock_timestamp() - t0) * 1000), n);
end $$;

select paso, ms as milisegundos, filas from _diag order by ms desc;

-- ---------------------------------------------------------------------------
-- BLOQUE 4 — el plan real de las dos sospechosas
--
-- Lo que importa: si dice "Seq Scan" sobre payments o cash_register_sessions,
-- está leyendo la tabla entera y hay que arreglarlo.
-- ---------------------------------------------------------------------------
explain (analyze, buffers)
select pp.business_id, max(pp.created_at) as ts
  from public.payments pp
 where pp.status = 'completed'
 group by pp.business_id;

explain (analyze, buffers)
select cr.business_id, max(crs.opened_at) as ts
  from public.cash_register_sessions crs
  join public.cash_registers cr on cr.id = crs.cash_register_id
 group by cr.business_id;
