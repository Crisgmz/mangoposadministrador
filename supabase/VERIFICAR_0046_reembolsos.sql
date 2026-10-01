-- =============================================================================
-- VERIFICAR 0046 (pagos de suscripción y reembolsos)
--
-- Correr DESPUÉS de aplicar supabase/migrations/0046_subscription_charges_refunds_admin.sql.
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja
-- reembolsos ni cambios. NO habla con Azul — prueba la reserva de saldo y la
-- RPC de la consola sobre un cobro real.
--
-- En Supabase Studio solo se ve el ÚLTIMO resultado: la fila `resultado`
-- ("OK — …" o "SIN DATOS — …"). Si algo falla, aparece un error "FALLA …".
-- =============================================================================

begin;

create temp table _verificar (resultado text);

do $$
declare
  v_charge   public.azul_charges;
  v_operator uuid;
  v_r1       public.azul_refunds;
  v_r2       public.azul_refunds;
  v_got      int;
  v_list     jsonb;
  v_row      jsonb;
begin
  -- Un cobro aprobado con AzulOrderId y sin reembolsos, de hace < 6 meses.
  select c.* into v_charge
    from public.azul_charges c
   where c.status = 'approved'
     and coalesce(c.azul_order_id, '') <> ''
     and c.amount_cents > 200
     and coalesce(c.completed_at, c.attempted_at) > now() - interval '6 months'
     and not exists (select 1 from public.azul_refunds r where r.charge_id = c.id)
   order by c.attempted_at desc
   limit 1;

  select po.user_id into v_operator from public.platform_operators po limit 1;

  if v_charge.id is null or v_operator is null then
    insert into _verificar values (
      'SIN DATOS — falta un cobro aprobado sin reembolsos o un operador; la prueba no corrió.'
    );
    return;
  end if;

  -- a) Sin reembolsos: todo el monto es reembolsable.
  v_got := public.azul_charge_refundable_cents(v_charge.id);
  if v_got <> v_charge.amount_cents then
    raise exception 'FALLA a) saldo inicial: esperado %, obtuvo %', v_charge.amount_cents, v_got;
  end if;

  -- b) Reserva parcial: queda pending con los datos que Azul exige.
  v_r1 := public.fn_azul_refund_reserve(v_charge.id, 100, 'VERIFICAR parcial', v_operator);
  if v_r1.status <> 'pending'
     or v_r1.original_azul_order_id <> v_charge.azul_order_id
     or v_r1.original_date !~ '^\d{8}$'
     or char_length(v_r1.order_number) > 15
     or v_r1.order_number !~ '^[A-Z0-9]+$' then
    raise exception 'FALLA b) reserva: status %, azul %, fecha %, order %',
      v_r1.status, v_r1.original_azul_order_id, v_r1.original_date, v_r1.order_number;
  end if;

  -- c) pending descuenta del saldo.
  v_got := public.azul_charge_refundable_cents(v_charge.id);
  if v_got <> v_charge.amount_cents - 100 then
    raise exception 'FALLA c) saldo con pending: esperado %, obtuvo %', v_charge.amount_cents - 100, v_got;
  end if;

  -- d) No se puede reservar más de lo disponible.
  begin
    perform public.fn_azul_refund_reserve(v_charge.id, v_charge.amount_cents - 99, 'VERIFICAR exceso', v_operator);
    raise exception 'FALLA d) aceptó un reembolso mayor al saldo';
  exception when sqlstate '22023' then
    null; -- esperado
  end;

  -- e) declined/error liberan el saldo; approved lo consume.
  update public.azul_refunds set status = 'declined' where id = v_r1.id;
  v_got := public.azul_charge_refundable_cents(v_charge.id);
  if v_got <> v_charge.amount_cents then
    raise exception 'FALLA e) declined no liberó: esperado %, obtuvo %', v_charge.amount_cents, v_got;
  end if;

  v_r2 := public.fn_azul_refund_reserve(v_charge.id, v_charge.amount_cents, 'VERIFICAR total', v_operator);
  update public.azul_refunds set status = 'approved' where id = v_r2.id;
  v_got := public.azul_charge_refundable_cents(v_charge.id);
  if v_got <> 0 then
    raise exception 'FALLA e) approved total: esperado 0, obtuvo %', v_got;
  end if;

  -- f) Razón obligatoria.
  begin
    perform public.fn_azul_refund_reserve(v_charge.id, 1, '   ', v_operator);
    raise exception 'FALLA f) aceptó razón vacía';
  exception when sqlstate '22023' then
    null;
  end;

  -- g) RPC de la consola, como operador (auth.uid() desde los claims).
  perform set_config('request.jwt.claims', json_build_object('sub', v_operator)::text, true);
  perform set_config('request.jwt.claim.sub', v_operator::text, true);
  v_list := public.admin_list_business_charges(v_charge.business_id, 120);
  select e into v_row
    from jsonb_array_elements(v_list) e
   where e->>'id' = v_charge.id::text;
  if v_row is null
     or (v_row->>'refunded_cents')::int <> v_charge.amount_cents
     or (v_row->>'refundable_cents')::int <> 0
     or jsonb_array_length(v_row->'refunds') <> 2 then
    raise exception 'FALLA g) admin_list_business_charges: %', v_row;
  end if;

  insert into _verificar values (format(
    'OK — las 7 verificaciones pasaron (cobro %s, %s centavos, AzulOrderId %s, OriginalDate %s).',
    v_charge.id, v_charge.amount_cents, v_charge.azul_order_id, v_r1.original_date
  ));
end $$;

select resultado from _verificar;

rollback;
