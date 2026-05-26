-- ---------------------------------------------------------------------------
-- 0020_admin_extensions.sql
--
-- Prórrogas, gracias y créditos operativos sobre la membresía de un negocio.
-- Cada otorgamiento es una fila inmutable en `admin_extensions` (no se
-- modifica; se revierte con `reverted_at`). Mantiene auditoría completa.
--
-- Tipos:
--   * trial_extension — extiende el `end_date` de la membresía X días.
--   * payment_grace   — gracia post-vencimiento, también extiende end_date.
--   * free_credit     — crédito monetario aplicable a la próxima factura
--                       (no toca end_date; lo descuenta `generate_membership_invoice`
--                       cuando se integre — pendiente).
--
-- RPCs:
--   - grant_extension(business_id, type, days, amount, reason, customer_msg)
--   - revert_extension(extension_id, reason)
--   - get_business_extensions(business_id)
-- ---------------------------------------------------------------------------

create table if not exists public.admin_extensions (
  id                       uuid primary key default gen_random_uuid(),
  business_id              uuid not null references public.businesses(id) on delete cascade,
  membership_id            uuid references public.memberships(id) on delete set null,
  granted_by               uuid not null references auth.users(id),
  extension_type           text not null
    check (extension_type in ('trial_extension', 'payment_grace', 'free_credit')),
  days_granted             int,                       -- para trial_extension / payment_grace
  amount                   numeric(12,2),             -- para free_credit (RD$)
  currency_code            text not null default 'DOP',
  reason                   text not null,
  customer_facing_message  text,
  effective_until          timestamptz,               -- nueva end_date efectiva (si aplica)
  previous_end_date        timestamptz,               -- end_date antes del grant (para revert)
  applied_to_invoice_id    uuid references public.membership_invoices(id) on delete set null,
  granted_at               timestamptz not null default now(),
  reverted_at              timestamptz,
  reverted_by              uuid references auth.users(id),
  reverted_reason          text,

  -- Coherencia: cada tipo exige sus campos.
  constraint admin_extensions_days_or_amount
    check (
      (extension_type in ('trial_extension', 'payment_grace')
        and days_granted is not null and days_granted > 0 and amount is null)
      or
      (extension_type = 'free_credit'
        and amount is not null and amount > 0 and days_granted is null)
    )
);

comment on table public.admin_extensions is
  'Prórrogas y créditos otorgados por el operador. Inmutable; se revierte vía reverted_*.';

create index if not exists admin_extensions_business_idx
  on public.admin_extensions (business_id, granted_at desc);
create index if not exists admin_extensions_active_idx
  on public.admin_extensions (business_id)
  where reverted_at is null;

alter table public.admin_extensions enable row level security;

drop policy if exists "admin_extensions operators read" on public.admin_extensions;
create policy "admin_extensions operators read"
on public.admin_extensions
for select
to authenticated
using (public.is_platform_operator());

-- INSERT/UPDATE solo vía RPC security definer. No policy de write directa.


-- ---------------------------------------------------------------------------
-- 1) grant_extension(business_id, type, days, amount, reason, customer_msg)
-- ---------------------------------------------------------------------------
create or replace function public.grant_extension(
  p_business_id  uuid,
  p_type         text,
  p_days         int          default null,
  p_amount       numeric      default null,
  p_reason       text         default null,
  p_customer_msg text         default null
)
returns public.admin_extensions
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_business        public.businesses;
  v_membership      public.memberships;
  v_extension       public.admin_extensions;
  v_reason          text := trim(coalesce(p_reason, ''));
  v_previous_end    timestamptz;
  v_new_end         timestamptz;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria.' using errcode = '22023';
  end if;

  if p_type not in ('trial_extension', 'payment_grace', 'free_credit') then
    raise exception 'Tipo de prórroga inválido: %', p_type using errcode = '22023';
  end if;

  if p_type in ('trial_extension', 'payment_grace') then
    if p_days is null or p_days <= 0 then
      raise exception 'Días debe ser > 0 para %', p_type using errcode = '22023';
    end if;
  else  -- free_credit
    if p_amount is null or p_amount <= 0 then
      raise exception 'Monto debe ser > 0 para free_credit' using errcode = '22023';
    end if;
  end if;

  select * into v_business from public.businesses where id = p_business_id;
  if v_business.id is null then
    raise exception 'Negocio % no existe', p_business_id using errcode = 'P0002';
  end if;

  -- Membresía activa más reciente del negocio.
  select * into v_membership
    from public.memberships
   where business_id = p_business_id
   order by created_at desc
   limit 1;

  if v_membership.id is null then
    raise exception 'El negocio % no tiene membresía', p_business_id
      using errcode = 'P0002';
  end if;

  v_previous_end := v_membership.end_date;

  -- Si es trial_extension o payment_grace, extiende end_date.
  if p_type in ('trial_extension', 'payment_grace') then
    v_new_end := coalesce(v_membership.end_date, now()) + make_interval(days => p_days);
    update public.memberships
       set end_date = v_new_end,
           status   = case when status in ('expired', 'canceled') then 'active' else status end
     where id = v_membership.id;
  end if;

  insert into public.admin_extensions (
    business_id,
    membership_id,
    granted_by,
    extension_type,
    days_granted,
    amount,
    reason,
    customer_facing_message,
    effective_until,
    previous_end_date
  )
  values (
    p_business_id,
    v_membership.id,
    auth.uid(),
    p_type,
    p_days,
    p_amount,
    v_reason,
    nullif(trim(coalesce(p_customer_msg, '')), ''),
    v_new_end,
    v_previous_end
  )
  returning * into v_extension;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'extension.grant',
    'admin_extensions',
    v_extension.id,
    p_business_id,
    jsonb_build_object(
      'type',              p_type,
      'days_granted',      p_days,
      'amount',            p_amount,
      'reason',            v_reason,
      'previous_end_date', v_previous_end,
      'new_end_date',      v_new_end
    )
  );

  return v_extension;
end;
$$;

comment on function public.grant_extension(uuid, text, int, numeric, text, text) is
  'Otorga prórroga, gracia o crédito. Inmutable + auditado. Reason obligatorio.';

grant execute on function public.grant_extension(uuid, text, int, numeric, text, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 2) revert_extension(extension_id, reason)
--    Marca la extensión como revertida. Si extendió end_date, restaura el
--    previous_end_date en la membresía.
-- ---------------------------------------------------------------------------
create or replace function public.revert_extension(
  p_extension_id uuid,
  p_reason       text
)
returns public.admin_extensions
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_extension public.admin_extensions;
  v_reason    text := trim(coalesce(p_reason, ''));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria para revertir.' using errcode = '22023';
  end if;

  select * into v_extension from public.admin_extensions where id = p_extension_id;
  if v_extension.id is null then
    raise exception 'Prórroga % no existe', p_extension_id using errcode = 'P0002';
  end if;

  if v_extension.reverted_at is not null then
    raise exception 'Prórroga % ya está revertida', p_extension_id
      using errcode = '22023';
  end if;

  -- Restaurar end_date si la membresía sigue siendo la misma y la prórroga
  -- realmente movió la fecha (trial_extension / payment_grace).
  if v_extension.membership_id is not null
     and v_extension.extension_type in ('trial_extension', 'payment_grace')
     and v_extension.effective_until is not null
  then
    update public.memberships
       set end_date = v_extension.previous_end_date
     where id = v_extension.membership_id
       and end_date = v_extension.effective_until;
  end if;

  update public.admin_extensions
     set reverted_at     = now(),
         reverted_by     = auth.uid(),
         reverted_reason = v_reason
   where id = p_extension_id
  returning * into v_extension;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'extension.revert',
    'admin_extensions',
    p_extension_id,
    v_extension.business_id,
    jsonb_build_object(
      'reason',           v_reason,
      'type',             v_extension.extension_type,
      'restored_end_date', v_extension.previous_end_date
    )
  );

  return v_extension;
end;
$$;

comment on function public.revert_extension(uuid, text) is
  'Revierte una prórroga. Restaura end_date si aplica. Auditado.';

grant execute on function public.revert_extension(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 3) get_business_extensions(business_id)
--    Histórico completo de prórrogas/créditos para mostrar en el detalle.
-- ---------------------------------------------------------------------------
create or replace function public.get_business_extensions(p_business_id uuid)
returns table (
  id                      uuid,
  business_id             uuid,
  extension_type          text,
  days_granted            int,
  amount                  numeric,
  currency_code           text,
  reason                  text,
  customer_facing_message text,
  effective_until         timestamptz,
  previous_end_date       timestamptz,
  granted_by_name         text,
  granted_at              timestamptz,
  reverted_at             timestamptz,
  reverted_by_name        text,
  reverted_reason         text
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
    e.id,
    e.business_id,
    e.extension_type,
    e.days_granted,
    e.amount,
    e.currency_code,
    e.reason,
    e.customer_facing_message,
    e.effective_until,
    e.previous_end_date,
    coalesce(gp.full_name, gu.email)             as granted_by_name,
    e.granted_at,
    e.reverted_at,
    coalesce(rp.full_name, ru.email)             as reverted_by_name,
    e.reverted_reason
  from public.admin_extensions e
  left join auth.users     gu on gu.id = e.granted_by
  left join public.profiles gp on gp.id = e.granted_by
  left join auth.users     ru on ru.id = e.reverted_by
  left join public.profiles rp on rp.id = e.reverted_by
  where e.business_id = p_business_id
  order by e.granted_at desc;
end;
$$;

grant execute on function public.get_business_extensions(uuid) to authenticated;
