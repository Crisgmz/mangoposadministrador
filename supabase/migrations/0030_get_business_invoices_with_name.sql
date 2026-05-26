-- ---------------------------------------------------------------------------
-- 0030_get_business_invoices_with_name.sql
--
-- `get_business_invoices(business_id)` (definida en 0004) devolvía
-- `setof public.membership_invoices`, que no incluye `business_name`
-- porque vive en `businesses`. El modelo Dart cae a "—" y la factura PDF
-- aparece sin nombre del cliente.
--
-- Reemplazo con `returns table (...)` haciendo join a `businesses` para
-- entregar `business_name` y `environment`. Las columnas adicionales son
-- additivas: el modelo existente ya las parsea (`business_name`,
-- `environment`); solo que ahora llegan pobladas.
-- ---------------------------------------------------------------------------

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
  notes             text
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
    i.notes
  from public.membership_invoices i
  join public.businesses b on b.id = i.business_id
  where i.business_id = p_business_id
  order by i.issue_date desc;
end;
$$;

grant execute on function public.get_business_invoices(uuid) to authenticated;

notify pgrst, 'reload schema';
