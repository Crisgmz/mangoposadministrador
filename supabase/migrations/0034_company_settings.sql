-- ---------------------------------------------------------------------------
-- 0034_company_settings.sql
--
-- Datos de la empresa MangoPOS (el emisor de las facturas de membresía).
-- Hasta ahora estaba hardcoded en `lib/data/services/invoice_pdf.dart`
-- como `class _Issuer`. Esto lo mueve a una tabla editable desde el panel.
--
-- Diseño: **single-row enforced** — la tabla solo contiene una fila con
-- `id=1`. Un check constraint impide insertar otra. Esto evita el patrón
-- "tabla settings con muchas filas y SELECT … LIMIT 1" que es propenso a
-- bugs si alguien inserta más por error.
--
-- RLS: SELECT abierto a authenticated (los datos de empresa no son
-- sensibles — aparecen en facturas que se mandan a clientes).
-- UPDATE solo vía RPC `admin_update_company_settings`.
-- ---------------------------------------------------------------------------

create table if not exists public.company_settings (
  id                    smallint primary key check (id = 1) default 1,
  legal_name            text not null default 'MangoPOS Servicios SRL',
  rnc                   text,
  address               text,
  city                  text,
  country               text default 'República Dominicana',
  phone                 text,
  email                 text,
  website               text,
  logo_url              text,
  payment_instructions  text,
  updated_at            timestamptz not null default now(),
  updated_by            uuid references auth.users(id)
);

comment on table public.company_settings is
  'Datos del emisor (MangoPOS). Single-row enforced. Editable desde /configuracion.';

-- Seed inicial con los valores que estaban hardcoded en _Issuer.
insert into public.company_settings (
  id, legal_name, rnc, address, city, phone, email, website,
  payment_instructions
)
values (
  1,
  'MangoPOS Servicios SRL',
  '1-31-23456-7',
  'Av. Lope de Vega No. 13, Naco',
  'Santo Domingo, RD',
  '+1 (809) 555-0100',
  'soporte@mangopos.do',
  'mangopos.do',
  'Métodos aceptados: transferencia bancaria, efectivo o tarjeta.'
  || E'\n' ||
  'Confirmar pago vía WhatsApp o email a soporte@mangopos.do.'
)
on conflict (id) do nothing;


alter table public.company_settings enable row level security;

drop policy if exists "company_settings read all" on public.company_settings;
create policy "company_settings read all"
on public.company_settings
for select
to authenticated
using (true);

-- UPDATE solo vía RPC security definer.


-- ---------------------------------------------------------------------------
-- get_company_settings()
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_company_settings()
returns public.company_settings
language sql
stable
security definer
set search_path = public
as $$
  select * from public.company_settings where id = 1 limit 1;
$$;

grant execute on function public.admin_get_company_settings() to authenticated;


-- ---------------------------------------------------------------------------
-- admin_update_company_settings(...)
-- ---------------------------------------------------------------------------
create or replace function public.admin_update_company_settings(
  p_legal_name           text,
  p_rnc                  text,
  p_address              text,
  p_city                 text,
  p_country              text,
  p_phone                text,
  p_email                text,
  p_website              text,
  p_logo_url             text,
  p_payment_instructions text
)
returns public.company_settings
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_before public.company_settings;
  v_after  public.company_settings;
  v_name   text := trim(coalesce(p_legal_name, ''));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_name = '' then
    raise exception 'El nombre legal es obligatorio.' using errcode = '22023';
  end if;

  select * into v_before from public.company_settings where id = 1;

  update public.company_settings
     set legal_name           = v_name,
         rnc                  = nullif(trim(coalesce(p_rnc, '')), ''),
         address              = nullif(trim(coalesce(p_address, '')), ''),
         city                 = nullif(trim(coalesce(p_city, '')), ''),
         country              = nullif(trim(coalesce(p_country, '')), ''),
         phone                = nullif(trim(coalesce(p_phone, '')), ''),
         email                = nullif(trim(coalesce(p_email, '')), ''),
         website              = nullif(trim(coalesce(p_website, '')), ''),
         logo_url             = nullif(trim(coalesce(p_logo_url, '')), ''),
         payment_instructions = nullif(trim(coalesce(p_payment_instructions, '')), ''),
         updated_at           = now(),
         updated_by           = auth.uid()
   where id = 1
  returning * into v_after;

  -- Si la tabla estaba vacía por alguna razón, crear la fila.
  if v_after.id is null then
    insert into public.company_settings (
      id, legal_name, rnc, address, city, country,
      phone, email, website, logo_url, payment_instructions,
      updated_at, updated_by
    )
    values (
      1, v_name,
      nullif(trim(coalesce(p_rnc, '')), ''),
      nullif(trim(coalesce(p_address, '')), ''),
      nullif(trim(coalesce(p_city, '')), ''),
      nullif(trim(coalesce(p_country, '')), ''),
      nullif(trim(coalesce(p_phone, '')), ''),
      nullif(trim(coalesce(p_email, '')), ''),
      nullif(trim(coalesce(p_website, '')), ''),
      nullif(trim(coalesce(p_logo_url, '')), ''),
      nullif(trim(coalesce(p_payment_instructions, '')), ''),
      now(), auth.uid()
    )
    returning * into v_after;
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, payload
  )
  values (
    auth.uid(),
    'company.update',
    'company_settings',
    jsonb_build_object(
      'before', to_jsonb(v_before),
      'after',  to_jsonb(v_after)
    )
  );

  return v_after;
end;
$$;

grant execute on function public.admin_update_company_settings(
  text, text, text, text, text, text, text, text, text, text
) to authenticated;


notify pgrst, 'reload schema';
