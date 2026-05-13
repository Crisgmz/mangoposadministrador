-- ============================================================================
-- Migración 0013 — Desglose de pagos por método dentro de una sesión de caja
--
-- Hoy el detalle de caja muestra solo `ventas_efectivo` (movimientos de
-- cash_transactions). Las ventas con tarjeta y transferencia entran a
-- `payments` con un `payment_method_id` pero no aparecen en la salud
-- de caja, lo que es engañoso para el operador (parece que el negocio
-- no vendió con tarjeta).
--
-- Esta RPC devuelve un desglose por método: cuántas transacciones de
-- ese método, suma total, % del total. Útil para que el operador valide
-- que el cierre cuadra contra la facturación real.
--
-- NOTA: el saldo en efectivo de la caja sigue calculándose SOLO con
-- `cash_transactions`. Tarjeta y transferencia no afectan el saldo
-- físico, son informativos.
-- ============================================================================

create or replace function public.get_cash_session_payment_breakdown(
  p_session_id uuid
)
returns table (
  payment_method_id uuid,
  method_code       text,
  method_name       text,
  txn_count         int,
  total_amount      numeric,
  pct_of_total      numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_session_total numeric;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Total general de la sesión (pagos completados).
  select coalesce(sum(p.amount), 0)
    into v_session_total
    from public.payments p
   where p.session_id = p_session_id
     and p.status = 'completed';

  return query
  select
    p.payment_method_id,
    pm.code  as method_code,
    pm.name  as method_name,
    count(*)::int                                                       as txn_count,
    coalesce(sum(p.amount), 0)::numeric                                 as total_amount,
    case when v_session_total = 0 then 0::numeric
         else round((coalesce(sum(p.amount), 0) / v_session_total) * 100, 1)
    end                                                                  as pct_of_total
  from public.payments p
  left join public.payment_methods pm on pm.id = p.payment_method_id
  where p.session_id = p_session_id
    and p.status = 'completed'
  group by p.payment_method_id, pm.code, pm.name
  order by total_amount desc;
end;
$$;

grant execute on function public.get_cash_session_payment_breakdown(uuid) to authenticated;
