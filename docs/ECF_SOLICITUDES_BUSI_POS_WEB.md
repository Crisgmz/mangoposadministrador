# Solicitudes de facturación electrónica de Busi Pos Web en el panel

Última actualización: 1 nov 2026.

Busi Pos Web (repo `flutter_shop+`) deja que sus clientes soliciten la
facturación electrónica desde Configuración. Cada solicitud se avisa de servidor
a servidor a MangoPOS (`ecf-request-inbox`), y este panel la muestra en
**Facturación electrónica** (menú Comercial), junto con las solicitudes que
hacen los clientes desde la POS de MangoPOS, para atenderlas en un solo lugar.

Desde el 1 nov 2026 esas empresas pasan por **el mismo proceso que un negocio
de MangoPOS**: cada solicitud abre su propia página de alta e-CF en el panel
(datos del contribuyente, empresa en Alanube, firma de los XML de la DGII, sets
de pruebas, simulación y representaciones impresas). Lo único distinto:

- **Secuencias e-NCF y encendido** los hace el cliente en Busi Pos Web, que es
  la que emite. MangoPOS no escribe en esa base; los pasos 4 y 5 de la página
  solo dicen qué tiene que hacer el cliente.
- **Certificado:** Busi Pos Web no lo guarda ni lo manda. Si el cliente
  **autoriza** a MangoPOS a guardarlo, el operador lo carga en la página y queda
  cifrado como el de un negocio de MangoPOS (la casilla de autorización queda
  en la auditoría).
- **Clave de la Oficina Virtual:** no llega. Se le pide al cliente.

## Cómo está armado

| Pieza | Dónde vive | Estado |
|---|---|---|
| Formulario y tarjeta en Configuración | `flutter_shop+` (app) | Hecho |
| `ecf-onboarding` (recibe la solicitud, registra en Alanube, avisa) | Supabase propio de Busi Pos Web: `supabase.busiposweb.com`, servidor `2.24.119.32`, Coolify, stack `x8y0lsyo0tdmk3rwvhbicwh5` | Publicada el 29 oct |
| Credenciales de Alanube (`ALANUBE_*`, **producción**: `api.alanube.co`) | Coolify → servicio `supabase-edge-functions` de ese stack | Puestas el 31 oct |
| `ecf-request-inbox` (bandeja) | Supabase de MangoPOS (autoalojado): `supabase.mangopos.do`, servidor `31.97.40.114` | Código en `mangospos` (commit `9098ed15`); **falta publicar** (1 nov: responde "worker boot error") |
| Tabla `external_ecf_requests` | Base de MangoPOS | Migraciones en `mangospos`; **sin correr** al 1 nov (`42P01`) |
| Página "Facturación electrónica" | Este repo (`mangopos_administrador`) | Cambios **sin commit**; falta publicar |
| Alta e-CF de empresas externas: migración `20261101_0002_ecf_onboarding_external_owner.sql` y `ecf-onboarding` con `external_request_id` | `mangospos` (base y funciones de MangoPOS) | Hecho el 1 nov, **sin commit**; falta correr la migración y publicar la función (paso 9) |
| Página de alta de una empresa externa (`/facturacion-electronica/externa/:id`) | Este repo | Hecho el 1 nov, **sin commit** |

Busi Pos Web registra sus empresas en la **misma cuenta de Alanube** que
MangoPOS, como empresas asociadas de MANGOPOS SRL.

## Lo que falta, en orden

### 1. Generar el secreto compartido

`ECF_PANEL_NOTIFY_SECRET` no lo da nadie: es una contraseña que se inventa y se
pone **igual en los dos lados**. Busi Pos Web la manda en el encabezado
`X-Ecf-Panel-Secret` y la bandeja la compara.

```bash
openssl rand -hex 32
```

Guárdalo para los pasos 3 y 5. No lo pegues en el repo ni en chats.

### 2. Correr las migraciones en la base de MangoPOS

La base de MangoPOS es la de **`supabase.mangopos.do`** (autoalojada en Coolify),
la misma que usa este panel. El proyecto `sqdwjjewdqzxglvqerqt` de supabase.co
es viejo: no lo uses.

En el SQL Editor del Studio de esa base, en este orden (archivos del repo
`mangospos`, carpeta `supabase/migrations/`):

1. `20260926_0001_external_ecf_requests.sql`: crea la tabla. Necesita
   `public.is_platform_operator(uuid)`, que crea
   `supabase/migrations/0001_platform_operators.sql` de este repo. Si falta, la
   migración se detiene con un mensaje que lo dice.
2. `20261028_0001_external_ecf_requests_details.sql`: agrega teléfono,
   representante legal, sucursales, tipos de e-CF y usuario OFV.

Las dos son idempotentes. Para comprobar:

```sql
select column_name
  from information_schema.columns
 where table_schema = 'public' and table_name = 'external_ecf_requests'
   and column_name in ('phone', 'legal_rep_name', 'branches', 'ecf_types', 'ofv_user');
-- Debe devolver 5 filas.
```

Mientras no estén, la página Facturación electrónica del panel muestra
`relation "public.external_ecf_requests" does not exist` (y sigue mostrando las
solicitudes de MangoPOS).

### 3. Poner el secreto en MangoPOS y publicar la bandeja

Las funciones de MangoPOS no se publican con `supabase functions deploy` (eso es
para supabase.co): se copian al volumen del servidor con los scripts del repo
`mangospos`. Desde `~/dev/mangospos`:

1. Agrega `ECF_PANEL_NOTIFY_SECRET` en Coolify, en las variables de entorno del
   stack de Supabase de MangoPOS (servicio de edge functions).
2. Escríbela en el disco del servidor y recrea solo el contenedor de funciones,
   sin tocar la base:

   ```bash
   VAR=ECF_PANEL_NOTIFY_SECRET ADD=1 ./scripts/functions_env.sh
   VAR=ECF_PANEL_NOTIFY_SECRET APPLY=1 ./scripts/functions_env.sh
   ```

   `ADD=1` pide el valor sin mostrarlo. `APPLY=1` solo recrea si la única
   diferencia es esa variable.
3. Publica la bandeja:

   ```bash
   CHECK=1 ./scripts/deploy_edge_functions.sh ecf-request-inbox
   ./scripts/deploy_edge_functions.sh ecf-request-inbox
   ```

En este servidor no hace falta `--no-verify-jwt`: las llamadas sin token llegan a
la función, y cada función revisa su propia autorización (esta, el secreto).

### 4. Probar la bandeja

```bash
curl -s -X POST https://supabase.mangopos.do/functions/v1/ecf-request-inbox \
  -H 'Content-Type: application/json' -H 'X-Ecf-Panel-Secret: clave-falsa' -d '{}'
```

| Respuesta | Significa |
|---|---|
| `{"error":{"code":"unauthorized","message":"Secreto invalido"}}` (401) | Bien: publicada y con secreto |
| 500 `config_error` "El servidor no tiene ECF_PANEL_NOTIFY_SECRET." | Falta el secreto (paso 3, puntos 1 y 2) |
| 500 `worker boot error: failed to read path` | No está publicada (paso 3, punto 3) |

### 5. Poner el secreto en Busi Pos Web (Coolify)

En Coolify, stack de `supabase.busiposweb.com` (`x8y0lsyo0tdmk3rwvhbicwh5`),
pestaña **Environment Variables**:

- `ECF_PANEL_NOTIFY_SECRET` = el mismo valor del paso 1.
- `ECF_PANEL_NOTIFY_URL` = `https://supabase.mangopos.do/functions/v1/ecf-request-inbox`
  (si quedó con `sqdwjjewdqzxglvqerqt.supabase.co`, cámbiala: ese proyecto es
  viejo y los avisos no llegarían al panel).

Las dos ya están referenciadas en el compose, dentro de `supabase-edge-functions`
→ `environment:`. **No las pongas bajo `supabase-kong`**: ahí no le llegan a las
funciones (pasó el 31 oct).

**Ojo:** el Redeploy de Coolify NO recreó el contenedor de funciones. Después de
cambiar variables, recréalo en el servidor:

```bash
cd /data/coolify/services/x8y0lsyo0tdmk3rwvhbicwh5 && \
  docker compose -p x8y0lsyo0tdmk3rwvhbicwh5 -f docker-compose.yml up -d --no-deps supabase-edge-functions
docker exec supabase-edge-functions-x8y0lsyo0tdmk3rwvhbicwh5 sh -c \
  'for v in ECF_PANEL_NOTIFY_URL ECF_PANEL_NOTIFY_SECRET ALANUBE_JWT; do [ -n "$(printenv $v)" ] && echo "✓ $v" || echo "✗ $v"; done'
```

`--no-deps` solo toca ese contenedor: la base y la app siguen corriendo. En ese
servidor hay **otro** stack de Supabase (`y10n4yq5ytxjito5vgbz51v8`, dominio
sslip.io): no es el de Busi Pos Web.

### 6. Publicar las funciones nuevas de Busi Pos Web

El 1 nov se corrigieron en `flutter_shop+` dos cosas que afectan el QR de las
facturas electrónicas en producción. Sin la corrección, el QR podía apuntar a la
consulta de **prueba** de la DGII:

- `ecf-onboarding` ahora guarda `company_ecf_settings.environment` según la
  cuenta de Alanube (`production` con `api.alanube.co`).
- `emit-document` ahora toma la URL del timbre de `documentStampUrl`, que es como
  la manda Alanube.

Desde el repo `flutter_shop+`:

```bash
tool/deploy_edge_functions.sh
scp build/edge-functions.tar.gz root@2.24.119.32:
```

En el servidor:

```bash
cd ~ && rm -rf edge-functions && tar xzf edge-functions.tar.gz && \
  bash edge-functions/install_on_server.sh /data/coolify/services/x8y0lsyo0tdmk3rwvhbicwh5/volumes/functions
```

Debe terminar con `✓ ecf-onboarding responde`. Si alguna empresa se registró
entre el 31 oct y esta publicación, corrige su ambiente en la base de Busi Pos
Web:

```sql
update public.company_ecf_settings
   set environment = 'production'
 where alanube_company_id is not null and environment = 'sandbox';
```

Esto vale solo mientras el servidor use la cuenta de producción de Alanube.

### 7. Publicar este panel

Cambios de este repo, sin commit (hay otros cambios sin commit en el repo que no
son de esto, así que haz commit solo de estos):

- `lib/domain/models/external_ecf_request.dart`
- `lib/data/repositories/external_ecf_requests_repository.dart`
- `lib/presentation/ecf_requests/` (página nueva y el cuadro de seguimiento,
  que antes era `lib/presentation/fiscal/external_ecf_requests_section.dart`)
- `lib/presentation/fiscal/fiscal_page.dart` (ya no muestra las solicitudes)
- Borrados: `lib/presentation/fiscal/ecf_requests_section.dart` y
  `test/presentation/fiscal/ecf_requests_section_test.dart`
- `lib/app/widgets/nav_items.dart`, `lib/app/widgets/nav_badges.dart`,
  `lib/app/router/app_router.dart`, `lib/app/router/route_prefetch.dart`
- `test/domain/external_ecf_request_test.dart`,
  `test/presentation/ecf_requests/ecf_requests_page_test.dart`
- Alta e-CF de empresas externas (1 nov):
  `lib/presentation/ecf_requests/external_ecf_onboarding_page.dart`,
  `lib/domain/models/ecf_onboarding.dart` (`EcfOwner`),
  `lib/data/repositories/ecf_onboarding_repository.dart`,
  `lib/presentation/businesses/ecf_onboarding_section.dart`,
  `lib/presentation/businesses/ecf_onboarding_dialogs.dart`,
  `lib/presentation/businesses/business_detail_page.dart`,
  `test/presentation/businesses/ecf_onboarding_section_test.dart`,
  `test/presentation/ecf_requests/external_ecf_onboarding_page_test.dart`

Comprobado: `flutter analyze` limpio y todas las pruebas pasan (`flutter test`).

**Publica el panel después del paso 2.** El repositorio ya pide las columnas
nuevas; sin la migración `20261028_0001`, las solicitudes de Busi Pos Web no
cargan (la página lo dice y sigue mostrando las de MangoPOS). Coolify lo construye con el `Dockerfile` (las credenciales de
Supabase van como *Build Arguments*).

### 8. Prueba de punta a punta

1. En Busi Pos Web: Configuración → Facturación electrónica → **Solicitar
   facturación electrónica**. Llena el formulario y envía.
2. En el panel: Facturación electrónica. Debe aparecer la fila con la etiqueta
   "Busi Pos Web"; al abrirla, teléfono, representante, sucursales,
   comprobantes y usuario OFV.

**Alanube está en producción:** enviar una solicitud registra la empresa en
Alanube de verdad, con el certificado que se suba. Haz la prueba con una
solicitud real, no con datos inventados.

### 9. Publicar el alta e-CF de empresas externas (1 nov)

En este orden; la función nueva lee columnas que crea la migración.

1. En el SQL Editor de la base de **MangoPOS** (`supabase.mangopos.do`), corre
   `20261101_0002_ecf_onboarding_external_owner.sql` (repo `mangospos`,
   `supabase/migrations/`). Es idempotente. Cambia la llave de
   `ecf_onboarding` a `id` y deja que el alta y los sets de pruebas sean de un
   negocio **o** de una solicitud externa. Los negocios de MangoPOS no cambian.
   Reversa: `..._ROLLBACK.sql` (borra el avance de las empresas externas).
2. Publica la función, desde la carpeta del repo `mangospos`:

   ```bash
   cd ~/dev/mangospos
   CHECK=1 ./scripts/deploy_edge_functions.sh ecf-onboarding
   ./scripts/deploy_edge_functions.sh ecf-onboarding
   ```
3. Publica el panel (paso 7).

Prueba local de la migración (Postgres desechable, no toca ninguna base):
`bash supabase/tests/ecf_onboarding_external_owner_local_test.sh` en `mangospos`.

## Atender una solicitud

1. Abre la fila en Facturación electrónica: lleva a la página de alta de esa
   empresa. **Datos y seguimiento** abre el cuadro de estado y notas: ponla
   **En proceso**.
2. **Datos del contribuyente:** "Capturar datos" arranca con el RNC, la razón
   social, el nombre comercial y el correo que mandó Busi Pos Web. Completa la
   dirección fiscal, la provincia y el municipio tal como están en la DGII.
   Pide al cliente la clave de la Oficina Virtual (no llega al panel).
3. **Certificado digital:** si el cliente autoriza que MangoPOS lo guarde,
   cárgalo con **Cargar certificado** y marca la casilla de autorización. Sin
   eso no se pueden firmar los sets de pruebas desde el panel.
4. **Empresa en Alanube:**
   - Si Busi Pos Web la registró, ya aparece con su ID ("Registrada por su
     app").
   - Si no (casi siempre una contraseña equivocada o un archivo que no es el
     certificado de firma), lo mejor es que el cliente reenvíe desde su tarjeta
     ("Reenviar con otro certificado"). Si la vinculas o la das de alta desde la
     página, Busi Pos Web no se entera: toca **Copiar SQL para Busi Pos Web** y
     córrelo en el SQL Editor de **Busi Pos Web** (es el mismo de "Enlazar a
     mano", abajo).
5. **Certificación DGII:** igual que un negocio de MangoPOS (postulación, firma
   de XML, pruebas de datos, aprobaciones comerciales, simulación y
   representaciones impresas). Al terminar, **La DGII ya lo autorizó**.
6. **Secuencias e-NCF:** el cliente pide sus secuencias (E31, E32…) en la
   Oficina Virtual y las carga en su tarjeta, **una por sucursal**: dos
   sucursales con el mismo rango emitirían el mismo e-NCF.
7. **Encender:** el cliente enciende la facturación electrónica en su tarjeta.
   Al encender se comprueba que el RNC de las facturas coincida con el de la
   empresa en Alanube. Pídele una venta de prueba pequeña en E32.
8. Márcala **Atendida** en Datos y seguimiento.

### Enlazar a mano una empresa que ya existía en Alanube

Primero confirma en el portal de Alanube que esa empresa tiene el certificado
correcto. Luego, en el SQL Editor de **Busi Pos Web** (no en el de MangoPOS),
cambia `<company_id>` por el "Empresa (id allá)" del panel y `<ULID>` por el id
de Alanube (el botón **Copiar SQL para Busi Pos Web** de la página ya lo trae
lleno):

```sql
update public.ecf_onboarding
   set alanube_company_id = '<ULID>',
       company_linked_via = 'existing',
       company_linked_at  = now()
 where company_id = '<company_id>';

insert into public.company_ecf_settings (company_id, alanube_company_id, environment)
values ('<company_id>', '<ULID>', 'production')
on conflict (company_id) do update
  set alanube_company_id = excluded.alanube_company_id,
      environment        = excluded.environment;
```

### Solicitudes que no llegaron al panel

Las que se enviaron antes de configurar el secreto no se avisaron, y no hay
reintento automático. Para verlas, en la base de Busi Pos Web:

```sql
select company_id, rnc, legal_name, contact_name, contact_phone,
       requested_at, alanube_company_id
  from public.ecf_onboarding
 where requested_at is not null and notified_at is null;
```

## Pendiente (fuera de este proceso)

- **Cron de reintentos:** cada venta se emite al cobrar. Si falla, solo se
  reintenta con "Emitir a DGII" en Comprobantes. Falta llamar `emit-document` en
  modo batch cada minuto.
- **Nota de crédito E34:** Busi Pos Web no la emite. Anular una venta no avisa a
  la DGII.
- **Secuencias y encendido desde el panel:** siguen en Busi Pos Web a
  propósito (MangoPOS no escribe en su base). El panel no ve sus secuencias.
