-- ---------------------------------------------------------------------------
-- 0023_delete_business_dynamic.sql
--
-- Reemplaza `delete_business` por una versión dinámica que descubre todas las
-- FK a `public.businesses` con delete_rule RESTRICT/NO ACTION y borra de
-- esas tablas antes de eliminar el negocio. Así el RPC funciona sin
-- mantenimiento cuando aparecen nuevas tablas en el schema compartido
-- (p.ej. `business_alanube_settings`, futuras `business_xxx_settings`).
--
-- Excepciones:
--   * `noc_audit_log.business_id`: NO se borra. Se desreferencia (set NULL),
--     preservando el log de auditoría con el `business_id_snapshot` en payload.
--   * FK con `on delete cascade` / `set null`: Postgres las maneja sola.
--
-- Política: las filas borradas por tabla se reportan en
-- `noc_audit_log.payload.deleted_rows_per_table` para forense.
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
  v_business     public.businesses;
  v_snapshot     jsonb;
  v_reason       text := trim(coalesce(p_reason, ''));
  v_confirmation text := trim(coalesce(p_confirmation, ''));
  v_audit_count  int;
  v_fk           record;
  v_deleted      int;
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

  -- Snapshot completo del negocio (para forense).
  v_snapshot := to_jsonb(v_business);

  -- Desreferenciar logs previos del negocio (preserva el id en payload).
  update public.noc_audit_log
     set business_id = null,
         payload     = coalesce(payload, '{}'::jsonb)
                        || jsonb_build_object('business_id_snapshot', p_business_id)
   where business_id = p_business_id;
  get diagnostics v_audit_count = row_count;

  -- Cascada dinámica: itera todas las FK que apuntan a `businesses` con
  -- delete_rule en ('RESTRICT','NO ACTION') y borra las filas referenciadas.
  -- Excluye explícitamente `noc_audit_log` (ya desreferenciado arriba) y
  -- la self-reference que no aplica.
  for v_fk in
    select
      kcu.table_schema  as ref_schema,
      kcu.table_name    as ref_table,
      kcu.column_name   as ref_column
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name
     and tc.table_schema    = kcu.table_schema
    join information_schema.referential_constraints rc
      on tc.constraint_name      = rc.constraint_name
     and tc.constraint_schema    = rc.constraint_schema
    join information_schema.constraint_column_usage ccu
      on rc.unique_constraint_name   = ccu.constraint_name
     and rc.unique_constraint_schema = ccu.constraint_schema
    where tc.constraint_type = 'FOREIGN KEY'
      and ccu.table_schema   = 'public'
      and ccu.table_name     = 'businesses'
      and ccu.column_name    = 'id'
      and rc.delete_rule    in ('RESTRICT', 'NO ACTION')
      and not (kcu.table_schema = 'public'
               and kcu.table_name = 'noc_audit_log')
  loop
    execute format(
      'delete from %I.%I where %I = $1',
      v_fk.ref_schema, v_fk.ref_table, v_fk.ref_column
    ) using p_business_id;
    get diagnostics v_deleted = row_count;
    if v_deleted > 0 then
      v_per_table := v_per_table
        || jsonb_build_object(
             v_fk.ref_schema || '.' || v_fk.ref_table || '.' || v_fk.ref_column,
             v_deleted
           );
    end if;
  end loop;

  -- Finalmente, borrar el negocio. Las tablas con ON DELETE CASCADE / SET NULL
  -- las maneja Postgres automáticamente aquí.
  delete from public.businesses where id = p_business_id;

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
      'business_id_snapshot',    p_business_id,
      'snapshot',                v_snapshot,
      'audit_logs_unlinked',     v_audit_count,
      'deleted_rows_per_table',  v_per_table
    )
  );
end;
$$;

comment on function public.delete_business(uuid, text, text) is
  'Borrado permanente. Descubre dinámicamente todas las FK con RESTRICT/NO ACTION a businesses y limpia en cascada. Preserva noc_audit_log desreferenciado.';

grant execute on function public.delete_business(uuid, text, text) to authenticated;
