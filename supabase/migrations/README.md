# Migraciones SQL — `mangopos_admin`

Migraciones que la consola del operador necesita aplicar **contra el proyecto Supabase de `mangospos`** (es el mismo proyecto, no uno nuevo).

## Cómo aplicarlas

Tres opciones, en orden de preferencia:

1. **Supabase CLI vinculada al proyecto `mangospos`:**
   ```bash
   cd ../mangospos
   supabase db push  # si decides copiar estos archivos al directorio de migraciones de mangospos
   ```

2. **SQL editor del dashboard de Supabase**: pegar el contenido del archivo y ejecutar.

3. **`psql` directo** con la connection string del proyecto (solo personal autorizado).

> Cada migración es **idempotente** (`if not exists`, `create or replace`, `drop policy if exists`). Se puede correr más de una vez sin romper nada.

## Migraciones

| # | Archivo | Resumen |
|---|---|---|
| 0001 | [0001_platform_operators.sql](0001_platform_operators.sql) | Whitelist de operadores + función `is_platform_operator(uid)`. Bloquea cualquier acceso transversal hasta que se sembre al menos un operador. |
| 0002 | [0002_super_owner_and_password_change.sql](0002_super_owner_and_password_change.sql) | Habilita el rol `super_owner`, añade `must_change_password` y expone los RPCs `must_change_password()` / `clear_must_change_password()` que la consola usa para forzar el cambio de clave al primer login. |
| 0003 | [0003_dashboard_rpcs.sql](0003_dashboard_rpcs.sql) | RPCs `get_platform_overview()`, `get_revenue_trend_12h()` y `get_platform_alerts()` que alimentan la "Vista global" (cards de métricas, gráfico de ingresos 12h, panel de alertas y tabla de negocios). Falla cerrada si el caller no es `is_platform_operator()`. |
| 0004 | [0004_membership_billing.sql](0004_membership_billing.sql) | Schema de **facturación de membresías** (`membership_invoices`) + helpers de pricing/numeración + RPCs: `get_billing_overview`, `get_billing_metrics`, `generate_membership_invoice`, `mark_invoice_paid`, `void_invoice`, `expire_overdue_invoices`, `get_business_invoices`. Solo operadores. |
| 0005 | [0005_dashboard_extras.sql](0005_dashboard_extras.sql) | RPCs auxiliares: `get_critical_audit_logs(business?, limit)`, `get_recent_print_failures(business?, hours, limit)`, `get_business_week_trend()`, `toggle_business_status(business)`. Para Auditoría, Impresión, BusinessDetail y activación/desactivación. |
| 0006 | [0006_business_environment.sql](0006_business_environment.sql) | Añade `businesses.environment` (production / sandbox), RPC `set_business_environment(business_id, env)` y reescribe los RPCs existentes para devolver `environment` y/o aceptar `p_env` para filtrado server-side (revenue trend 12h, billing metrics). |
| 0007 | [0007_update_business_membership.sql](0007_update_business_membership.sql) | RPC `update_business_membership(business_id, plan_type, end_date, status)` para que el operador edite plan + fecha de corte + estado (active/expired/canceled) por negocio. Crea la membresía si el negocio no tiene. |
| 0008 | [0008_business_activity.sql](0008_business_activity.sql) | Reescribe `get_platform_overview()` para añadir `activity_status` y `last_activity_at` derivados de señales reales (último login de miembros, último pago, última apertura de caja). Funciona aunque `agent_nodes` esté vacío. |
| 0009 | [0009_cash_health_admin.sql](0009_cash_health_admin.sql) | **Salud de Cajas NOC** (PRD-12 Fase 1). Tabla `noc_audit_log`, vista `v_admin_cash_health` (extiende `v_cash_sessions_health` con `business_name` + cajero), y RPCs `get_admin_cash_health`, `get_cash_session_detail`, `get_cash_session_kardex`, `admin_force_close_cash_session`. Requiere que mangospos ya tenga `v_cash_sessions_health` (migración 0015) y `fn_force_close_cash_session` (0016). |
| 0010 | [0010_print_health_admin.sql](0010_print_health_admin.sql) | **Salud de Impresión NOC** (PRD-12 Fase 2). Vistas `v_admin_print_agents` y `v_admin_print_jobs` + RPCs `get_admin_print_health`, `get_admin_print_agents(env)`, `get_admin_print_jobs(env, biz, status, limit)`, `get_admin_top_print_failures`, `admin_retry_print_job`, `admin_cancel_print_job`. Aprovecha las columnas `retry_count`, `last_error`, `kind`, `priority`, `printer_id` añadidas a `print_jobs` en mangospos migración 0008. |
| 0011 | [0011_fix_cash_health_dupes.sql](0011_fix_cash_health_dupes.sql) | **Fix duplicados en `v_admin_cash_health`**. El JOIN a `employees` no estaba acotado por `business_id`; si un mismo `user_id` era empleado en N negocios, la vista devolvía la sesión repetida N veces. Recrea la vista con `e.user_id = h.user_id AND e.business_id = h.business_id`. |
| 0012 | [0012_fiscal_health_admin.sql](0012_fiscal_health_admin.sql) | **Salud Fiscal NOC** (PRD-12 Fase 3). Vistas `v_admin_fiscal_problems` (e-CFs stuck/rejected/cancelled) y `v_admin_ncf_sequences` (disponibilidad + vencimiento) + RPCs `get_admin_fiscal_health`, `get_admin_fiscal_problems`, `get_admin_ncf_sequences`, `admin_mark_ecf_for_retry`. |
| 0013 | [0013_cash_session_payment_breakdown.sql](0013_cash_session_payment_breakdown.sql) | **Desglose de pagos por método** dentro de una sesión de caja. RPC `get_cash_session_payment_breakdown(session_id)` agrega `payments` por `payment_method_id` con conteo, total y porcentaje. Permite ver ventas con efectivo, tarjeta y transferencia juntas (el saldo de caja sigue siendo solo efectivo). |
| 0014 | [0014_table_health_admin.sql](0014_table_health_admin.sql) | **Salud de Mesas NOC** (PRD-12 Fase 4). Vistas `v_admin_zombie_table_sessions` (>24h sin cerrar), `v_admin_stuck_payments` (`partially_paid` >1h), `v_admin_orphan_order_items` (items activos cuya orden/sesión cerró). RPCs `get_admin_table_health`, `get_admin_zombie_sessions`, `get_admin_stuck_payments`, `get_admin_orphan_items`, `admin_close_zombie_table_session` (libera mesa + void órdenes opcional), `admin_void_orphan_item`. |
| 0015 | [0015_incidents_admin.sql](0015_incidents_admin.sql) | **Sistema de Incidentes NOC** (PRD-12 Fase 5 parte A). Tablas `noc_incidents` (con dedupe_key y source manual/auto), `noc_webhooks`, `noc_alert_rules` (esqueleto). Vista `v_admin_noc_incidents`. RPCs `open_noc_incident`, `close_noc_incident`, `get_admin_incidents`, `get_admin_incident_summary`, `get_admin_active_incidents_count`. |
| 0016 | [0016_incidents_auto_detection.sql](0016_incidents_auto_detection.sql) | **Auto-detección de incidentes** (PRD-12 Fase 5 parte B). Función `noc_run_auto_detection()` que escanea todas las vistas de salud y abre/cierra incidentes con `dedupe_key`. Cubre 7 tipos: `print_agent_down`, `ncf_critical`, `ncf_expired`, `ecf_rejected`, `ecf_stuck`, `cash_zombie`, `cash_variance`, `table_zombie`, `payment_stuck`. Diseñada para correr vía `pg_cron` cada minuto (template comentado al pie). |

## Después de aplicar 0001

Para autorizar al primer operador, conseguir su `auth.users.id` y correr:

```sql
insert into public.platform_operators (user_id, role, notes)
values ('<uuid-del-usuario>', 'platform_operator', '<tu-nombre>');
```

A partir de ahí, ese usuario podrá iniciar sesión en `mangopos_admin` y pasar el guard.

## Seeds

Bloques SQL de un solo uso que pueblan datos iniciales. Pegar en Supabase Studio → SQL Editor y ejecutar.

| # | Archivo | Resumen |
|---|---|---|
| 0001 | [../seeds/0001_super_owner_mangopos.sql](../seeds/0001_super_owner_mangopos.sql) | Crea el usuario `mangopos.do@gmail.com` (clave temporal `12345678`), lo registra como `super_owner` y deja activo el flag `must_change_password` para forzar cambio en el primer login. Idempotente. Requiere haber aplicado la migración 0002. |
