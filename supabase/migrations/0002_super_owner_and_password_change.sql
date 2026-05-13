-- ============================================================================
-- Migración 0002 — super_owner + must_change_password
--
-- 1) Permite el rol 'super_owner' en `platform_operators`.
-- 2) Añade la columna `must_change_password` para forzar el cambio de
--    contraseña al primer login desde la consola.
-- 3) Expone dos RPCs:
--      - `must_change_password()`        — el cliente consulta su propio flag.
--      - `clear_must_change_password()`  — el cliente limpia su propio flag
--        después de actualizar la contraseña vía Supabase Auth.
--
-- Aplicar contra el mismo proyecto Supabase de `mangospos`.
-- Idempotente.
-- ============================================================================

-- 1) Ampliar el check de roles para incluir 'super_owner'.
alter table public.platform_operators
  drop constraint if exists platform_operators_role_check;

alter table public.platform_operators
  add constraint platform_operators_role_check
  check (role in ('platform_operator', 'platform_finance', 'super_owner'));

-- 2) Flag de cambio de contraseña forzado.
alter table public.platform_operators
  add column if not exists must_change_password boolean not null default false;

comment on column public.platform_operators.must_change_password is
  'Si true, la consola obliga al usuario a cambiar su contraseña antes de operar.';

-- 3a) Lectura del flag por el propio usuario.
create or replace function public.must_change_password(uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select must_change_password
    from public.platform_operators
    where user_id = uid
  ), false);
$$;

comment on function public.must_change_password(uuid) is
  'Retorna true si el usuario debe cambiar su contraseña antes de operar la consola.';

grant execute on function public.must_change_password(uuid) to authenticated;

-- 3b) Limpieza del flag tras cambio exitoso (solo afecta al usuario que llama).
create or replace function public.clear_must_change_password()
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.platform_operators
     set must_change_password = false
   where user_id = auth.uid();
$$;

comment on function public.clear_must_change_password() is
  'El usuario autenticado limpia su propio flag must_change_password después de cambiar su contraseña.';

grant execute on function public.clear_must_change_password() to authenticated;
