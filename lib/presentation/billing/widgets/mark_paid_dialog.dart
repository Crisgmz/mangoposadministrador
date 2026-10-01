import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../data/repositories/billing_matrix_repository.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/subscription_billing_repository.dart';
import '../../../domain/models/invoice_payment_result.dart';

/// Lo mínimo para pagar una factura, venga de la lista de facturas o de una
/// celda de la matriz.
class PayableInvoice {
  const PayableInvoice({
    required this.id,
    required this.number,
    required this.businessId,
    required this.businessName,
    required this.total,
  });

  final String id;
  final String number;
  final String businessId;
  final String businessName;
  final double total;
}

/// Abre el diálogo, registra el pago y refresca todo lo que depende de él
/// (lista, métricas, matriz, facturas y suscripción de cada negocio tocado).
/// Devuelve el resultado, o `null` si se canceló.
Future<InvoicePaymentResult?> showMarkPaidDialog(
  BuildContext context,
  WidgetRef ref,
  List<PayableInvoice> invoices,
) async {
  if (invoices.isEmpty) return null;
  final result = await showDialog<InvoicePaymentResult>(
    context: context,
    builder: (_) => MarkPaidDialog(invoices: invoices),
  );
  if (result == null) return null;

  ref.invalidate(billingOverviewProvider);
  ref.invalidate(billingMetricsProvider);
  ref.invalidate(billingMatrixProvider);
  ref.invalidate(paymentsProvider);
  final touched = {
    for (final p in result.paid) p.businessId,
    for (final m in result.moved) m.businessId,
  };
  for (final id in touched) {
    ref.invalidate(businessInvoicesProvider(id));
    // El próximo cobro con tarjeta pudo moverse: la tarjeta de suscripción
    // del detalle tiene que mostrar la fecha nueva.
    ref.invalidate(subscriptionBillingProvider(id));
  }

  if (context.mounted) {
    final n = result.paid.length;
    final moved = result.moved.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$n ${n == 1 ? "factura pagada" : "facturas pagadas"} · '
          '${formatRd(result.totalPaid)}'
          '${moved == 0 ? '' : ' · $moved ${moved == 1 ? "cobro con tarjeta corrido" : "cobros con tarjeta corridos"}'}',
        ),
      ),
    );
  }
  return result;
}

/// Registrar el pago de una o varias facturas.
///
/// Al abrir pide al servidor una vista previa (misma lógica, revertida) para
/// mostrar ANTES de confirmar qué cobros con tarjeta se van a correr. Ese es
/// el efecto que no se ve a simple vista y el que evita cobrar dos veces.
class MarkPaidDialog extends ConsumerStatefulWidget {
  const MarkPaidDialog({required this.invoices, super.key});

  final List<PayableInvoice> invoices;

  @override
  ConsumerState<MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends ConsumerState<MarkPaidDialog> {
  static const _methods = <(String, String)>[
    ('transfer', 'Transferencia'),
    ('cash', 'Efectivo'),
    ('card', 'Tarjeta'),
    ('other', 'Otro'),
  ];

  final _referenceController = TextEditingController();
  String _method = 'transfer';
  DateTime _paidOn = DateTime.now();

  InvoicePaymentResult? _preview;
  String? _previewError;
  bool _saving = false;
  String? _error;

  List<String> get _ids =>
      widget.invoices.map((i) => i.id).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    try {
      final preview = await ref
          .read(billingRepositoryProvider)
          .markInvoicesPaid(invoiceIds: _ids, method: _method, dryRun: true);
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _previewError = '$e');
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _paidOn.year == now.year &&
        _paidOn.month == now.month &&
        _paidOn.day == now.day;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      helpText: 'Fecha del pago',
    );
    if (picked != null) setState(() => _paidOn = picked);
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref.read(billingRepositoryProvider).markInvoicesPaid(
        invoiceIds: _ids,
        method: _method,
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        // Hoy → hora del servidor. Otro día → mediodía, para que ninguna zona
        // horaria lo empuje al día anterior.
        paidAt: _isToday
            ? null
            : DateTime(_paidOn.year, _paidOn.month, _paidOn.day, 12),
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.invoices.length;
    final payableCount = _preview?.paid.length ?? n;
    final canConfirm =
        !_saving && (_preview == null ? _previewError != null : payableCount > 0);

    return AlertDialog(
      title: Text(n == 1 ? 'Registrar pago' : 'Registrar pago de $n facturas'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InvoiceSummary(invoices: widget.invoices),
              const SizedBox(height: 16),
              const _Label('Método de pago'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (value, label) in _methods)
                    ChoiceChip(
                      label: Text(label),
                      selected: _method == value,
                      onSelected: (_) => setState(() => _method = value),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _referenceController,
                      decoration: const InputDecoration(
                        labelText: 'Referencia (opcional)',
                        hintText: 'Nº de transferencia, recibo…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(HugeIcons.strokeRoundedCalendar03, size: 14),
                    label: Text(
                      _isToday
                          ? 'Hoy'
                          : DateFormat('d MMM yyyy', 'es_DO').format(_paidOn),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Impact(preview: _preview, error: _previewError),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.destructive,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: canConfirm ? _confirm : null,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  payableCount == 1
                      ? 'Marcar como pagada'
                      : 'Marcar $payableCount como pagadas',
                ),
        ),
      ],
    );
  }
}

class _InvoiceSummary extends StatelessWidget {
  const _InvoiceSummary({required this.invoices});
  final List<PayableInvoice> invoices;

  static const _maxLines = 5;

  @override
  Widget build(BuildContext context) {
    final total = invoices.fold<double>(0, (s, i) => s + i.total);
    final shown = invoices.take(_maxLines).toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final i in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(
                    i.number,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      i.businessName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Text(
                    formatRd(i.total),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          if (invoices.length > _maxLines)
            Text(
              'y ${invoices.length - _maxLines} más',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.mutedForeground,
              ),
            ),
          const Divider(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                formatRd(total),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Qué más cambia al confirmar: cobros con tarjeta que se corren y facturas
/// que se omiten.
class _Impact extends StatelessWidget {
  const _Impact({required this.preview, required this.error});
  final InvoicePaymentResult? preview;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Text(
        'No se pudo calcular el efecto sobre los cobros con tarjeta: $error',
        style: const TextStyle(fontSize: 12, color: AppColors.warning),
      );
    }
    final p = preview;
    if (p == null) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Revisando cobros con tarjeta…',
            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
          ),
        ],
      );
    }

    final fmt = DateFormat('d MMM', 'es_DO');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.moved.isEmpty)
          const Text(
            'Ningún cobro con tarjeta se ve afectado.',
            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Se corre el próximo cobro con tarjeta',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Estas facturas ya cubren esos períodos: así no se cobra dos veces.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
                ),
                const SizedBox(height: 8),
                for (final m in p.moved)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${m.businessName} · ${fmt.format(m.from)} → ${fmt.format(m.to)}'
                      '${m.wasPastDue ? ' · estaba atrasada, vuelve a activa' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        if (p.skipped.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Se omiten ${p.skipped.length}: '
            '${p.skipped.map((s) => '${s.invoiceNumber ?? 'factura'} (${s.reasonLabel})').join(', ')}',
            style: const TextStyle(fontSize: 12, color: AppColors.warning),
          ),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: AppColors.mutedForeground,
    ),
  );
}
