-- =============================================================================
-- 0041 — get_revenue_trend_12h: serie de comparación contra ayer
-- =============================================================================
-- POR QUÉ:
--   La Vista Global v2 muestra los ingresos de las últimas 12 horas contra
--   "ayer a la misma hora". Sin esa serie, el número de arriba no dice nada:
--   RD$ 486,320 puede ser un día excelente o un desastre y el operador no
--   tiene forma de saberlo sin abrir otro reporte.
--
--   La comparación se calcula en la MISMA consulta —no en un segundo RPC—
--   porque las dos series tienen que compartir exactamente los mismos cortes
--   horarios. Dos llamadas separadas pueden caer en distintos minutos y
--   desalinear el gráfico.
--
-- QUÉ CAMBIA:
--   Se agregan dos columnas al output: `revenue_prev` y `transactions_prev`,
--   con la ventana desplazada 24 h hacia atrás. El resto del contrato
--   (nombres, orden, filtro por entorno, permisos) queda igual.
--
--   Como el `returns table` cambia de forma, hay que DROP antes del CREATE:
--   Postgres no permite alterar el tipo de retorno con CREATE OR REPLACE.
--
-- COMPATIBILIDAD:
--   El cliente Flutter lee las columnas nuevas como opcionales — si esta
--   migración todavía no está aplicada, el gráfico simplemente no dibuja la
--   línea punteada y oculta el delta. Nada se rompe.
-- =============================================================================

begin;

drop function if exists public.get_revenue_trend_12h(text);

create or replace function public.get_revenue_trend_12h(p_env text default null)
returns table (
  hour               timestamptz,
  hour_label         text,
  revenue            numeric,
  transactions       int,
  revenue_prev       numeric,
  transactions_prev  int
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
  with hours as (
    select date_trunc('hour', now()) - (interval '1 hour' * gs) as hour_start
      from generate_series(11, 0, -1) gs
  ),
  filtered_biz as (
    select id from public.businesses
     where p_env is null or environment = p_env
  ),
  -- Agregamos hoy y ayer por separado y los unimos por hora: un LEFT JOIN
  -- doble sobre `payments` multiplicaría las filas y duplicaría los montos.
  today as (
    select h.hour_start,
           coalesce(sum(p.amount), 0)::numeric as revenue,
           coalesce(count(p.id), 0)::int       as transactions
      from hours h
      left join public.payments p
        on p.created_at >= h.hour_start
       and p.created_at <  h.hour_start + interval '1 hour'
       and p.status = 'completed'
       and (p_env is null or p.business_id in (select id from filtered_biz))
     group by h.hour_start
  ),
  yesterday as (
    select h.hour_start,
           coalesce(sum(p.amount), 0)::numeric as revenue,
           coalesce(count(p.id), 0)::int       as transactions
      from hours h
      left join public.payments p
        on p.created_at >= h.hour_start - interval '24 hours'
       and p.created_at <  h.hour_start - interval '23 hours'
       and p.status = 'completed'
       and (p_env is null or p.business_id in (select id from filtered_biz))
     group by h.hour_start
  )
  select t.hour_start as hour,
         to_char(t.hour_start at time zone 'America/Santo_Domingo', 'HH24:MI')
           as hour_label,
         t.revenue,
         t.transactions,
         y.revenue      as revenue_prev,
         y.transactions as transactions_prev
    from today t
    join yesterday y on y.hour_start = t.hour_start
   order by t.hour_start asc;
end;
$$;

grant execute on function public.get_revenue_trend_12h(text) to authenticated;

comment on function public.get_revenue_trend_12h(text) is
  'Ingresos por hora de las últimas 12 h con la serie equivalente de ayer '
  '(revenue_prev / transactions_prev) para comparar en el mismo gráfico.';

commit;
