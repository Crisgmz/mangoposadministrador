-- ============================================================================
-- Migración 0039 — Gestión de suscripción/cobro automático (Azul) desde la
-- consola operadora.
--
-- El estado de suscripción del POS vive en `public.memberships` en la fila
-- marcada `is_billing_anchor = true` (una por negocio). El cron
-- `azul_charge_due` cobra automáticamente a las membresías con
-- `billing_status in ('active','past_due')`, `next_billing_date <= hoy`,
-- `plan_id` asignado, menos de 3 intentos y una tarjeta default `verified`
-- en `azul_payment_methods`.
--
-- RPCs:
--   1) admin_get_business_billing(p_business_id) → jsonb
--      Estado de facturación del ancla + plan + tarjeta default + último cobro.
--      Devuelve NULL si el negocio no tiene membresía ancla.
--
--   2) admin_update_subscription_billing(...) → jsonb
--      Actualiza estado/fechas del ancla. Si el negocio no tiene ancla,
--      promueve su membresía más reciente (preferencia: owner). Permite:
--        - cambiar billing_status (trial/active/past_due/suspended/cancelled)
--        - quitar el trial (p_clear_trial) o mover trial_ends_at
--        - asignar/cambiar next_billing_date y el período vigente
--        - resetear el contador de intentos de cobro
--      Al pasar a 'active' limpia suspended_at/cancelled_at y resetea
--      intentos; también rellena plan_id desde plan_type si faltaba, para
--      que el cobro automático quede elegible.
--
-- Ambas requieren `is_platform_operator()`; la de escritura registra la
-- intervención en `noc_audit_log` con razón obligatoria.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) admin_get_business_billing
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_business_billing(
  p_business_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'membership_id',          m.id,
    'business_id',            m.business_id,
    'billing_status',         m.billing_status,
    'plan_code',              p.code,
    'plan_name',              p.name,
    'price_cents_monthly',    p.price_cents_monthly,
    'currency_code',          p.currency_code,
    'trial_ends_at',          m.trial_ends_at,
    'current_period_start',   m.current_period_start,
    'current_period_end',     m.current_period_end,
    'next_billing_date',      m.next_billing_date,
    'current_attempt_number', m.current_attempt_number,
    'consent_granted_at',     m.consent_granted_at,
    'suspended_at',           m.suspended_at,
    'cancelled_at',           m.cancelled_at,
    'cancellation_reason',    m.cancellation_reason,
    'card', (
      select jsonb_build_object(
        'brand',      pm.data_vault_brand,
        'masked',     pm.card_number_masked,
        'status',     pm.status,
        'expiration', pm.data_vault_expiration
      )
      from public.azul_payment_methods pm
      where pm.business_id = m.business_id
        and pm.is_default = true
      limit 1
    ),
    'last_charge', (
      select jsonb_build_object(
        'status',           c.status,
        'amount_cents',     c.amount_cents,
        'attempted_at',     c.attempted_at,
        'response_message', c.response_message
      )
      from public.azul_charges c
      where c.membership_id = m.id
      order by c.attempted_at desc nulls last
      limit 1
    )
  )
  into v_result
  from public.memberships m
  left join public.plans p on p.id = m.plan_id
  where m.business_id = p_business_id
    and m.is_billing_anchor = true
  limit 1;

  return v_result;
end;
$$;

comment on function public.admin_get_business_billing(uuid) is
  'Estado de suscripción/cobro automático (Azul) del negocio: membresía ancla + plan + tarjeta default + último cobro. Solo operadores.';

grant execute on function public.admin_get_business_billing(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) admin_update_subscription_billing
-- ---------------------------------------------------------------------------
create or replace function public.admin_update_subscription_billing(
  p_business_id          uuid,
  p_reason               text,
  p_billing_status       text        default null,
  p_trial_ends_at        timestamptz default null,
  p_clear_trial          boolean     default false,
  p_next_billing_date    date        default null,
  p_current_period_start date        default null,
  p_current_period_end   date        default null,
  p_reset_attempts       boolean     default false
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_membership public.memberships;
  v_before     public.memberships;
  v_reason     text := trim(coalesce(p_reason, ''));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria' using errcode = '22023';
  end if;

  if p_billing_status is not null
     and p_billing_status not in ('trial', 'active', 'past_due', 'suspended', 'cancelled') then
    raise exception 'Estado de facturación inválido: %', p_billing_status
      using errcode = '22023';
  end if;

  -- Membresía ancla; si no existe, promovemos la más reciente (owner primero).
  select * into v_membership
    from public.memberships
   where business_id = p_business_id
     and is_billing_anchor = true
   limit 1;

  if v_membership.id is null then
    select * into v_membership
      from public.memberships
     where business_id = p_business_id
     order by (role = 'owner') desc, created_at desc
     limit 1;

    if v_membership.id is null then
      raise exception 'El negocio no tiene membresía. Crea una con "Editar membresía" primero.'
        using errcode = 'P0001';
    end if;

    update public.memberships
       set is_billing_anchor = true
     where id = v_membership.id;
  end if;

  v_before := v_membership;

  update public.memberships m
     set billing_status       = coalesce(p_billing_status, m.billing_status),
         trial_ends_at        = case
                                  when p_clear_trial then null
                                  else coalesce(p_trial_ends_at, m.trial_ends_at)
                                end,
         next_billing_date    = coalesce(p_next_billing_date, m.next_billing_date),
         current_period_start = coalesce(p_current_period_start, m.current_period_start),
         current_period_end   = coalesce(p_current_period_end, m.current_period_end),
         current_attempt_number = case
                                    when p_reset_attempts or p_billing_status = 'active' then 0
                                    else m.current_attempt_number
                                  end,
         suspended_at         = case
                                  when p_billing_status = 'suspended' then coalesce(m.suspended_at, now())
                                  when p_billing_status in ('active', 'trial') then null
                                  else m.suspended_at
                                end,
         cancelled_at         = case
                                  when p_billing_status = 'cancelled' then coalesce(m.cancelled_at, now())
                                  when p_billing_status in ('active', 'trial') then null
                                  else m.cancelled_at
                                end,
         cancellation_reason  = case
                                  when p_billing_status = 'cancelled' then v_reason
                                  when p_billing_status in ('active', 'trial') then null
                                  else m.cancellation_reason
                                end,
         -- Backfill: membresías legacy solo tienen plan_type; sin plan_id el
         -- cron de cobro automático las ignora.
         plan_id              = coalesce(
                                  m.plan_id,
                                  (select pl.id from public.plans pl where pl.code = m.plan_type)
                                )
   where m.id = v_membership.id
  returning * into v_membership;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'subscription.billing_update',
    'memberships',
    v_membership.id,
    p_business_id,
    jsonb_build_object(
      'reason', v_reason,
      'before', jsonb_build_object(
        'billing_status',         v_before.billing_status,
        'trial_ends_at',          v_before.trial_ends_at,
        'next_billing_date',      v_before.next_billing_date,
        'current_period_start',   v_before.current_period_start,
        'current_period_end',     v_before.current_period_end,
        'current_attempt_number', v_before.current_attempt_number
      ),
      'after', jsonb_build_object(
        'billing_status',         v_membership.billing_status,
        'trial_ends_at',          v_membership.trial_ends_at,
        'next_billing_date',      v_membership.next_billing_date,
        'current_period_start',   v_membership.current_period_start,
        'current_period_end',     v_membership.current_period_end,
        'current_attempt_number', v_membership.current_attempt_number
      )
    )
  );

  return public.admin_get_business_billing(p_business_id);
end;
$$;

comment on function public.admin_update_subscription_billing(uuid, text, text, timestamptz, boolean, date, date, date, boolean) is
  'Actualiza estado y fechas de la suscripción (membresía ancla) de un negocio: quitar trial, activar producción/cobro automático, mover fechas de facturación, resetear intentos. Solo operadores; audita en noc_audit_log.';

grant execute on function public.admin_update_subscription_billing(uuid, text, text, timestamptz, boolean, date, date, date, boolean) to authenticated;
