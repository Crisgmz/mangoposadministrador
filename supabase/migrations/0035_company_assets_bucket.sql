-- ---------------------------------------------------------------------------
-- 0035_company_assets_bucket.sql
--
-- Bucket de Supabase Storage para assets de la empresa (logo, marca, etc).
-- Usado por el formulario /configuracion para subir el logo de MangoPOS
-- desde la PC. La URL pública se guarda en `company_settings.logo_url`
-- y el PDF de facturas la descarga + embebe.
--
-- Bucket: `company-assets`
--   - public: true (las URLs van en facturas que ven los clientes)
--   - file_size_limit: 1 MB (logos chicos; suficiente para PNG/JPEG/WebP/SVG)
--   - allowed_mime_types: imágenes comunes
--
-- Policies (sobre storage.objects):
--   - SELECT: anyone (público)
--   - INSERT/UPDATE/DELETE: solo platform operators
-- ---------------------------------------------------------------------------

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'company-assets',
  'company-assets',
  true,
  1048576,
  array['image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/svg+xml']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- Policies del bucket.
drop policy if exists "company-assets public read" on storage.objects;
create policy "company-assets public read"
on storage.objects
for select
to public
using (bucket_id = 'company-assets');

drop policy if exists "company-assets operators write" on storage.objects;
create policy "company-assets operators write"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'company-assets'
  and public.is_platform_operator()
);

drop policy if exists "company-assets operators update" on storage.objects;
create policy "company-assets operators update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'company-assets'
  and public.is_platform_operator()
)
with check (
  bucket_id = 'company-assets'
  and public.is_platform_operator()
);

drop policy if exists "company-assets operators delete" on storage.objects;
create policy "company-assets operators delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'company-assets'
  and public.is_platform_operator()
);
