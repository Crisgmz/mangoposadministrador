import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../data/repositories/billing_matrix_repository.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/subscription_billing_repository.dart';
import '../../../domain/models/card_charge_result.dart';
import '../../../domain/models/invoice_payment_result.dart';
import '../../../domain/models/membership_invoice.dart';
import '../../../domain/models/subscription_billing.dart';
import 'edit_invoice_dialog.dart';

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

  factory PayableInvoice.fromInvoice(MembershipInvoice i) => PayableInvoice(
        id: i.id,
        number: i.invoiceNumber,
        businessId: i.businessId,
        businessName: i.businessName,
        total: i.total,
      );

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

  // Un cobro a la tarjeta también es un pago: aparece en Pagos.
  ref.invalidate(subscriptionChargesProvider);

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

/// Registrar el pago de una o varias facturas. Con varias, cada una lleva su
/// casilla: se puede cobrar solo una parte (2 de las 5 pendientes). El precio
/// de cada una se puede cambiar: la factura queda con el monto cobrado
/// (migración 0053).
///
/// Dos formas, a elección del operador:
///   · Registrar pago: el cliente ya pagó por otro medio; no se cobra nada.
///   · Cobrar a la tarjeta: UN cargo por el total a la tarjeta principal del
///     negocio (migración 0054). Solo con facturas de un mismo negocio y
///     tarjeta verificada. Si no se sabe si Azul cobró, el diálogo NO deja
///     volver a cobrar: ofrece Verificar.
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

/// Cómo se paga: se registra un pago ya hecho, o se cobra a la tarjeta.
enum PayMode { manual, card }

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

  /// Las que se van a pagar. Arrancan todas marcadas.
  late final Set<String> _selected = {for (final i in widget.invoices) i.id};

  /// Cada cambio de selección pide otra vista previa; solo vale la última.
  int _previewVersion = 0;

  List<PayableInvoice> get _chosen =>
      widget.invoices.where((i) => _selected.contains(i.id)).toList(growable: false);

  List<String> get _ids => _chosen.map((i) => i.id).toList(growable: false);

  /// Precio a cobrar que el operador cambió, por factura.
  final Map<String, double> _prices = {};

  PayMode _mode = PayMode.manual;

  /// Llave del pedido de cobro a la tarjeta. Se conserva entre reintentos del
  /// MISMO cobro (si se cae la red, repetirla no cobra dos veces) y se
  /// descarta cuando Azul responde algo definitivo.
  String? _requestKey;

  /// Cobro a la tarjeta que quedó sin confirmar: solo se puede verificar.
  String? _pendingChargeId;

  /// Un solo negocio: el cobro a la tarjeta es de un negocio a la vez.
  String? get _singleBusinessId {
    final ids = widget.invoices.map((i) => i.businessId).toSet();
    return ids.length == 1 ? ids.first : null;
  }

  double get _chosenTotal => _chosen.fold(0, (s, i) => s + (_prices[i.id] ?? i.total));

  /// Lo que se manda al servidor: solo las marcadas con precio distinto.
  Map<String, double> get _totals => {
        for (final i in _chosen)
          if (_prices[i.id] != null && (_prices[i.id]! - i.total).abs() >= 0.005) i.id: _prices[i.id]!,
      };

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
    final version = ++_previewVersion;
    final ids = _ids;
    if (ids.isEmpty) return;
    try {
      final preview = await ref
          .read(billingRepositoryProvider)
          .markInvoicesPaid(invoiceIds: ids, method: _method, dryRun: true, totals: _totals);
      if (mounted && version == _previewVersion) setState(() => _preview = preview);
    } catch (e) {
      if (mounted && version == _previewVersion) setState(() => _previewError = '$e');
    }
  }

  void _toggle(String id, bool on) {
    setState(() {
      on ? _selected.add(id) : _selected.remove(id);
      // La vista previa vieja habla de otras facturas: no se puede confirmar
      // con ella.
      _preview = null;
      _previewError = null;
    });
    _loadPreview();
  }

  Future<void> _editPrice(PayableInvoice i) async {
    final price = await showDialog<double>(
      context: context,
      builder: (_) => _PriceDialog(invoice: i, current: _prices[i.id] ?? i.total),
    );
    if (price == null || !mounted) return;
    setState(() {
      if ((price - i.total).abs() < 0.005) {
        _prices.remove(i.id);
      } else {
        _prices[i.id] = price;
      }
      _preview = null;
      _previewError = null;
    });
    _loadPreview();
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
    if (_mode == PayMode.card) return _chargeCard();
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
        totals: _totals,
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

  /// Lo pagado según el servidor o, si respondió sin detalle (cobro ya
  /// cerrado), las facturas que se cobraron.
  InvoicePaymentResult _paidFrom(CardChargeResult r) =>
      r.payment ??
      InvoicePaymentResult(
        paid: [
          for (final i in _chosen)
            PaidInvoice(
              invoiceId: i.id,
              invoiceNumber: i.number,
              businessId: i.businessId,
              businessName: i.businessName,
              total: _prices[i.id] ?? i.total,
            ),
        ],
        skipped: const [],
        moved: const [],
        dryRun: false,
      );

  Future<void> _chargeCard() async {
    final card = _cardLabelOf(_billing(listen: false));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cobrar a la tarjeta'),
        content: Text(
          'Se cobra ${formatRd(_chosenTotal)} a $card, ahora, en un solo cargo por '
          '${_chosen.length} ${_chosen.length == 1 ? "factura" : "facturas"}. Es un cobro real.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cobrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    _requestKey ??= _newRequestKey();
    try {
      final r = await ref.read(billingRepositoryProvider).chargeInvoicesToCard(
            invoiceIds: _ids,
            requestKey: _requestKey!,
            totals: _totals,
          );
      _onCardResult(r);
    } on CardChargeException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
        if (e.code == 'charge_pending') {
          _pendingChargeId = e.chargeId;
        } else if (e.code != 'finalize_failed') {
          // El servidor no llegó a cobrar: el próximo intento es otro pedido.
          _requestKey = null;
        } else {
          _pendingChargeId = e.chargeId;
        }
      });
    } catch (e) {
      // Sin respuesta: puede que se haya cobrado. La misma llave lo sabe.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No llegó la respuesta ($e). Toca "Cobrar" otra vez: con el mismo pedido no se cobra dos veces.';
      });
    }
  }

  Future<void> _verify() async {
    final id = _pendingChargeId;
    if (id == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _onCardResult(await ref.read(billingRepositoryProvider).verifyCardCharge(id));
    } on CardChargeException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  void _onCardResult(CardChargeResult r) {
    if (!mounted) return;
    switch (r.status) {
      case CardChargeStatus.approved:
        Navigator.of(context).pop(_paidFrom(r));
      case CardChargeStatus.pending:
        setState(() {
          _saving = false;
          _pendingChargeId = r.chargeId;
          _error = r.message ?? 'No se supo si Azul cobró. Verifica antes de volver a cobrar.';
        });
      case CardChargeStatus.declined:
      case CardChargeStatus.error:
        setState(() {
          _saving = false;
          _pendingChargeId = null;
          _requestKey = null;
          _error = r.message ?? 'Azul no cobró.';
        });
    }
  }

  static String _newRequestKey() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versión 4
    b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Suscripción del negocio (trae la tarjeta principal). Null con varios negocios.
  AsyncValue<SubscriptionBilling?>? _billing({required bool listen}) {
    final id = _singleBusinessId;
    if (id == null) return null;
    final p = subscriptionBillingProvider(id);
    return listen ? ref.watch(p) : ref.read(p);
  }

  /// "MASTERCARD ••1627" de la tarjeta principal, o null si no se puede cobrar.
  static String? _cardLabelOf(AsyncValue<SubscriptionBilling?>? billing) {
    final card = billing?.valueOrNull?.card;
    if (card == null || card.status != 'verified') return null;
    final m = card.masked ?? '';
    return '${(card.brand ?? 'Tarjeta').toUpperCase()} ••${m.length >= 4 ? m.substring(m.length - 4) : m}';
  }

  /// Por qué no se puede cobrar a la tarjeta, o null si se puede.
  static String? _cardBlockerOf(AsyncValue<SubscriptionBilling?>? billing) {
    if (billing == null) return 'Cobrar a la tarjeta es de un negocio a la vez.';
    if (billing.isLoading) return 'Revisando la tarjeta…';
    final card = billing.valueOrNull?.card;
    if (card == null) return 'El negocio no tiene tarjeta principal.';
    if (card.status != 'verified') return 'La tarjeta principal no está verificada.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final n = _selected.length;
    final payableCount = _preview?.paid.length ?? n;
    final billing = _billing(listen: true);
    final cardBlocker = _cardBlockerOf(billing);
    final byCard = _mode == PayMode.card;
    final pending = _pendingChargeId != null;
    final canConfirm = !_saving &&
        !pending &&
        n > 0 &&
        (!byCard || cardBlocker == null) &&
        (_preview == null ? _previewError != null : payableCount > 0);

    return AlertDialog(
      title: Text(n == 1 ? 'Registrar pago' : 'Registrar pago de $n facturas'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InvoiceSummary(
                invoices: widget.invoices,
                selected: _selected,
                prices: _prices,
                onToggle: _saving || pending || widget.invoices.length == 1 ? null : _toggle,
                onEditPrice: _saving || pending ? null : _editPrice,
              ),
              const SizedBox(height: 16),
              SegmentedButton<PayMode>(
                segments: const [
                  ButtonSegment(
                    value: PayMode.manual,
                    icon: Icon(HugeIcons.strokeRoundedTick02, size: 15),
                    label: Text('Registrar pago'),
                  ),
                  ButtonSegment(
                    value: PayMode.card,
                    icon: Icon(HugeIcons.strokeRoundedCreditCard, size: 15),
                    label: Text('Cobrar a la tarjeta'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _saving || pending
                    ? null
                    : (v) => setState(() {
                          _mode = v.first;
                          _error = null;
                        }),
              ),
              const SizedBox(height: 12),
              if (byCard)
                Text(
                  cardBlocker ??
                      'Se cobra ${formatRd(_chosenTotal)} a ${_cardLabelOf(billing)} (tarjeta principal), '
                          'ahora, en un solo cargo. Si Azul aprueba, las facturas quedan pagadas.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cardBlocker == null ? AppColors.foreground : AppColors.warning,
                  ),
                )
              else ...[
              const Text(
                'El cliente ya pagó por otro medio: no se le cobra nada.',
                style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
              ),
              const SizedBox(height: 10),
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
              ],
              const SizedBox(height: 16),
              if (n == 0)
                const Text(
                  'Marca al menos una factura.',
                  style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                )
              else
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
          child: Text(pending ? 'Cerrar' : 'Cancelar'),
        ),
        if (pending)
          FilledButton(
            onPressed: _saving ? null : _verify,
            child: const Text('Verificar cobro'),
          )
        else
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
                  byCard
                      ? 'Cobrar ${formatRd(_chosenTotal)}'
                      : payableCount == 1
                          ? 'Marcar como pagada'
                          : payableCount == 0
                              ? 'Marcar como pagadas'
                              : 'Marcar $payableCount como pagadas',
                ),
        ),
      ],
    );
  }
}

class _InvoiceSummary extends StatelessWidget {
  const _InvoiceSummary({
    required this.invoices,
    required this.selected,
    required this.prices,
    required this.onToggle,
    required this.onEditPrice,
  });
  final List<PayableInvoice> invoices;
  final Set<String> selected;
  final Map<String, double> prices;

  /// Null = sin casillas (una sola factura, o guardando).
  final void Function(String id, bool on)? onToggle;
  final void Function(PayableInvoice invoice)? onEditPrice;

  @override
  Widget build(BuildContext context) {
    final total = invoices
        .where((i) => selected.contains(i.id))
        .fold<double>(0, (s, i) => s + (prices[i.id] ?? i.total));
    final checkable = invoices.length > 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final i in invoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  if (checkable)
                    SizedBox(
                      width: 28,
                      height: 22,
                      child: Checkbox(
                        value: selected.contains(i.id),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: onToggle == null ? null : (v) => onToggle!(i.id, v ?? false),
                      ),
                    ),
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
                  if (prices[i.id] != null) ...[
                    Text(
                      formatRd(i.total),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground,
                        decoration: TextDecoration.lineThrough,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Tocar el monto cambia el precio a cobrar.
                  Tooltip(
                    message: 'Cambiar el precio a cobrar',
                    child: InkWell(
                      key: ValueKey('price-${i.id}'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: onEditPrice == null ? null : () => onEditPrice!(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatRd(prices[i.id] ?? i.total),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: prices[i.id] != null ? AppColors.accent : null,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(HugeIcons.strokeRoundedEdit02, size: 12, color: AppColors.mutedForeground),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  checkable && selected.length != invoices.length
                      ? 'Total (${selected.length} de ${invoices.length})'
                      : 'Total',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
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

/// Precio a cobrar de una factura.
class _PriceDialog extends StatefulWidget {
  const _PriceDialog({required this.invoice, required this.current});
  final PayableInvoice invoice;
  final double current;

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final _controller = TextEditingController(text: widget.current.toStringAsFixed(2));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseAmount(_controller.text);
    if (v == null || v < 0) {
      setState(() => _error = 'Escribe un monto válido.');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Precio a cobrar · ${widget.invoice.number}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Total',
                prefixText: 'RD\$ ',
                errorText: _error,
                helperText: 'Factura: ${formatRd(widget.invoice.total)}. '
                    'La factura queda con este monto.',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(widget.invoice.total),
          child: const Text('Volver al de la factura'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Usar este precio')),
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
