-- ============================================================================
-- Migración 0046 — Pagos de suscripción y reembolsos (consola).
--
-- La consola solo mostraba el ÚLTIMO cobro con tarjeta y los reembolsos se
-- hacían a mano en el portal de Azul, sin rastro en la base: un cobro
-- devuelto a medias seguía viéndose "Aprobado" por el monto completo. Caso
-- real: el 16/09 el cron cobró precio de lista a dos clientes con precio
-- especial (la función con precio efectivo aún no estaba desplegada) y hubo
-- que devolver la diferencia.
--
-- Esta migración deja todo lo de base de datos; el reembolso en sí lo hace la
-- Edge Function `admin-azul-refund` (supabase/functions de este repo), porque
-- tiene que hablar con Azul.
--
--   0) guard de dependencias
--   1) tabla azul_refunds
--   2) azul_charge_refundable_cents(charge)            → int   (service_role)
--   3) fn_azul_refund_reserve(charge, monto, razón, op) → fila (service_role)
--   4) admin_list_business_charges(business, límite)   → jsonb (operadores)
--
-- REGLAS (doc Azul E-Commerce WebServices v3.2, "Refund"):
--   * Se permiten reembolsos parciales y varios por cobro, mientras la suma no
--     supere el monto original, dentro de 6 meses.
--   * AzulOrderId + OriginalDate (yyyymmdd) de la venta son obligatorios.
--
-- ESTADOS de un reembolso — pensados para no devolver dinero dos veces:
--   pending   reservado; la llamada está en curso O su resultado es
--             desconocido (timeout, sidecar caído). CUENTA contra el saldo.
--             Se resuelve con VerifyPayment por custom_order_id.
--   approved  Azul aprobó (IsoCode 00). Cuenta.
--   declined  Azul lo procesó y lo rechazó. No movió dinero; no cuenta.
--   error     Azul NO lo procesó, o VerifyPayment confirmó que nunca llegó.
--
-- La reserva bloquea la fila del cobro (FOR UPDATE): dos operadores a la vez
-- no pueden devolver más de lo cobrado.
--
-- DEPENDE de mangospos: 20260526_0002 (azul_charges), 20260915_0006
-- (subscription_effective_price_cents) y de 0009 de este repo (noc_audit_log,
-- que usa la Edge Function). Idempotente.
--
-- ROLLBACK (borra el historial de reembolsos — exportarlo antes si hubo alguno):
--   drop function if exists public.admin_list_business_charges(uuid, int);
--   drop function if exists public.fn_azul_refund_reserve(uuid, integer, text, uuid);
--   drop function if exists public.azul_charge_refundable_cents(uuid);
--   drop table if exists public.azul_refunds;
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0) Guard
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.azul_charges') is null then
    raise exception 'Falta la tabla azul_charges (mangospos 20260526_0002).';
  end if;
  if to_regprocedure('public.subscription_effective_price_cents(uuid,date)') is null then
    raise exception
      'Falta mangospos 20260915_0006_subscription_price_override.sql. Aplicarla antes que 0046.';
  end if;
  if to_regclass('public.noc_audit_log') is null then
    raise exception 'Falta noc_audit_log (migración 0009 de este repo).';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1) Tabla
-- ---------------------------------------------------------------------------
create table if not exists public.azul_refunds (
  id uuid primary key default gen_random_uuid(),
  charge_id uuid not null references public.azul_charges(id) on delete restrict,
  business_id uuid not null references public.businesses(id) on delete restrict,

  amount_cents integer not null check (amount_cents > 0),
  itbis_cents integer not null default 0 check (itbis_cents >= 0),
  currency_code text not null default 'DOP' check (char_length(currency_code) = 3),
  reason text not null check (char_length(btrim(reason)) > 0),

  status text not null default 'pending'
    check (status in ('pending', 'approved', 'declined', 'error')),

  -- Lo que viaja a Azul.
  order_number text not null unique,
  custom_order_id text not null unique,
  original_azul_order_id text not null,
  original_date text not null check (original_date ~ '^\d{8}$'),

  -- Respuesta de Azul.
  azul_order_id text,
  authorization_code text,
  response_code text,
  iso_code text,
  response_message text,
  error_description text,
  rrn text,
  raw_request jsonb,
  raw_response jsonb,

  requested_by uuid not null references auth.users(id),
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  -- Cómo se resolvió un `pending` (VerifyPayment).
  resolution_note text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_azul_refunds_charge
  on public.azul_refunds(charge_id);
create index if not exists idx_azul_refunds_business
  on public.azul_refunds(business_id, requested_at desc);

comment on table public.azul_refunds is
  'Reembolsos (totales o parciales) de cobros de suscripción Azul, pedidos desde '
  'la consola. pending y approved cuentan contra el saldo reembolsable del cobro.';

create or replace function public.fn_azul_refunds_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_azul_refunds_updated_at on public.azul_refunds;
create trigger trg_azul_refunds_updated_at
  before update on public.azul_refunds
  for each row execute function public.fn_azul_refunds_touch_updated_at();

alter table public.azul_refunds enable row level security;
-- Sin políticas: solo service_role (la Edge Function) y las RPC security
-- definer. Guarda la respuesta cruda del procesador.
revoke all on public.azul_refunds from public, anon, authenticated;
grant select, insert, update on public.azul_refunds to service_role;

-- ---------------------------------------------------------------------------
-- 2) Saldo reembolsable (centavos): aprobado − reembolsos approved/pending.
--    0 si el cobro no es reembolsable (no aprobado, sin AzulOrderId, > 6 meses).
-- ---------------------------------------------------------------------------
create or replace function public.azul_charge_refundable_cents(p_charge_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
           when c.status <> 'approved'
             or coalesce(c.azul_order_id, '') = ''
             or coalesce(c.completed_at, c.attempted_at) < now() - interval '6 months'
           then 0
           else greatest(
             0,
             c.amount_cents - coalesce((
               select sum(r.amount_cents)
                 from public.azul_refunds r
                where r.charge_id = c.id
                  and r.status in ('pending', 'approved')
             ), 0)
           )::int
         end
    from public.azul_charges c
   where c.id = p_charge_id;
$$;

comment on function public.azul_charge_refundable_cents(uuid) is
  'Cuánto se puede reembolsar todavía de un cobro (centavos).';

-- ---------------------------------------------------------------------------
-- 3) Reserva atómica. La Edge Function la llama ANTES de hablar con Azul: si
--    el monto no cabe, nada llega a Azul.
-- ---------------------------------------------------------------------------
create or replace function public.fn_azul_refund_reserve(
  p_charge_id    uuid,
  p_amount_cents integer,
  p_reason       text,
  p_requested_by uuid
) returns public.azul_refunds
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_reason    text := btrim(coalesce(p_reason, ''));
  v_charge    public.azul_charges;
  v_reserved  integer;
  v_available integer;
  v_id        uuid := gen_random_uuid();
  v_hex       text := upper(replace(v_id::text, '-', ''));
  v_orig_date text;
  v_itbis     integer;
  v_refund    public.azul_refunds;
begin
  if p_requested_by is null then
    raise exception 'Falta el operador que pide el reembolso' using errcode = '22023';
  end if;
  if v_reason = '' then
    raise exception 'La razón es obligatoria' using errcode = '22023';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'El monto a reembolsar debe ser mayor que cero' using errcode = '22023';
  end if;

  -- Lock: serializa reembolsos concurrentes del mismo cobro.
  select * into v_charge
    from public.azul_charges
   where id = p_charge_id
   for update;

  if v_charge.id is null then
    raise exception 'Cobro no encontrado' using errcode = 'P0002';
  end if;
  if v_charge.status <> 'approved' then
    raise exception 'Solo se reembolsan cobros aprobados (este está "%")', v_charge.status
      using errcode = 'P0001';
  end if;
  if coalesce(v_charge.azul_order_id, '') = '' then
    raise exception 'El cobro no tiene AzulOrderId: reembolsarlo desde el portal de Azul'
      using errcode = 'P0001';
  end if;
  if coalesce(v_charge.completed_at, v_charge.attempted_at) < now() - interval '6 months' then
    raise exception 'Azul solo permite reembolsos dentro de los 6 meses del cobro'
      using errcode = 'P0001';
  end if;

  select coalesce(sum(amount_cents), 0)::int into v_reserved
    from public.azul_refunds
   where charge_id = v_charge.id
     and status in ('pending', 'approved');

  v_available := v_charge.amount_cents - v_reserved;
  if p_amount_cents > v_available then
    raise exception 'El monto excede lo reembolsable de este cobro (disponible RD$%)',
      to_char(greatest(v_available, 0) / 100.0, 'FM999,999,990.00')
      using errcode = '22023';
  end if;

  -- OriginalDate: el DateTime (YYYYMMDDHHMMSS) que Azul devolvió en el cobro;
  -- si no está, la fecha del cobro en hora RD.
  v_orig_date := case
    when v_charge.raw_response->>'DateTime' ~ '^\d{14}$'
      then left(v_charge.raw_response->>'DateTime', 8)
    else to_char(
      coalesce(v_charge.completed_at, v_charge.attempted_at) at time zone 'America/Santo_Domingo',
      'YYYYMMDD'
    )
  end;

  -- ITBIS proporcional al monto devuelto (hoy los cobros van con ITBIS 0).
  v_itbis := case
    when v_charge.itbis_cents > 0 and v_charge.amount_cents > 0
      then round(v_charge.itbis_cents::numeric * p_amount_cents / v_charge.amount_cents)::int
    else 0
  end;

  insert into public.azul_refunds (
    id, charge_id, business_id,
    amount_cents, itbis_cents, currency_code, reason,
    status,
    -- OrderNumber alfanumérico ≤15, como los cobros. CustomOrderId único:
    -- llave de VerifyPayment.
    order_number, custom_order_id,
    original_azul_order_id, original_date,
    requested_by
  )
  values (
    v_id, v_charge.id, v_charge.business_id,
    p_amount_cents, v_itbis, v_charge.currency_code, v_reason,
    'pending',
    'RF' || left(v_hex, 13), 'mprf-' || lower(v_hex),
    v_charge.azul_order_id, v_orig_date,
    p_requested_by
  )
  returning * into v_refund;

  return v_refund;
end;
$$;

comment on function public.fn_azul_refund_reserve(uuid, integer, text, uuid) is
  'Reserva un reembolso (pending) contra un cobro aprobado validando el saldo con '
  'la fila del cobro bloqueada. La llama admin-azul-refund antes de Azul.';

revoke all on function public.azul_charge_refundable_cents(uuid) from public, anon, authenticated;
revoke all on function public.fn_azul_refund_reserve(uuid, integer, text, uuid) from public, anon, authenticated;
grant execute on function public.azul_charge_refundable_cents(uuid) to service_role;
grant execute on function public.fn_azul_refund_reserve(uuid, integer, text, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 4) admin_list_business_charges
--
--    Cobros con tarjeta del negocio (más reciente primero) con lo reembolsado,
--    lo pendiente de confirmar, el saldo y cada reembolso. `current_price_cents`
--    = lo que costaría HOY ese período con la configuración actual (precio
--    especial incluido): marca de un vistazo un cobro por encima de lo
--    acordado. Si el precio especial se cargó DESPUÉS del cobro, la diferencia
--    no es un error de cobro.
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
  'Cobros de suscripción (Azul) de un negocio con reembolsos, saldo reembolsable y precio vigente del período. Solo operadores.';

revoke all on function public.admin_list_business_charges(uuid, int) from public, anon;
grant execute on function public.admin_list_business_charges(uuid, int) to authenticated;

commit;
