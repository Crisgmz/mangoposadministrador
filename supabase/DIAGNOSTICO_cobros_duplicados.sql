-- ===========================================================================
-- DIAGNÓSTICO — cobros de suscripción duplicados (Azul)
--
-- Solo lee: no cambia nada. Se corre entero en el SQL Editor; devuelve UNA
-- tabla (la última consulta) con una fila por cobro sospechoso.
--
-- Por qué hace falta mirar más que `azul_charges`:
-- el cobro (azul-charge-subscription) reintenta sobre la MISMA fila cuando la
-- encuentra en `pending` o `error`. Si la primera llamada sí había pasado en
-- Azul, la segunda respuesta PISA a la primera: en `azul_charges` queda una
-- sola fila aprobada, pero la tarjeta tiene dos ventas. El rastro de la
-- primera solo sobrevive en `azul_webhook_events`, que guarda cada respuesta
-- de Azul. Por eso se leen las dos tablas.
--
-- TIPOS
--   A  Una fila, dos (o más) ventas aprobadas por Azul.  → duplicado SEGURO
--   B  Dos filas aprobadas de la misma suscripción para el MISMO período
--      (fechas de período a menos de 25 días). → duplicado probable.
--      Dos meses distintos cobrados en días seguidos (un atraso que se pone
--      al día) NO salen: cada cobro es de su mes.
--   C  Un intento que quedó en error/pending y DESPUÉS otro aprobado del
--      mismo período. → posible duplicado: el primero pudo haber pasado en
--      Azul sin que nos enteráramos. Confirmar en el portal de Azul con el
--      OrderNumber de la columna `detalle`.
--   D  Un `pending` colgado hace más de 15 minutos. → RIESGO ACTIVO: el
--      próximo intento lo va a volver a cobrar.
--
-- Los REEMBOLSOS también se registran en azul_webhook_events con el mismo
-- tipo y el mismo cobro (función admin-azul-refund, raw_url
-- 'azul-proxy /call (…)'); se excluyen para no contarlos como ventas.
--
-- Los datos de Azul se leen con expresiones regulares sobre el texto (no con
-- ::jsonb) para que una respuesta truncada no haga fallar la consulta entera.
-- ===========================================================================

with respuestas as (
  select e.related_charge_id as charge_id,
         e.received_at,
         substring(e.raw_body from '"IsoCode"\s*:\s*"([^"]*)"')     as iso_code,
         substring(e.raw_body from '"AzulOrderId"\s*:\s*"([^"]*)"') as azul_order_id,
         substring(e.raw_body from '"AuthorizationCode"\s*:\s*"([^"]*)"') as auth_code
    from public.azul_webhook_events e
   where e.event_type = 'webservice_response'
     and e.related_charge_id is not null
     -- Fuera los reembolsos: su respuesta aprobada NO es una segunda venta.
     and coalesce(e.raw_url, '') not like 'azul-proxy /call%'
     -- Ni las consultas VerifyPayment: repiten el 00 de una venta ya contada.
     and coalesce(e.raw_url, '') not like '%(VerifyPayment%'
),
aprobadas_por_fila as (
  select r.charge_id,
         count(*) as ventas_aprobadas,
         string_agg(
           'AzulOrderId ' || coalesce(r.azul_order_id, '?')
             || ' auth ' || coalesce(r.auth_code, '?')
             || ' a las ' || to_char(r.received_at at time zone 'America/Santo_Domingo', 'DD/MM HH24:MI:SS'),
           '  |  ' order by r.received_at
         ) as ventas
    from respuestas r
   where r.iso_code = '00'
   group by r.charge_id
),
cobros as (
  select c.id, c.membership_id, c.business_id, b.business_name,
         c.billing_period_start, c.attempt_number, c.status,
         c.amount_cents, c.attempted_at, c.completed_at,
         c.order_number, c.azul_order_id, c.authorization_code,
         m.next_billing_date
    from public.azul_charges c
    join public.businesses b on b.id = c.business_id
    left join public.memberships m on m.id = c.membership_id
),
sospechosos as (
  -- A) Una fila, varias ventas aprobadas en Azul.
  select 'A · duplicado seguro: 1 fila, ' || a.ventas_aprobadas || ' ventas aprobadas en Azul' as tipo,
         co.business_name, co.id, co.billing_period_start, co.attempt_number,
         co.status, co.amount_cents, co.attempted_at, co.next_billing_date,
         'OrderNumber ' || co.order_number || '  →  ' || a.ventas as detalle
    from aprobadas_por_fila a
    join cobros co on co.id = a.charge_id
   where a.ventas_aprobadas > 1

  union all

  -- B) Dos filas aprobadas del mismo período.
  select 'B · duplicado probable: 2 cobros aprobados del mismo período',
         co.business_name, co.id, co.billing_period_start, co.attempt_number,
         co.status, co.amount_cents, co.attempted_at, co.next_billing_date,
         'OrderNumber ' || co.order_number
           || ' · AzulOrderId ' || coalesce(co.azul_order_id, '?')
           || ' · auth ' || coalesce(co.authorization_code, '?')
    from cobros co
   where co.status = 'approved'
     and exists (
       select 1
         from public.azul_charges o
        where o.membership_id = co.membership_id
          and o.id <> co.id
          and o.status = 'approved'
          -- Mismo mes facturado. Se compara el PERÍODO, no cuándo se cobró:
          -- agosto atrasado y septiembre cobrados en días seguidos son dos
          -- meses distintos, no un duplicado.
          and abs(o.billing_period_start - co.billing_period_start) < 25
     )

  union all

  -- C1) La MISMA fila tuvo un error de comunicación con Azul y después una
  --     venta aprobada. Es el caso típico del cron: el día N la llamada
  --     revienta (timeout del sidecar) pero Azul sí cobró; la fila queda en
  --     `error`, y el día N+1 el cron la reintenta y cobra de nuevo.
  select 'C · posible duplicado: falló la comunicación y se reintentó',
         co.business_name, co.id, co.billing_period_start, co.attempt_number,
         co.status, co.amount_cents, co.attempted_at, co.next_billing_date,
         'Buscar en el portal de Azul el OrderNumber ' || co.order_number
           || ': si aparecen DOS ventas, es duplicado'
    from cobros co
   where exists (
     select 1
       from public.azul_webhook_events e1
      where e1.related_charge_id = co.id
        and e1.event_type = 'webservice_response'
        and e1.raw_body like 'EXCEPTION:%'
        and coalesce(e1.raw_url, '') not like 'azul-proxy /call%'
        and exists (
          select 1
            from respuestas r
           where r.charge_id = co.id
             and r.iso_code = '00'
             and r.received_at > e1.received_at
        )
   )

  union all

  -- C2) Resultado desconocido en una fila y un cobro aprobado en OTRA fila
  --     del mismo período (claves distintas: otro intento u otra fecha).
  select 'C · posible duplicado: intento en ' || co.status || ' y después uno aprobado',
         co.business_name, co.id, co.billing_period_start, co.attempt_number,
         co.status, co.amount_cents, co.attempted_at, co.next_billing_date,
         'Buscar en el portal de Azul el OrderNumber ' || co.order_number
           || ' del ' || to_char(co.attempted_at at time zone 'America/Santo_Domingo', 'DD/MM/YYYY HH24:MI')
    from cobros co
   where co.status in ('error', 'pending')
     and exists (
       select 1
         from public.azul_charges o
        where o.membership_id = co.membership_id
          and o.id <> co.id
          and o.status = 'approved'
          and o.attempted_at > co.attempted_at
          and abs(o.billing_period_start - co.billing_period_start) < 25
     )

  union all

  -- D) Pending colgado: el próximo intento lo recobra.
  select 'D · RIESGO ACTIVO: pending colgado hace más de 15 min',
         co.business_name, co.id, co.billing_period_start, co.attempt_number,
         co.status, co.amount_cents, co.attempted_at, co.next_billing_date,
         'OrderNumber ' || co.order_number || ' — verificar en Azul ANTES del próximo cobro'
    from cobros co
   where co.status = 'pending'
     and co.attempted_at < now() - interval '15 minutes'
)
select tipo,
       business_name                        as negocio,
       id                                   as charge_id,
       billing_period_start                 as periodo,
       attempt_number                       as intento,
       status                               as estado,
       to_char(amount_cents / 100.0, 'FM999,999,990.00') as monto_rd,
       to_char(attempted_at at time zone 'America/Santo_Domingo', 'DD/MM/YYYY HH24:MI:SS') as intentado,
       next_billing_date                    as proximo_cobro_actual,
       detalle
  from sospechosos
 order by negocio, attempted_at;
