import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/subscription_billing_repository.dart';
import '../../domain/models/subscription_charge.dart';

/// Sección "Pagos de suscripción" del detalle de negocio.
///
/// Lista los cobros con tarjeta (Azul) del negocio con lo reembolsado y lo que
/// queda por devolver, y permite reembolsos totales o parciales. El reembolso lo
/// hace la Edge Function `admin-azul-refund` (supabase/functions de este repo);
/// el saldo lo valida el servidor (esta pantalla solo lo anticipa).
class SubscriptionChargesSection extends ConsumerWidget {
  const SubscriptionChargesSection({
    required this.businessId,
    required this.businessName,
    super.key,
  });

  final String businessId;
  final String businessName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chargesAsync = ref.watch(subscriptionChargesProvider(businessId));
    final count = chargesAsync.valueOrNull?.length;
    final duplicates = chargesAsync.valueOrNull
            ?.where((c) => c.isDuplicated && !c.duplicateResolved)
            .length ??
        0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              HugeIcons.strokeRoundedInvoice03,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                count == null || count == 0
                    ? 'Pagos de suscripción'
                    : 'Pagos de suscripción ($count)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ),
            if (duplicates > 0) ...[
              _Pill(
                label: duplicates == 1
                    ? '1 COBRO DUPLICADO'
                    : '$duplicates COBROS DUPLICADOS',
                color: AppColors.destructive,
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: 'Actualizar',
              onPressed: () =>
                  ref.invalidate(subscriptionChargesProvider(businessId)),
              icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        chargesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => _messageCard(
            'No se pudieron cargar los pagos: $e',
            error: true,
          ),
          data: (charges) {
            if (charges.isEmpty) {
              return _messageCard(
                'Todavía no hay cobros con tarjeta para este negocio. '
                'Aparecen aquí cuando el cobro automático o "Pagar ahora" '
                'procesa uno.',
              );
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.border, width: 0.6),
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppColors.shadowCard,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < charges.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: AppColors.border),
                    _ChargeTile(
                      charge: charges[i],
                      businessId: businessId,
                      businessName: businessName,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _messageCard(String text, {bool error = false}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: error ? AppColors.destructive : AppColors.mutedForeground,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila de cobro
// ---------------------------------------------------------------------------

class _ChargeTile extends StatelessWidget {
  const _ChargeTile({
    required this.charge,
    required this.businessId,
    required this.businessName,
  });

  final SubscriptionCharge charge;
  final String businessId;
  final String businessName;

  static const _muted = TextStyle(
    fontSize: 12,
    color: AppColors.mutedForeground,
  );

  @override
  Widget build(BuildContext context) {
    final c = charge;
    final (statusLabel, statusColor) = _chargeStatus(c.status);
    final failure = c.isApproved ? null : (c.errorDescription ?? c.responseMessage);
    final over = c.overPriceCents;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          formatRd(c.amountCents / 100),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: AppColors.foreground,
                          ),
                        ),
                        _Pill(label: statusLabel, color: statusColor),
                        // Un duplicado devuelto NO es "reembolsado": el mes
                        // sigue pago con la otra venta.
                        if (c.isDuplicated)
                          _Pill(
                            label: c.duplicateResolved
                                ? 'DUPLICADO DEVUELTO'
                                : 'COBRADO ${c.azulSales.length} VECES',
                            color: c.duplicateResolved
                                ? AppColors.mutedForeground
                                : AppColors.destructive,
                          )
                        else if (c.fullyRefunded)
                          const _Pill(
                            label: 'REEMBOLSADO',
                            color: AppColors.mutedForeground,
                          )
                        else if (c.refundedCents > 0)
                          const _Pill(
                            label: 'REEMBOLSO PARCIAL',
                            color: AppColors.accent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Período ${_fmtDate(c.billingPeriodStart)} → '
                      '${_fmtDate(c.billingPeriodEnd)} · intento ${c.attemptNumber}',
                      style: _muted,
                    ),
                    if (c.ecfOverageCents > 0)
                      Text(
                        'Incluye ${c.ecfExtra} facturas electrónicas extra '
                        '(${formatRd(c.ecfOverageCents / 100)})',
                        style: _muted,
                      ),
                    Text(
                      [
                        _fmtDateTime(c.attemptedAt),
                        if (c.cardLabel.isNotEmpty) c.cardLabel,
                        if (c.azulOrderId != null) 'Azul #${c.azulOrderId}',
                      ].join(' · '),
                      style: _muted,
                    ),
                    if (failure != null && failure.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          failure,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    if (c.refundedCents > 0 || c.pendingRefundCents > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (c.refundedCents > 0)
                              'Reembolsado ${formatRd(c.refundedCents / 100)}',
                            if (c.pendingRefundCents > 0)
                              'Sin confirmar ${formatRd(c.pendingRefundCents / 100)}',
                            if (c.canRefund)
                              'Disponible ${formatRd(c.refundableCents / 100)}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          ),
                        ),
                      ),
                    if (c.isDuplicated) _DuplicateNotice(charge: c),
                    // El caso del 16/09: cobró lista con precio especial vigente.
                    if (over != null && c.canRefund)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Cobró ${formatRd(over / 100)} más que el precio actual '
                          'del período (${formatRd(c.currentPriceCents! / 100)}).',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (c.canRefund) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _refund(context),
                  icon: const Icon(
                    HugeIcons.strokeRoundedArrowTurnBackward,
                    size: 14,
                  ),
                  label: const Text('Reembolsar'),
                ),
              ],
            ],
          ),
          for (final r in c.refunds)
            _RefundRow(
              refund: r,
              onVerify: r.isPending ? () => _verify(context, r) : null,
            ),
        ],
      ),
    );
  }

  Future<void> _refund(BuildContext context) async {
    final request = await showDialog<RefundRequest>(
      context: context,
      builder: (_) => RefundChargeDialog(
        businessName: businessName,
        charge: charge,
      ),
    );
    if (request == null || !context.mounted) return;

    final amount = formatRd(request.amountCents / 100);
    final card = charge.cardLabel.isEmpty ? 'la tarjeta' : charge.cardLabel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar reembolso'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Se devolverán $amount a $card de $businessName '
            '(cobro Azul #${charge.azulOrderId}).\n\n'
            'Un reembolso aprobado no se puede deshacer.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructive,
              foregroundColor: AppColors.destructiveForeground,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Reembolsar $amount'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await _runRefundAction(
      context,
      progressLabel: 'Procesando el reembolso con Azul…',
      action: (repo) => repo.refundCharge(
        chargeId: charge.id,
        amountCents: request.amountCents,
        reason: request.reason,
      ),
    );
  }

  Future<void> _verify(BuildContext context, ChargeRefund refund) {
    return _runRefundAction(
      context,
      progressLabel: 'Consultando a Azul…',
      action: (repo) => repo.verifyRefund(refund.id),
    );
  }

  /// Corre el pedido con un diálogo bloqueante (evita el doble clic mientras
  /// Azul responde), refresca pagos y suscripción y muestra el resultado.
  Future<void> _runRefundAction(
    BuildContext context, {
    required String progressLabel,
    required Future<RefundActionResult> Function(
      SubscriptionBillingRepository repo,
    ) action,
  }) async {
    // El contenedor y no `ref`: al refrescar, esta fila se reconstruye y el
    // widget que lanzó la acción puede ya no existir cuando Azul responde.
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(progressLabel)),
            ],
          ),
        ),
      ),
    );

    String message;
    try {
      final result =
          await action(container.read(subscriptionBillingRepositoryProvider));
      message = result.message.isNotEmpty
          ? result.message
          : (result.approved ? 'Reembolso aprobado.' : 'Reembolso no aprobado.');
    } on SubscriptionRefundException catch (e) {
      message = e.message;
    } catch (e) {
      message = 'Error: $e';
    } finally {
      navigator.pop();
    }

    container.invalidate(subscriptionChargesProvider(businessId));
    container.invalidate(subscriptionBillingProvider(businessId));
    container.invalidate(paymentsProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aviso de cobro duplicado
// ---------------------------------------------------------------------------

/// Azul aprobó más de una venta por el mismo cobro. Lista las ventas con sus
/// números y la hora con segundos: dos ventas en el mismo segundo es la huella
/// de un reintento concurrente, no de dos meses distintos.
class _DuplicateNotice extends StatelessWidget {
  const _DuplicateNotice({required this.charge});

  final SubscriptionCharge charge;

  @override
  Widget build(BuildContext context) {
    final c = charge;
    final resolved = c.duplicateResolved;
    final color = resolved ? AppColors.mutedForeground : AppColors.destructive;
    final sales = c.azulSales.length;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resolved
                ? 'Cobro duplicado: Azul aprobó $sales ventas por este período. '
                    'Lo cobrado de más ya se devolvió.'
                : 'Cobro duplicado: Azul aprobó $sales ventas por este período. '
                    'El cliente pagó ${formatRd(c.amountCents * sales / 100)} '
                    'en vez de ${formatRd(c.amountCents / 100)}.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: resolved ? AppColors.foreground : AppColors.destructive,
            ),
          ),
          const SizedBox(height: 6),
          for (final sale in c.azulSales)
            Text(
              [
                'Azul #${sale.azulOrderId ?? '?'}',
                if (sale.authorizationCode != null)
                  'autorización ${sale.authorizationCode}',
                _fmtDateTimeSeconds(sale.approvedAt),
              ].join(' · '),
              style: const TextStyle(
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
                color: AppColors.mutedForeground,
              ),
            ),
          if (c.duplicateOutstandingCents > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Reembolsa ${formatRd(c.duplicateOutstandingCents / 100)} '
                'para corregirlo.',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.foreground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila de reembolso
// ---------------------------------------------------------------------------

class _RefundRow extends StatelessWidget {
  const _RefundRow({required this.refund, this.onVerify});

  final ChargeRefund refund;

  /// Solo para reembolsos `pending`.
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final r = refund;
    final (label, color) = _refundStatus(r.status);
    final failure = r.status == 'declined' || r.status == 'error'
        ? (r.errorDescription ?? r.responseMessage)
        : null;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              HugeIcons.strokeRoundedArrowTurnBackward,
              size: 14,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Reembolso ${formatRd(r.amountCents / 100)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: AppColors.foreground,
                      ),
                    ),
                    _Pill(label: label, color: color),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  r.reason,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.foreground,
                  ),
                ),
                Text(
                  [
                    if (r.requestedByEmail != null) r.requestedByEmail!,
                    _fmtDateTime(r.requestedAt),
                    if (r.azulOrderId != null) 'Azul #${r.azulOrderId}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
                if (r.isPending)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text(
                      'Azul no confirmó el resultado. Verifica antes de '
                      'volver a reembolsar: este monto sigue apartado.',
                      style: TextStyle(fontSize: 11, color: AppColors.warning),
                    ),
                  ),
                if (failure != null && failure.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      failure,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.destructive,
                      ),
                    ),
                  ),
                if (r.resolutionNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      r.resolutionNote!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onVerify != null)
            TextButton.icon(
              onPressed: onVerify,
              icon: const Icon(HugeIcons.strokeRoundedSearch01, size: 14),
              label: const Text('Verificar con Azul'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogo de reembolso
// ---------------------------------------------------------------------------

/// Lo que devuelve [RefundChargeDialog].
class RefundRequest {
  const RefundRequest({required this.amountCents, required this.reason});
  final int amountCents;
  final String reason;
}

/// Monto + razón de un reembolso. Valida contra el saldo disponible para
/// avisar antes; el servidor lo vuelve a validar con el cobro bloqueado.
class RefundChargeDialog extends StatefulWidget {
  const RefundChargeDialog({
    required this.businessName,
    required this.charge,
    super.key,
  });

  final String businessName;
  final SubscriptionCharge charge;

  @override
  State<RefundChargeDialog> createState() => _RefundChargeDialogState();
}

class _RefundChargeDialogState extends State<RefundChargeDialog> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  static final _amountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

  SubscriptionCharge get _c => widget.charge;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  /// Centavos del monto escrito; null si está vacío o no es un monto válido.
  int? get _amountCents {
    final raw = _amountController.text.trim().replaceAll(',', '');
    if (raw.isEmpty || !_amountPattern.hasMatch(raw)) return null;
    return (double.parse(raw) * 100).round();
  }

  String? get _amountError {
    if (_amountController.text.trim().isEmpty) return null;
    final cents = _amountCents;
    if (cents == null || cents <= 0) return 'Monto inválido';
    if (cents > _c.refundableCents) {
      return 'Máximo ${formatRd(_c.refundableCents / 100)}';
    }
    return null;
  }

  bool get _canContinue =>
      _amountCents != null &&
      _amountError == null &&
      _reasonController.text.trim().isNotEmpty;

  void _fill(int cents) {
    setState(() => _amountController.text = (cents / 100).toStringAsFixed(2));
  }

  /// Atajo del cobro duplicado: el monto de la venta de más y, si la razón está
  /// vacía, una con los números de Azul (lo que después se busca en el portal).
  void _fillDuplicate() {
    if (_reasonController.text.trim().isEmpty) {
      final ids =
          _c.azulSales.map((s) => '#${s.azulOrderId ?? '?'}').join(' y ');
      _reasonController.text = 'Cobro duplicado: Azul aprobó '
          '${_c.azulSales.length} ventas por el mismo período ($ids).';
    }
    _fill(_c.duplicateOutstandingCents);
  }

  @override
  Widget build(BuildContext context) {
    final over = _c.overPriceCents;
    return AlertDialog(
      title: Text('Reembolsar — ${widget.businessName}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.25),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Cobro del ${_fmtDateTime(_c.attemptedAt)} · '
                  '${formatRd(_c.amountCents / 100)}\n'
                  'Período ${_fmtDate(_c.billingPeriodStart)} → '
                  '${_fmtDate(_c.billingPeriodEnd)} · Azul #${_c.azulOrderId}\n'
                  '${_c.isDuplicated ? 'Cobrado ${_c.azulSales.length} veces en Azul\n' : ''}'
                  '${_c.refundedCents > 0 ? 'Ya reembolsado: ${formatRd(_c.refundedCents / 100)}\n' : ''}'
                  '${_c.pendingRefundCents > 0 ? 'Sin confirmar: ${formatRd(_c.pendingRefundCents / 100)}\n' : ''}'
                  'Disponible para reembolsar: ${formatRd(_c.refundableCents / 100)}',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              const _DialogLabel('Monto a devolver'),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  prefixText: 'RD\$ ',
                  border: const OutlineInputBorder(),
                  errorText: _amountError,
                  helperText: 'Puede ser parcial. Azul permite varios '
                      'reembolsos hasta el total cobrado.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_c.duplicateOutstandingCents > 0)
                    ActionChip(
                      label: Text(
                        'Venta duplicada · '
                        '${formatRd(_c.duplicateOutstandingCents / 100)}',
                      ),
                      onPressed: _fillDuplicate,
                    ),
                  if (over != null && over <= _c.refundableCents)
                    ActionChip(
                      label: Text(
                        'Diferencia con precio actual · ${formatRd(over / 100)}',
                      ),
                      onPressed: () => _fill(over),
                    ),
                  ActionChip(
                    label: Text(
                      'Todo lo disponible · ${formatRd(_c.refundableCents / 100)}',
                    ),
                    onPressed: () => _fill(_c.refundableCents),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _DialogLabel('Razón (obligatoria, queda en auditoría)'),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                minLines: 1,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText:
                      'Ej: se cobró precio de lista con precio especial vigente',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _canContinue
              ? () => Navigator.of(context).pop(
                    RefundRequest(
                      amountCents: _amountCents!,
                      reason: _reasonController.text.trim(),
                    ),
                  )
              : null,
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: AppColors.mutedForeground,
      ),
    );
  }
}

(String, Color) _chargeStatus(String status) => switch (status) {
      'approved' => ('APROBADO', AppColors.success),
      'declined' => ('DECLINADO', AppColors.destructive),
      'error' => ('ERROR', AppColors.warning),
      'pending' => ('PENDIENTE', AppColors.warning),
      'voided' => ('ANULADO', AppColors.mutedForeground),
      _ => (status.toUpperCase(), AppColors.mutedForeground),
    };

(String, Color) _refundStatus(String status) => switch (status) {
      'approved' => ('APROBADO', AppColors.success),
      'pending' => ('SIN CONFIRMAR', AppColors.warning),
      'declined' => ('RECHAZADO', AppColors.destructive),
      'error' => ('NO PROCESADO', AppColors.mutedForeground),
      _ => (status.toUpperCase(), AppColors.mutedForeground),
    };

String _fmtDate(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy').format(d.toLocal());

String _fmtDateTime(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());

String _fmtDateTimeSeconds(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm:ss').format(d.toLocal());
