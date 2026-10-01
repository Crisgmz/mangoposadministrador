-- ============================================================================
-- Migración 0040 — Control del bloqueo del POS por falta de pago.
--
-- Depende de la migración `20260825_0001_business_access_control.sql` del repo
-- `mangospos` (misma base), que crea:
--   * public.platform_access_policy   — política global + kill switch
--   * public.business_access_control  — controles manuales por negocio
--   * public.fn_business_access_state(uuid) — motor de estado
--
-- RPCs de esta migración (todas gateadas por is_platform_operator()):
--   1) admin_get_business_access(p_business_id)  → estado + configuración
--   2) admin_set_business_access(...)            → bloquear / desbloquear /
--      programar corte / dar prórroga / editar mensaje y contacto
--   3) admin_get_access_policy()                 → política global
--   4) admin_set_access_policy(...)              → kill switch y defaults
--   5) admin_list_locked_businesses()            → negocios bloqueados o en
--      gracia, para la vista de cartera
--
-- Toda escritura exige razón y queda en `noc_audit_log`.
-- ============================================================================

do $$
begin
  if to_regprocedure('public.fn_business_access_state(uuid)') is null then
    raise exception
      'Falta public.fn_business_access_state(uuid). Aplica primero la migración '
      '20260825_0001_business_access_control.sql del repo mangospos.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1) admin_get_business_access
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_business_access(
  p_business_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return public.fn_business_access_state(p_business_id);
end;
$$;

comment on function public.admin_get_business_access(uuid) is
  'Estado de acceso al POS del negocio (ok|warning|grace|locked) + controles '
  'manuales vigentes. Solo operadores.';

grant execute on function public.admin_get_business_access(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) admin_set_business_access
--
--    p_action:
--      'lock'      → corte inmediato (lock_mode='forced_locked'). Limpia
--                    cualquier prórroga vigente.
--      'unlock'    → vuelve a 'auto' y limpia corte programado. El negocio
--                    puede quedar bloqueado igual si su billing_status manda
--                    (suspended/past_due vencido) — para eso está 'extend'.
--      'schedule'  → programa el corte en p_scheduled_lock_at.
--      'extend'    → prórroga (lock_mode='forced_open' + override_until).
--                    Garantiza acceso aunque el billing diga lo contrario.
--      'update'    → solo toca mensaje/contacto/gracia/enforcement.
--
--    Los parámetros no enviados (null) NO se tocan, salvo los que la acción
--    limpia por definición. Para borrar un valor explícitamente usa los flags
--    p_clear_*.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_business_access(
  p_business_id       uuid,
  p_action            text,
  p_reason            text,
  p_customer_message  text        default null,
  p_scheduled_lock_at timestamptz default null,
  p_override_until    timestamptz default null,
  p_grace_days        integer     default null,
  p_enforcement       text        default null,
  p_contact_name      text        default null,
  p_contact_phone     text        default null,
  p_clear_schedule    boolean     default false,
  p_clear_override    boolean     default false,
  p_clear_message     boolean     default false
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_reason text := trim(coalesce(p_reason, ''));
  v_before jsonb;
  v_after  jsonb;
  v_name   text;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria.' using errcode = '22023';
  end if;

  if p_action not in ('lock', 'unlock', 'schedule', 'extend', 'update') then
    raise exception 'Acción inválida: %', p_action using errcode = '22023';
  end if;

  if p_enforcement is not null and p_enforcement not in ('inherit', 'on', 'off') then
    raise exception 'enforcement inválido: %', p_enforcement using errcode = '22023';
  end if;

  select business_name into v_name from public.businesses where id = p_business_id;
  if v_name is null then
    raise exception 'Negocio % no existe', p_business_id using errcode = 'P0002';
  end if;

  if p_action = 'schedule' and p_scheduled_lock_at is null then
    raise exception 'Programar un corte requiere la fecha.' using errcode = '22023';
  end if;

  if p_action = 'extend' and p_override_until is null then
    raise exception 'La prórroga requiere fecha de vencimiento.'
      using errcode = '22023';
  end if;

  if p_action = 'extend' and p_override_until <= now() then
    raise exception 'La prórroga debe vencer en el futuro.' using errcode = '22023';
  end if;

  v_before := public.fn_business_access_state(p_business_id);

  insert into public.business_access_control (business_id) values (p_business_id)
  on conflict (business_id) do nothing;

  update public.business_access_control ac
     set lock_mode = case p_action
                       when 'lock'   then 'forced_locked'
                       when 'unlock' then 'auto'
                       when 'extend' then 'forced_open'
                       else ac.lock_mode
                     end,

         -- 'lock' mata la prórroga; 'unlock' y 'extend' la reescriben.
         override_until = case
                            when p_action = 'lock'    then null
                            when p_action = 'extend'  then p_override_until
                            when p_action = 'unlock'  then null
                            when p_clear_override     then null
                            else coalesce(p_override_until, ac.override_until)
                          end,

         -- 'unlock' y 'extend' quitan el corte programado (sería contradictorio).
         scheduled_lock_at = case
                               when p_action in ('unlock', 'extend') then null
                               when p_action = 'schedule' then p_scheduled_lock_at
                               when p_clear_schedule      then null
                               else coalesce(p_scheduled_lock_at, ac.scheduled_lock_at)
                             end,

         customer_message = case
                              when p_clear_message then null
                              else coalesce(p_customer_message, ac.customer_message)
                            end,

         grace_days   = coalesce(p_grace_days, ac.grace_days),
         enforcement  = coalesce(p_enforcement, ac.enforcement),
         contact_name = coalesce(p_contact_name, ac.contact_name),
         contact_phone = coalesce(p_contact_phone, ac.contact_phone),
         lock_reason  = case
                          when p_action in ('lock', 'schedule') then v_reason
                          when p_action = 'unlock' then null
                          else ac.lock_reason
                        end,
         locked_at    = case
                          when p_action = 'lock' then coalesce(ac.locked_at, now())
                          when p_action = 'unlock' then null
                          else ac.locked_at
                        end,
         locked_by    = case
                          when p_action = 'lock' then auth.uid()
                          when p_action = 'unlock' then null
                          else ac.locked_by
                        end,
         updated_by   = auth.uid(),
         updated_at   = now()
   where ac.business_id = p_business_id;

  v_after := public.fn_business_access_state(p_business_id);

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'business.access.' || p_action,
    'business_access_control',
    p_business_id,
    p_business_id,
    jsonb_build_object(
      'reason',        v_reason,
      'business_name', v_name,
      'before',        v_before,
      'after',         v_after
    )
  );

  return v_after;
end;
$$;

comment on function public.admin_set_business_access(uuid, text, text, text, timestamptz, timestamptz, integer, text, text, text, boolean, boolean, boolean) is
  'Bloquea/desbloquea el POS de un negocio, programa el corte, otorga prórroga '
  'o edita el mensaje al cliente. Razón obligatoria; audita en noc_audit_log.';

grant execute on function public.admin_set_business_access(uuid, text, text, text, timestamptz, timestamptz, integer, text, text, text, boolean, boolean, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) admin_get_access_policy
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_access_policy()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select to_jsonb(p) into v from public.platform_access_policy p where p.id = true;
  return v;
end;
$$;

grant execute on function public.admin_get_access_policy() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) admin_set_access_policy — kill switch global y defaults
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_access_policy(
  p_reason                  text,
  p_enforcement_enabled     boolean default null,
  p_default_grace_days      integer default null,
  p_lock_on_past_due        boolean default null,
  p_lock_on_trial_expired   boolean default null,
  p_offline_max_days        integer default null,
  p_default_customer_message text   default null,
  p_contact_name            text    default null,
  p_contact_phone           text    default null,
  p_contact_email           text    default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_reason text := trim(coalesce(p_reason, ''));
  v_before jsonb;
  v_after  jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria.' using errcode = '22023';
  end if;

  insert into public.platform_access_policy (id) values (true)
  on conflict (id) do nothing;

  select to_jsonb(p) into v_before from public.platform_access_policy p where p.id = true;

  update public.platform_access_policy p
     set enforcement_enabled      = coalesce(p_enforcement_enabled, p.enforcement_enabled),
         default_grace_days       = coalesce(p_default_grace_days, p.default_grace_days),
         lock_on_past_due         = coalesce(p_lock_on_past_due, p.lock_on_past_due),
         lock_on_trial_expired    = coalesce(p_lock_on_trial_expired, p.lock_on_trial_expired),
         offline_max_days         = coalesce(p_offline_max_days, p.offline_max_days),
         default_customer_message = coalesce(p_default_customer_message, p.default_customer_message),
         contact_name             = coalesce(p_contact_name, p.contact_name),
         contact_phone            = coalesce(p_contact_phone, p.contact_phone),
         contact_email            = coalesce(p_contact_email, p.contact_email),
         updated_by               = auth.uid(),
         updated_at               = now()
   where p.id = true;

  select to_jsonb(p) into v_after from public.platform_access_policy p where p.id = true;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'platform.access_policy.update',
    'platform_access_policy',
    null,
    null,
    jsonb_build_object('reason', v_reason, 'before', v_before, 'after', v_after)
  );

  return v_after;
end;
$$;

comment on function public.admin_set_access_policy(text, boolean, integer, boolean, boolean, integer, text, text, text, text) is
  'Política global de bloqueo por falta de pago. p_enforcement_enabled es el '
  'kill switch: en false ningún POS bloquea. Razón obligatoria; audita.';

grant execute on function public.admin_set_access_policy(text, boolean, integer, boolean, boolean, integer, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) admin_list_locked_businesses — vista de cartera
--
--    Calcula el estado de TODOS los negocios y devuelve los que no están 'ok'.
--    Con el parque actual (cientos de negocios) el costo es aceptable; si
--    crece, materializar.
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_locked_businesses(
  p_include_ok boolean default false
) returns table (
  business_id   uuid,
  business_name text,
  state         text,
  reason        text,
  enforced      boolean,
  locked_at     timestamptz,
  grace_ends_at timestamptz,
  billing_status text
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
  select b.id,
         b.business_name,
         s.js->>'state',
         s.js->>'reason',
         (s.js->>'enforced')::boolean,
         (s.js->>'locked_at')::timestamptz,
         (s.js->>'grace_ends_at')::timestamptz,
         s.js->>'billing_status'
    from public.businesses b
    cross join lateral public.fn_business_access_state(b.id) as s(js)
   where p_include_ok or (s.js->>'state') <> 'ok'
   order by case s.js->>'state'
              when 'locked'  then 0
              when 'grace'   then 1
              when 'warning' then 2
              else 3
            end,
            b.business_name;
end;
$$;

comment on function public.admin_list_locked_businesses(boolean) is
  'Negocios bloqueados, en gracia o con aviso. Para la vista de cartera de '
  'cobranza del panel. Solo operadores.';

grant execute on function public.admin_list_locked_businesses(boolean) to authenticated;
