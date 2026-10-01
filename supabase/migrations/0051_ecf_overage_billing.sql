-- ============================================================================
-- Migración 0051 — Facturas electrónicas incluidas + extra en la mensualidad.
--
-- QUÉ
-- A cada negocio se le puede fijar una cantidad de e-CF incluidas por período.
-- Las que la DGII acepte por encima de esa cantidad se cobran a un precio por
-- unidad y se suman a la mensualidad del período siguiente (se facturan
-- vencidas, como un consumo):
--   · cobro con tarjeta (Azul): azul-charge-subscription cobra plan + extra
--     usando subscription_charge_breakdown() y guarda el desglose en el cobro;
--   · factura manual (generate_membership_invoice) y factura creada por un
--     cobro (fn_reconcile_card_charge): el extra va dentro del monto y
--     desglosado en ecf_overage_amount / ecf_detail (el PDF lo muestra aparte).
--
-- REGLAS
--   · Cuentan solo las e-CF ACEPTADAS por la DGII (fiscal_documents.is_electronic
--     y ecf_status = 'accepted', que incluye "aceptada con observaciones"),
--     por la fecha de aceptación (accepted_at): cada una cuenta una sola vez,
--     en el período en que la DGII la aceptó.
--   · Precio: el del negocio si tiene uno propio; si no, el global
--     (company_settings.ecf_overage_price_cents). Global en 0 = el extra no se
--     cobra hasta que se defina un precio.
--   · El período sigue el ciclo de cobro del negocio, no el mes calendario: la
--     ventana termina donde empieza el período que se cobra y empieza donde
--     terminó lo último ya facturado (sin huecos ni solapes si el ciclo se
--     corre unos días). Sin nada facturado antes: un mes hacia atrás.
--   · "A partir de ahí": al fijar la cantidad por primera vez se cuenta desde
--     ese momento (counting_since); editarla no reinicia la cuenta.
--   · Sin cantidad configurada, las e-CF no se cobran aparte.
--
-- LÍMITE CONOCIDO: el cron de cobro (mangospos 20260915_0007) no encola
-- suscripciones con precio de plan 0; un plan gratis con extra de e-CF no se
-- cobra por tarjeta. generate_membership_invoice tampoco factura planes de
-- costo 0.
--
-- OJO AL APLICAR: crea un índice parcial sobre fiscal_documents (bloquea
-- escrituras de esa tabla unos segundos). Mejor fuera de hora pico.
--
-- DEPENDE de 0048, 0049, 0050 y de mangospos 20260506_0001 (accepted_at) y
-- 20260915_0006 (subscription_effective_price_cents). Idempotente.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0) Guard
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.fn_reconcile_card_charge(uuid,boolean)') is null then
    raise exception 'Faltan 0049/0050. Aplicarlas antes que 0051.';
  end if;
  if to_regprocedure('public.subscription_effective_price_cents(uuid,date)') is null then
    raise exception 'Falta mangospos 20260915_0006 (subscription_effective_price_cents).';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'fiscal_documents'
       and column_name = 'accepted_at'
  ) then
    raise exception 'Falta fiscal_documents.accepted_at (mangospos 20260506_0001).';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1) Configuración: precio global y cantidad por negocio
-- ---------------------------------------------------------------------------
alter table public.company_settings
  add column if not exists ecf_overage_price_cents integer not null default 0
    check (ecf_overage_price_cents >= 0);

comment on column public.company_settings.ecf_overage_price_cents is
  'Precio por e-CF aceptada por encima de lo incluido, en centavos. 0 = no se cobra.';

create table if not exists public.business_ecf_quota (
  business_id          uuid primary key references public.businesses(id) on delete cascade,
  included_per_period  integer not null check (included_per_period >= 0),
  -- NULL = usa el precio global.
  price_override_cents integer check (price_override_cents is null or price_override_cents >= 0),
  -- Desde cuándo se cuentan: la primera vez que se fijó la cantidad.
  counting_since       timestamptz not null default now(),
  notes                text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  updated_by           uuid references auth.users(id)
);

comment on table public.business_ecf_quota is
  'e-CF incluidas por período de cobro de cada negocio (0051). Sin fila = las e-CF no se cobran aparte.';

alter table public.business_ecf_quota enable row level security;
revoke all on public.business_ecf_quota from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Desglose en cobros y facturas
-- ---------------------------------------------------------------------------
alter table public.azul_charges
  add column if not exists ecf_overage_cents integer not null default 0,
  add column if not exists ecf_detail        jsonb,
  add column if not exists ecf_usage_from    timestamptz,
  add column if not exists ecf_usage_to      timestamptz;

alter table public.membership_invoices
  add column if not exists ecf_overage_amount numeric(12,2) not null default 0,
  add column if not exists ecf_detail         jsonb,
  add column if not exists ecf_usage_from     timestamptz,
  add column if not exists ecf_usage_to       timestamptz;

comment on column public.azul_charges.ecf_overage_cents is
  'Parte del cobro que corresponde a facturas electrónicas extra (0051).';
comment on column public.membership_invoices.ecf_overage_amount is
  'Parte del monto que corresponde a facturas electrónicas extra (0051).';

-- Contar aceptadas por negocio y fecha de aceptación sin recorrer la tabla.
create index if not exists idx_fiscal_documents_ecf_accepted
  on public.fiscal_documents (business_id, accepted_at)
  where is_electronic = true and ecf_status = 'accepted';

-- ---------------------------------------------------------------------------
-- 3) Conteo y excedente
-- ---------------------------------------------------------------------------
create or replace function public.ecf_usage(
  p_business_id uuid,
  p_from        timestamptz,
  p_to          timestamptz
) returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.fiscal_documents fd
   where fd.business_id = p_business_id
     and fd.is_electronic = true
     and fd.ecf_status = 'accepted'
     and fd.accepted_at >= p_from
     and fd.accepted_at <  p_to;
$$;

-- Excedente de e-CF que se factura con el período que empieza en
-- p_period_start (fecha local RD).
create or replace function public.subscription_ecf_overage(
  p_business_id  uuid,
  p_period_start date
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_quota       public.business_ecf_quota;
  v_global      integer;
  v_to          timestamptz := p_period_start::timestamp at time zone 'America/Santo_Domingo';
  v_from        timestamptz;
  v_last_billed timestamptz;
  v_used        integer := 0;
  v_extra       integer;
  v_unit        integer;
begin
  select * into v_quota from public.business_ecf_quota where business_id = p_business_id;
  if v_quota.business_id is null then
    return jsonb_build_object('has_quota', false, 'overage_cents', 0);
  end if;

  -- Donde terminó lo último ya facturado: cobro aprobado o factura no anulada.
  select max(x.t) into v_last_billed
    from (
      select c.ecf_usage_to as t
        from public.azul_charges c
       where c.business_id = p_business_id
         and c.status = 'approved'
         and c.ecf_usage_to is not null
      union all
      select i.ecf_usage_to
        from public.membership_invoices i
       where i.business_id = p_business_id
         and i.status <> 'void'
         and i.ecf_usage_to is not null
    ) x;

  v_from := greatest(
    v_quota.counting_since,
    coalesce(v_last_billed,
             (p_period_start - interval '1 month')::timestamp at time zone 'America/Santo_Domingo')
  );

  if v_from < v_to then
    v_used := public.ecf_usage(p_business_id, v_from, v_to);
  else
    v_from := v_to;
  end if;

  select coalesce(ecf_overage_price_cents, 0) into v_global
    from public.company_settings
   where id = 1;

  v_extra := greatest(0, v_used - v_quota.included_per_period);
  v_unit  := coalesce(v_quota.price_override_cents, v_global, 0);

  return jsonb_build_object(
    'has_quota',        true,
    'included',         v_quota.included_per_period,
    'used',             v_used,
    'extra',            v_extra,
    'unit_price_cents', v_unit,
    'price_source',     case when v_quota.price_override_cents is null then 'global' else 'business' end,
    'overage_cents',    v_extra * v_unit,
    'usage_from',       v_from,
    'usage_to',         v_to
  );
end;
$$;

revoke all on function public.ecf_usage(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.subscription_ecf_overage(uuid, date) from public, anon, authenticated;

-- Lo que cobra azul-charge-subscription: plan (precio efectivo) + extra de e-CF.
create or replace function public.subscription_charge_breakdown(
  p_membership_id uuid,
  p_period_start  date
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_business uuid;
  v_plan     integer;
  v_ecf      jsonb;
  v_overage  integer;
begin
  select m.business_id into v_business
    from public.memberships m
   where m.id = p_membership_id;
  if v_business is null then
    raise exception 'Membresía % no encontrada', p_membership_id using errcode = 'P0002';
  end if;

  v_plan := public.subscription_effective_price_cents(p_membership_id, p_period_start);
  if v_plan is null then
    raise exception 'No se pudo resolver el precio de la membresía %', p_membership_id
      using errcode = 'P0001';
  end if;

  v_ecf     := public.subscription_ecf_overage(v_business, p_period_start);
  v_overage := coalesce((v_ecf->>'overage_cents')::integer, 0);

  return jsonb_build_object(
    'plan_cents',        v_plan,
    'ecf_overage_cents', v_overage,
    'ecf',               v_ecf,
    'total_cents',       v_plan + v_overage
  );
end;
$$;

comment on function public.subscription_charge_breakdown(uuid, date) is
  'Monto del cobro de un período: precio efectivo del plan + facturas electrónicas extra (0051).';

revoke all on function public.subscription_charge_breakdown(uuid, date) from public, anon, authenticated;
grant execute on function public.subscription_charge_breakdown(uuid, date) to service_role;

-- ---------------------------------------------------------------------------
-- 4) Factura manual con el extra (redefine la de 0043)
-- ---------------------------------------------------------------------------
create or replace function public.generate_membership_invoice(p_business_id uuid)
returns public.membership_invoices
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_membership      public.memberships;
  v_period_start    date;
  v_period_end      date;
  v_due_date        timestamptz;
  v_list_amount     numeric;
  v_override_cents  integer;
  v_amount_gross    numeric;
  v_amount_net      numeric;
  v_itbis_rate      numeric := 0.18;
  v_itbis           numeric;
  v_tax_included    boolean;
  v_invoice         public.membership_invoices;
  v_remaining       numeric;
  v_total_applied   numeric := 0;
  v_applied_ids     uuid[]  := '{}'::uuid[];
  v_credit          record;
  v_notes           text;
  v_ecf             jsonb;
  v_ecf_amount      numeric := 0;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select * into v_membership
    from public.memberships
   where business_id = p_business_id
     and status = 'active'
   order by created_at desc
   limit 1;

  if v_membership.id is null then
    raise exception 'El negocio % no tiene membresía activa', p_business_id;
  end if;

  v_period_start := coalesce(
    (v_membership.end_date at time zone 'America/Santo_Domingo')::date,
    (now() at time zone 'America/Santo_Domingo')::date
  );
  v_period_end := (v_period_start + interval '1 month' - interval '1 day')::date;
  v_due_date   := v_period_start::timestamptz;

  v_list_amount := public.plan_monthly_fee(v_membership.plan_type);
  if v_list_amount = 0 then
    raise exception 'Plan % sin costo, no se genera factura', v_membership.plan_type
      using errcode = '22023';
  end if;

  -- Precio especial del negocio para ESTE plan en ESTE período. least() con la
  -- lista del catálogo: nunca facturar por encima de lo que cuesta el plan.
  v_override_cents := public.business_price_override_cents(
    p_business_id, v_membership.plan_type, v_period_start
  );
  v_amount_gross := case
    when v_override_cents is null then v_list_amount
    else least(v_override_cents / 100.0, v_list_amount)
  end;

  -- Leer tax_included del plan. Si el plan no existe en catálogo (legacy),
  -- asumimos true (inclusivo) como default seguro.
  select coalesce(tax_included, true) into v_tax_included
    from public.plan_catalog
   where code = v_membership.plan_type;
  v_tax_included := coalesce(v_tax_included, true);

  select * into v_invoice
    from public.membership_invoices
   where business_id = p_business_id
     and period_start = v_period_start
   limit 1;
  if v_invoice.id is not null then
    return v_invoice;
  end if;

  -- free_credit FIFO.
  v_remaining := v_amount_gross;
  for v_credit in
    select id, amount
      from public.admin_extensions
     where business_id          = p_business_id
       and extension_type       = 'free_credit'
       and reverted_at         is null
       and applied_to_invoice_id is null
     order by granted_at asc
  loop
    exit when v_remaining <= 0;
    if v_credit.amount <= v_remaining then
      v_remaining      := v_remaining - v_credit.amount;
      v_total_applied  := v_total_applied + v_credit.amount;
      v_applied_ids    := array_append(v_applied_ids, v_credit.id);
    end if;
  end loop;

  v_amount_net := greatest(0, v_amount_gross - v_total_applied);

  -- Facturas electrónicas por encima de lo incluido (0051). Se facturan
  -- vencidas: lo aceptado por la DGII hasta el inicio de este período. El
  -- ITBIS de abajo (planes sin ITBIS incluido) también cae sobre este extra.
  v_ecf := public.subscription_ecf_overage(p_business_id, v_period_start);
  v_ecf_amount := coalesce((v_ecf->>'overage_cents')::numeric, 0) / 100.0;
  v_amount_net := v_amount_net + v_ecf_amount;

  if v_tax_included then
    v_itbis := 0;
  else
    v_itbis := round(v_amount_net * v_itbis_rate, 2);
  end if;

  -- La nota deja rastro del precio especial EN la factura: quien la lea meses
  -- después tiene que entender por qué no coincide con el precio del plan.
  if v_amount_gross < v_list_amount then
    v_notes := format(
      'Precio especial RD$%s (lista RD$%s).',
      to_char(v_amount_gross, 'FM999,999,990.00'),
      to_char(v_list_amount, 'FM999,999,990.00')
    );
  end if;

  if v_total_applied > 0 then
    v_notes := coalesce(v_notes || ' ', '') || format(
      'Crédito aplicado: RD$%s sobre %s factura(s) original RD$%s.',
      v_total_applied,
      cardinality(v_applied_ids),
      v_amount_gross
    );
  end if;

  if v_tax_included then
    v_notes := coalesce(v_notes || ' ', '') || 'Precio incluye ITBIS.';
  end if;

  if v_ecf_amount > 0 then
    v_notes := coalesce(v_notes || ' ', '') || format(
      'Incluye %s facturas electrónicas extra (%s incluidas, %s aceptadas; RD$%s c/u).',
      v_ecf->>'extra', v_ecf->>'included', v_ecf->>'used',
      to_char((v_ecf->>'unit_price_cents')::numeric / 100.0, 'FM999,999,990.00'));
  end if;

  insert into public.membership_invoices (
    business_id, membership_id, plan_type,
    period_start, period_end, due_date,
    amount, itbis,
    status, paid_at, payment_method,
    notes,
    ecf_overage_amount, ecf_detail, ecf_usage_from, ecf_usage_to
  )
  values (
    p_business_id, v_membership.id, v_membership.plan_type,
    v_period_start, v_period_end, v_due_date,
    v_amount_net,
    v_itbis,
    case when v_amount_net = 0 then 'paid' else 'pending' end,
    case when v_amount_net = 0 then now() else null end,
    case when v_amount_net = 0 then 'credit_applied' else null end,
    v_notes,
    v_ecf_amount,
    case when coalesce((v_ecf->>'has_quota')::boolean, false) then v_ecf end,
    (v_ecf->>'usage_from')::timestamptz,
    (v_ecf->>'usage_to')::timestamptz
  )
  returning * into v_invoice;

  if cardinality(v_applied_ids) > 0 then
    update public.admin_extensions
       set applied_to_invoice_id = v_invoice.id
     where id = any(v_applied_ids);

    insert into public.noc_audit_log (
      user_id, action, target_resource, target_id, business_id, payload
    )
    values (
      auth.uid(),
      'invoice.credit_applied',
      'membership_invoices',
      v_invoice.id,
      p_business_id,
      jsonb_build_object(
        'credit_total',  v_total_applied,
        'extension_ids', to_jsonb(v_applied_ids),
        'amount_gross',  v_amount_gross,
        'amount_net',    v_amount_net,
        'auto_paid',     (v_amount_net = 0)
      )
    );
  end if;

  return v_invoice;
end;
$$;

grant execute on function public.generate_membership_invoice(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Factura creada por un cobro: copia el desglose (redefine la de 0050)
-- ---------------------------------------------------------------------------
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
    azul_charge_id, notes,
    ecf_overage_amount, ecf_detail, ecf_usage_from, ecf_usage_to
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
      end,
      -- 0051: el cobro incluyó facturas electrónicas extra.
      case when coalesce(v_charge.ecf_overage_cents, 0) > 0 then format(
        'Incluye %s facturas electrónicas extra (RD$%s).',
        v_charge.ecf_detail->>'extra',
        to_char(v_charge.ecf_overage_cents / 100.0, 'FM999,999,990.00'))
      end),
    round(coalesce(v_charge.ecf_overage_cents, 0) / 100.0, 2),
    v_charge.ecf_detail,
    v_charge.ecf_usage_from,
    v_charge.ecf_usage_to
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

revoke all on function public.fn_reconcile_card_charge(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6) Listados con el desglose
-- ---------------------------------------------------------------------------
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
        'ecf_overage_cents',    c.ecf_overage_cents,
        'ecf_detail',           c.ecf_detail,
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

drop function if exists public.get_billing_overview();
create or replace function public.get_billing_overview()
returns table (
  id              uuid,
  invoice_number  text,
  business_id     uuid,
  business_name   text,
  plan_type       text,
  period_start    date,
  period_end      date,
  issue_date      timestamptz,
  due_date        timestamptz,
  amount          numeric,
  itbis           numeric,
  total           numeric,
  status          text,
  paid_at         timestamptz,
  payment_method  text,
  payment_reference text,
  environment     text,
  ecf_overage_amount numeric,
  ecf_detail      jsonb
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
  select i.id, i.invoice_number, i.business_id, b.business_name,
         i.plan_type, i.period_start, i.period_end,
         i.issue_date, i.due_date,
         i.amount, i.itbis, i.total,
         i.status, i.paid_at, i.payment_method, i.payment_reference,
         b.environment,
         i.ecf_overage_amount, i.ecf_detail
    from public.membership_invoices i
    join public.businesses b on b.id = i.business_id
   order by i.issue_date desc;
end;
$$;

grant execute on function public.get_billing_overview() to authenticated;

drop function if exists public.get_business_invoices(uuid);
create or replace function public.get_business_invoices(p_business_id uuid)
returns table (
  id                uuid,
  invoice_number    text,
  business_id       uuid,
  business_name     text,
  environment       text,
  plan_type         text,
  period_start      date,
  period_end        date,
  issue_date        timestamptz,
  due_date          timestamptz,
  amount            numeric,
  itbis             numeric,
  total             numeric,
  status            text,
  paid_at           timestamptz,
  payment_method    text,
  payment_reference text,
  notes             text,
  ecf_overage_amount numeric,
  ecf_detail        jsonb
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
    i.id,
    i.invoice_number,
    i.business_id,
    b.business_name,
    b.environment,
    i.plan_type,
    i.period_start,
    i.period_end,
    i.issue_date,
    i.due_date,
    i.amount,
    i.itbis,
    i.total,
    i.status,
    i.paid_at,
    i.payment_method,
    i.payment_reference,
    i.notes,
    i.ecf_overage_amount,
    i.ecf_detail
  from public.membership_invoices i
  join public.businesses b on b.id = i.business_id
  where i.business_id = p_business_id
  order by i.issue_date desc;
end;
$$;

grant execute on function public.get_business_invoices(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Consola: configurar y ver el uso
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_ecf_usage(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_quota   public.business_ecf_quota;
  v_global  integer;
  v_next    date;
  v_today   date := (now() at time zone 'America/Santo_Domingo')::date;
  v_current jsonb;
  v_history jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select * into v_quota from public.business_ecf_quota where business_id = p_business_id;
  select coalesce(ecf_overage_price_cents, 0) into v_global
    from public.company_settings where id = 1;
  select m.next_billing_date into v_next
    from public.memberships m
   where m.business_id = p_business_id
     and m.is_billing_anchor = true
   limit 1;

  -- Período en curso: lo aceptado desde lo último facturado hasta hoy.
  v_current := public.subscription_ecf_overage(p_business_id, v_today + 1);

  select coalesce(jsonb_agg(to_jsonb(h) order by h.usage_to desc), '[]'::jsonb)
    into v_history
    from (
      select 'card'::text                   as source,
             c.billing_period_start         as period_start,
             c.ecf_usage_from               as usage_from,
             c.ecf_usage_to                 as usage_to,
             (c.ecf_detail->>'used')::int   as used,
             (c.ecf_detail->>'extra')::int  as extra,
             c.ecf_overage_cents            as overage_cents
        from public.azul_charges c
       where c.business_id = p_business_id
         and c.status = 'approved'
         and c.ecf_detail is not null
      union all
      select 'invoice'::text,
             i.period_start,
             i.ecf_usage_from,
             i.ecf_usage_to,
             (i.ecf_detail->>'used')::int,
             (i.ecf_detail->>'extra')::int,
             round(i.ecf_overage_amount * 100)::int
        from public.membership_invoices i
       where i.business_id = p_business_id
         and i.status <> 'void'
         and i.ecf_detail is not null
         and i.azul_charge_id is null
       order by 4 desc
       limit 6
    ) h;

  return jsonb_build_object(
    'has_quota',            v_quota.business_id is not null,
    'included',             v_quota.included_per_period,
    'price_override_cents', v_quota.price_override_cents,
    'global_price_cents',   v_global,
    'unit_price_cents',     coalesce(v_quota.price_override_cents, v_global),
    'counting_since',       v_quota.counting_since,
    'notes',                v_quota.notes,
    'next_charge_date',     v_next,
    'current',              v_current,
    'last_30_days',         public.ecf_usage(p_business_id, now() - interval '30 days', now()),
    'history',              v_history
  );
end;
$$;

create or replace function public.admin_set_ecf_quota(
  p_business_id          uuid,
  p_included             integer,
  p_price_override_cents integer default null,
  p_notes                text    default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_before public.business_ecf_quota;
  v_after  public.business_ecf_quota;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_included is null or p_included < 0 then
    raise exception 'La cantidad incluida tiene que ser 0 o más' using errcode = '22023';
  end if;
  if p_price_override_cents is not null and p_price_override_cents < 0 then
    raise exception 'El precio no puede ser negativo' using errcode = '22023';
  end if;
  if not exists (select 1 from public.businesses where id = p_business_id) then
    raise exception 'Negocio no encontrado' using errcode = 'P0002';
  end if;

  select * into v_before from public.business_ecf_quota where business_id = p_business_id;

  -- counting_since solo se fija al crear: editar no reinicia la cuenta.
  insert into public.business_ecf_quota (
    business_id, included_per_period, price_override_cents, notes, updated_by
  )
  values (
    p_business_id, p_included, p_price_override_cents,
    nullif(btrim(coalesce(p_notes, '')), ''), auth.uid()
  )
  on conflict (business_id) do update
     set included_per_period  = excluded.included_per_period,
         price_override_cents = excluded.price_override_cents,
         notes                = excluded.notes,
         updated_at           = now(),
         updated_by           = auth.uid()
  returning * into v_after;

  insert into public.noc_audit_log (user_id, action, target_resource, target_id, business_id, payload)
  values (
    auth.uid(), 'ecf_quota.set', 'business_ecf_quota', p_business_id, p_business_id,
    jsonb_build_object(
      'before', case when v_before.business_id is null then null else to_jsonb(v_before) end,
      'after',  to_jsonb(v_after)
    )
  );

  return public.admin_get_ecf_usage(p_business_id);
end;
$$;

create or replace function public.admin_clear_ecf_quota(p_business_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_before public.business_ecf_quota;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  delete from public.business_ecf_quota
   where business_id = p_business_id
  returning * into v_before;

  if v_before.business_id is not null then
    insert into public.noc_audit_log (user_id, action, target_resource, target_id, business_id, payload)
    values (
      auth.uid(), 'ecf_quota.clear', 'business_ecf_quota', p_business_id, p_business_id,
      jsonb_build_object('before', to_jsonb(v_before))
    );
  end if;

  return public.admin_get_ecf_usage(p_business_id);
end;
$$;

create or replace function public.admin_set_ecf_overage_price(p_price_cents integer)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_before integer;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_price_cents is null or p_price_cents < 0 then
    raise exception 'El precio no puede ser negativo' using errcode = '22023';
  end if;

  select ecf_overage_price_cents into v_before from public.company_settings where id = 1;

  update public.company_settings
     set ecf_overage_price_cents = p_price_cents,
         updated_at              = now(),
         updated_by              = auth.uid()
   where id = 1;
  if not found then
    insert into public.company_settings (id, ecf_overage_price_cents, updated_by)
    values (1, p_price_cents, auth.uid());
  end if;

  insert into public.noc_audit_log (user_id, action, target_resource, target_id, business_id, payload)
  values (
    auth.uid(), 'ecf_overage_price.set', 'company_settings', null, null,
    jsonb_build_object('before_cents', v_before, 'after_cents', p_price_cents)
  );

  return p_price_cents;
end;
$$;

revoke all on function public.admin_get_ecf_usage(uuid) from public, anon;
revoke all on function public.admin_set_ecf_quota(uuid, integer, integer, text) from public, anon;
revoke all on function public.admin_clear_ecf_quota(uuid) from public, anon;
revoke all on function public.admin_set_ecf_overage_price(integer) from public, anon;
grant execute on function public.admin_get_ecf_usage(uuid) to authenticated;
grant execute on function public.admin_set_ecf_quota(uuid, integer, integer, text) to authenticated;
grant execute on function public.admin_clear_ecf_quota(uuid) to authenticated;
grant execute on function public.admin_set_ecf_overage_price(integer) to authenticated;

commit;

notify pgrst, 'reload schema';
