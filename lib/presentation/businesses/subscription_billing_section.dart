import 'package:flutter/material.dart';
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
              ..._headerActions(context, ref, billingAsync.valueOrNull!)
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
      if (billing.isTrial) ...[
        FilledButton.icon(
          onPressed: () => _edit(context, ref, billing,
              preset: SubscriptionBillingPreset.activateProduction),
          icon: const Icon(HugeIcons.strokeRoundedRocket, size: 14),
          label: const Text('Quitar trial · Producción'),
        ),
        const SizedBox(width: 8),
      ] else if (billing.billingStatus == 'suspended' ||
          billing.billingStatus == 'cancelled') ...[
        FilledButton.icon(
          onPressed: () => _edit(context, ref, billing,
              preset: SubscriptionBillingPreset.activateProduction),
          icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 14),
          label: const Text('Reactivar'),
        ),
        const SizedBox(width: 8),
      ],
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
}

// ---------------------------------------------------------------------------
// Tarjeta de estado
// ---------------------------------------------------------------------------

class _BillingCard extends StatelessWidget {
  const _BillingCard({required this.billing});
  final SubscriptionBilling billing;

  @override
  Widget build(BuildContext context) {
    final price = billing.priceCentsMonthly == null
        ? null
        : billing.priceCentsMonthly! / 100;
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
              Expanded(
                child: Text(
                  billing.planName == null
                      ? 'Sin plan asignado'
                      : '${billing.planName}'
                          '${price == null ? '' : ' · ${formatRd(price)}/mes'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                  ),
                ),
              ),
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
                    '(${_remaining(billing.nextBillingDate!)})',
          ),
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
