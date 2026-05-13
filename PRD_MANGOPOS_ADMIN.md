# PRD — MangoPOS Admin (Operator Console en Flutter)

> **Nombre tentativo del proyecto:** `mangopos_admin`
> **Tipo de aplicación:** Aplicación Flutter (desktop primero — macOS / Windows — y web), multiplataforma.
> **Repos de referencia:**
> - Prototipo UI/UX: [`mango-overview-desk/`](.) (React + Vite + shadcn/ui, con `mockData`)
> - Backend real y modelo de datos: [`mangospos/`](../mangospos) (Flutter POS + Supabase, schema completo en `mangospos/backend data structure/schema.txt`)
> **Versión PRD:** 1.0 — 2026-05-07
> **Idioma del producto:** Español (es-DO). Mercado: República Dominicana.

---

## 1. Resumen ejecutivo

`mangopos_admin` es la **consola del operador** de la plataforma MangoPOS. No es la app de venta (esa es `mangospos`). Es la herramienta interna que el equipo de Mango usa para:

1. Vigilar en tiempo real el estado de **todos** los negocios suscritos (multi-tenant cross-business).
2. Reaccionar a incidentes operativos: agentes de impresión caídos, secuencias NCF a punto de agotarse, fallas de impresoras, membresías vencidas.
3. Cobrar y administrar **facturación de membresías** (planes Trial/Free/Basic/Pro).
4. Auditar acciones críticas hechas por usuarios dentro de los negocios (anulaciones, eliminaciones, voids).
5. Activar/desactivar negocios, regenerar facturas, exportar PDF y enviar por WhatsApp.

El prototipo `mango-overview-desk` ya define la **forma final del producto**: navegación, módulos, métricas, badges, layout. Este PRD especifica cómo construirlo en Flutter sobre el backend real de `mangospos`.

---

## 2. Visión y objetivos

### 2.1 Visión
> Una sola pantalla donde el equipo de Mango ve, en menos de 5 segundos, el estado de la plataforma — y con un clic más, entra al negocio que requiere atención.

### 2.2 Objetivos de negocio (12 meses)
| KPI | Baseline | Objetivo |
|---|---|---|
| Tiempo medio de detección de agente caído | ~horas (cliente reporta) | < 2 minutos |
| Cobranza de membresías cobradas a tiempo | manual / hojas | ≥ 95% en sistema |
| Tickets de soporte por NCF agotado | reactivo | 0 (alerta a 200 NCF) |
| Fallas de impresión sin diagnóstico | inciertas | 100% trazables por negocio |

### 2.3 No-objetivos (out of scope para v1)
- No ejecuta operaciones de venta (eso es `mangospos`).
- No edita catálogo, productos, mesas o recetas del negocio.
- No reemplaza al panel del dueño dentro de `mangospos`.
- No incluye chat / soporte integrado en v1 (se delega a WhatsApp).

---

## 3. Personas y permisos

### 3.1 Personas
| Rol | Descripción | Necesita |
|---|---|---|
| **Operador de plataforma** (Mango) | Equipo interno (soporte, ops, finanzas) | Todo: ver, alertar, cobrar, activar/desactivar |
| **Finanzas Mango** | Subset del operador | Solo módulo Facturación + reportes de cobros |
| **Owner del negocio** | (Lectura limitada — *fuera de v1*) | Vista solo de su propio negocio. **Diferido.** |

### 3.2 Modelo de acceso
- v1: **un solo rol** — `platform_operator`. Todo lo accede.
- Auth: Supabase Auth (mismo proyecto Supabase de `mangospos`).
- El rol se determina por una lista blanca: tabla nueva `platform_operators (user_id, role, created_at)` o claim JWT custom (`role: 'platform_operator'`).
- **Crítico (RLS):** la app necesita leer datos transversales a todos los `business_id`. Las políticas RLS actuales de `mangospos` están filtradas por tenant (vía `memberships` / `user_businesses`). Para esta app:
  - **Opción A (recomendada):** crear funciones RPC `SECURITY DEFINER` que devuelvan agregados/listados sin RLS, validando internamente que el caller esté en `platform_operators`.
  - **Opción B:** políticas RLS adicionales `USING (auth.jwt() ->> 'role' = 'platform_operator')` aplicadas a las tablas que lee la consola.
  - **No usar la `service_role` key en el cliente.** Toda escritura privilegiada va por RPC.

---

## 4. Stack técnico

| Capa | Decisión | Justificación |
|---|---|---|
| Framework | **Flutter 3.x (Dart ^3.8)** | Mismo stack que `mangospos`, compartimos paquetes y conocimiento del equipo. |
| Plataformas v1 | **macOS, Windows, Web** | El operador trabaja desde laptop. Móvil más adelante (BottomNav del prototipo ya está pensado). |
| State management | **Riverpod (`flutter_riverpod`)** | Convención del repo `mangospos` (CLAUDE.md). |
| Routing | **`go_router`** | Convención del repo. |
| Backend | **Supabase** (mismo proyecto que `mangospos`) | Datos en común, RLS, Realtime, Storage. |
| Realtime | **`supabase_flutter` Realtime channels** | Para `print_jobs`, `agent_nodes.last_seen`, `fiscal_documents`. |
| Charts | **`fl_chart`** | Ya usado en `mangospos`. |
| Iconos | **`hugeicons`** + Material | Convención del repo. |
| PDFs | **`pdf` + `printing`** | Para facturas de membresía descargables. |
| WhatsApp share | URL scheme `https://wa.me/?text=...` + `url_launcher` | El prototipo lo hace con un PDF más texto. |
| Auth | **`supabase_flutter`** (email/password + OTP opcional) | — |
| Tests | `flutter_test`, golden tests para tarjetas de métrica | — |
| CI | Igual a `mangospos` (a definir, fuera de PRD) | — |

### 4.1 Paquetes nuevos a evaluar (no presentes en `mangospos`)
- `data_table_2` o `pluto_grid`: tablas grandes con scroll/sticky header (BusinessTable).
- `responsive_framework` o breakpoint manual: layout sidebar/topbar/bottomnav adaptativo.
- `flutter_quill` o similar: **no necesario** en v1.

---

## 5. Arquitectura del proyecto

Espejo de la estructura por capas de `mangospos` (ver `mangospos/CLAUDE.md`):

```
mangopos_admin/
├── lib/
│   ├── main.dart                       # bootstrap, Supabase init, GoRouter
│   ├── app/
│   │   ├── router/                     # rutas: dashboard, negocios, fiscal, ...
│   │   ├── theme/                      # tokens equivalentes a tailwind del prototipo
│   │   ├── widgets/                    # AppShell, Sidebar, Topbar, BottomNav
│   │   └── di/                         # providers globales (supabase, repos)
│   ├── core/
│   │   ├── auth/                       # platform_operator gate
│   │   ├── network/                    # supabase client, error mapping
│   │   ├── realtime/                   # wrapper de canales Realtime
│   │   ├── format/                     # formatRD, formatRelative (es-DO)
│   │   └── utils/
│   ├── data/
│   │   ├── datasources/
│   │   │   ├── businesses_remote.dart  # consulta `businesses` + agregados
│   │   │   ├── fiscal_remote.dart
│   │   │   ├── print_remote.dart
│   │   │   ├── audit_remote.dart
│   │   │   ├── billing_remote.dart
│   │   │   └── alerts_remote.dart
│   │   ├── models/
│   │   │   ├── business_overview.dart  # equivalente a Business del prototipo
│   │   │   ├── invoice.dart
│   │   │   ├── print_job.dart
│   │   │   ├── audit_log.dart
│   │   │   └── ncf_status.dart
│   │   └── repositories/
│   ├── domain/
│   │   ├── models/
│   │   ├── repositories/               # interfaces
│   │   └── usecases/
│   └── presentation/
│       ├── dashboard/                  # Vista global
│       ├── businesses/                 # Lista + detalle
│       ├── fiscal/                     # NCF
│       ├── printing/                   # Agentes + jobs
│       ├── audit/                      # Auditoría
│       ├── alerts/                     # Centro de alertas
│       ├── billing/                    # Facturación de membresía
│       └── shell/                      # AppShell + responsive
├── test/
├── pubspec.yaml
└── docs/
    └── PRD.md (este archivo, copiado)
```

**Reglas de oro** (heredadas de `mangospos/CLAUDE.md`):
- `presentation` no llama a Supabase directo; pasa por `repository`.
- `repository` retorna modelos del dominio, no DTOs crudos.
- Realtime se gestiona en `core/realtime` y se expone por providers Riverpod.

---

## 6. Mapeo: prototipo → backend real

El prototipo usa `mockData.ts` con un tipo `Business`. La fuente real son varias tablas de `mangospos`. Esta es la traducción uno-a-uno:

### 6.1 Tabla `businesses` en `mockData` ↔ Supabase

| Campo prototipo | Origen real | Notas |
|---|---|---|
| `id` | `businesses.id` | uuid |
| `name` | `businesses.business_name` | |
| `domain` | `businesses.domain` | regex `*.mangopos.do` |
| `status` | `businesses.status` | `active` / `inactive` |
| `type` (cafe, retail…) | **NO existe** en `businesses` actual | **Gap → ver §10.1** |
| `plan` | `memberships.plan_type` (latest active) | `trial`/`free`/`basic`/`pro` |
| `planEndDate` | `memberships.end_date` | |
| `totalUsers` | count(`user_businesses` o `memberships` por `business_id`) | RPC agregado |
| `salesToday` | count(`orders`) hoy con `business_id` (vía `table_sessions` join) o vía `payments` | RPC agregado |
| `revenueToday` | sum(`payments.amount`) hoy | |
| `ticketAverage` | `revenueToday / salesToday` | computado |
| `ncfIssuedToday` | count(`fiscal_documents`) hoy | |
| `ncfAvailable` | sum(`ncf_sequences.range_end - current_number`) activos | |
| `ncfStatus` | derivado: <50 = crítico, <200 = warning, else OK | |
| `agentStatus` | derivado de `agent_nodes.last_seen`: ≤2min en línea, ≤15min tardío, >15min desconectado, sin row = sin agente | |
| `agentLastSeen` | `agent_nodes.last_seen` | |
| `agentName` | `agent_nodes.name` | |
| `printJobsToday` | count(`print_jobs`) hoy | |
| `printFailures` | count(`print_jobs.status='failed'`) hoy | |
| `printSuccessRate` | `(jobs - failures) / jobs * 100` | |
| `openSessions` | count(`cash_register_sessions.status='open'`) | |
| `openTables` | count(`table_sessions.closed_at IS NULL`) | |
| `weekRevenue` | sum(`payments.amount`) últimos 7 días | |
| `lastWeekRevenue` | sum(`payments.amount`) días [-14, -7] | |

> **Recomendación:** crear una **vista o RPC `business_overview(business_id, day)`** que devuelva estos agregados precalculados. Llamarla desde el cliente con `select`. Para el listado global: RPC `platform_overview()` que devuelve un array.

### 6.2 `printJobs` en `mockData` ↔ `public.print_jobs`
1:1 — el prototipo ya usa los campos: `id`, `businessId`, `createdAt`, `status`, `error`, `printerIp`, `printerName` (este último viene por join con `printers.name`).

### 6.3 `auditLogs` en `mockData` ↔ realidad
**Gap.** No hay tabla `audit_logs` única. Las "acciones críticas" hoy se infieren de:
- `fiscal_documents.status='cancelled'` con `cancelled_by`, `cancelled_at`, `cancellation_reason`.
- `payments.status='refunded'|'cancelled'`.
- `orders.status='canceled'`.
- (Posible) eliminación de `order_items` — sin auditoría persistente actualmente.

→ **Decisión necesaria** (ver §10.2):
- Opción A: crear tabla `audit_logs` general y triggers. Requiere migración en `mangospos`.
- Opción B (v1): en la consola, **componer** la vista de auditoría con UNION de las 3 fuentes anteriores vía RPC `platform_audit_feed(limit, since)`.

### 6.4 `Invoice` (membresía) ↔ realidad
**Gap mayor.** El prototipo administra facturas de plan en `billingStore.ts` (Zustand local). En `mangospos` no existe tabla equivalente. Lo más cercano: `memberships` (plan + dates) y `fiscal_documents` (pero esos son comprobantes fiscales del negocio a sus clientes finales, **no** la facturación de Mango al negocio).

→ **Hay que crear backend nuevo** (ver §10.3): tablas `platform_invoices` + `platform_invoice_payments` + RPC `generate_membership_invoice(business_id, period)`.

---

## 7. Módulos de la aplicación

> Cada módulo replica la pantalla del prototipo, citada por archivo. Si discrepa con este PRD, gana este PRD.

### 7.1 Vista global (Dashboard) — ruta `/`
**Referencia:** [`src/pages/Dashboard.tsx`](src/pages/Dashboard.tsx).

**Layout:**
- Header con hora local AST y subtítulo "X negocios activos".
- 2 filas de 4 `MetricCard`:
  - Negocios activos · Ingresos hoy · NCF emitidos · Agentes en línea
  - Fallas de impresión 24h · Membresías por vencer · Ticket promedio · Tendencia semanal
- Sección con `RevenueChart` (12 horas) + `AlertsPanel` lateral.
- Tabla `BusinessTable` al final.

**Datos:** RPC `platform_overview()` → entrega `{metrics, hourly_revenue[12], businesses[], alerts[]}`.

**Realtime:** suscribir canal a:
- `agent_nodes` (UPDATE de `last_seen`).
- `print_jobs` (INSERT con `status='failed'`).
- `payments` (INSERT) → invalidar tarjeta "Ingresos hoy".

**Refresh policy:** además de Realtime, polling cada 60s como fallback.

**Aceptación:**
- [ ] Carga inicial < 1.5s con red estable y caché caliente.
- [ ] Reloj actualiza cada segundo, en zona `America/Santo_Domingo`.
- [ ] Una fila roja (negocio crítico) destaca visualmente.
- [ ] Click en `MetricCard` "Membresías por vencer" navega a `/facturacion?filter=expiring`.

---

### 7.2 Negocios — rutas `/negocios` y `/negocios/:id`
**Referencias:** [`src/pages/Negocios.tsx`](src/pages/Negocios.tsx), [`src/pages/BusinessDetail.tsx`](src/pages/BusinessDetail.tsx).

**Listado (`/negocios`):**
- Tabla con todas las columnas del prototipo: Negocio + dominio · Tipo · Plan · Agente · NCF · Ingresos hoy · Ventas hoy · Ticket prom · Estado · Acciones.
- Filtros: status (active/inactive), plan, agentStatus, ncfStatus.
- Búsqueda por nombre / dominio.
- Orden por columna (default: ingresos hoy desc).
- Acción rápida: toggle activar/desactivar (con confirmación).

**Detalle (`/negocios/:id`):**
- Header: nombre, dominio, badges (plan, agente, NCF, status), botón Activar/Desactivar.
- Identity strip: tipo, ID, usuarios, días restantes de membresía.
- Métricas de hoy: ingresos, ticket promedio, cajas abiertas, semana actual + tendencia.
- 2 tarjetas paralelas:
  - **Facturación fiscal** — NCF emitidos hoy, NCF disponibles, ITBIS estimado (`revenueToday * 0.18`).
  - **Agente local** — nombre, último ping, jobs hoy, tasa de éxito.
- Tabla **Fallas de impresión recientes** (últimas N de `print_jobs.status='failed'` para este `business_id`).
- Sección **Facturación de membresía** — listado de `platform_invoices` del negocio, con acciones por fila (descargar PDF, marcar pagada, anular, enviar WhatsApp).
- Sección **Auditoría reciente** — feed de acciones críticas del negocio.

**Aceptación:**
- [ ] Botón Desactivar pide confirmación, ejecuta `update businesses set status='inactive'` vía RPC con audit log.
- [ ] "Generar + WhatsApp" produce un PDF con el branding de Mango y abre `wa.me` con texto y URL al PDF subido a Storage.
- [ ] Si el negocio no existe → 404 amigable.

---

### 7.3 Fiscal / NCF — ruta `/fiscal`
**Referencia:** [`src/pages/Fiscal.tsx`](src/pages/Fiscal.tsx).

**Contenido:**
- Tabla ordenada por `ncf_available ASC` (los más críticos arriba).
- Columnas: Negocio · Emitidos hoy · Disponibles · ITBIS estimado · Estado.
- Tarjeta de política: crítico <50, warning <200.
- Click en fila → `/negocios/:id`.

**Reglas de negocio (RD):**
- ITBIS = 18%.
- NCF disponibles = suma de `ncf_sequences.range_end - current_number` con `is_active=true` y `expiration_date >= today`.
- Distinguir tipos NCF (B01, B02, etc.) — al menos en tooltip.
- Campo `expiration_date < 30d` también dispara warning.

**v1.5:**
- Vista por tipo de NCF (B01 consumidor final vs B02 crédito fiscal vs E-CF).
- Botón "Solicitar nuevas secuencias" — placeholder que registra una solicitud y manda email al equipo de Mango.

---

### 7.4 Impresión — ruta `/impresion`
**Referencia:** [`src/pages/Impresion.tsx`](src/pages/Impresion.tsx).

**Contenido:**
- Sección **Agentes**: grid de tarjetas, una por negocio: nombre del agente, status badge, jobs/fallas/éxito hoy, último ping.
- Sección **Fallas recientes**: tabla unificada plataforma (últimas 50): Hora · Negocio · Impresora · IP · Error.

**Datos:** RPC `platform_print_overview()` y `platform_recent_failed_print_jobs(limit)`.

**Realtime:** canal sobre `print_jobs` filtrando `status='failed'`. Toast (snackbar) cuando llega uno nuevo.

**v1.5:**
- Acción "Reintentar" sobre un job fallido (RPC `retry_print_job(id)`).
- Drill-down por impresora con histórico 7d.

---

### 7.5 Auditoría — ruta `/auditoria`
**Referencia:** [`src/pages/Auditoria.tsx`](src/pages/Auditoria.tsx).

**Contenido:**
- Feed cronológico de acciones críticas en toda la plataforma.
- Cada fila: badge de severidad (info/warning/critical), nombre del negocio, razón, tabla afectada, usuario, "hace X tiempo".

**Fuentes (UNION en RPC `platform_audit_feed(since, limit)`):**
1. `fiscal_documents` con `status='cancelled'` → `action='void_fiscal_document'`, severity=critical.
2. `payments` con `status IN ('refunded','cancelled')` → `action='void_payment'`, severity=warning.
3. `orders` con `status='canceled'` → `action='cancel_order'`, severity=info.

**v1.5 (requiere migración en `mangospos`):**
- Tabla `audit_logs` general con triggers en eliminaciones de `order_items`, `menu_items`.
- Filtros: severidad, negocio, rango de fechas.
- Export CSV.

---

### 7.6 Alertas — ruta `/alertas`
**Referencia:** [`src/pages/Alertas.tsx`](src/pages/Alertas.tsx) + [`src/components/dashboard/AlertsPanel.tsx`](src/components/dashboard/AlertsPanel.tsx).

**Tipos de alerta v1:**
| Tipo | Trigger | Severidad |
|---|---|---|
| Agente desconectado | `agent_nodes.last_seen` > 15 min | critical |
| NCF críticamente bajo | `ncf_available` < 50 | critical |
| NCF advertencia | `ncf_available` < 200 | warning |
| Membresía vencida | `memberships.end_date < now` | critical |
| Membresía por vencer | `end_date - now ≤ 7d` | warning |
| NCF próximo a expirar (fecha) | `expiration_date - now ≤ 30d` | warning |

**Comportamiento:**
- Lista clickeable: cada alerta linkea a `/negocios/:id`.
- Contador en sidebar (badge rojo si hay críticas).
- En Dashboard se muestra el panel con scroll interno; en `/alertas` ocupa el ancho completo.

**v1.5:**
- "Marcar como vista" (snooze 1h) — requiere tabla `platform_alert_acks (operator_id, alert_key, acked_until)`.
- Notificaciones de escritorio nativas vía `local_notifier` o equivalente.

---

### 7.7 Facturación — ruta `/facturacion`
**Referencia:** [`src/pages/Facturacion.tsx`](src/pages/Facturacion.tsx) + [`src/store/billingStore.ts`](src/store/billingStore.ts).

**Modelo:** facturas de **membresía** (Mango → negocio), no fiscales del negocio a sus clientes.

**Estados:** `pending`, `paid`, `expired`, `void`.

**Tarifas (de `planMonthlyFee`):**
| Plan | Tarifa mensual (DOP) |
|---|---|
| Trial | 0 |
| Free | 0 |
| Basic | 1,500 |
| Pro | 4,500 |
> ITBIS 18% calculado sobre el monto. Total = monto + ITBIS.

**Pantalla:**
- 4 métricas: MRR activo, Cobrado histórico, Por cobrar, Vencido.
- Filtros: Todas / Pendientes / Pagadas / Vencidas / Anuladas.
- Tabla: Factura · Negocio · Plan · Monto · ITBIS · Total · Vence · Estado · Acciones.
- Botón **"Generar facturas del mes"**: bulk → para cada negocio activo con plan ≠ free/trial sin factura del mes en curso, crea una factura `pending` con vencimiento +15 días.

**Acciones por factura:**
- Marcar como pagada (selector de método: transfer / card / cash).
- Marcar como vencida.
- Anular.
- Descargar PDF.
- Enviar por WhatsApp (genera link `wa.me/${phone}?text=…`).

**Backend nuevo** (ver §10.3):
```sql
create table public.platform_invoices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  number text not null unique,           -- MPOS-YYYYMM-XXXX
  plan text not null,                    -- snapshot del plan al emitir
  amount numeric not null,
  itbis numeric not null,
  total numeric not null,
  issue_date timestamptz not null default now(),
  due_date timestamptz not null,
  paid_date timestamptz,
  payment_method text,                   -- transfer | card | cash
  status text not null default 'pending', -- pending|paid|expired|void
  notes text,
  voided_by uuid,
  voided_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index on public.platform_invoices (business_id, issue_date desc);
create index on public.platform_invoices (status);
```

**Cron / Edge function:**
- Job nocturno (Supabase Scheduled Function) que mueve facturas a `expired` cuando `due_date < now()` y `status='pending'`.
- Job 1° de cada mes que llama `bulk_generate_membership_invoices()`.

**Aceptación:**
- [ ] Generar bulk no duplica facturas del mismo período.
- [ ] PDF descargable con número, RNC del negocio, totales, métodos de pago de Mango.
- [ ] Marcar pagada registra `paid_date`, método y `created_by` (operador).
- [ ] Filtros en URL (`?filter=pending`).

---

## 8. Diseño / sistema visual

Replicar el lenguaje del prototipo:

- **Tipografía:** display + sans (equivalente a la del prototipo). Usar `google_fonts` (Inter o similar).
- **Tokens de color:** mapear `--background`, `--foreground`, `--primary`, `--accent`, `--success`, `--warning`, `--destructive`, `--muted`, `--card`, `--border` desde `index.css` del prototipo a un `ThemeData` con `ColorScheme`.
- **Spacing:** seguir 4px grid.
- **Componentes a portar (1 a 1):**
  - `MetricCard` ([src/components/dashboard/MetricCard.tsx](src/components/dashboard/MetricCard.tsx)) — variantes `primary | accent | success | warning | destructive | default`, con trend opcional.
  - `BusinessTable` ([src/components/dashboard/BusinessTable.tsx](src/components/dashboard/BusinessTable.tsx))
  - `RevenueChart` ([src/components/dashboard/RevenueChart.tsx](src/components/dashboard/RevenueChart.tsx)) — `fl_chart` BarChart o LineChart.
  - `AlertsPanel` ([src/components/dashboard/AlertsPanel.tsx](src/components/dashboard/AlertsPanel.tsx))
  - `StatusBadges` (`AgentBadge`, `NCFBadge`, `PlanBadge`) ([src/components/dashboard/StatusBadges.tsx](src/components/dashboard/StatusBadges.tsx))
  - `InvoiceStatusBadge`, `InvoiceActions`.
  - Layout: `AppShell`, `Sidebar`, `Topbar`, `BottomNav` ([src/components/layout/](src/components/layout/)).
- **Responsive:**
  - ≥ 1024 px: sidebar fijo + topbar.
  - < 1024 px: bottom nav + topbar (oculta sidebar).
- **Locale:** `intl` con `es_DO`. Fechas relativas en español ("hace X min").
- **Dark mode:** opcional v1.5 (el prototipo ya contempla tokens HSL).

---

## 9. Routing

```dart
// lib/app/router/app_router.dart
GoRouter(
  routes: [
    ShellRoute(
      builder: (_, __, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
        GoRoute(path: '/negocios', builder: (_, __) => const BusinessesPage()),
        GoRoute(path: '/negocios/:id', builder: (_, s) => BusinessDetailPage(id: s.pathParameters['id']!)),
        GoRoute(path: '/fiscal', builder: (_, __) => const FiscalPage()),
        GoRoute(path: '/impresion', builder: (_, __) => const PrintingPage()),
        GoRoute(path: '/auditoria', builder: (_, __) => const AuditPage()),
        GoRoute(path: '/alertas', builder: (_, __) => const AlertsPage()),
        GoRoute(path: '/facturacion', builder: (_, __) => const BillingPage()),
      ],
    ),
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
  ],
  redirect: platformOperatorGuard,  // si no es platform_operator → /login o /forbidden
)
```

---

## 10. Cambios requeridos en el backend de `mangospos`

> Esto define qué migraciones nuevas necesita el repo `mangospos/supabase/migrations/`. **Ningún cambio se merge sin revisión por el equipo de POS.**

### 10.1 Tipo de negocio (`business_type`)
El prototipo asume `restaurant | retail | cafe | bar | bakery`. La tabla `businesses` no tiene este campo.
- Añadir columna `business_type text` (con CHECK enum) o tabla pivote.
- En el onboarding de `mangospos` ya se pregunta esto (verificar `register_business_onboarding_rpc`); si el dato existe pero no se persiste en `businesses`, sólo añadir la columna y backfill.

### 10.2 Auditoría unificada (opcional v1, requerido v1.5)
- Tabla `audit_logs (id, business_id, user_id, action, severity, ref_table, ref_id, reason, created_at)`.
- Triggers en: `fiscal_documents` (cancelaciones), `payments` (refunds), `orders` (cancelaciones), `order_items` (deletes), `menu_items` (deletes con razón).
- En v1, la consola usa el RPC compositor descrito en §7.5 sobre las tablas existentes.

### 10.3 Facturación de membresía
Migración nueva `platform_invoices` (definición SQL en §7.7) + `platform_operators` (whitelist) + RPCs:
- `generate_membership_invoice(business_id uuid)` → retorna `platform_invoices` row.
- `bulk_generate_membership_invoices()` → retorna count.
- `mark_invoice_paid(invoice_id uuid, method text)`.
- `void_invoice(invoice_id uuid, reason text)`.
- `expire_overdue_invoices()` (cron).
- `platform_invoice_pdf_url(invoice_id uuid)` opcional, si los PDFs se generan server-side.

### 10.4 RPCs de agregación (lecturas de la consola)
- `platform_overview()` → métricas + array de negocios con todos los campos del §6.1 + `hourly_revenue[12]`.
- `platform_business_detail(business_id uuid)` → detalle completo.
- `platform_print_overview()`, `platform_recent_failed_print_jobs(limit int)`.
- `platform_audit_feed(since timestamptz, limit int)`.
- `platform_active_alerts()`.

Todas con `SECURITY DEFINER` y guard `if not is_platform_operator(auth.uid()) then raise exception 'forbidden'`.

### 10.5 Realtime
- Habilitar replicación lógica (publicación) en: `agent_nodes`, `print_jobs`, `payments`, `fiscal_documents`, `memberships`, `platform_invoices`.

---

## 11. Performance y observabilidad

- **Carga inicial Dashboard:** < 1.5 s con caché frío contra Supabase RD-region. Una sola RPC para evitar N+1.
- **Realtime:** un canal por dominio (no uno por fila). Throttling cliente (max 1 update por seg por tarjeta).
- **Logs:** `logger` (mismo paquete que `mangospos`). Eventos clave: login, operación destructiva (toggle status, void invoice), error de RPC.
- **Crash reporting:** Sentry o equivalente — definir post-v1.

---

## 12. Seguridad

- TODO escritura sensible va por **RPC** (no SQL directo desde cliente).
- `service_role` JAMÁS embebido en la app — sólo en Edge Functions.
- 2FA recomendado para `platform_operator` (Supabase MFA TOTP) — habilitar en v1.5.
- Audit del acceso del operador: nueva tabla `platform_operator_actions (operator_id, action, target_business_id, payload, created_at)`.
- Storage de PDFs en bucket privado `platform-invoices/` con URLs firmadas (TTL 24h) para WhatsApp.
- WhatsApp share: el link `wa.me` lleva sólo URL firmada y no datos PII en query string innecesario.

---

## 13. Roadmap / fases

### Fase 0 — Setup (semana 1)
- [ ] Crear repo `mangopos_admin` con estructura del §5.
- [ ] Conectar a Supabase del proyecto MangoPOS (env separado: `staging`, `prod`).
- [ ] Migración `platform_operators` + seed con el equipo de Mango.
- [ ] Login + guard.

### Fase 1 — Vista global y negocios (semanas 2-3)
- [ ] RPC `platform_overview` + `platform_business_detail`.
- [ ] Dashboard, Negocios listado, Detalle (sin facturación todavía).
- [ ] AppShell + responsive desktop.
- [ ] Realtime básico (agent_nodes, print_jobs failed).

### Fase 2 — Operación (semana 4)
- [ ] Módulo Fiscal/NCF.
- [ ] Módulo Impresión.
- [ ] Módulo Alertas.
- [ ] Toggle activar/desactivar negocio.

### Fase 3 — Facturación (semanas 5-6)
- [ ] Migración `platform_invoices` + RPCs.
- [ ] Pantalla Facturación.
- [ ] Generación PDF + WhatsApp share.
- [ ] Cron de expiración / generación bulk.

### Fase 4 — Auditoría y refinamiento (semana 7)
- [ ] Auditoría compuesta v1.
- [ ] (Si hay capacidad) tabla `audit_logs` + triggers.
- [ ] Tests, polish, dark mode.

### Fase 5 — Lanzamiento (semana 8)
- [ ] Empaquetado: msix (Windows), dmg (macOS), build web.
- [ ] Documentación interna de uso.
- [ ] Onboarding del equipo de soporte.

---

## 14. Métricas de éxito post-lanzamiento

- Tiempo desde "agente cae" hasta "operador lo ve" < 2 min (medido vs. timestamps).
- 100% de negocios activos cobrados en sistema en el ciclo M+1.
- 0 incidentes de NCF agotado sin alerta previa.
- NPS interno del equipo de Mango ≥ 8/10 en encuesta 30 días post-launch.

---

## 15. Preguntas abiertas / decisiones pendientes

| # | Pregunta | Bloquea |
|---|---|---|
| Q1 | ¿`business_type` se persiste en `businesses` o se infiere? | Listado / detalle |
| Q2 | ¿Implementamos `audit_logs` general en v1 o componemos en RPC? | Módulo Auditoría |
| Q3 | ¿Tarifas de planes Basic/Pro fijas o configurables por negocio? El prototipo asume fijas. | Facturación |
| Q4 | ¿Quién genera el PDF de la factura: cliente Flutter o Edge Function? | Facturación |
| Q5 | ¿WhatsApp por API oficial (Cloud API) o solo `wa.me`? | Facturación |
| Q6 | ¿Móvil entra en v1 (BottomNav) o se difiere? | Scope/timeline |
| Q7 | ¿Dark mode v1 o v1.5? | UI scope |
| Q8 | Política de retención: ¿cuántos meses de facturas / audit / print jobs se mantienen visibles? | Performance |

---

## 16. Apéndice: cuadro de orígenes (tablas Supabase consumidas)

Tablas leídas por la consola (todas existen ya en `mangospos/backend data structure/schema.txt` salvo donde se indica):

`businesses`, `business_settings`, `memberships`, `user_businesses`, `profiles`, `agent_nodes`, `discovery_jobs`, `print_jobs`, `printers`, `print_areas`, `fiscal_documents`, `fiscal_settings`, `ncf_sequences`, `cash_register_sessions`, `cash_registers`, `cash_transactions`, `payments`, `payment_methods`, `orders`, `order_items`, `order_checks`, `table_sessions`, `dining_tables`, `zones`.

Tablas **a crear**:
- `platform_operators` (whitelist de roles).
- `platform_invoices` (facturación de membresía).
- `platform_operator_actions` (audit de la consola).
- `audit_logs` (opcional/v1.5).
- `platform_alert_acks` (opcional/v1.5).

---

**Fin del PRD v1.0.**
