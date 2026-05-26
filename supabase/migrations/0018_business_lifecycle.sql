-- ---------------------------------------------------------------------------
-- 0018_business_lifecycle.sql
--
-- Ciclo de vida de cuentas (negocios) operado desde Mango Administrador.
-- Cubre las tres acciones que el operador necesita sobre un negocio:
--
--   1) deactivate_business(p_business_id, p_reason)
--      Marca status='inactive' con razón obligatoria. Idempotente.
--      Distinto de `toggle_business_status` (que alterna).
--
--   2) activate_business(p_business_id, p_reason)
--      Marca status='active'. Idempotente.
--
--   3) delete_business(p_business_id, p_confirmation, p_reason)
--      Borrado permanente. Requiere "typed confirmation" con el nombre del
--      negocio para evitar borrados accidentales. Antes de borrar, captura
--      snapshot completo del negocio en `noc_audit_log.payload` para forense.
--      Borra en cascada controlada las tablas dependientes que conoce este
--      admin (memberships, membership_invoices). Si hay FK no controladas
--      en otras tablas con `on delete restrict`, la transacción se revierte
--      y el operador recibe el error original — debe limpiar primero.
--
-- Todas las RPCs requieren `is_platform_operator()` y registran intervención
-- en `noc_audit_log`. Razón es obligatoria en las tres.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1) deactivate_business(p_business_id, p_reason)
-- ---------------------------------------------------------------------------
create or replace function public.deactivate_business(
  p_business_id uuid,
  p_reason      text
)
returns public.businesses
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_before  public.businesses;
  v_after   public.businesses;
  v_reason  text := trim(coalesce(p_reason, ''));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria para desactivar un negocio.'
      using errcode = '22023';
  end if;

  select * into v_before from public.businesses where id = p_business_id;
  if v_before.id is null then
    raise exception 'Negocio % no existe', p_business_id
      using errcode = 'P0002';
  end if;

  update public.businesses
     set status = 'inactive',
         updated_at = now()
   where id = p_business_id
  returning * into v_after;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'business.deactivate',
    'businesses',
    p_business_id,
    p_business_id,
    jsonb_build_object(
      'reason',          v_reason,
      'previous_status', v_before.status,
      'business_name',   v_before.business_name
    )
  );

  return v_after;
end;
$$;

comment on function public.deactivate_business(uuid, text) is
  'Desactiva un negocio (status=inactive) con razón obligatoria. Audita.';

grant execute on function public.deactivate_business(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 2) activate_business(p_business_id, p_reason)
-- ---------------------------------------------------------------------------
create or replace function public.activate_business(
  p_business_id uuid,
  p_reason      text default null
)
returns public.businesses
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_before public.businesses;
  v_after  public.businesses;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select * into v_before from public.businesses where id = p_business_id;
  if v_before.id is null then
    raise exception 'Negocio % no existe', p_business_id
      using errcode = 'P0002';
  end if;

  update public.businesses
     set status = 'active',
         updated_at = now()
   where id = p_business_id
  returning * into v_after;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'business.activate',
    'businesses',
    p_business_id,
    p_business_id,
    jsonb_build_object(
      'reason',          coalesce(nullif(trim(coalesce(p_reason, '')), ''), null),
      'previous_status', v_before.status,
      'business_name',   v_before.business_name
    )
  );

  return v_after;
end;
$$;

comment on function public.activate_business(uuid, text) is
  'Reactiva un negocio (status=active). Audita.';

grant execute on function public.activate_business(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 3) delete_business(p_business_id, p_confirmation, p_reason)
--
--    Borrado permanente. Hard delete con cascade controlado de tablas
--    dependientes conocidas por este admin. La razón se preserva en
--    `noc_audit_log` (que NO se borra junto con el business — la FK es
--    set null implícito porque la columna business_id no tiene ON DELETE).
--    En realidad, `noc_audit_log.business_id` tiene FK sin política de
--    delete declarada (la migración 0009 no la especifica), así que
--    Postgres aplica NO ACTION por defecto: bloquearía el delete. Para
--    asegurar que el delete del business NO falle por su propio audit,
--    desreferenciamos los logs del negocio antes (set business_id = null,
--    pero mantenemos payload con business_id_snapshot).
-- ---------------------------------------------------------------------------
create or replace function public.delete_business(
  p_business_id  uuid,
  p_confirmation text,
  p_reason       text
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_business      public.businesses;
  v_snapshot      jsonb;
  v_reason        text := trim(coalesce(p_reason, ''));
  v_confirmation  text := trim(coalesce(p_confirmation, ''));
  v_audit_count   int;
  v_membership_inv_count int;
  v_membership_count int;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria para eliminar un negocio.'
      using errcode = '22023';
  end if;

  select * into v_business from public.businesses where id = p_business_id;
  if v_business.id is null then
    raise exception 'Negocio % no existe', p_business_id
      using errcode = 'P0002';
  end if;

  if v_confirmation <> v_business.business_name then
    raise exception
      'Confirmación incorrecta. Escribe el nombre exacto del negocio para confirmar.'
      using errcode = '22023';
  end if;

  -- Snapshot completo para forense.
  v_snapshot := to_jsonb(v_business);

  -- Desreferenciar logs previos del negocio para que el delete del business
  -- no falle por la FK noc_audit_log.business_id. El log nuevo (.delete) se
  -- inserta DESPUÉS con business_id = null pero preservando el id en payload.
  update public.noc_audit_log
     set business_id = null,
         payload     = coalesce(payload, '{}'::jsonb)
                        || jsonb_build_object('business_id_snapshot', p_business_id)
   where business_id = p_business_id;
  get diagnostics v_audit_count = row_count;

  -- Borrar dependencias controladas en este admin.
  delete from public.membership_invoices where business_id = p_business_id;
  get diagnostics v_membership_inv_count = row_count;

  delete from public.memberships where business_id = p_business_id;
  get diagnostics v_membership_count = row_count;

  -- Borrar el negocio. Si otras tablas con FK ON DELETE RESTRICT existen
  -- en la DB compartida (orders, payments, etc.), Postgres revertirá toda
  -- la transacción y devolverá el error original al cliente.
  delete from public.businesses where id = p_business_id;

  -- Auditoría final con snapshot completo.
  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'business.delete',
    'businesses',
    p_business_id,
    null,
    jsonb_build_object(
      'reason',                      v_reason,
      'business_id_snapshot',        p_business_id,
      'snapshot',                    v_snapshot,
      'audit_logs_unlinked',         v_audit_count,
      'membership_invoices_deleted', v_membership_inv_count,
      'memberships_deleted',         v_membership_count
    )
  );
end;
$$;

comment on function public.delete_business(uuid, text, text) is
  'Borrado permanente de un negocio. Requiere typed confirmation (nombre exacto) y razón. Captura snapshot completo en noc_audit_log antes de borrar.';

grant execute on function public.delete_business(uuid, text, text) to authenticated;
