-- ---------------------------------------------------------------------------
-- 0026_delete_business_force.sql
--
-- Agrega un parámetro `p_force` a `delete_business` para saltar triggers
-- custom de `mangospos` que se interponen al borrado administrativo (p.ej.
-- `cash_count_blind is immutable after signing`, validaciones fiscales).
--
-- Mecanismo: `set local session_replication_role = 'replica'` deshabilita
-- triggers user-defined Y constraint triggers (FK checks) durante la
-- transacción actual. Como nuestro cleanup recursivo ya borra las FK en
-- orden topológico explícito, el bypass de FK no genera huérfanos:
-- la integridad la garantiza el código, no Postgres.
--
-- Riesgo: si el trigger custom defendía una invariante semántica (no solo
-- "firma fiscal"), el bypass la viola. Por eso `p_force` es opt-in y la UI
-- lo expone como checkbox separado con advertencia.
--
-- Requiere ownership `postgres` en la función (security definer) para que
-- `SET session_replication_role` no requiera privilegio adicional.
-- ---------------------------------------------------------------------------

create or replace function public.delete_business(
  p_business_id  uuid,
  p_confirmation text,
  p_reason       text,
  p_force        boolean default false
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_business     public.businesses;
  v_snapshot     jsonb;
  v_reason       text  := trim(coalesce(p_reason, ''));
  v_confirmation text  := trim(coalesce(p_confirmation, ''));
  v_audit_count  int;
  v_per_table    jsonb := '{}'::jsonb;
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

  -- Bypass de triggers user-defined + FK checks (solo en esta transacción).
  -- Necesario para vencer protectores como `cash_count_blind is immutable
  -- after signing`. Mantiene integridad porque borramos en orden recursivo.
  if p_force then
    set local session_replication_role = 'replica';
  end if;

  v_snapshot := to_jsonb(v_business);

  -- Desreferenciar audit logs previos (preserva el id en payload).
  update public.noc_audit_log
     set business_id = null,
         payload     = coalesce(payload, '{}'::jsonb)
                        || jsonb_build_object('business_id_snapshot', p_business_id)
   where business_id = p_business_id;
  get diagnostics v_audit_count = row_count;

  v_per_table := public._cascade_delete_for_business(
    'public',
    'businesses',
    'id',
    array[p_business_id]::uuid[],
    0,
    v_per_table
  );

  delete from public.businesses where id = p_business_id;

  -- Restaurar replication role (solo necesario si lo cambiamos; SET LOCAL
  -- lo desharía solo al commit, pero lo hacemos explícito para que el audit
  -- log final se inserte con triggers activos).
  if p_force then
    set local session_replication_role = 'origin';
  end if;

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
      'reason',                  v_reason,
      'forced',                  p_force,
      'business_id_snapshot',    p_business_id,
      'snapshot',                v_snapshot,
      'audit_logs_unlinked',     v_audit_count,
      'deleted_rows_per_table',  v_per_table
    )
  );
end;
$$;

comment on function public.delete_business(uuid, text, text, boolean) is
  'Borrado permanente con cascada recursiva. `p_force=true` saltea triggers custom (cash_count_blind, etc). Audita uso del force.';

-- Asegurar ownership postgres para que SET session_replication_role pase.
alter function public.delete_business(uuid, text, text, boolean) owner to postgres;

grant execute on function public.delete_business(uuid, text, text, boolean) to authenticated;

-- Drop la signature anterior de 3 args (sin p_force) para evitar resolución
-- ambigua. PostgREST resuelve por nombres de parámetros, así que la nueva
-- recibe los 3 mismos + el opcional sin romper callers existentes; pero
-- mantener dos versiones convivendo confunde, mejor unificar.
drop function if exists public.delete_business(uuid, text, text);
