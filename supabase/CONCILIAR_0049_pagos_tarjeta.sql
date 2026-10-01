-- =============================================================================
-- CONCILIAR 0049 — dejar pagadas las facturas de los cobros con tarjeta que ya
-- se hicieron ANTES de la migración 0049.
--
-- Desde 0049 cada cobro aprobado paga su factura solo (trigger). Los cobros
-- anteriores hay que conciliarlos una vez. Dos pasos:
--
--   PASO 1 — vista previa. No escribe nada. Correr y revisar.
--   PASO 2 — aplicar. Descomentar y correr SOLO si el paso 1 se ve bien.
--
-- Se puede correr más de una vez: lo ya conciliado sale como already_linked.
--
-- REQUIERE 0050 aplicada (monto de las facturas nuevas descontando reembolsos
-- de precio). Sin 0050, factura_rd sale vacío: no aplicar.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASO 1 — VISTA PREVIA (no cambia nada)
--
-- Qué significa cada acción:
--   marked_paid                 la factura del mes estaba pendiente/vencida → quedará pagada
--   created_paid                no había factura del mes → se creará ya pagada, por lo cobrado
--   linked_paid_card            ya estaba pagada con tarjeta a mano → solo se vincula
--   already_linked              ya conciliado antes
--   paid_other_method           el mes ya estaba pagado por transferencia/efectivo → NO se toca.
--                               REVISAR: el cliente pudo haber pagado dos veces.
--   period_paid_by_other_charge otro cobro con tarjeta ya pagó ese mes → NO se toca.
--                               REVISAR: dos cobros para un mismo mes (posible duplicado).
--   period_taken                ese inicio de período lo ocupa una factura anulada → NO se crea.
--   no_membership / no_plan_type faltan datos de la suscripción → NO se crea.
--
-- Columnas:
--   cobrado_rd         lo que se cobró con la tarjeta
--   factura_rd         (solo created_paid) monto de la factura nueva: lo cobrado
--                      menos lo reembolsado por corrección de precio
--   facturas_cercanas  (solo created_paid) otras facturas del negocio que empiezan
--                      a 16–24 días: si aparece alguna, puede ser el MISMO mes con
--                      otra fecha y conviene revisarla antes de aplicar
-- -----------------------------------------------------------------------------

select r->>'action'         as accion,
       r->>'business_name'  as negocio,
       r->>'period_start'   as periodo,
       r->>'amount'         as cobrado_rd,
       coalesce(r->>'invoice_amount', '') as factura_rd,
       r->>'reference'      as referencia,
       case when r->>'invoice_number' like 'PREVIA-%' then '(nueva)'
            else r->>'invoice_number' end as factura,
       coalesce(r->>'payment_method', '') as pagada_con,
       case when r->>'action' = 'created_paid' then (
         select string_agg(
                  mi.invoice_number || ' (' || mi.period_start || ', ' || mi.status || ')',
                  ', ' order by mi.period_start)
           from public.membership_invoices mi
          where mi.business_id = (r->>'business_id')::uuid
            and mi.status <> 'void'
            and abs(mi.period_start - (r->>'period_start')::date) between 16 and 24
       ) end as facturas_cercanas
  from jsonb_array_elements(public.admin_backfill_card_payments(true)->'results') r
 order by case r->>'action'
            when 'paid_other_method'           then 1
            when 'period_paid_by_other_charge' then 2
            when 'period_taken'                then 3
            when 'no_membership'               then 4
            when 'no_plan_type'                then 5
            else 9
          end,
          negocio, periodo;

-- -----------------------------------------------------------------------------
-- PASO 2 — APLICAR (descomentar)
--
-- select public.admin_backfill_card_payments(false)->'by_action';
-- -----------------------------------------------------------------------------
