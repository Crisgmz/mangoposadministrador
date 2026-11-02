# Revisión pendiente: cobro de ECO BAR AND LOUNGE

Registro preparado el 28/10/2026 para retomar la investigación. Horas en Santo Domingo (AST, UTC−4), salvo indicación expresa.

## Punto de partida

El pago de suscripción de **RD$2,999.99** para el período **27/10/2026–27/11/2026** quedó en `error`. Azul devolvió:

```text
Invalid XML: The 'br' start tag on line 1 position 133 does not match the end tag of 'body'. Line 1, position 178.
```

El cron se ejecutó y apunta al dominio esperado. La fila y el request guardado no tienen `CustomOrderId`, aunque el código local actual lo genera antes de llamar a Azul. La comparación de archivos confirmó diferencias entre el repositorio y el volumen configurado del servidor; todavía falta revisar su contenido y confirmar qué código sirve la ruta de producción.

**El resultado bancario sigue sin confirmar.** El usuario no encontró la operación en el portal de Azul. Eso no equivale a una confirmación de que no hubo débito.

## Identificadores para retomar el caso

| Dato | Valor |
| --- | --- |
| Negocio | ECO BAR AND LOUNGE |
| `business_id` | `fc3065c8-cb40-45ad-bec1-aecb388001c1` |
| `membership_id` | `50656e43-7f63-4f3e-8485-b3559b50588d` |
| `charge_id` | `0d47f52e-f3f2-4920-9f8e-8b46f2f5d1a4` |
| Orden | `MP50656E2610271` |
| Monto y moneda | RD$2,999.99 / DOP |
| Tarjeta de la captura | Visa terminada en `0102` |
| Fecha del intento | 27/10/2026, 03:00:06 AST / 07:00:06 UTC |
| Intento | 1 |

## Evidencia SQL confirmada

### Cobro y respuesta

- Creado: `2026-10-27 03:00:06.427321` AST.
- Última actualización: `2026-10-27 03:00:10.082394` AST.
- Completado: `2026-10-27 03:00:10.060` AST.
- Estado: `error`; `response_code = 'Error'`; `iso_code = ''`.
- `custom_order_id` y `azul_order_id`: `NULL`.
- El request guardado contiene `method = ProcessPayment`, `TrxType = Sale` y la orden indicada; **no contiene la clave `CustomOrderId`**.
- La respuesta guardada es un objeto con el error XML anterior. No hay evidencia de aprobación ni de rechazo bancario definitivo en estos campos.
- Último evento asociado: `404b7053-de83-4342-b46b-f8143e0a722a`, recibido a las `03:00:10.213137` AST. Es un `webservice_response` de `ProcessPayment`, marcado `processed = true`, con el mismo error. No apareció un evento asociado de `VerifyPayment`.
- La consulta posterior seguía mostrando los mismos timestamps y estado: no se observó otro intento para ese período.

### Suscripción

| Campo | Valor consultado |
| --- | --- |
| `billing_status` | `active` |
| `current_attempt_number` | `0` |
| Período actual | `2026-09-27` → `2026-10-27` |
| `next_billing_date` | `2026-10-27` |
| `last_successful_charge_id` | `a1c941dc-0681-4f3c-815e-6beb3352de6e` |
| `last_failed_charge_id` | `NULL` |

En el código local, un error técnico no incrementa el contador de rechazos ni avanza el período. Estos valores son compatibles con ese comportamiento; no demuestran qué versión estaba desplegada.

### Historial consultado

Hay cinco filas para el negocio. Todas tenían `custom_order_id = NULL`.

| Fecha del intento AST | Período facturado | Estado | Orden / ID Azul |
| --- | --- | --- | --- |
| 27/10, 03:00 | 27/10–27/11 | error | `MP50656E2610271` / sin ID Azul |
| 06/10, 03:00 | 27/09–27/10 | approved | `MP50656E2609271` / `390879066` |
| 05/10, 03:00 | 27/08–27/09 | approved | `MP50656E2608271` / `390147142` |
| 04/10, 03:00 | 27/07–27/08 | approved | `MP50656E2607271` / `389630669` |
| 03/10, 16:21 | 27/06–27/07 | approved | `MP50656E2606271` / `389353840` |

Las cuatro filas aprobadas tienen ISO `00` y suman RD$11,999.96. Corresponden a períodos distintos; este historial por sí solo no demuestra cobros duplicados en el banco ni valida la política de recuperación de atrasos.

### Cron y respuestas HTTP

- Job: `4`, nombre `azul_charge_due`, activo.
- Horario: `0 7 * * *`, equivalente a las **03:00 AST**.
- Rutina: `private.fn_azul_run_due_charges()`; usa `net.http_post`, filtra precio cero e invoca `azul-charge-subscription`.
- Destino configurado: `https://supabase.mangopos.do/functions/v1`.
- Configuración actualizada: `2026-06-24 17:59:59.751878+00`.
- Ejecución del 27/10: `runid = 270246`, `succeeded`, desde `03:00:00.146669` hasta `03:00:00.214265` AST.
- `succeeded` confirma que la rutina SQL terminó sin error; no confirma aprobación bancaria ni el resultado final de la petición HTTP.
- `net._http_response` existe y su retención configurada es **6 horas**. La búsqueda del intervalo del incidente devolvió cero filas; pueden haber expirado.
- El 27/10 se creó una sola fila de cobro en el conjunto consultado: la de este incidente, sin `custom_order_id` y en `error`.
- La hora SQL aportada al retomar era **28/10/2026, 00:30:58 AST**: la ejecución de las 03:00 del 28 aún no había ocurrido en ese momento. Al retomar, hay que volver a consultar el estado.

Huellas SQL registradas:

```text
command_hash:       43cf0a021c76ff9564359c04d78ea63b
function_body_hash: edce2b3c4e18fbb3f797d89152318bd0
```

## Comparación del servidor ya realizada

El usuario ejecutó este comando desde su Mac:

```bash
CHECK=1 bash /Users/cristiangomez/dev/mangospos/scripts/deploy_edge_functions.sh azul-charge-subscription
```

Destino inspeccionado:

```text
root@31.97.40.114
/data/coolify/services/n84o0s8s0w08cko8c48gsog4/volumes/functions
```

Salida relevante:

```text
→ _shared
./
ecf-certificate.ts
→ azul-charge-subscription
./
billing_period.ts
charge_breakdown.ts
index.ts
retry_policy.ts
```

El modo `CHECK=1` compara mediante rsync sin copiar ni reiniciar. La salida confirma archivos diferentes o ausentes en el destino, **no cuál versión es más reciente ni qué diferencias contienen**. Las entradas `./` también pueden reflejar metadatos del directorio.

`_shared/ecf-certificate.ts` pertenece al trabajo separado de certificados de facturación electrónica. No es evidencia de la causa de este cobro. No desplegar todo `_shared` como parte de una corrección de cobros sin revisar el alcance.

El modo de comprobación del script termina antes de identificar el contenedor por su montaje. Falta validar que el volumen inspeccionado sea el que atiende la ruta pública y comparar el contenido de los cuatro archivos del cobro.

El acceso SSH del agente fue rechazado por autenticación (`Permission denied (publickey,password)`). El usuario sí pudo autenticarse desde su terminal. No se ha solicitado ni guardado su contraseña.

## Qué dice el código local actual

Repositorio: `/Users/cristiangomez/dev/mangospos`.

- `supabase/functions/azul-charge-subscription/index.ts` genera el UUID y guarda `custom_order_id` en el INSERT, antes de llamar a Azul. También incluye `CustomOrderId` en el request auditado.
- Ante un cobro previo `error` o `pending` antiguo, consulta `VerifyPayment` antes de volver a enviar una venta.
- Si el intento previo no tiene `custom_order_id`, responde `409 unverifiable_previous_attempt` y bloquea el reintento automático.
- La integración implementada consulta `VerifyPayment` por **CustomOrderId**. No se encontró una consulta local equivalente por `OrderNumber` o por `AzulOrderId`.

Esto hace sospechar una diferencia en el código desplegado o en el proceso que escribió el cobro. **No prueba que esa diferencia causara el error XML.** SQL no identifica la versión Deno cargada por Edge Runtime.

## Pasos para retomar

1. **Actualizar la evidencia del mismo cobro/período.** Ejecutar primero el bloque 6 del diagnóstico de cron. Un reintento puede actualizar la fila creada el 27; no basta con buscar filas creadas el 28.
2. **Conciliar la operación original con Azul.** Buscar por fecha/hora, monto, comercio y tarjeta, además de la orden. Si sigue sin aparecer, obtener confirmación de Azul sobre la operación original antes de habilitar otra venta.
3. **Revisar producción en modo de solo lectura.** Identificar el contenedor y volumen que atienden `supabase.mangopos.do`; obtener los cuatro archivos indicados y comparar sus diferencias con el repositorio. No hace falta volver a ejecutar `CHECK=1` mientras no cambien los archivos: su salida ya está registrada arriba.
4. **Preparar una corrección limitada según el diff.** Revisar generación de `CustomOrderId`, verificación antes del reintento y cálculo de período. Preservar cambios del servidor que no formen parte del incidente. Definir respaldo y reversión antes de desplegar.
5. **Resolver el cobro según la confirmación bancaria.** Si hubo aprobación, conciliar con los datos reales sin volver a cobrar. Si se confirma que no hubo venta, preparar el reintento controlado conservando la evidencia original. La ejecución del cobro requiere una decisión explícita aparte.

## Límites de la investigación realizada

- No se ejecutaron pagos, verificaciones contra Azul, devoluciones ni anulaciones durante este diagnóstico.
- No se actualizó la fila del cobro, la suscripción, la configuración ni el cron.
- No se desplegaron funciones ni se reiniciaron servicios.
- No se rellenó `custom_order_id`. Inventar uno ahora y obtener `Found=0` no demostraría que la operación original no se cobró: ese identificador no fue enviado en el request guardado.
- No ejecutar `private.fn_azul_run_due_charges()` para comprobar el cron: encola cobros reales.

## Archivos de consulta

- [Cobro, eventos e historial](../supabase/DIAGNOSTICO_ecobar_cobro_20261027.sql).
- [Cron, respuestas HTTP y estado actual del período — bloque 6](../supabase/DIAGNOSTICO_ecobar_cron_20261027.sql).
- Script de comparación existente: `/Users/cristiangomez/dev/mangospos/scripts/deploy_edge_functions.sh` con `CHECK=1`.

Los bloques 3, 4 y 5 del diagnóstico de cron están anclados al **27/10/2026**. Para investigar otra ejecución hay que ajustar las fechas; el bloque 6 consulta el período afectado sin depender de la fecha de creación de la fila.
