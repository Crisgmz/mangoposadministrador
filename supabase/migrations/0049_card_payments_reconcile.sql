-- ============================================================================
-- Migración 0049 — Pagos con tarjeta ↔ facturas, y lista de pagos.
--
-- ANTES: los cobros con tarjeta (azul_charges) y las facturas
-- (membership_invoices) no se conocían. Cuando Azul aprobaba la mensualidad,
-- la factura de ese mes seguía "pendiente" (o no existía: las facturas se
-- generan a mano) hasta que alguien la marcaba.
--
-- AHORA:
--   1) membership_invoices.azul_charge_id — qué cobro con tarjeta pagó la
--      factura.
--   2) Al aprobarse un cobro (trigger), la factura del mes queda pagada sola:
--        · pendiente/vencida        → pagada, método card, referencia Azul #
--        · no existe                → se crea pagada, por lo COBRADO
--        · ya pagada con tarjeta a
--          mano (sin vínculo)       → se vincula
--        · ya pagada por otro medio → NO se toca (posible pago doble: queda
--          (transferencia, efectivo)  a la vista en la lista de pagos)
--      Si algo falla, el cobro igual queda aprobado: la conciliación nunca
--      bloquea el registro del pago (si lo bloqueara, el próximo intento lo
--      cobraría de nuevo).
--   3) admin_backfill_card_payments(dry_run) — concilia los cobros aprobados
--      ANTERIORES a esta migración. Se previsualiza primero (no escribe nada,
--      ni siquiera consume números de factura); ver
--      supabase/CONCILIAR_0049_pagos_tarjeta.sql.
--   4) admin_list_payments() — todos los pagos (tarjeta + manuales) para la
--      pestaña Pagos de Facturación, sin contar dos veces la misma plata.
--
-- CÓMO SE ENCUENTRA "LA FACTURA DEL MES"
-- Las fechas no coinciden exacto: la factura manual arranca en
-- memberships.end_date y el cobro en next_billing_date. Se toma la factura
-- (no anulada) cuyo inicio esté a ±15 días del período cobrado, la más
-- cercana. Buscar la fecha exacta crearía una segunda factura del mismo mes.
--
-- MONTO de una factura creada por un cobro: exactamente lo cobrado (con el
-- ITBIS del cobro, hoy 0). En planes sin ITBIS incluido la factura manual
-- suma 18%, pero la tarjeta no lo cobra: la factura refleja lo que se pagó.
--
-- REEMBOLSOS: no se revierten solos. Si un cobro que pagó una factura se
-- reembolsa entero, la factura hay que corregirla a mano.
--
-- DEPENDE de 0004 (membership_invoices), 0046 (azul_refunds) y de mangospos
-- 20260526_0002 (azul_charges, azul_webhook_events). Idempotente.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0) Guard
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.azul_charges') is null
     or to_regclass('public.azul_webhook_events') is null then
    raise exception 'Faltan azul_charges / azul_webhook_events (mangospos 20260526_0002).';
  end if;
  if to_regclass('public.azul_refunds') is null then
    raise exception 'Falta azul_refunds (migración 0046). Aplicarla antes que 0049.';
  end if;
  if to_regprocedure('public.next_membership_invoice_number()') is null then
    raise exception 'Falta next_membership_invoice_number() (migración 0004).';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1) Vínculo factura → cobro
-- ---------------------------------------------------------------------------
alter table public.membership_invoices
  add column if not exists azul_charge_id uuid
    references public.azul_charges(id) on delete set null;

-- Un cobro paga una sola factura.
create unique index if not exists membership_invoices_azul_charge_key
  on public.membership_invoices (azul_charge_id)
  where azul_charge_id is not null;

comment on column public.membership_invoices.azul_charge_id is
  'Cobro con tarjeta (Azul) que pagó esta factura. Lo pone la conciliación '
  'automática (0049). NULL = pagada a mano o todavía sin pagar.';

-- ---------------------------------------------------------------------------
-- 2) Conciliar UN cobro aprobado con la factura de su mes
-- ---------------------------------------------------------------------------
-- Versión previa sin p_preview (si se llegó a aplicar un borrador).
drop function if exists public.fn_reconcile_card_charge(uuid);

create or replace function public.fn_reconcile_card_charge(
  p_charge_id uuid,
  -- Vista previa: las facturas nuevas llevan un número provisorio. La
  -- numeración sale de una secuencia, y una secuencia NO se deshace con el
  -- rollback de la vista previa: cada vista previa dejaría huecos.
  p_preview   boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_charge     public.azul_charges;
  v_business   text;
  v_membership public.memberships;
  v_inv        public.membership_invoices;
  v_charged    numeric(12,2);
  v_itbis      numeric(12,2);
  v_paid_at    timestamptz;
  v_reference  text;
  v_result     jsonb;
begin
  select * into v_charge from public.azul_charges where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'approved' then
    return jsonb_build_object('action', 'not_approved', 'charge_id', p_charge_id);
  end if;

  select b.business_name into v_business
    from public.businesses b
   where b.id = v_charge.business_id;

  v_charged   := round(v_charge.amount_cents / 100.0, 2);
  v_itbis     := round(coalesce(v_charge.itbis_cents, 0) / 100.0, 2);
  v_paid_at   := coalesce(v_charge.completed_at, v_charge.attempted_at, now());
  v_reference := 'Azul #' || coalesce(nullif(v_charge.azul_order_id, ''), v_charge.order_number);

  v_result := jsonb_build_object(
    'charge_id',     v_charge.id,
    'business_id',   v_charge.business_id,
    'business_name', v_business,
    'period_start',  v_charge.billing_period_start,
    'amount',        v_charged,
    'reference',     v_reference
  );

  -- Idempotencia: este cobro ya pagó una factura.
  select * into v_inv
    from public.membership_invoices
   where azul_charge_id = v_charge.id
   limit 1;
  if v_inv.id is not null then
    return v_result || jsonb_build_object(
      'action', 'already_linked', 'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number);
  end if;

  -- La factura del mismo mes: la no anulada más cercana a ±15 días.
  select * into v_inv
    from public.membership_invoices mi
   where mi.business_id = v_charge.business_id
     and mi.status <> 'void'
     and mi.period_start between v_charge.billing_period_start - 15
                             and v_charge.billing_period_start + 15
   order by abs(mi.period_start - v_charge.billing_period_start), mi.created_at
   limit 1
   for update;

  if v_inv.id is not null then
    if v_inv.status = 'paid' then
      if v_inv.azul_charge_id is not null then
        -- Otro cobro con tarjeta ya pagó este mes: dos cobros para un mes.
        return v_result || jsonb_build_object(
          'action', 'period_paid_by_other_charge',
          'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number,
          'other_charge_id', v_inv.azul_charge_id);
      end if;
      if v_inv.payment_method = 'card' then
        -- Alguien la marcó pagada con tarjeta a mano: es este mismo pago.
        update public.membership_invoices
           set azul_charge_id    = v_charge.id,
               payment_reference = coalesce(nullif(payment_reference, ''), v_reference)
         where id = v_inv.id;
        return v_result || jsonb_build_object(
          'action', 'linked_paid_card', 'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number);
      end if;
      -- Pagada por otro medio: no se toca. Posible pago doble.
      return v_result || jsonb_build_object(
        'action', 'paid_other_method',
        'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number,
        'payment_method', v_inv.payment_method);
    end if;

    -- Pendiente o vencida → pagada por este cobro.
    update public.membership_invoices
       set status            = 'paid',
           paid_at           = v_paid_at,
           paid_by           = null,
           payment_method    = 'card',
           payment_reference = v_reference,
           azul_charge_id    = v_charge.id,
           notes = concat_ws(' ',
             nullif(notes, ''),
             format('Pagada automáticamente con tarjeta (%s).', v_reference),
             case when v_inv.total <> v_charged then format(
               'Cobrado RD$%s; factura RD$%s.',
               to_char(v_charged, 'FM999,999,990.00'),
               to_char(v_inv.total, 'FM999,999,990.00'))
             end)
     where id = v_inv.id;
    return v_result || jsonb_build_object(
      'action', 'marked_paid', 'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number);
  end if;

  -- No hay factura del mes → se crea, ya pagada, por lo cobrado.
  select * into v_membership from public.memberships where id = v_charge.membership_id;
  if v_membership.id is null then
    return v_result || jsonb_build_object('action', 'no_membership');
  end if;
  if v_membership.plan_type is null then
    return v_result || jsonb_build_object('action', 'no_plan_type');
  end if;

  insert into public.membership_invoices (
    invoice_number,
    business_id, membership_id, plan_type,
    period_start, period_end, due_date,
    amount, itbis,
    status, paid_at, payment_method, payment_reference,
    azul_charge_id, notes
  )
  values (
    case when p_preview
      then 'PREVIA-' || replace(gen_random_uuid()::text, '-', '')
      else public.next_membership_invoice_number()
    end,
    v_charge.business_id, v_membership.id, v_membership.plan_type,
    v_charge.billing_period_start,
    (v_charge.billing_period_start + interval '1 month' - interval '1 day')::date,
    v_charge.billing_period_start::timestamptz,
    v_charged - v_itbis, v_itbis,
    'paid', v_paid_at, 'card', v_reference,
    v_charge.id,
    format('Factura creada automáticamente por el cobro con tarjeta (%s).', v_reference)
  )
  on conflict (business_id, period_start) do nothing
  returning * into v_inv;

  if v_inv.id is null then
    -- Ese inicio exacto lo ocupa una factura anulada.
    return v_result || jsonb_build_object('action', 'period_taken');
  end if;
  return v_result || jsonb_build_object(
    'action', 'created_paid', 'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number);
end;
$$;

comment on function public.fn_reconcile_card_charge(uuid, boolean) is
  'Deja pagada la factura del mes de un cobro con tarjeta aprobado (la crea si '
  'no existe). Idempotente. La llama el trigger de azul_charges y el backfill.';

revoke all on function public.fn_reconcile_card_charge(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Trigger: al aprobarse un cobro
-- ---------------------------------------------------------------------------
create or replace function public.trg_azul_charge_reconcile_invoice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and old.status = 'approved' then
    return null;
  end if;
  begin
    perform public.fn_reconcile_card_charge(new.id);
  exception when others then
    -- NUNCA bloquear el registro del cobro: si la fila no queda aprobada, el
    -- próximo intento lo vuelve a cobrar. El pago sin factura queda a la
    -- vista en la pestaña Pagos ("Sin factura").
    raise warning 'Conciliación automática falló para el cobro %: % (%)',
      new.id, sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

revoke all on function public.trg_azul_charge_reconcile_invoice() from public, anon, authenticated;

drop trigger if exists trg_azul_charges_reconcile_invoice on public.azul_charges;
create trigger trg_azul_charges_reconcile_invoice
  after insert or update of status on public.azul_charges
  for each row
  when (new.status = 'approved')
  execute function public.trg_azul_charge_reconcile_invoice();

-- ---------------------------------------------------------------------------
-- 4) Backfill de los cobros anteriores (con vista previa)
-- ---------------------------------------------------------------------------
create or replace function public.admin_backfill_card_payments(p_dry_run boolean default true)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_results jsonb := '[]'::jsonb;
  v_charge  record;
begin
  begin
    -- Del más viejo al más nuevo: si dos cobros caen en el mismo mes, el
    -- primero paga la factura y el segundo sale como period_paid_by_other_charge.
    for v_charge in
      select c.id
        from public.azul_charges c
       where c.status = 'approved'
       order by c.attempted_at, c.id
    loop
      v_results := v_results || jsonb_build_array(
        public.fn_reconcile_card_charge(v_charge.id, p_dry_run));
    end loop;

    if p_dry_run then
      -- Deshace TODO lo de arriba; las variables sobreviven al rollback.
      raise exception 'vista previa' using errcode = 'MGDRY';
    end if;
  exception when sqlstate 'MGDRY' then
    null;
  end;

  return jsonb_build_object(
    'dry_run',   p_dry_run,
    'total',     jsonb_array_length(v_results),
    'by_action', coalesce((
      select jsonb_object_agg(x.action, x.n)
        from (select r->>'action' as action, count(*) as n
                from jsonb_array_elements(v_results) r
               group by 1) x
    ), '{}'::jsonb),
    'results',   v_results
  );
end;
$$;

comment on function public.admin_backfill_card_payments(boolean) is
  'Concilia los cobros con tarjeta aprobados anteriores a 0049. Con dry_run=true '
  '(por defecto) solo muestra qué haría. Solo desde el SQL Editor.';

revoke all on function public.admin_backfill_card_payments(boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) Lista de pagos (pestaña Pagos de Facturación)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_payments(p_limit int default 2000)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit  int := greatest(1, least(coalesce(p_limit, 2000), 5000));
  v_result jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  with card as (
    -- Cobros con tarjeta aprobados, con la factura que pagaron.
    select 'card'::text                                   as kind,
           c.id,
           c.business_id,
           b.business_name,
           b.environment,
           coalesce(c.completed_at, c.attempted_at)       as paid_at,
           c.amount_cents::bigint                         as amount_cents,
           c.currency_code,
           'card'::text                                   as method,
           c.azul_order_id                                as reference,
           c.billing_period_start                         as period_start,
           c.billing_period_end                           as period_end,
           mi.id                                          as invoice_id,
           mi.invoice_number,
           mi.status                                      as invoice_status,
           coalesce((
             select sum(r.amount_cents)
               from public.azul_refunds r
              where r.charge_id = c.id
                and r.status = 'approved'
           ), 0)::bigint                                  as refunded_cents,
           -- Ventas aprobadas en la bitácora (mismo criterio que 0048).
           (select count(*)
              from public.azul_webhook_events e
             where e.related_charge_id = c.id
               and e.event_type = 'webservice_response'
               and coalesce(e.raw_url, '') not like 'azul-proxy /call%'
               and coalesce(e.raw_url, '') not like '%(VerifyPayment%'
               and substring(e.raw_body from '"IsoCode"\s*:\s*"([^"]*)"') = '00'
           )::int                                         as sales_count,
           nullif(btrim(concat_ws(' ', pm.data_vault_brand, pm.card_number_masked)), '')
                                                          as card_label
      from public.azul_charges c
      join public.businesses b on b.id = c.business_id
      left join public.membership_invoices mi on mi.azul_charge_id = c.id
      left join public.azul_payment_methods pm on pm.id = c.payment_method_id
     where c.status = 'approved'
  ),
  manual as (
    -- Facturas pagadas a mano. Las pagadas por un cobro con tarjeta ya
    -- salen arriba; los créditos aplicados no son plata recibida.
    select 'manual'::text,
           mi.id,
           mi.business_id,
           b.business_name,
           b.environment,
           mi.paid_at,
           round(mi.total * 100)::bigint,
           'DOP'::text,
           coalesce(nullif(mi.payment_method, ''), 'other'),
           mi.payment_reference,
           mi.period_start,
           mi.period_end,
           mi.id,
           mi.invoice_number,
           mi.status,
           0::bigint,
           0::int,
           null::text
      from public.membership_invoices mi
      join public.businesses b on b.id = mi.business_id
     where mi.status = 'paid'
       and mi.azul_charge_id is null
       and mi.paid_at is not null
       and coalesce(mi.payment_method, '') <> 'credit_applied'
  )
  select coalesce(jsonb_agg(to_jsonb(p) order by p.paid_at desc), '[]'::jsonb)
    into v_result
    from (
      select * from card
      union all
      select * from manual
      order by paid_at desc
      limit v_limit
    ) p;

  return v_result;
end;
$$;

comment on function public.admin_list_payments(int) is
  'Pagos recibidos de todos los negocios: cobros con tarjeta aprobados (con '
  'factura, reembolsos y ventas en Azul) y facturas pagadas a mano. Solo operadores.';

revoke all on function public.admin_list_payments(int) from public, anon;
grant execute on function public.admin_list_payments(int) to authenticated;

commit;

notify pgrst, 'reload schema';
