-- ============================================================================
-- Seed — Super Owner inicial: Mangopos.do@gmail.com
--
-- Crea (o reutiliza si ya existe) el usuario `mangopos.do@gmail.com` en
-- `auth.users` con la contraseña temporal `12345678`, lo registra como
-- `super_owner` en `public.platform_operators` y deja activado el flag
-- `must_change_password` para que la consola lo obligue a cambiarla en su
-- primer inicio de sesión.
--
-- Pre-requisito: haber aplicado la migración
-- `0002_super_owner_and_password_change.sql`.
--
-- Cómo correrlo: pegar todo el archivo en Supabase Studio → SQL Editor y
-- ejecutar (debe correrse con privilegios de servicio; el SQL Editor de Studio
-- ya corre como `postgres`). Es idempotente: pueden re-ejecutarlo sin romper
-- nada (no duplica el usuario ni la fila en `platform_operators`).
-- ============================================================================

create extension if not exists pgcrypto;

do $$
declare
  v_email text := 'mangopos.do@gmail.com';
  v_password text := '12345678';
  v_uid uuid;
begin
  -- 1) Buscar el usuario por email (case-insensitive: Supabase guarda lower).
  select id into v_uid
  from auth.users
  where lower(email) = lower(v_email)
  limit 1;

  -- 2) Si no existe, crearlo en auth.users + auth.identities.
  if v_uid is null then
    v_uid := gen_random_uuid();

    insert into auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      email_change,
      email_change_token_new,
      recovery_token
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      v_uid,
      'authenticated',
      'authenticated',
      lower(v_email),
      crypt(v_password, gen_salt('bf')),
      now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      '{}'::jsonb,
      now(),
      now(),
      '',
      '',
      '',
      ''
    );

    insert into auth.identities (
      provider_id,
      user_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at
    )
    values (
      v_uid::text,
      v_uid,
      jsonb_build_object(
        'sub', v_uid::text,
        'email', lower(v_email),
        'email_verified', true
      ),
      'email',
      now(),
      now(),
      now()
    );
  else
    -- Si ya existía, sólo nos aseguramos que la contraseña temporal y la
    -- confirmación de email queden como las queremos para el primer login.
    update auth.users
       set encrypted_password = crypt(v_password, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_uid;
  end if;

  -- 3) Registrarlo como super_owner con cambio de contraseña obligatorio.
  insert into public.platform_operators (user_id, role, notes, must_change_password)
  values (v_uid, 'super_owner', 'Super owner inicial — Mangopos.do', true)
  on conflict (user_id) do update
    set role = 'super_owner',
        must_change_password = true,
        notes = coalesce(public.platform_operators.notes, excluded.notes);
end
$$;
