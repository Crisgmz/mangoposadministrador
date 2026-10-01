-- ============================================================================
-- Migración 0050 — La factura creada por un cobro descuenta los reembolsos de
-- precio.
--
-- 0049 creaba la factura del mes por lo COBRADO. En la vista previa de la
-- conciliación salió el problema: La Maison Francaise y Tiempo Extra (16/09)
-- se cobraron a precio de lista (RD$4,799.99) con precio especial vigente y se
-- les devolvió la diferencia (RD$1,799.99) ANTES de conciliar. Sus facturas
-- habrían quedado en 4,799.99 cuando el mes vale 3,000.00.
--
-- Ahora la factura nueva = cobrado − reembolsos aprobados que corrigieron el
-- precio. Si Azul aprobó la venta dos veces por el mismo cobro, la devolución
-- de la venta de más NO achica el mes (el mes igual vale un cobro):
--
--   reembolso de precio = max(0, reembolsado − cobrado × (ventas − 1))
--
-- Solo cambia la creación de facturas. Marcar una factura existente no toca su
-- monto (ya lo definió quien la emitió). El resultado agrega invoice_amount
-- para verlo en la vista previa.
--
-- DEPENDE de 0049. Idempotente (create or replace, misma firma).
-- ============================================================================

begin;

do $$
begin
  if to_regprocedure('public.fn_reconcile_card_charge(uuid,boolean)') is null then
    raise exception 'Falta 0049_card_payments_reconcile.sql. Aplicarla antes que 0050.';
  end if;
end $$;

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
  v_refunded       numeric(12,2);
  v_sales          int;
  v_price_refund   numeric(12,2);
  v_invoice_amount numeric(12,2);
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

  -- Monto de la factura nueva: lo cobrado menos los reembolsos que CORRIGIERON
  -- EL PRECIO (0050). Caso real: La Maison y Tiempo Extra el 16/09, cobrados a
  -- lista (4,799.99) y devuelta la diferencia (1,799.99): el mes vale 3,000.
  -- Si Azul aprobó la venta dos veces, devolver la venta de más no achica el
  -- mes: esa parte del reembolso no cuenta.
  select coalesce(sum(r.amount_cents), 0) / 100.0 into v_refunded
    from public.azul_refunds r
   where r.charge_id = v_charge.id
     and r.status = 'approved';
  select count(*) into v_sales
    from public.azul_webhook_events e
   where e.related_charge_id = v_charge.id
     and e.event_type = 'webservice_response'
     and coalesce(e.raw_url, '') not like 'azul-proxy /call%'
     and coalesce(e.raw_url, '') not like '%(VerifyPayment%'
     and substring(e.raw_body from '"IsoCode"\s*:\s*"([^"]*)"') = '00';
  v_price_refund   := greatest(0, v_refunded - v_charged * greatest(v_sales - 1, 0));
  v_invoice_amount := greatest(0, v_charged - v_price_refund);

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
    greatest(0, v_invoice_amount - v_itbis), v_itbis,
    'paid', v_paid_at, 'card', v_reference,
    v_charge.id,
    concat_ws(' ',
      format('Factura creada automáticamente por el cobro con tarjeta (%s).', v_reference),
      case when v_price_refund > 0 then format(
        'Cobrado RD$%s; reembolsado RD$%s.',
        to_char(v_charged, 'FM999,999,990.00'),
        to_char(v_price_refund, 'FM999,999,990.00'))
      end)
  )
  on conflict (business_id, period_start) do nothing
  returning * into v_inv;

  if v_inv.id is null then
    -- Ese inicio exacto lo ocupa una factura anulada.
    return v_result || jsonb_build_object('action', 'period_taken');
  end if;
  return v_result || jsonb_build_object(
    'action', 'created_paid', 'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number,
    'invoice_amount', v_invoice_amount);
end;
$$;

comment on function public.fn_reconcile_card_charge(uuid, boolean) is
  'Deja pagada la factura del mes de un cobro con tarjeta aprobado (la crea si '
  'no existe, por lo cobrado menos los reembolsos de precio). Idempotente. La '
  'llama el trigger de azul_charges y el backfill.';

revoke all on function public.fn_reconcile_card_charge(uuid, boolean) from public, anon, authenticated;

commit;

notify pgrst, 'reload schema';
