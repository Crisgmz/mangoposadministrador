-- ============================================================================
-- Migración 0052 — Las e-CF se cuentan hasta el momento de facturar.
--
-- QUÉ
-- 0051 contaba las e-CF de una factura hasta el INICIO del período que se
-- cobra. Si la factura se generaba antes de esa fecha ("Generar facturas del
-- mes" corre para todos el mismo día, y cada negocio tiene su fecha de corte),
-- las que la DGII aceptaba entre la generación y el inicio del período no
-- entraban en esa factura ni en la siguiente (la siguiente empieza donde
-- terminó esta). Se perdían.
--
-- Ahora la ventana termina en lo que llegue primero: el inicio del período o
-- el momento en que se factura. Lo que se acepte después va en la próxima
-- factura o cobro. Sin huecos ni solapes: cada e-CF se cobra una sola vez.
--
-- Decisión 2026-11-04: siguen cobrándose solo en los negocios con cantidad
-- incluida configurada (business_ecf_quota), y solo lo que pase de ella.
--
-- El cobro con tarjeta no cambia: el cron cobra el día del período o después,
-- y ahí el inicio del período ya llegó. La vista "período en curso" del
-- detalle (admin_get_ecf_usage) queda contada hasta ahora mismo.
--
-- Redefine subscription_ecf_overage (0051) con la misma firma. DEPENDE de
-- 0051. Idempotente.
-- ============================================================================

begin;

do $$
begin
  if to_regprocedure('public.subscription_ecf_overage(uuid,date)') is null then
    raise exception 'Falta 0051 (subscription_ecf_overage). Aplicarla antes que 0052.';
  end if;
end $$;

-- Excedente de e-CF que se factura con el período que empieza en
-- p_period_start (fecha local RD), contado hasta ese inicio o hasta ahora, lo
-- que llegue primero.
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
  -- Facturar antes del inicio del período no deja fuera lo que falta: eso
  -- entra en la próxima ventana, que empieza donde termina esta.
  v_to          timestamptz := least(
                                 p_period_start::timestamp at time zone 'America/Santo_Domingo',
                                 now()
                               );
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

comment on function public.subscription_ecf_overage(uuid, date) is
  'e-CF aceptadas por encima de lo incluido, desde lo último facturado hasta el inicio de p_period_start o hasta ahora, lo que llegue primero (0052).';

revoke all on function public.subscription_ecf_overage(uuid, date) from public, anon, authenticated;

commit;
