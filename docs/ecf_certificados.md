# Certificado de la solicitud e-CF

El panel muestra el nombre y la fecha del certificado recibido y permite
usarlo al registrar la empresa o firmar los sets e-CF, ACECF y simulación.
El archivo y su contraseña permanecen cifrados en el servidor; el panel
envía únicamente la elección del certificado guardado.

## Publicación

Los cambios requieren este panel y el repositorio `mangospos`:

1. Aplicar en la base de MangoPOS
   `supabase/migrations/20261027_0001_ecf_onboarding_certificate.sql`.
2. Conservar la misma `ECF_CREDENTIALS_KEY` que usa el entorno para la OFV.
3. Publicar `supabase/functions/ecf-onboarding/index.ts` y el nuevo módulo
   `supabase/functions/_shared/ecf-certificate.ts` mediante el despliegue
   habitual de Edge Functions del entorno self-hosted.
4. Publicar la POS con el aviso actualizado y
   `accept_certificate_storage: true`, y después este panel.

Las solicitudes nuevas de esa versión de la POS conservan el certificado,
incluso si el registro en Alanube queda pendiente. Las POS anteriores siguen
registrando la solicitud sin guardar el certificado.

## Solicitudes anteriores

En el detalle del negocio, abrir **Facturación electrónica → Datos del
contribuyente → Cargar certificado**. Indicar el `.p12` o `.pfx` del
contribuyente y su contraseña. Esto permite guardarlo sin volver a crear la
empresa en Alanube. El servidor verifica el archivo, la contraseña y su
vigencia antes de reemplazar el certificado guardado.

Al firmar, **Usar certificado de la solicitud** utiliza la copia del servidor.
**Subir otro certificado** utiliza ese otro archivo solo para la operación.

El rollback de la migración elimina las copias guardadas y requiere volver a
cargarlas; primero se debe publicar un backend que no use esas columnas.
