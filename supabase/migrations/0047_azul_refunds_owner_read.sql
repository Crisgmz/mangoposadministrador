-- ============================================================================
-- Migración 0047 — El dueño ve los reembolsos de su suscripción.
--
-- 0046 dejó azul_refunds cerrada (solo service_role): tiene la razón interna
-- del operador y la respuesta cruda de Azul. Pero al cliente hay que decirle
-- que se le devolvió dinero: si no, ve "Aprobado RD$4,799.99" en su historial
-- y no sabe que le reembolsaron la diferencia.
--
-- En vez de abrir la tabla (como azul_charges, que expone raw_request a quien
-- tenga acceso al negocio), una RPC que devuelve SOLO lo que el cliente
-- necesita:
--   * solo reembolsos `approved` (pendientes/rechazados no le dicen nada útil
--     y lo confundirían: "¿me devolvieron o no?");
--   * monto, moneda, cobro al que aplica y fecha;
--   * NUNCA la razón, quién lo hizo ni datos de Azul.
--
--   fn_business_subscription_refunds(business) → setof
--
-- La consumen mango_dashboard (pantalla Suscripción) y, cuando se agregue, el
-- POS (Mi suscripción). Acceso: user_has_business_access (misma regla que la
-- política de azul_charges). DEPENDE de 0046. Idempotente.
-- ============================================================================

begin;

do $$
begin
  if to_regclass('public.azul_refunds') is null then
    raise exception 'Falta azul_refunds (migración 0046). Aplicarla antes que 0047.';
  end if;
end $$;

create or replace function public.fn_business_subscription_refunds(p_business_id uuid)
returns table (
  id            uuid,
  charge_id     uuid,
  amount_cents  integer,
  currency_code text,
  refunded_at   timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id,
         r.charge_id,
         r.amount_cents,
         r.currency_code,
         coalesce(r.completed_at, r.requested_at) as refunded_at
    from public.azul_refunds r
   where r.business_id = p_business_id
     and r.status = 'approved'
     and public.user_has_business_access(auth.uid(), p_business_id)
   order by coalesce(r.completed_at, r.requested_at) desc;
$$;

comment on function public.fn_business_subscription_refunds(uuid) is
  'Reembolsos aprobados de la suscripción del negocio (monto, cobro, fecha) para '
  'la app del dueño. Sin razón ni datos de Azul. Requiere acceso al negocio.';

revoke all on function public.fn_business_subscription_refunds(uuid) from public, anon;
grant execute on function public.fn_business_subscription_refunds(uuid) to authenticated;

commit;
