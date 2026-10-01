-- ============================================================================
-- Migración 0048 — Cobros duplicados visibles en la consola.
--
-- En agosto 2026 varias suscripciones quedaron con DOS ventas aprobadas en
-- Azul por un mismo cobro (caso confirmado: La Maison Francaise, 16/08). En
-- `azul_charges` se veía una sola fila aprobada: el reintento pisó la primera
-- respuesta con la segunda. Solo `azul_webhook_events` guarda las dos.
--
-- `admin_list_business_charges` suma `azul_sales` a cada cobro: las ventas
-- aprobadas por Azul según la bitácora (número de orden, autorización y hora).
-- La sección "Pagos de suscripción" marca COBRADO 2 VECES cuando hay más de
-- una y ofrece reembolsar la venta de más.
--
-- Solo agrega una clave al jsonb: la app actual la ignora sin romperse.
-- DEPENDE de 0046. Idempotente (create or replace).
-- ============================================================================

begin;

do $$
begin
  if to_regclass('public.azul_refunds') is null then
    raise exception 'Falta azul_refunds (migración 0046). Aplicarla antes que 0048.';
  end if;
  if to_regclass('public.azul_webhook_events') is null then
    raise exception 'Falta azul_webhook_events (mangospos 20260526_0002).';
  end if;
end $$;

create or replace function public.admin_list_business_charges(
  p_business_id uuid,
  p_limit       int default 24
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit  int := greatest(1, least(coalesce(p_limit, 24), 120));
  v_result jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(t.row_json order by t.attempted_at desc), '[]'::jsonb)
    into v_result
  from (
    select
      c.attempted_at,
      jsonb_build_object(
        'id',                   c.id,
        'membership_id',        c.membership_id,
        'order_number',         c.order_number,
        'billing_period_start', c.billing_period_start,
        'billing_period_end',   c.billing_period_end,
        'attempt_number',       c.attempt_number,
        'amount_cents',         c.amount_cents,
        'itbis_cents',          c.itbis_cents,
        'currency_code',        c.currency_code,
        'status',               c.status,
        'response_message',     c.response_message,
        'error_description',    c.error_description,
        'authorization_code',   c.authorization_code,
        'azul_order_id',        c.azul_order_id,
        'attempted_at',         c.attempted_at,
        'completed_at',         c.completed_at,
        'card', (
          select jsonb_build_object(
                   'brand',  pm.data_vault_brand,
                   'masked', pm.card_number_masked
                 )
            from public.azul_payment_methods pm
           where pm.id = c.payment_method_id
        ),
        'current_price_cents',
          public.subscription_effective_price_cents(c.membership_id, c.billing_period_start),
        'refunded_cents', coalesce((
          select sum(r.amount_cents)
            from public.azul_refunds r
           where r.charge_id = c.id
             and r.status = 'approved'
        ), 0),
        'pending_refund_cents', coalesce((
          select sum(r.amount_cents)
            from public.azul_refunds r
           where r.charge_id = c.id
             and r.status = 'pending'
        ), 0),
        'refundable_cents', public.azul_charge_refundable_cents(c.id),
        -- Ventas que Azul APROBÓ para este cobro, según la bitácora. Más de una
        -- = el cliente pagó dos veces el mismo período: el reintento pisa la
        -- fila de azul_charges y solo la bitácora conserva las dos respuestas.
        -- Fuera: reembolsos (admin-azul-refund loguea con raw_url
        -- 'azul-proxy /call (…)') y consultas VerifyPayment, que repiten el
        -- IsoCode 00 de una venta que ya se contó.
        'azul_sales', coalesce((
          select jsonb_agg(
                   jsonb_build_object(
                     'azul_order_id',      substring(e.raw_body from '"AzulOrderId"\s*:\s*"([^"]*)"'),
                     'authorization_code', substring(e.raw_body from '"AuthorizationCode"\s*:\s*"([^"]*)"'),
                     'approved_at',        e.received_at
                   )
                   order by e.received_at
                 )
            from public.azul_webhook_events e
           where e.related_charge_id = c.id
             and e.event_type = 'webservice_response'
             and coalesce(e.raw_url, '') not like 'azul-proxy /call%'
             and coalesce(e.raw_url, '') not like '%(VerifyPayment%'
             and substring(e.raw_body from '"IsoCode"\s*:\s*"([^"]*)"') = '00'
        ), '[]'::jsonb),
        'refunds', coalesce((
          select jsonb_agg(
                   jsonb_build_object(
                     'id',                 r.id,
                     'amount_cents',       r.amount_cents,
                     'status',             r.status,
                     'reason',             r.reason,
                     'requested_by_email', (
                       select u.email from auth.users u where u.id = r.requested_by
                     ),
                     'requested_at',       r.requested_at,
                     'completed_at',       r.completed_at,
                     'azul_order_id',      r.azul_order_id,
                     'response_message',   r.response_message,
                     'error_description',  r.error_description,
                     'resolution_note',    r.resolution_note
                   )
                   order by r.requested_at desc
                 )
            from public.azul_refunds r
           where r.charge_id = c.id
        ), '[]'::jsonb)
      ) as row_json
    from public.azul_charges c
    where c.business_id = p_business_id
    order by c.attempted_at desc
    limit v_limit
  ) t;

  return v_result;
end;
$$;

comment on function public.admin_list_business_charges(uuid, int) is
  'Cobros de suscripción (Azul) de un negocio con reembolsos, saldo reembolsable, precio vigente del período y ventas aprobadas por Azul (azul_sales: más de una = cobro duplicado). Solo operadores.';

revoke all on function public.admin_list_business_charges(uuid, int) from public, anon;
grant execute on function public.admin_list_business_charges(uuid, int) to authenticated;

commit;

notify pgrst, 'reload schema';
