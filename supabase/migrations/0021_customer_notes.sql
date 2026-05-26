-- ---------------------------------------------------------------------------
-- 0021_customer_notes.sql
--
-- CRM ligero: notas internas que el operador toma sobre un negocio.
-- No es ticket ni email — es la "memoria" del equipo. Categorías curadas,
-- pin para fijar lo crítico arriba, autoría inmutable.
--
-- RPCs:
--   - create_customer_note(business_id, category, body, pinned)
--   - update_customer_note(note_id, category, body, pinned)
--   - toggle_customer_note_pin(note_id)
--   - delete_customer_note(note_id)
--   - get_customer_notes(business_id)
--
-- Política de edición: solo el autor puede editar/borrar su propia nota.
-- Cualquier operador puede pin/unpin.
-- ---------------------------------------------------------------------------

create table if not exists public.admin_customer_notes (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses(id) on delete cascade,
  author_id     uuid not null references auth.users(id) on delete restrict,
  category      text not null check (category in (
                  'general',
                  'billing_issue',
                  'feature_request',
                  'complaint',
                  'compliment',
                  'churn_risk',
                  'churn_reason',
                  'sales_followup',
                  'training',
                  'incident'
                )),
  body          text not null check (length(trim(body)) > 0),
  pinned        boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.admin_customer_notes is
  'Notas internas del operador sobre cada negocio. CRM ligero.';

create index if not exists admin_customer_notes_business_idx
  on public.admin_customer_notes (business_id, pinned desc, created_at desc);
create index if not exists admin_customer_notes_author_idx
  on public.admin_customer_notes (author_id, created_at desc);
create index if not exists admin_customer_notes_category_idx
  on public.admin_customer_notes (category, created_at desc);

alter table public.admin_customer_notes enable row level security;

drop policy if exists "admin_customer_notes operators read"
  on public.admin_customer_notes;
create policy "admin_customer_notes operators read"
on public.admin_customer_notes
for select
to authenticated
using (public.is_platform_operator());

-- INSERT/UPDATE/DELETE solo vía RPC security definer.


-- ---------------------------------------------------------------------------
-- 1) create_customer_note
-- ---------------------------------------------------------------------------
create or replace function public.create_customer_note(
  p_business_id uuid,
  p_category    text,
  p_body        text,
  p_pinned      boolean default false
)
returns public.admin_customer_notes
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_note public.admin_customer_notes;
  v_body text := trim(coalesce(p_body, ''));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_body = '' then
    raise exception 'El cuerpo de la nota no puede estar vacío.'
      using errcode = '22023';
  end if;

  if p_category not in (
    'general','billing_issue','feature_request','complaint','compliment',
    'churn_risk','churn_reason','sales_followup','training','incident'
  ) then
    raise exception 'Categoría inválida: %', p_category using errcode = '22023';
  end if;

  if not exists (select 1 from public.businesses where id = p_business_id) then
    raise exception 'Negocio % no existe', p_business_id using errcode = 'P0002';
  end if;

  insert into public.admin_customer_notes (
    business_id, author_id, category, body, pinned
  )
  values (
    p_business_id, auth.uid(), p_category, v_body, coalesce(p_pinned, false)
  )
  returning * into v_note;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'note.create',
    'admin_customer_notes',
    v_note.id,
    p_business_id,
    jsonb_build_object(
      'category', p_category,
      'pinned',   coalesce(p_pinned, false),
      'preview',  left(v_body, 80)
    )
  );

  return v_note;
end;
$$;

grant execute on function public.create_customer_note(uuid, text, text, boolean)
  to authenticated;


-- ---------------------------------------------------------------------------
-- 2) update_customer_note — solo autor
-- ---------------------------------------------------------------------------
create or replace function public.update_customer_note(
  p_note_id  uuid,
  p_category text,
  p_body     text,
  p_pinned   boolean
)
returns public.admin_customer_notes
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_note public.admin_customer_notes;
  v_body text := trim(coalesce(p_body, ''));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_body = '' then
    raise exception 'El cuerpo de la nota no puede estar vacío.'
      using errcode = '22023';
  end if;

  if p_category not in (
    'general','billing_issue','feature_request','complaint','compliment',
    'churn_risk','churn_reason','sales_followup','training','incident'
  ) then
    raise exception 'Categoría inválida: %', p_category using errcode = '22023';
  end if;

  update public.admin_customer_notes
     set category   = p_category,
         body       = v_body,
         pinned     = coalesce(p_pinned, pinned),
         updated_at = now()
   where id = p_note_id
     and author_id = auth.uid()
  returning * into v_note;

  if v_note.id is null then
    raise exception
      'Nota no encontrada o no eres el autor (solo el autor puede editar).'
      using errcode = '42501';
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'note.update',
    'admin_customer_notes',
    p_note_id,
    v_note.business_id,
    jsonb_build_object('category', p_category, 'pinned', v_note.pinned)
  );

  return v_note;
end;
$$;

grant execute on function public.update_customer_note(uuid, text, text, boolean)
  to authenticated;


-- ---------------------------------------------------------------------------
-- 3) toggle_customer_note_pin — cualquier operador
-- ---------------------------------------------------------------------------
create or replace function public.toggle_customer_note_pin(p_note_id uuid)
returns public.admin_customer_notes
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_note public.admin_customer_notes;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update public.admin_customer_notes
     set pinned     = not pinned,
         updated_at = now()
   where id = p_note_id
  returning * into v_note;

  if v_note.id is null then
    raise exception 'Nota % no existe', p_note_id using errcode = 'P0002';
  end if;

  return v_note;
end;
$$;

grant execute on function public.toggle_customer_note_pin(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 4) delete_customer_note — solo autor
-- ---------------------------------------------------------------------------
create or replace function public.delete_customer_note(p_note_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  delete from public.admin_customer_notes
   where id = p_note_id
     and author_id = auth.uid()
  returning business_id into v_business_id;

  if v_business_id is null then
    raise exception
      'Nota no encontrada o no eres el autor (solo el autor puede borrar).'
      using errcode = '42501';
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'note.delete',
    'admin_customer_notes',
    p_note_id,
    v_business_id,
    '{}'::jsonb
  );
end;
$$;

grant execute on function public.delete_customer_note(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 5) get_customer_notes — con autor enriquecido
-- ---------------------------------------------------------------------------
create or replace function public.get_customer_notes(p_business_id uuid)
returns table (
  id            uuid,
  business_id   uuid,
  author_id     uuid,
  author_name   text,
  is_own        boolean,
  category      text,
  body          text,
  pinned        boolean,
  created_at    timestamptz,
  updated_at    timestamptz
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
    n.id,
    n.business_id,
    n.author_id,
    coalesce(p.full_name, u.email)        as author_name,
    (n.author_id = auth.uid())            as is_own,
    n.category,
    n.body,
    n.pinned,
    n.created_at,
    n.updated_at
  from public.admin_customer_notes n
  left join auth.users     u on u.id = n.author_id
  left join public.profiles p on p.id = n.author_id
  where n.business_id = p_business_id
  order by n.pinned desc, n.created_at desc;
end;
$$;

grant execute on function public.get_customer_notes(uuid) to authenticated;
