-- ---------------------------------------------------------------------------
-- 0029_delete_business_disable_triggers.sql
--
-- En Supabase, ni `postgres` ni los roles aplicativos tienen permiso para
-- `SET session_replication_role` (es exclusivo de superuser; postgres en
-- Supabase es `nosuperuser`). La 0026 falla con permission denied al
-- hacer `set local session_replication_role = 'replica'`.
--
-- Alternativa que SÍ funciona como owner de las tablas (postgres en
-- Supabase es dueño de public.*): `ALTER TABLE … DISABLE TRIGGER USER`
-- que deshabilita solo triggers user-defined (no los internos de FK).
-- El DDL es transaccional, así que si la transacción rolledback los
-- triggers quedan habilitados igual que antes.
--
-- Algoritmo cuando p_force=true:
--   1) Descubrir todas las tablas en la cascada transitiva desde businesses.
--   2) ALTER TABLE ... DISABLE TRIGGER USER en cada una.
--   3) Ejecutar el cleanup recursivo + delete businesses.
--   4) ALTER TABLE ... ENABLE TRIGGER USER en cada una.
--
-- Owner de la función debe ser postgres para que el ALTER pase.
-- ---------------------------------------------------------------------------

-- Helper: devuelve el set de (schema, tabla) que la cascada transitiva
-- tocaría partiendo de (root_schema, root_table, root_col). Excluye
-- noc_audit_log porque se maneja aparte.
create or replace function public._cascade_tables_from(
  p_schema text,
  p_table  text,
  p_col    text
)
returns table (rel_schema text, rel_table text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pending text[][];   -- pares (schema, table, col) pendientes de expandir
  v_seen    text[][];   -- pares ya expandidos
  v_current text[];
  v_fk      record;
begin
  v_pending := array[array[p_schema, p_table, p_col]];

  while array_length(v_pending, 1) > 0 loop
    v_current := v_pending[1];
    v_pending := v_pending[2:array_length(v_pending, 1)];

    -- evita re-expandir
    if v_seen @> array[v_current] then
      continue;
    end if;
    v_seen := v_seen || array[v_current];

    for v_fk in
      select kcu.table_schema as cs, kcu.table_name as ct, kcu.column_name as cc
      from information_schema.table_constraints tc
      join information_schema.key_column_usage kcu
        on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
      join information_schema.referential_constraints rc
        on tc.constraint_name = rc.constraint_name and tc.constraint_schema = rc.constraint_schema
      join information_schema.constraint_column_usage ccu
        on rc.unique_constraint_name = ccu.constraint_name and rc.unique_constraint_schema = ccu.constraint_schema
      where tc.constraint_type = 'FOREIGN KEY'
        and ccu.table_schema = v_current[1]
        and ccu.table_name   = v_current[2]
        and ccu.column_name  = v_current[3]
        and not (kcu.table_schema = 'public' and kcu.table_name = 'noc_audit_log')
    loop
      rel_schema := v_fk.cs;
      rel_table  := v_fk.ct;
      return next;
      -- agregar el hijo (asumiendo PK 'id') para seguir expandiendo
      v_pending := v_pending
        || array[array[v_fk.cs, v_fk.ct, 'id']];
    end loop;
  end loop;
end;
$$;


-- delete_business con DISABLE TRIGGER USER en force mode.
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
  v_tables       record;
  v_touched      text[][] := array[]::text[][];
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

  v_snapshot := to_jsonb(v_business);

  -- Si force, deshabilitar triggers user-defined en TODAS las tablas
  -- que la cascada va a tocar. DDL es transaccional, así que si el
  -- delete falla por otro motivo todo se rolledback igual.
  if p_force then
    for v_tables in
      select distinct rel_schema, rel_table
      from public._cascade_tables_from('public', 'businesses', 'id')
    loop
      execute format(
        'alter table %I.%I disable trigger user',
        v_tables.rel_schema, v_tables.rel_table
      );
      v_touched := v_touched
        || array[array[v_tables.rel_schema, v_tables.rel_table]];
    end loop;
  end if;

  -- Desreferenciar audit logs previos.
  update public.noc_audit_log
     set business_id = null,
         payload     = coalesce(payload, '{}'::jsonb)
                        || jsonb_build_object('business_id_snapshot', p_business_id)
   where business_id = p_business_id;
  get diagnostics v_audit_count = row_count;

  v_per_table := public._cascade_delete_for_business(
    'public', 'businesses', 'id',
    array[p_business_id]::uuid[], 0, v_per_table
  );

  delete from public.businesses where id = p_business_id;

  -- Re-habilitar triggers. (Si la transacción aborta antes, el DDL hace rollback solo.)
  if p_force then
    declare
      i int;
    begin
      for i in 1 .. coalesce(array_length(v_touched, 1), 0) loop
        execute format(
          'alter table %I.%I enable trigger user',
          v_touched[i][1], v_touched[i][2]
        );
      end loop;
    end;
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
      'deleted_rows_per_table',  v_per_table,
      'triggers_disabled_on',    case
        when p_force then to_jsonb(v_touched)
        else null
      end
    )
  );
end;
$$;

comment on function public.delete_business(uuid, text, text, boolean) is
  'Borrado permanente con cascada recursiva. p_force=true deshabilita triggers user-defined en las tablas de la cascada (requiere ownership de la tabla).';

-- Asegurar ownership postgres.
alter function public.delete_business(uuid, text, text, boolean) owner to postgres;
alter function public._cascade_tables_from(text, text, text) owner to postgres;

grant execute on function public.delete_business(uuid, text, text, boolean) to authenticated;
