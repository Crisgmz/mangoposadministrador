-- ---------------------------------------------------------------------------
-- 0032_reapply_table_health.sql
--
-- La migración 0014 (Salud de Mesas NOC) no se aplicó en la DB del usuario.
-- `select proname from pg_proc where proname like 'get_admin_%'` mostró solo
-- cash + fiscal — las 4 RPCs de mesas (`get_admin_table_health`,
-- `_zombie_sessions`, `_stuck_payments`, `_orphan_items`) y sus 3 vistas
-- (`v_admin_zombie_table_sessions`, `v_admin_stuck_payments`,
-- `v_admin_orphan_order_items`) están ausentes.
--
-- Esta migración re-aplica el mismo contenido de 0014 de forma idempotente
-- (drop view if exists cascade + create or replace function). Si por algún
-- motivo la 0014 sí se llegó a aplicar parcialmente, esto la deja consistente.
-- ---------------------------------------------------------------------------

-- 1) v_admin_zombie_table_sessions
drop view if exists public.v_admin_zombie_table_sessions cascade;

create view public.v_admin_zombie_table_sessions as
select
  ts.id                                                  as session_id,
  ts.business_id,
  b.business_name,
  b.environment,
  ts.table_id,
  dt.code                                                as table_code,
  dt.label                                               as table_label,
  dt.state::text                                         as table_state,
  ts.opened_at,
  ts.customer_name,
  ts.waiter_user_id,
  coalesce(
    nullif(trim(coalesce(e.first_name, '') || ' ' || coalesce(e.last_name, '')), ''),
    p.full_name
  )                                                      as waiter_name,
  extract(epoch from (now() - ts.opened_at))::bigint     as age_seconds,
  (select count(*)::int
     from public.orders o
    where o.session_id = ts.id
      and o.status_ext <> 'void')                         as orders_count,
  (select count(*)::int
     from public.orders o
    where o.session_id = ts.id
      and o.status_ext in ('open', 'sent_to_kitchen'))    as open_orders,
  (select coalesce(sum(o.total), 0)::numeric
     from public.orders o
    where o.session_id = ts.id
      and o.status_ext <> 'void')                         as total_unpaid_estimated
from public.table_sessions ts
join public.businesses    b  on b.id = ts.business_id
left join public.dining_tables dt on dt.id = ts.table_id
left join public.employees e
  on e.user_id = ts.waiter_user_id and e.business_id = ts.business_id
left join public.profiles  p on p.id = ts.waiter_user_id
where ts.closed_at is null
  and ts.opened_at < now() - interval '24 hours';

comment on view public.v_admin_zombie_table_sessions is
  'Sesiones de mesa abiertas hace más de 24 horas — probablemente abandonadas o '
  'no cerradas correctamente. El operador puede forzar el cierre.';


-- 2) v_admin_stuck_payments
drop view if exists public.v_admin_stuck_payments cascade;

create view public.v_admin_stuck_payments as
select
  o.id                                                   as order_id,
  o.session_id,
  ts.business_id,
  b.business_name,
  b.environment,
  ts.table_id,
  dt.code                                                as table_code,
  dt.label                                               as table_label,
  o.status_ext::text                                     as order_status,
  o.subtotal,
  o.discounts,
  o.tax,
  o.service_fee,
  o.total,
  o.created_at,
  extract(epoch from (now() - o.created_at))::bigint     as age_seconds,
  (select coalesce(sum(p.amount), 0)::numeric
     from public.payments p
    where p.order_id = o.id
      and p.status = 'completed')                         as paid_so_far,
  greatest(
    o.total - coalesce((select sum(p.amount) from public.payments p
                          where p.order_id = o.id and p.status = 'completed'), 0),
    0
  )::numeric                                             as remaining
from public.orders o
join public.table_sessions ts on ts.id = o.session_id
join public.businesses     b  on b.id = ts.business_id
left join public.dining_tables dt on dt.id = ts.table_id
where o.status_ext = 'partially_paid'
  and o.created_at < now() - interval '1 hour'
  and ts.closed_at is null;

comment on view public.v_admin_stuck_payments is
  'Órdenes con pago parcial hace más de 1 hora sin avance. Indicio de '
  'que el cliente se fue sin terminar o de un bug del POS.';


-- 3) v_admin_orphan_order_items
drop view if exists public.v_admin_orphan_order_items cascade;

create view public.v_admin_orphan_order_items as
select
  oi.id                                                  as item_id,
  oi.order_id,
  oi.product_name,
  oi.status::text                                        as item_status,
  oi.created_at                                          as item_created_at,
  o.status_ext::text                                     as order_status,
  o.closed_at                                            as order_closed_at,
  ts.id                                                  as session_id,
  ts.business_id,
  b.business_name,
  b.environment,
  dt.code                                                as table_code,
  ts.closed_at                                           as session_closed_at
from public.order_items oi
join public.orders         o  on o.id = oi.order_id
join public.table_sessions ts on ts.id = o.session_id
join public.businesses     b  on b.id = ts.business_id
left join public.dining_tables dt on dt.id = ts.table_id
where oi.status in ('pending', 'preparing', 'ready')
  and (
    o.status_ext in ('paid', 'void')
    or ts.closed_at is not null
  );

comment on view public.v_admin_orphan_order_items is
  'Items en estados activos (pending/preparing/ready) cuya orden o sesión '
  'de mesa ya está cerrada.';


-- 4) get_admin_table_health
create or replace function public.get_admin_table_health(p_env text default null)
returns table (
  zombie_sessions int,
  stuck_payments  int,
  orphan_items    int,
  total_unpaid    numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  select
    (select count(*)::int
       from public.v_admin_zombie_table_sessions z
      where p_env is null or z.environment = p_env),
    (select count(*)::int
       from public.v_admin_stuck_payments s
      where p_env is null or s.environment = p_env),
    (select count(*)::int
       from public.v_admin_orphan_order_items o
      where p_env is null or o.environment = p_env),
    (select coalesce(sum(s.remaining), 0)::numeric
       from public.v_admin_stuck_payments s
      where p_env is null or s.environment = p_env);
end;
$$;

grant execute on function public.get_admin_table_health(text) to authenticated;


-- 5) get_admin_zombie_sessions
create or replace function public.get_admin_zombie_sessions(
  p_env         text default null,
  p_business_id uuid default null,
  p_limit       int  default 100
)
returns setof public.v_admin_zombie_table_sessions
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  select * from public.v_admin_zombie_table_sessions z
   where (p_env is null or z.environment = p_env)
     and (p_business_id is null or z.business_id = p_business_id)
   order by z.opened_at asc
   limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.get_admin_zombie_sessions(text, uuid, int) to authenticated;


-- 6) get_admin_stuck_payments
create or replace function public.get_admin_stuck_payments(
  p_env         text default null,
  p_business_id uuid default null,
  p_limit       int  default 100
)
returns setof public.v_admin_stuck_payments
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  select * from public.v_admin_stuck_payments s
   where (p_env is null or s.environment = p_env)
     and (p_business_id is null or s.business_id = p_business_id)
   order by s.created_at asc
   limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.get_admin_stuck_payments(text, uuid, int) to authenticated;


-- 7) get_admin_orphan_items
create or replace function public.get_admin_orphan_items(
  p_env         text default null,
  p_business_id uuid default null,
  p_limit       int  default 200
)
returns setof public.v_admin_orphan_order_items
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  select * from public.v_admin_orphan_order_items o
   where (p_env is null or o.environment = p_env)
     and (p_business_id is null or o.business_id = p_business_id)
   order by o.item_created_at asc
   limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.get_admin_orphan_items(text, uuid, int) to authenticated;


-- 8) admin_close_zombie_table_session
create or replace function public.admin_close_zombie_table_session(
  p_session_id uuid,
  p_reason     text,
  p_void_open_orders boolean default true
)
returns public.table_sessions
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_session public.table_sessions;
  v_table_id uuid;
  v_void_count int := 0;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 5 then
    raise exception 'La razón es requerida (mínimo 5 caracteres)'
      using errcode = '22023';
  end if;

  update public.table_sessions
     set closed_at = now(),
         note = coalesce(note, '') ||
                ' [FORCE_CLOSED by NOC: ' || p_reason || ']'
   where id = p_session_id
     and closed_at is null
  returning * into v_session;

  if v_session.id is null then
    raise exception 'Sesión % no existe o ya está cerrada', p_session_id;
  end if;

  -- Postgres no permite `RETURNING *, columna INTO var1, var2` (mezcla
  -- record con item individual). Capturamos el table_id del record después.
  v_table_id := v_session.table_id;

  if p_void_open_orders then
    update public.orders
       set status_ext = 'void'
     where session_id = p_session_id
       and status_ext in ('open', 'sent_to_kitchen');
    get diagnostics v_void_count = row_count;
  end if;

  if v_table_id is not null
     and not exists (
       select 1 from public.table_sessions ts2
        where ts2.table_id = v_table_id
          and ts2.id <> p_session_id
          and ts2.closed_at is null
     ) then
    update public.dining_tables
       set state = 'available'
     where id = v_table_id;
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'close_zombie_table_session',
    'table_sessions',
    p_session_id,
    v_session.business_id,
    jsonb_build_object(
      'reason', p_reason,
      'voided_orders', v_void_count,
      'table_id', v_table_id
    )
  );

  return v_session;
end;
$$;

grant execute on function public.admin_close_zombie_table_session(uuid, text, boolean) to authenticated;


-- 9) admin_void_orphan_item
create or replace function public.admin_void_orphan_item(
  p_item_id uuid,
  p_reason  text
)
returns public.order_items
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_item public.order_items;
  v_business_id uuid;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'La razón es requerida (mínimo 3 caracteres)'
      using errcode = '22023';
  end if;

  update public.order_items
     set status = 'void'
   where id = p_item_id
     and status in ('pending', 'preparing', 'ready')
  returning * into v_item;

  if v_item.id is null then
    raise exception 'Item % no existe o ya no es void-able', p_item_id;
  end if;

  select ts.business_id into v_business_id
    from public.orders o
    join public.table_sessions ts on ts.id = o.session_id
   where o.id = v_item.order_id;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'void_orphan_item',
    'order_items',
    p_item_id,
    v_business_id,
    jsonb_build_object('reason', p_reason, 'product_name', v_item.product_name)
  );

  return v_item;
end;
$$;

grant execute on function public.admin_void_orphan_item(uuid, text) to authenticated;


-- Refrescar el cache de PostgREST.
notify pgrst, 'reload schema';
