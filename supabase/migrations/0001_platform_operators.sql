-- ============================================================================
-- Migración 0001 — platform_operators (whitelist de operadores de la consola)
--
-- Crea la tabla `platform_operators` y la función `is_platform_operator()`
-- usada por la consola `mangopos_admin` para autorizar acceso transversal
-- a los datos de todos los negocios.
--
-- Aplicar contra el proyecto Supabase de `mangospos`.
-- ============================================================================

-- 1) Tabla
create table if not exists public.platform_operators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'platform_operator'
    check (role in ('platform_operator', 'platform_finance')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  notes text
);

comment on table public.platform_operators is
  'Whitelist de usuarios autorizados como operadores de la plataforma (consola mangopos_admin).';

-- 2) RLS — solo los operadores pueden leer la tabla.
alter table public.platform_operators enable row level security;

drop policy if exists "platform_operators read self or operator" on public.platform_operators;
create policy "platform_operators read self or operator"
on public.platform_operators
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.platform_operators po
    where po.user_id = auth.uid()
  )
);

-- Inserciones / borrados solo via service_role (no expuesto al cliente).

-- 3) Función helper — usable desde el cliente vía rpc('is_platform_operator')
--    y desde políticas RLS de otras tablas.
create or replace function public.is_platform_operator(uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_operators
    where user_id = uid
  );
$$;

comment on function public.is_platform_operator(uuid) is
  'Retorna true si el uuid dado (default: auth.uid()) está en platform_operators.';

grant execute on function public.is_platform_operator(uuid) to authenticated;

-- 4) Seed comentado — el equipo de Mango debe correr esto manualmente con el
--    user_id real de cada operador autorizado.
--
-- insert into public.platform_operators (user_id, role, notes)
-- values
--   ('00000000-0000-0000-0000-000000000000', 'platform_operator', 'Cristian — admin');
