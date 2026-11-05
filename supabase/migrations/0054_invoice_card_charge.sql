-- ============================================================================
-- Migración 0054 — Cobrar facturas a la tarjeta desde la consola.
--
-- QUÉ
-- El operador elige facturas pendientes de UN negocio y las cobra en UN solo
-- cargo a la tarjeta principal (token DataVault), con el precio que eligió en
-- cada una. Lo hace la Edge Function admin-azul-charge-invoices:
--   1. fn_invoice_charge_reserve: valida, calcula el total y crea el cobro en
--      `pending` (source = 'invoices'). Si algo no cuadra, nada llega a Azul.
--   2. Venta (Sale) con el token, igual que el cobro mensual.
--   3. fn_invoice_charge_finalize: con la venta aprobada, EN UNA TRANSACCIÓN,
--      aplica los precios, marca las facturas pagadas (método card, referencia
--      Azul #), las vincula al cobro y corre el próximo cobro automático si
--      alguna lo cubre (fn_apply_invoice_payments, 0044). Rechazada o no
--      procesada: las facturas no se tocan.
--   Respuesta ambigua o caída de la llamada: el cobro queda `pending` y
--   bloquea otro cobro de facturas del negocio hasta verificarlo con
--   VerifyPayment (acción verify). Nunca se vuelve a cobrar a ciegas.
--
-- CAMBIOS DE ESQUEMA
--   · azul_charges.source ('subscription' | 'invoices'), invoice_totals,
--     requested_by, request_key (idempotencia del pedido de la consola).
--   · El candado (membresía, período, intento) del cobro mensual pasa a ser
--     solo de source = 'subscription': un cobro de facturas atrasadas cubre
--     períodos que el cron ya intentó (y declinó) y chocaría con esos intentos.
--     El cron sigue igual: inserta con source por defecto y choca como antes.
--   · Un cobro puede pagar VARIAS facturas: el índice único de
--     membership_invoices.azul_charge_id (0049) pasa a ser normal.
--     admin_list_payments junta las facturas de un cobro en una sola fila
--     (si no, el mismo dinero salía una vez por factura).
--   · La conciliación automática (trigger de 0049) no toca los cobros de
--     facturas: ya quedan conciliados al aprobarse.
--   · Pagar a mano una factura que se está cobrando a la tarjeta (cobro
--     `pending`) la omite con motivo card_charge_pending
--     (fn_apply_invoice_payments).
--
-- El cobro de facturas NO cuenta como intento del cobro mensual (no toca
-- current_attempt_number ni suspende): si se rechaza, solo se informa.
--
-- DEPENDE de 0044, 0049, 0053 y de mangospos 20260526_0002 / 20260917_0004.
-- Idempotente.
-- ============================================================================

begin;

do $$
begin
  if to_regprocedure('public.fn_set_invoice_total(uuid,numeric)') is null then
    raise exception 'Falta 0053 (fn_set_invoice_total). Aplicarla antes que 0054.';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'azul_charges'
       and column_name = 'custom_order_id'
  ) then
    raise exception 'Falta azul_charges.custom_order_id (mangospos 20260917_0004).';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1) Esquema
-- ---------------------------------------------------------------------------
alter table public.azul_charges
  add column if not exists source         text not null default 'subscription',
  add column if not exists invoice_totals jsonb,
  add column if not exists requested_by   uuid references auth.users(id),
  add column if not exists request_key    uuid;

alter table public.azul_charges
  drop constraint if exists azul_charges_source_check,
  add constraint azul_charges_source_check
    check (source in ('subscription', 'invoices')),
  drop constraint if exists azul_charges_invoice_totals_check,
  add constraint azul_charges_invoice_totals_check
    check (source <> 'invoices' or jsonb_typeof(invoice_totals) = 'object');

comment on column public.azul_charges.source is
  'subscription = mensualidad (cron / Pagar sistema). invoices = facturas cobradas desde la consola (0054).';
comment on column public.azul_charges.invoice_totals is
  'Cobro de facturas: {"<invoice_id>": total cobrado}. La suma es amount_cents.';

create unique index if not exists azul_charges_request_key
  on public.azul_charges (request_key)
  where request_key is not null;

-- El candado del cobro mensual, solo para el cobro mensual.
drop index if exists public.azul_charges_one_per_period_per_attempt;
create unique index azul_charges_one_per_period_per_attempt
  on public.azul_charges (membership_id, billing_period_start, attempt_number)
  where source = 'subscription';

-- Un cobro de facturas paga varias facturas.
drop index if exists public.membership_invoices_azul_charge_key;
create index if not exists membership_invoices_azul_charge_idx
  on public.membership_invoices (azul_charge_id)
  where azul_charge_id is not null;

-- ---------------------------------------------------------------------------
-- 2) La conciliación automática no toca los cobros de facturas
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
  -- Cobro de facturas desde la consola: fn_invoice_charge_finalize ya pagó y
  -- vinculó sus facturas en la misma transacción.
  if new.source = 'invoices' then
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

-- ---------------------------------------------------------------------------
-- 2b) Pago manual: no pagar una factura que se está cobrando a la tarjeta
-- ---------------------------------------------------------------------------
-- Misma función de 0044 con una omisión más ('card_charge_pending').
create or replace function public.fn_apply_invoice_payments(
  p_invoice_ids uuid[],
  p_method      text,
  p_reference   text,
  p_paid_at     timestamptz
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_inv      record;
  v_anchor   public.memberships;
  v_new_next date;
  v_paid     jsonb := '[]'::jsonb;
  v_skipped  jsonb := '[]'::jsonb;
  v_moved    jsonb := '[]'::jsonb;
begin
  select coalesce(
           jsonb_agg(jsonb_build_object('invoice_id', x.id, 'reason', 'not_found')),
           '[]'::jsonb
         )
    into v_skipped
    from unnest(p_invoice_ids) as x(id)
   where not exists (
     select 1 from public.membership_invoices mi where mi.id = x.id
   );

  -- Por negocio y período: si se pagan octubre y noviembre juntos, el próximo
  -- cobro avanza dos veces y en el orden correcto.
  for v_inv in
    select mi.*, b.business_name
      from public.membership_invoices mi
      join public.businesses b on b.id = mi.business_id
     where mi.id = any(p_invoice_ids)
     order by mi.business_id, mi.period_start
       for update of mi
  loop
    if v_inv.status not in ('pending', 'expired') then
      v_skipped := v_skipped || jsonb_build_object(
        'invoice_id',     v_inv.id,
        'invoice_number', v_inv.invoice_number,
        'business_name',  v_inv.business_name,
        'reason',         v_inv.status
      );
      continue;
    end if;

    -- Se está cobrando a la tarjeta desde la consola (0054): marcarla a mano
    -- ahora la dejaría pagada dos veces si Azul aprueba.
    if exists (
      select 1 from public.azul_charges c
       where c.source = 'invoices'
         and c.status = 'pending'
         and c.invoice_totals ? v_inv.id::text
    ) then
      v_skipped := v_skipped || jsonb_build_object(
        'invoice_id',     v_inv.id,
        'invoice_number', v_inv.invoice_number,
        'business_name',  v_inv.business_name,
        'reason',         'card_charge_pending'
      );
      continue;
    end if;

    update public.membership_invoices
       set status            = 'paid',
           paid_at           = p_paid_at,
           paid_by           = auth.uid(),
           payment_method    = p_method,
           payment_reference = coalesce(p_reference, payment_reference)
     where id = v_inv.id;

    v_paid := v_paid || jsonb_build_object(
      'invoice_id',     v_inv.id,
      'invoice_number', v_inv.invoice_number,
      'business_id',    v_inv.business_id,
      'business_name',  v_inv.business_name,
      'total',          v_inv.total
    );

    insert into public.noc_audit_log (
      user_id, action, target_resource, target_id, business_id, payload
    )
    values (
      auth.uid(), 'invoice.paid', 'membership_invoices', v_inv.id, v_inv.business_id,
      jsonb_build_object(
        'invoice_number', v_inv.invoice_number,
        'total',          v_inv.total,
        'method',         p_method,
        'reference',      p_reference,
        'paid_at',        p_paid_at
      )
    );

    -- ¿Esta factura cubre la fecha en que la tarjeta iba a cobrar?
    select * into v_anchor
      from public.memberships
     where business_id = v_inv.business_id
       and is_billing_anchor = true
     limit 1
       for update;

    if v_anchor.id is not null
       and v_anchor.billing_status in ('active', 'past_due')
       and v_anchor.next_billing_date is not null
       and v_anchor.next_billing_date between v_inv.period_start and v_inv.period_end
    then
      v_new_next := v_inv.period_end + 1;

      update public.memberships
         set next_billing_date      = v_new_next,
             current_period_start   = v_inv.period_start,
             current_period_end     = v_new_next,
             current_attempt_number = 0,
             billing_status         = 'active'
       where id = v_anchor.id;

      v_moved := v_moved || jsonb_build_object(
        'business_id',    v_inv.business_id,
        'business_name',  v_inv.business_name,
        'invoice_number', v_inv.invoice_number,
        'from',           v_anchor.next_billing_date,
        'to',             v_new_next,
        'was_past_due',   v_anchor.billing_status = 'past_due'
      );

      insert into public.noc_audit_log (
        user_id, action, target_resource, target_id, business_id, payload
      )
      values (
        auth.uid(), 'subscription.next_charge_moved', 'memberships', v_anchor.id, v_inv.business_id,
        jsonb_build_object(
          'reason',     format('Factura %s pagada (%s)', v_inv.invoice_number, p_method),
          'invoice_id', v_inv.id,
          'before', jsonb_build_object(
            'next_billing_date',      v_anchor.next_billing_date,
            'billing_status',         v_anchor.billing_status,
            'current_attempt_number', v_anchor.current_attempt_number
          ),
          'after', jsonb_build_object(
            'next_billing_date',      v_new_next,
            'billing_status',         'active',
            'current_attempt_number', 0
          )
        )
      );
    end if;
  end loop;

  return jsonb_build_object('paid', v_paid, 'skipped', v_skipped, 'moved', v_moved);
end;
$$;

revoke all on function public.fn_apply_invoice_payments(uuid[], text, text, timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Reservar el cobro
-- ---------------------------------------------------------------------------
-- Solo service_role (la Edge Function valida antes que el usuario es operador
-- y pasa su id). Devuelve lo que la función necesita para hablar con Azul.
create or replace function public.fn_invoice_charge_reserve(
  p_operator_id uuid,
  p_request_key uuid,
  p_invoice_ids uuid[],
  p_totals      jsonb default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_existing    public.azul_charges;
  v_business    uuid;
  v_count       integer;
  v_businesses  integer;
  v_totals      jsonb := '{}'::jsonb;
  v_sum         numeric := 0;
  v_cents       integer;
  v_inv         record;
  v_key         text;
  v_value       jsonb;
  v_pm          public.azul_payment_methods;
  v_membership  uuid;
  v_start       date;
  v_end         date;
  v_id          uuid := gen_random_uuid();
  v_hex         text;
  v_charge      public.azul_charges;
begin
  if p_operator_id is null or p_request_key is null then
    raise exception 'Faltan el operador o la llave del pedido.' using errcode = '22023';
  end if;
  if p_invoice_ids is null or cardinality(p_invoice_ids) = 0 then
    raise exception 'No hay facturas seleccionadas.' using errcode = '22023';
  end if;
  if cardinality(p_invoice_ids) > 60 then
    raise exception 'Máximo 60 facturas por cobro.' using errcode = '22023';
  end if;

  -- El mismo pedido repetido (doble clic, reintento de red): el mismo cobro.
  select * into v_existing from public.azul_charges where request_key = p_request_key;
  if v_existing.id is not null then
    return jsonb_build_object(
      'existing',          true,
      'charge_id',         v_existing.id,
      'status',            v_existing.status,
      'amount_cents',      v_existing.amount_cents,
      'order_number',      v_existing.order_number,
      'custom_order_id',   v_existing.custom_order_id,
      'payment_method_id', v_existing.payment_method_id,
      'business_id',       v_existing.business_id
    );
  end if;

  -- Todas del mismo negocio (una tarjeta, un cargo).
  select count(*), min(business_id::text)::uuid, count(distinct business_id)
    into v_count, v_business, v_businesses
    from public.membership_invoices
   where id = any(p_invoice_ids);
  if v_count <> cardinality(p_invoice_ids) then
    raise exception 'Alguna de las facturas no existe.' using errcode = 'P0002';
  end if;
  if v_businesses > 1 then
    raise exception 'Un cobro a la tarjeta es de un solo negocio: elige facturas del mismo negocio.'
      using errcode = '22023';
  end if;

  -- Un cobro de facturas a la vez por negocio.
  if exists (
    select 1 from public.azul_charges c
     where c.business_id = v_business and c.source = 'invoices' and c.status = 'pending'
  ) then
    raise exception 'Hay un cobro a la tarjeta de este negocio sin confirmar. Verifícalo antes de cobrar otro.'
      using errcode = '55P03';
  end if;

  -- Precios: validados como en admin_mark_invoices_paid (0053).
  if p_totals is not null then
    if jsonb_typeof(p_totals) <> 'object' then
      raise exception 'p_totals debe ser un objeto {factura: total}' using errcode = '22023';
    end if;
    for v_key, v_value in select key, value from jsonb_each(p_totals) loop
      if not (v_key::uuid = any(p_invoice_ids)) then
        raise exception 'El precio de % es de una factura que no se está cobrando', v_key
          using errcode = '22023';
      end if;
      if jsonb_typeof(v_value) <> 'number' or (v_value #>> '{}')::numeric < 0 then
        raise exception 'Precio inválido para %: %', v_key, v_value using errcode = '22023';
      end if;
    end loop;
  end if;

  -- Bloqueadas mientras se arma el cobro: nadie las paga a la vez.
  for v_inv in
    select mi.*
      from public.membership_invoices mi
     where mi.id = any(p_invoice_ids)
     order by mi.period_start
       for update
  loop
    if v_inv.status not in ('pending', 'expired') then
      raise exception 'La factura % está %: solo se cobran pendientes o vencidas.',
        v_inv.invoice_number, v_inv.status using errcode = '22023';
    end if;
    v_value := coalesce(p_totals -> v_inv.id::text, to_jsonb(v_inv.total));
    v_totals := v_totals || jsonb_build_object(v_inv.id::text, round((v_value #>> '{}')::numeric, 2));
    v_sum   := v_sum + round((v_value #>> '{}')::numeric, 2);
    v_start := least(coalesce(v_start, v_inv.period_start), v_inv.period_start);
    v_end   := greatest(coalesce(v_end, v_inv.period_end), v_inv.period_end);
  end loop;

  v_cents := round(v_sum * 100)::int;
  if v_cents <= 0 then
    raise exception 'El total es RD$0: no hay nada que cobrar. Regístralas como pagadas.'
      using errcode = '22023';
  end if;

  -- Tarjeta principal verificada y vigente.
  select * into v_pm
    from public.azul_payment_methods
   where business_id = v_business and is_default = true
   limit 1;
  if v_pm.id is null then
    raise exception 'El negocio no tiene tarjeta principal.' using errcode = '22023';
  end if;
  if v_pm.status <> 'verified' or v_pm.revoked_at is not null then
    raise exception 'La tarjeta principal no está verificada (%).', v_pm.status using errcode = '22023';
  end if;
  if v_pm.data_vault_expiration < to_char(now() at time zone 'America/Santo_Domingo', 'YYYYMM') then
    raise exception 'La tarjeta principal está vencida.' using errcode = '22023';
  end if;

  -- azul_charges exige una membresía: la ancla de facturación o, si no hay,
  -- la más reciente del negocio.
  select m.id into v_membership
    from public.memberships m
   where m.business_id = v_business
   order by m.is_billing_anchor desc nulls last, m.created_at desc
   limit 1;
  if v_membership is null then
    raise exception 'El negocio no tiene membresía.' using errcode = '22023';
  end if;

  v_hex := replace(v_id::text, '-', '');
  insert into public.azul_charges (
    id, business_id, membership_id, payment_method_id,
    order_number, custom_order_id,
    billing_period_start, billing_period_end, attempt_number,
    amount_cents, itbis_cents, currency_code,
    status, attempted_at,
    source, invoice_totals, requested_by, request_key
  ) values (
    v_id, v_business, v_membership, v_pm.id,
    -- ≤15 alfanumérico (Azul).
    'FA' || upper(substr(v_hex, 1, 13)),
    'mpfa-' || v_hex,
    v_start, v_end, 1,
    v_cents, 0, 'DOP',
    'pending', now(),
    'invoices', v_totals, p_operator_id, p_request_key
  )
  returning * into v_charge;

  insert into public.noc_audit_log (user_id, action, target_resource, target_id, business_id, payload)
  values (
    p_operator_id, 'invoice.card_charge_requested', 'azul_charges', v_charge.id, v_business,
    jsonb_build_object(
      'amount_cents',  v_cents,
      'invoice_totals', v_totals,
      'order_number',  v_charge.order_number,
      'card',          concat_ws(' ', v_pm.data_vault_brand, v_pm.card_number_masked))
  );

  return jsonb_build_object(
    'existing',          false,
    'charge_id',         v_charge.id,
    'status',            v_charge.status,
    'amount_cents',      v_charge.amount_cents,
    'order_number',      v_charge.order_number,
    'custom_order_id',   v_charge.custom_order_id,
    'payment_method_id', v_charge.payment_method_id,
    'business_id',       v_business
  );
end;
$$;

revoke all on function public.fn_invoice_charge_reserve(uuid, uuid, uuid[], jsonb)
  from public, anon, authenticated;
grant execute on function public.fn_invoice_charge_reserve(uuid, uuid, uuid[], jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 4) Cerrar el cobro con lo que respondió Azul
-- ---------------------------------------------------------------------------
-- p_outcome: approved | declined | error. Un cobro que ya no está `pending` no
-- se vuelve a cerrar (idempotente: devuelve cómo quedó).
create or replace function public.fn_invoice_charge_finalize(
  p_charge_id   uuid,
  p_outcome     text,
  p_azul        jsonb,
  p_operator_id uuid
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_charge  public.azul_charges;
  v_ids     uuid[];
  v_result  jsonb := jsonb_build_object('paid', '[]'::jsonb, 'skipped', '[]'::jsonb, 'moved', '[]'::jsonb);
  v_paid    uuid[];
  v_ref     text;
begin
  if p_outcome not in ('approved', 'declined', 'error') then
    raise exception 'Resultado inválido: %', p_outcome using errcode = '22023';
  end if;

  select * into v_charge from public.azul_charges where id = p_charge_id for update;
  if v_charge.id is null or v_charge.source <> 'invoices' then
    raise exception 'Cobro de facturas % no encontrado', p_charge_id using errcode = 'P0002';
  end if;
  if v_charge.status <> 'pending' then
    return jsonb_build_object('status', v_charge.status, 'already_final', true, 'charge_id', v_charge.id);
  end if;

  select array_agg(key::uuid) into v_ids from jsonb_object_keys(v_charge.invoice_totals) key;

  -- El cobro sale de `pending` ANTES de pagar las facturas: mientras está
  -- pending, fn_apply_invoice_payments las omite (nadie las paga a mano a la
  -- vez). Todo en esta transacción: si algo falla, sigue pending.
  update public.azul_charges
     set status             = p_outcome,
         authorization_code = p_azul->>'AuthorizationCode',
         response_code      = p_azul->>'ResponseCode',
         iso_code           = p_azul->>'IsoCode',
         response_message   = p_azul->>'ResponseMessage',
         error_description  = p_azul->>'ErrorDescription',
         rrn                = p_azul->>'RRN',
         azul_order_id      = p_azul->>'AzulOrderId',
         raw_response       = p_azul,
         completed_at       = now()
   where id = v_charge.id;

  if p_outcome = 'approved' then
    v_ref := 'Azul #' || coalesce(nullif(p_azul->>'AzulOrderId', ''), v_charge.order_number);
    -- El precio cobrado queda en cada factura (Pagos lo lee de ahí).
    perform public.fn_apply_invoice_totals(v_ids, v_charge.invoice_totals);
    v_result := public.fn_apply_invoice_payments(v_ids, 'card', v_ref, now());
    select array_agg((p->>'invoice_id')::uuid) into v_paid
      from jsonb_array_elements(v_result->'paid') p;
    update public.membership_invoices
       set azul_charge_id = v_charge.id,
           paid_by        = p_operator_id
     where id = any(coalesce(v_paid, '{}'::uuid[]));
  end if;

  insert into public.noc_audit_log (user_id, action, target_resource, target_id, business_id, payload)
  values (
    p_operator_id, 'invoice.card_charge_' || p_outcome, 'azul_charges', v_charge.id, v_charge.business_id,
    jsonb_build_object(
      'amount_cents',  v_charge.amount_cents,
      'order_number',  v_charge.order_number,
      'azul_order_id', p_azul->>'AzulOrderId',
      'iso_code',      p_azul->>'IsoCode',
      'message',       p_azul->>'ResponseMessage',
      'paid',          v_result->'paid',
      'skipped',       v_result->'skipped')
  );

  return v_result || jsonb_build_object('status', p_outcome, 'charge_id', v_charge.id,
    'amount_cents', v_charge.amount_cents);
end;
$$;

revoke all on function public.fn_invoice_charge_finalize(uuid, text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.fn_invoice_charge_finalize(uuid, text, jsonb, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 5) Pagos: un cobro que pagó varias facturas sale UNA vez
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
    -- Cobros con tarjeta aprobados, con la(s) factura(s) que pagaron.
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
           inv.invoice_id,
           inv.invoice_number,
           inv.invoice_status,
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
      left join lateral (
        select (array_agg(mi.id order by mi.period_start))[1]           as invoice_id,
               string_agg(mi.invoice_number, ', ' order by mi.period_start) as invoice_number,
               min(mi.status)                                            as invoice_status
          from public.membership_invoices mi
         where mi.azul_charge_id = c.id
      ) inv on true
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
  'Todos los pagos: cobros con tarjeta aprobados (uno por cobro, con sus facturas) y facturas pagadas a mano. Solo operadores (0049, 0054).';

revoke all on function public.admin_list_payments(int) from public, anon;
grant execute on function public.admin_list_payments(int) to authenticated;

commit;

notify pgrst, 'reload schema';
