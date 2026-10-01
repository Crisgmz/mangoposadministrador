import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/subscription_billing_repository.dart';
import '../../domain/models/subscription_billing.dart';

/// Sección "Suscripción y cobro automático" del detalle de negocio.
///
/// Muestra la membresía ancla (`memberships.is_billing_anchor`) con su
/// `billing_status`, fechas de trial/cobro y tarjeta Azul, y permite al
/// operador quitar el trial, pasar a producción (estado `active`, elegible
/// para el cron de cobro automático), mover fechas y resetear intentos.
class SubscriptionBillingSection extends ConsumerWidget {
  const SubscriptionBillingSection({
    required this.businessId,
    required this.businessName,
    super.key,
  });

  final String businessId;
  final String businessName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billingAsync = ref.watch(subscriptionBillingProvider(businessId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              HugeIcons.strokeRoundedCreditCard,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Suscripción y cobro automático',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ),
            if (billingAsync.valueOrNull != null)
              // Wrap y no Row: con trial + precio especial + editar son tres
              // botones, y en un detalle angosto desbordaban la cabecera.
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _headerActions(context, ref, billingAsync.valueOrNull!),
                ),
              )
            else if (billingAsync.hasValue)
              OutlinedButton.icon(
                onPressed: () => _edit(context, ref, null,
                    preset: SubscriptionBillingPreset.activateProduction),
                icon: const Icon(HugeIcons.strokeRoundedSettings02, size: 14),
                label: const Text('Configurar suscripción'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        billingAsync.when(
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
          error: (e, _) => _messageCard('Error: $e', error: true),
          data: (billing) {
            if (billing == null) {
              return _messageCard(
                'Este negocio no tiene suscripción de cobro configurada. '
                'Usa "Configurar suscripción" para activar el cobro automático.',
              );
            }
            return _BillingCard(billing: billing);
          },
        ),
      ],
    );
  }

  List<Widget> _headerActions(
    BuildContext context,
    WidgetRef ref,
    SubscriptionBilling billing,
  ) {
    return [
      if (billing.isTrial)
        FilledButton.icon(
          onPressed: () => _edit(context, ref, billing,
              preset: SubscriptionBillingPreset.activateProduction),
          icon: const Icon(HugeIcons.strokeRoundedRocket, size: 14),
          label: const Text('Quitar trial · Producción'),
        )
      else if (billing.billingStatus == 'suspended' ||
          billing.billingStatus == 'cancelled')
        FilledButton.icon(
          onPressed: () => _edit(context, ref, billing,
              preset: SubscriptionBillingPreset.activateProduction),
          icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 14),
          label: const Text('Reactivar'),
        ),
      // Sin plan no hay contra qué comparar el precio: el servidor lo rechaza,
      // así que ni se ofrece.
      if (billing.planCode != null)
        OutlinedButton.icon(
          onPressed: () => _editPrice(context, ref, billing),
          icon: const Icon(HugeIcons.strokeRoundedTag01, size: 14),
          label: Text(
            billing.hasPriceOverride ? 'Precio especial' : 'Dar precio especial',
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => _edit(context, ref, billing),
        icon: const Icon(HugeIcons.strokeRoundedCalendar03, size: 14),
        label: const Text('Editar fechas / estado'),
      ),
    ];
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
        style: TextStyle(
          color: error ? AppColors.destructive : AppColors.mutedForeground,
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    SubscriptionBilling? billing, {
    SubscriptionBillingPreset preset = SubscriptionBillingPreset.edit,
  }) async {
    final result = await showDialog<SubscriptionBillingEditResult>(
      context: context,
      builder: (_) => SubscriptionBillingDialog(
        businessName: businessName,
        billing: billing,
        preset: preset,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(subscriptionBillingRepositoryProvider).update(
            businessId: businessId,
            reason: result.reason,
            billingStatus: result.billingStatus,
            trialEndsAt: result.trialEndsAt,
            clearTrial: result.clearTrial,
            nextBillingDate: result.nextBillingDate,
            currentPeriodStart: result.currentPeriodStart,
            currentPeriodEnd: result.currentPeriodEnd,
            resetAttempts: result.resetAttempts,
          );
      ref.invalidate(subscriptionBillingProvider(businessId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suscripción de $businessName actualizada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _editPrice(
    BuildContext context,
    WidgetRef ref,
    SubscriptionBilling billing,
  ) async {
    final result = await showDialog<PriceOverrideResult>(
      context: context,
      builder: (_) => PriceOverrideDialog(
        businessName: businessName,
        billing: billing,
      ),
    );
    if (result == null || !context.mounted) return;
    final repo = ref.read(subscriptionBillingRepositoryProvider);
    try {
      if (result.clear) {
        await repo.clearPriceOverride(
          businessId: businessId,
          reason: result.reason,
        );
      } else {
        await repo.setPriceOverride(
          businessId: businessId,
          priceMonthly: result.priceMonthly!,
          endsOn: result.endsOn,
          reason: result.reason,
        );
      }
      ref.invalidate(subscriptionBillingProvider(businessId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.clear
                ? '$businessName vuelve al precio de lista.'
                : 'Precio especial de $businessName: '
                    '${formatRd(result.priceMonthly!)}/mes.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de estado
// ---------------------------------------------------------------------------

class _BillingCard extends StatelessWidget {
  const _BillingCard({required this.billing});
  final SubscriptionBilling billing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StatusBadge(status: billing.billingStatus),
              const SizedBox(width: 10),
              Expanded(child: _PlanPriceLine(billing: billing)),
            ],
          ),
          const SizedBox(height: 14),
          _row(
            'Trial termina',
            billing.trialEndsAt == null
                ? '—'
                : '${_fmtDate(billing.trialEndsAt)} '
                    '(${_remaining(billing.trialEndsAt!)})',
            highlight: billing.isTrial &&
                billing.trialEndsAt != null &&
                daysUntil(billing.trialEndsAt) < 3,
          ),
          _row(
            'Próximo cobro',
            billing.nextBillingDate == null
                ? '—'
                : '${_fmtDate(billing.nextBillingDate)} '
                    '(${_remaining(billing.nextBillingDate!)})'
                    '${billing.chargePriceCents == null ? '' : ' · ${formatRd(billing.chargePriceCents! / 100)}'}',
          ),
          if (billing.priceOverrideApplies) ...[
            _row('Precio especial', _savingsLabel()),
            _row(
              'Aplica hasta',
              billing.priceOverrideEndsOn == null
                  ? 'Sin vencimiento'
                  : '${_fmtDate(billing.priceOverrideEndsOn)} '
                      '(${_remaining(billing.priceOverrideEndsOn!)})',
            ),
            if (billing.priceOverrideReason != null)
              _row('Motivo', billing.priceOverrideReason!),
          ] else if (billing.priceOverrideStale)
            _row('Precio especial', _staleOverrideLabel(), highlight: true),
          _row(
            'Período vigente',
            billing.currentPeriodStart == null &&
                    billing.currentPeriodEnd == null
                ? '—'
                : '${_fmtDate(billing.currentPeriodStart)} → '
                    '${_fmtDate(billing.currentPeriodEnd)}',
          ),
          _row(
            'Intentos de cobro',
            '${billing.currentAttemptNumber} de 3',
            highlight: billing.currentAttemptNumber > 0,
          ),
          _row(
            'Tarjeta',
            billing.card == null
                ? 'Sin tarjeta registrada'
                : '${billing.card!.brand ?? ''} '
                        '${billing.card!.masked ?? ''} · ${_cardStatusLabel(billing.card!.status)}'
                    .trim(),
            highlight: billing.card == null || !billing.hasVerifiedCard,
          ),
          if (billing.lastCharge != null)
            _row(
              'Último cobro',
              '${_chargeStatusLabel(billing.lastCharge!.status)}'
              '${billing.lastCharge!.amountCents == null ? '' : ' · ${formatRd(billing.lastCharge!.amountCents! / 100)}'}'
              '${billing.lastCharge!.attemptedAt == null ? '' : ' · ${formatRelative(billing.lastCharge!.attemptedAt)}'}',
              highlight: billing.lastCharge!.status == 'declined' ||
                  billing.lastCharge!.status == 'error',
            ),
          if (billing.billingStatus == 'cancelled' &&
              billing.cancellationReason != null)
            _row('Razón de cancelación', billing.cancellationReason!),
          const SizedBox(height: 12),
          _AutoChargeBanner(billing: billing),
        ],
      ),
    );
  }

  /// "Ahorra RD$1,799.00 (37.5%)".
  String _savingsLabel() {
    final list = billing.priceCentsMonthly;
    final effective = billing.effectivePriceCents;
    if (list == null || effective == null || list <= 0) return '—';
    final saved = list - effective;
    return 'Ahorra ${formatRd(saved / 100)} (${_pct(saved / list)})';
  }

  /// Por qué un precio especial cargado NO se va a aplicar al próximo cobro.
  String _staleOverrideLabel() {
    final amount = formatRd(billing.priceOverrideCents! / 100);
    final forPlan = billing.priceOverridePlanCode;
    if (forPlan != null && forPlan != billing.planCode) {
      return 'No aplica: $amount era para el plan $forPlan';
    }
    final ends = billing.priceOverrideEndsOn;
    if (ends != null) {
      final now = DateTime.now();
      final expired = DateTime(ends.year, ends.month, ends.day)
          .isBefore(DateTime(now.year, now.month, now.day));
      return expired
          ? 'Venció el ${_fmtDate(ends)} ($amount)'
          : 'Vence el ${_fmtDate(ends)}, antes del próximo cobro';
    }
    return 'No aplica ($amount)';
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color:
                    highlight ? AppColors.warning : AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _remaining(DateTime when) {
    final days = daysUntil(when);
    if (days < 0) return 'venció hace ${-days}d';
    if (days == 0) return 'hoy';
    return 'en $days días';
  }
}

/// Banner de elegibilidad para el cron de cobro automático.
class _AutoChargeBanner extends StatelessWidget {
  const _AutoChargeBanner({required this.billing});
  final SubscriptionBilling billing;

  @override
  Widget build(BuildContext context) {
    final ready = billing.autoChargeReady;
    final color = ready ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready
                    ? HugeIcons.strokeRoundedCheckmarkCircle02
                    : HugeIcons.strokeRoundedAlert02,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready
                      ? 'Cobro automático ACTIVO — se cobrará el ${_fmtDate(billing.nextBillingDate)}.'
                      : 'Cobro automático INACTIVO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (!ready) ...[
            const SizedBox(height: 6),
            for (final reason in billing.autoChargeBlockers)
              Padding(
                padding: const EdgeInsets.only(left: 23, top: 2),
                child: Text(
                  '• $reason',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.foreground,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'trial' => ('TRIAL', AppColors.accent),
      'active' => ('ACTIVA', AppColors.success),
      'past_due' => ('ATRASADA', AppColors.warning),
      'suspended' => ('SUSPENDIDA', AppColors.destructive),
      'cancelled' => ('CANCELADA', AppColors.mutedForeground),
      _ => (status.toUpperCase(), AppColors.mutedForeground),
    };
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

String _cardStatusLabel(String status) => switch (status) {
      'verified' => 'Verificada',
      'pending_verification' => 'Pendiente de verificar',
      'failed_verification' => 'Verificación fallida',
      'expired' => 'Expirada',
      'revoked' => 'Revocada',
      _ => status,
    };

String _chargeStatusLabel(String status) => switch (status) {
      'approved' => 'Aprobado',
      'declined' => 'Declinado',
      'error' => 'Error',
      'pending' => 'Pendiente',
      'voided' => 'Anulado',
      _ => status,
    };

String _fmtDate(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy').format(d.toLocal());

// ---------------------------------------------------------------------------
// Diálogo de edición
// ---------------------------------------------------------------------------

enum SubscriptionBillingPreset { edit, activateProduction }

class SubscriptionBillingEditResult {
  const SubscriptionBillingEditResult({
    required this.reason,
    this.billingStatus,
    this.trialEndsAt,
    this.clearTrial = false,
    this.nextBillingDate,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.resetAttempts = false,
  });

  final String reason;
  final String? billingStatus;
  final DateTime? trialEndsAt;
  final bool clearTrial;
  final DateTime? nextBillingDate;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool resetAttempts;
}

class SubscriptionBillingDialog extends StatefulWidget {
  const SubscriptionBillingDialog({
    required this.businessName,
    required this.billing,
    this.preset = SubscriptionBillingPreset.edit,
    super.key,
  }) ;

  final String businessName;

  /// `null` cuando el negocio aún no tiene membresía ancla configurada.
  final SubscriptionBilling? billing;
  final SubscriptionBillingPreset preset;

  @override
  State<SubscriptionBillingDialog> createState() =>
      _SubscriptionBillingDialogState();
}

class _SubscriptionBillingDialogState extends State<SubscriptionBillingDialog> {
  static const _statuses = <(String, String)>[
    ('trial', 'Trial'),
    ('active', 'Activa (producción)'),
    ('past_due', 'Atrasada'),
    ('suspended', 'Suspendida'),
    ('cancelled', 'Cancelada'),
  ];

  final _reasonController = TextEditingController();
  late String _status;
  late bool _clearTrial;
  DateTime? _trialEndsAt;
  DateTime? _nextBillingDate;
  DateTime? _periodStart;
  DateTime? _periodEnd;
  late bool _resetAttempts;
  bool _periodEndTouched = false;

  bool get _activateMode => widget.preset == SubscriptionBillingPreset.activateProduction;

  @override
  void initState() {
    super.initState();
    final b = widget.billing;
    if (_activateMode) {
      final today = DateTime.now();
      final existingNext = b?.nextBillingDate;
      _status = 'active';
      _clearTrial = b?.trialEndsAt != null;
      _trialEndsAt = null;
      _nextBillingDate =
          (existingNext != null && existingNext.isAfter(today))
              ? existingNext
              : today.add(const Duration(days: 30));
      _periodStart = today;
      _periodEnd = _nextBillingDate;
      _resetAttempts = true;
    } else {
      _status = b?.billingStatus ?? 'trial';
      _clearTrial = false;
      _trialEndsAt = b?.trialEndsAt;
      _nextBillingDate = b?.nextBillingDate;
      _periodStart = b?.currentPeriodStart;
      _periodEnd = b?.currentPeriodEnd;
      _resetAttempts = false;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _enabled => _reasonController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _activateMode
            ? 'Activar producción — ${widget.businessName}'
            : 'Editar suscripción — ${widget.businessName}',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_activateMode)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.25),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Quita el trial y deja la suscripción en producción '
                    '(estado Activa). El cron cobrará automáticamente en la '
                    'fecha de próximo cobro si el negocio tiene plan y '
                    'tarjeta verificada.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.foreground),
                  ),
                ),
              const _DialogLabel('Estado de la suscripción'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _status,
                items: [
                  for (final (value, label) in _statuses)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              if (widget.billing?.trialEndsAt != null || _status == 'trial') ...[
                CheckboxListTile(
                  value: _clearTrial,
                  onChanged: (v) => setState(() => _clearTrial = v ?? false),
                  title: const Text(
                    'Quitar trial (borrar fecha de fin de trial)',
                    style: TextStyle(fontSize: 13),
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (!_clearTrial)
                  _DateField(
                    label: 'Trial termina',
                    value: _trialEndsAt,
                    onChanged: (d) => setState(() => _trialEndsAt = d),
                  ),
                const SizedBox(height: 10),
              ],
              _DateField(
                label: 'Próximo cobro',
                value: _nextBillingDate,
                onChanged: (d) => setState(() {
                  _nextBillingDate = d;
                  // El período vigente normalmente termina el día del cobro.
                  if (!_periodEndTouched) _periodEnd = d;
                }),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Período desde',
                      value: _periodStart,
                      onChanged: (d) => setState(() => _periodStart = d),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: 'Período hasta',
                      value: _periodEnd,
                      onChanged: (d) => setState(() {
                        _periodEnd = d;
                        _periodEndTouched = true;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _resetAttempts,
                onChanged: (v) => setState(() => _resetAttempts = v ?? false),
                title: Text(
                  'Resetear intentos de cobro'
                  '${widget.billing == null ? '' : ' (actual: ${widget.billing!.currentAttemptNumber} de 3)'}',
                  style: const TextStyle(fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 10),
              const _DialogLabel('Razón (obligatoria, queda en auditoría)'),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Ej: cliente pagó por transferencia, pasa a producción…',
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
          onPressed: _enabled
              ? () => Navigator.of(context).pop(
                    SubscriptionBillingEditResult(
                      reason: _reasonController.text.trim(),
                      billingStatus: _status,
                      trialEndsAt: _clearTrial ? null : _trialEndsAt,
                      clearTrial: _clearTrial,
                      nextBillingDate: _nextBillingDate,
                      currentPeriodStart: _periodStart,
                      currentPeriodEnd: _periodEnd,
                      resetAttempts: _resetAttempts,
                    ),
                  )
              : null,
          child: Text(_activateMode ? 'Activar producción' : 'Guardar'),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DialogLabel(label),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 2),
              lastDate: DateTime(now.year + 3),
            );
            if (picked != null) onChanged(picked);
          },
          icon: const Icon(HugeIcons.strokeRoundedCalendar03, size: 14),
          label: Text(
            value == null ? 'Elegir fecha' : _fmtDate(value),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
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

// ---------------------------------------------------------------------------
// Precio especial
// ---------------------------------------------------------------------------

/// 0.375 → "37.5%", 0.4 → "40%".
String _pct(double ratio) {
  final s = (ratio * 100).toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}%';
}

/// Plan + precio en la cabecera de la tarjeta. Con precio especial vigente
/// muestra lo que paga, la lista tachada y la marca: de un vistazo se ve que
/// ese cliente no paga lo mismo que el resto.
class _PlanPriceLine extends StatelessWidget {
  const _PlanPriceLine({required this.billing});
  final SubscriptionBilling billing;

  static const _base = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.foreground,
  );

  @override
  Widget build(BuildContext context) {
    final name = billing.planName;
    if (name == null) return const Text('Sin plan asignado', style: _base);

    final list = billing.priceCentsMonthly;
    final effective = billing.effectivePriceCents;
    if (!billing.priceOverrideApplies || list == null || effective == null) {
      return Text(
        '$name${list == null ? '' : ' · ${formatRd(list / 100)}/mes'}',
        style: _base,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$name · ${formatRd(effective / 100)}/mes', style: _base),
        Text(
          formatRd(list / 100),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.mutedForeground,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'PRECIO ESPECIAL',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Lo que devuelve [PriceOverrideDialog].
class PriceOverrideResult {
  const PriceOverrideResult.set({
    required this.reason,
    required double this.priceMonthly,
    this.endsOn,
  }) : clear = false;

  const PriceOverrideResult.clear({required this.reason})
      : priceMonthly = null,
        endsOn = null,
        clear = true;

  final String reason;
  final double? priceMonthly;
  final DateTime? endsOn;
  final bool clear;
}

/// Dar, cambiar o quitar el precio especial de un cliente.
///
/// Muestra el ahorro en vivo contra el precio de lista: el error típico acá es
/// de tipeo (47990 por 4799) y verlo como "debe ser menor al precio de lista"
/// antes de guardar lo delata. El servidor igual lo rechaza.
class PriceOverrideDialog extends StatefulWidget {
  const PriceOverrideDialog({
    required this.businessName,
    required this.billing,
    super.key,
  });

  final String businessName;
  final SubscriptionBilling billing;

  @override
  State<PriceOverrideDialog> createState() => _PriceOverrideDialogState();
}

class _PriceOverrideDialogState extends State<PriceOverrideDialog> {
  late final TextEditingController _priceController;
  final _reasonController = TextEditingController();
  late bool _hasEnd;
  DateTime? _endsOn;

  SubscriptionBilling get _b => widget.billing;

  @override
  void initState() {
    super.initState();
    final current = _b.priceOverrideCents;
    _priceController = TextEditingController(
      text: current == null ? '' : (current / 100).toStringAsFixed(2),
    );
    _endsOn = _b.priceOverrideEndsOn;
    _hasEnd = _endsOn != null;
  }

  @override
  void dispose() {
    _priceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double? get _price {
    final raw = _priceController.text.trim().replaceAll(',', '');
    return raw.isEmpty ? null : double.tryParse(raw);
  }

  String? get _priceError {
    if (_priceController.text.trim().isEmpty) return null;
    final p = _price;
    if (p == null || p <= 0) return 'Monto inválido';
    final list = _b.priceCentsMonthly;
    if (list != null && (p * 100).round() >= list) {
      return 'Tiene que ser menor al precio de lista (${formatRd(list / 100)})';
    }
    return null;
  }

  String? get _endError {
    if (!_hasEnd) return null;
    final e = _endsOn;
    if (e == null) return 'Elige hasta cuándo aplica';
    final now = DateTime.now();
    if (DateTime(e.year, e.month, e.day)
        .isBefore(DateTime(now.year, now.month, now.day))) {
      return 'No puede estar en el pasado';
    }
    return null;
  }

  String? get _savings {
    final p = _price;
    final list = _b.priceCentsMonthly;
    if (p == null || list == null || list <= 0 || _priceError != null) {
      return null;
    }
    final listRd = list / 100;
    final saved = listRd - p;
    return 'Ahorra ${formatRd(saved)}/mes (${_pct(saved / listRd)})';
  }

  bool get _reasonOk => _reasonController.text.trim().isNotEmpty;

  bool get _canSave =>
      _price != null && _priceError == null && _endError == null && _reasonOk;

  @override
  Widget build(BuildContext context) {
    final list = _b.priceCentsMonthly;
    return AlertDialog(
      title: Text('Precio especial — ${widget.businessName}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
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
                  'Plan ${_b.planName ?? _b.planCode ?? '—'}'
                  '${list == null ? '' : ' · lista ${formatRd(list / 100)}/mes'}.\n'
                  'Aplica solo mientras el negocio siga en este plan: si '
                  'cambia de plan, vuelve al precio normal.',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              const _DialogLabel('Precio mensual para este cliente'),
              const SizedBox(height: 6),
              TextField(
                controller: _priceController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  prefixText: 'RD\$ ',
                  border: const OutlineInputBorder(),
                  errorText: _priceError,
                  helperText: _savings,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _hasEnd,
                onChanged: (v) => setState(() => _hasEnd = v ?? false),
                title: const Text(
                  'Con fecha de vencimiento',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Sin fecha, aplica hasta que lo quites.',
                  style: TextStyle(fontSize: 11),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_hasEnd) ...[
                _DateField(
                  label: 'Aplica hasta (inclusive)',
                  value: _endsOn,
                  onChanged: (d) => setState(() => _endsOn = d),
                ),
                if (_endError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _endError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.destructive,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              const _DialogLabel('Razón (obligatoria, queda en auditoría)'),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Ej: cliente fundador, acuerdo comercial…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_b.hasPriceOverride)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            onPressed: _reasonOk
                ? () => Navigator.of(context).pop(
                      PriceOverrideResult.clear(
                        reason: _reasonController.text.trim(),
                      ),
                    )
                : null,
            child: const Text('Quitar precio especial'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _canSave
              ? () => Navigator.of(context).pop(
                    PriceOverrideResult.set(
                      reason: _reasonController.text.trim(),
                      priceMonthly: _price!,
                      endsOn: _hasEnd ? _endsOn : null,
                    ),
                  )
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
