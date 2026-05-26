-- ---------------------------------------------------------------------------
-- 0031_invoice_period_from_membership.sql
--
-- Cambia `generate_membership_invoice` para que el `period_start` se
-- calcule a partir de `memberships.end_date` (la fecha en que se cumple
-- la membresía), no del primer día del mes calendario actual.
--
-- Antes:
--   period_start = primer día del mes actual
--   period_end   = último día del mes actual
--
-- Después:
--   period_start = membership.end_date (si está) o today
--   period_end   = period_start + 1 mes - 1 día
--   due_date     = period_start (la factura vence el día que arranca el
--                  período; cualquier prórroga la otorga el admin con
--                  grant_extension).
--
-- Ejemplo: si la membresía vence el 01/05/2026 y se factura ese día,
-- la factura cubre 01/05/2026 → 31/05/2026.
--
-- Mantiene idempotencia por (business_id, period_start): si re-llaman el
-- RPC con la misma membresía + end_date no cambia, devuelve la existente.
--
-- El cleanup de créditos `free_credit` (introducido en 0022) se preserva
-- intacto. Solo cambia el cómputo del período y el due_date.
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
  v_amount_gross    numeric;
  v_amount_net      numeric;
  v_itbis_rate      numeric := 0.18;
  v_itbis           numeric;
  v_invoice         public.membership_invoices;
  v_remaining       numeric;
  v_total_applied   numeric := 0;
  v_applied_ids     uuid[]  := '{}'::uuid[];
  v_credit          record;
  v_notes           text;
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

  v_amount_gross := public.plan_monthly_fee(v_membership.plan_type);
  if v_amount_gross = 0 then
    raise exception 'Plan % sin costo, no se genera factura', v_membership.plan_type
      using errcode = '22023';
  end if;

  -- Período arranca en la fecha de expiración de la membresía. Si end_date
  -- es null o ya pasó hace tiempo, usamos `today` como fallback razonable.
  v_period_start := coalesce(
    (v_membership.end_date at time zone 'America/Santo_Domingo')::date,
    (now() at time zone 'America/Santo_Domingo')::date
  );
  v_period_end := (v_period_start + interval '1 month' - interval '1 day')::date;
  v_due_date   := v_period_start::timestamptz;

  -- Idempotencia.
  select * into v_invoice
    from public.membership_invoices
   where business_id = p_business_id
     and period_start = v_period_start
   limit 1;
  if v_invoice.id is not null then
    return v_invoice;
  end if;

  -- Aplicar free_credit en orden FIFO (igual que 0022).
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
  v_itbis      := round(v_amount_net * v_itbis_rate, 2);

  if v_total_applied > 0 then
    v_notes := format(
      'Crédito aplicado: RD$%s sobre %s factura(s) original RD$%s.',
      v_total_applied,
      cardinality(v_applied_ids),
      v_amount_gross
    );
  end if;

  insert into public.membership_invoices (
    business_id, membership_id, plan_type,
    period_start, period_end, due_date,
    amount, itbis,
    status, paid_at, payment_method,
    notes
  )
  values (
    p_business_id, v_membership.id, v_membership.plan_type,
    v_period_start, v_period_end, v_due_date,
    v_amount_net,
    v_itbis,
    case when v_amount_net = 0 then 'paid' else 'pending' end,
    case when v_amount_net = 0 then now() else null end,
    case when v_amount_net = 0 then 'credit_applied' else null end,
    v_notes
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

comment on function public.generate_membership_invoice(uuid) is
  'Genera factura mensual usando membership.end_date como inicio de período. due_date = period_start.';

grant execute on function public.generate_membership_invoice(uuid) to authenticated;
