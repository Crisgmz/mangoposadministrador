-- ---------------------------------------------------------------------------
-- 0024_delete_business_recursive.sql
--
-- Reemplaza `delete_business` por una versión RECURSIVA que limpia cadenas
-- de FK de cualquier profundidad. La versión dinámica anterior (0023) solo
-- limpiaba FK directas, así que fallaba con cadenas tipo:
--
--     businesses → taxes → order_item_tax_lines
--
-- Cuando intentaba borrar `taxes`, su propio hijo `order_item_tax_lines`
-- lo bloqueaba con RESTRICT.
--
-- Algoritmo:
--   * Helper `_cascade_delete(schema, table, pk_col, ids[], depth)`:
--     1) Para cada FK que apunta a (schema.table.pk_col) con RESTRICT/NO ACTION,
--        obtiene los ids del hijo a borrar.
--     2) Llama RECURSIVAMENTE para limpiar sus dependientes.
--     3) Borra del hijo.
--   * Tope de profundidad 10 (defensa contra ciclos / schemas patológicos).
--   * Asume PK de las tablas hijas se llama `id` (convención del proyecto).
--   * Excluye `noc_audit_log` (se desreferencia aparte en el caller).
--
-- Reporta cuántas filas borró por tabla en `noc_audit_log.payload`.
-- ---------------------------------------------------------------------------

-- Helper privada. Devuelve el jsonb actualizado con conteos por tabla.
create or replace function public._cascade_delete_for_business(
  p_target_schema   text,
  p_target_table    text,
  p_target_pk_col   text,
  p_target_pk_ids   uuid[],
  p_depth           int,
  p_per_table       jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_fk          record;
  v_child_ids   uuid[];
  v_deleted     int;
  v_per_table   jsonb := p_per_table;
  v_key         text;
begin
  if p_depth > 10 then
    raise exception
      'Cascada de borrado excedió profundidad máxima en %.%',
      p_target_schema, p_target_table
      using errcode = '54000';
  end if;

  if p_target_pk_ids is null or array_length(p_target_pk_ids, 1) is null then
    return v_per_table;
  end if;

  for v_fk in
    select
      kcu.table_schema  as child_schema,
      kcu.table_name    as child_table,
      kcu.column_name   as child_fk_col
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
      and ccu.table_schema   = p_target_schema
      and ccu.table_name     = p_target_table
      and ccu.column_name    = p_target_pk_col
      and rc.delete_rule    in ('RESTRICT', 'NO ACTION')
      -- noc_audit_log se desreferencia explícitamente arriba (set null).
      and not (kcu.table_schema = 'public'
               and kcu.table_name = 'noc_audit_log')
  loop
    -- Obtener los ids del hijo que están a punto de quedar huérfanos.
    -- Asume que la PK del hijo se llama 'id' (convención del proyecto).
    -- Si la tabla no tiene 'id' la consulta fallará y el operador verá
    -- un error claro indicando la tabla problemática.
    execute format(
      'select coalesce(array_agg(id), array[]::uuid[]) '
      'from %I.%I where %I = any($1)',
      v_fk.child_schema, v_fk.child_table, v_fk.child_fk_col
    )
    into v_child_ids
    using p_target_pk_ids;

    -- Recurse: limpiar nietos antes de tocar este hijo.
    if v_child_ids is not null and array_length(v_child_ids, 1) > 0 then
      v_per_table := public._cascade_delete_for_business(
        v_fk.child_schema,
        v_fk.child_table,
        'id',
        v_child_ids,
        p_depth + 1,
        v_per_table
      );
    end if;

    -- Ya con los nietos fuera, borrar las filas del hijo.
    execute format(
      'delete from %I.%I where %I = any($1)',
      v_fk.child_schema, v_fk.child_table, v_fk.child_fk_col
    ) using p_target_pk_ids;
    get diagnostics v_deleted = row_count;

    if v_deleted > 0 then
      v_key := v_fk.child_schema || '.' ||
               v_fk.child_table  || '.' ||
               v_fk.child_fk_col;
      v_per_table := v_per_table
        || jsonb_build_object(v_key, v_deleted);
    end if;
  end loop;

  return v_per_table;
end;
$$;

comment on function public._cascade_delete_for_business(text, text, text, uuid[], int, jsonb) is
  'Helper recursivo para delete_business. Limpia FK RESTRICT/NO ACTION en cadena.';

-- No granteamos execute a authenticated — solo delete_business la llama.


-- ---------------------------------------------------------------------------
-- delete_business: usa el helper recursivo.
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

  -- Snapshot para forense.
  v_snapshot := to_jsonb(v_business);

  -- Desreferenciar logs previos. Preservamos el id en payload.
  update public.noc_audit_log
     set business_id = null,
         payload     = coalesce(payload, '{}'::jsonb)
                        || jsonb_build_object('business_id_snapshot', p_business_id)
   where business_id = p_business_id;
  get diagnostics v_audit_count = row_count;

  -- Cascada recursiva desde businesses.id.
  v_per_table := public._cascade_delete_for_business(
    'public',
    'businesses',
    'id',
    array[p_business_id]::uuid[],
    0,
    v_per_table
  );

  -- Borrar el negocio. CASCADE / SET NULL los maneja Postgres.
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
  'Borrado permanente con cascada recursiva. Limpia FK RESTRICT/NO ACTION en cadena. Preserva noc_audit_log desreferenciado.';

grant execute on function public.delete_business(uuid, text, text) to authenticated;
