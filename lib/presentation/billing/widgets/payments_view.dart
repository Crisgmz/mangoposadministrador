import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../domain/models/membership_invoice.dart';
import '../../../domain/models/payment_record.dart';

// ---------------------------------------------------------------------------
// Filtros
// ---------------------------------------------------------------------------

enum PaymentSourceFilter { all, card, manual }

enum PaymentRangeFilter { all, thisMonth, last3Months }

class PaymentFilters {
  const PaymentFilters({
    this.query = '',
    this.source = PaymentSourceFilter.all,
    this.range = PaymentRangeFilter.all,
    this.businessId,
    this.businessName,
  });

  /// Texto libre: negocio, referencia, factura o tarjeta.
  final String query;
  final PaymentSourceFilter source;
  final PaymentRangeFilter range;

  /// Negocio elegido tocando su nombre en la lista.
  final String? businessId;
  final String? businessName;

  PaymentFilters copyWith({
    String? query,
    PaymentSourceFilter? source,
    PaymentRangeFilter? range,
    String? businessId,
    String? businessName,
    bool clearBusiness = false,
  }) {
    return PaymentFilters(
      query: query ?? this.query,
      source: source ?? this.source,
      range: range ?? this.range,
      businessId: clearBusiness ? null : (businessId ?? this.businessId),
      businessName: clearBusiness ? null : (businessName ?? this.businessName),
    );
  }
}

final paymentFiltersProvider = StateProvider.autoDispose<PaymentFilters>(
  (ref) => const PaymentFilters(),
);

/// Aplica los filtros de la pestaña. Pública para poder probarla sin UI.
List<PaymentRecord> applyPaymentFilters(
  List<PaymentRecord> all,
  PaymentFilters f, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final from = switch (f.range) {
    PaymentRangeFilter.all => null,
    PaymentRangeFilter.thisMonth => DateTime(today.year, today.month),
    // Este mes y los dos anteriores (DateTime normaliza meses negativos).
    PaymentRangeFilter.last3Months => DateTime(today.year, today.month - 2),
  };
  final q = f.query.trim().toLowerCase();

  return all
      .where((p) {
        if (f.businessId != null && p.businessId != f.businessId) return false;
        if (f.source == PaymentSourceFilter.card && !p.isCard) return false;
        if (f.source == PaymentSourceFilter.manual && p.isCard) return false;
        if (from != null && p.paidAt.toLocal().isBefore(from)) return false;
        if (q.isNotEmpty) {
          final haystack = [
            p.businessName,
            p.reference,
            p.invoiceNumber,
            p.cardLabel,
          ].whereType<String>().join(' ').toLowerCase();
          if (!haystack.contains(q)) return false;
        }
        return true;
      })
      .toList(growable: false);
}

class PaymentTotals {
  const PaymentTotals({
    required this.count,
    required this.netCents,
    required this.cardCents,
    required this.manualCents,
    required this.refundedCents,
    required this.duplicated,
    required this.missingInvoice,
  });

  final int count;

  /// Cobrado menos reembolsado.
  final int netCents;
  final int cardCents;
  final int manualCents;
  final int refundedCents;

  /// Cobros con más de una venta aprobada en Azul.
  final int duplicated;

  /// Cobros con tarjeta que no dejaron ninguna factura pagada.
  final int missingInvoice;
}

PaymentTotals summarizePayments(List<PaymentRecord> list) {
  var net = 0, card = 0, manual = 0, refunded = 0, dup = 0, missing = 0;
  for (final p in list) {
    net += p.netCents;
    refunded += p.refundedCents;
    if (p.isCard) {
      card += p.netCents;
    } else {
      manual += p.netCents;
    }
    if (p.isDuplicated) dup++;
    if (p.missingInvoice) missing++;
  }
  return PaymentTotals(
    count: list.length,
    netCents: net,
    cardCents: card,
    manualCents: manual,
    refundedCents: refunded,
    duplicated: dup,
    missingInvoice: missing,
  );
}

// ---------------------------------------------------------------------------
// Pestaña
// ---------------------------------------------------------------------------

/// Pestaña "Pagos" de Facturación: todo lo que pagó cada negocio, con tarjeta
/// (Azul) o registrado a mano. Desde la migración 0049 un cobro con tarjeta
/// aprobado deja pagada la factura de su mes solo; esta lista muestra con qué
/// factura quedó cada pago y marca lo que hay que revisar.
class PaymentsView extends ConsumerStatefulWidget {
  const PaymentsView({super.key});

  @override
  ConsumerState<PaymentsView> createState() => _PaymentsViewState();
}

class _PaymentsViewState extends ConsumerState<PaymentsView> {
  /// Filas visibles. Construir cientos de filas de golpe traba la entrada a la
  /// pestaña; se muestran de a tandas.
  static const _pageSize = 100;

  final _search = TextEditingController();
  int _visible = _pageSize;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _update(PaymentFilters Function(PaymentFilters) change) {
    final notifier = ref.read(paymentFiltersProvider.notifier);
    notifier.state = change(notifier.state);
    setState(() => _visible = _pageSize);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(filteredPaymentsProvider);
    final filters = ref.watch(paymentFiltersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          search: _search,
          filters: filters,
          onChanged: _update,
          onRefresh: () => ref.invalidate(paymentsProvider),
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) =>
              _Message('No se pudieron cargar los pagos: $e', error: true),
          data: (all) {
            final rows = applyPaymentFilters(all, filters);
            final totals = summarizePayments(rows);
            final shown = rows.take(_visible).toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalsStrip(totals: totals),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const _Message('No hay pagos con estos filtros.')
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.border, width: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppColors.shadowCard,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: AppColors.border),
                          _PaymentRow(
                            payment: shown[i],
                            onPickBusiness: () => _update(
                              (f) => f.copyWith(
                                businessId: shown[i].businessId,
                                businessName: shown[i].businessName,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (rows.length > shown.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _visible += _pageSize),
                        child: Text(
                          'Mostrar más (${rows.length - shown.length} restantes)',
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de filtros
// ---------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.filters,
    required this.onChanged,
    required this.onRefresh,
  });

  final TextEditingController search;
  final PaymentFilters filters;
  final void Function(PaymentFilters Function(PaymentFilters)) onChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: search,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(HugeIcons.strokeRoundedSearch01, size: 16),
              hintText: 'Buscar negocio, referencia o factura',
            ),
            onChanged: (v) => onChanged((f) => f.copyWith(query: v)),
          ),
        ),
        if (filters.businessId != null)
          InputChip(
            label: Text('Negocio: ${filters.businessName ?? '—'}'),
            onDeleted: () => onChanged((f) => f.copyWith(clearBusiness: true)),
          ),
        for (final (value, label) in const [
          (PaymentSourceFilter.all, 'Todos'),
          (PaymentSourceFilter.card, 'Tarjeta'),
          (PaymentSourceFilter.manual, 'Manual'),
        ])
          ChoiceChip(
            label: Text(label),
            selected: filters.source == value,
            onSelected: (_) => onChanged((f) => f.copyWith(source: value)),
          ),
        const SizedBox(width: 6),
        for (final (value, label) in const [
          (PaymentRangeFilter.all, 'Todo'),
          (PaymentRangeFilter.thisMonth, 'Este mes'),
          (PaymentRangeFilter.last3Months, 'Últimos 3 meses'),
        ])
          ChoiceChip(
            label: Text(label),
            selected: filters.range == value,
            onSelected: (_) => onChanged((f) => f.copyWith(range: value)),
          ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: onRefresh,
          icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Totales
// ---------------------------------------------------------------------------

class _TotalsStrip extends StatelessWidget {
  const _TotalsStrip({required this.totals});

  final PaymentTotals totals;

  @override
  Widget build(BuildContext context) {
    final t = totals;
    final review = t.duplicated + t.missingInvoice;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _TotalTile(
          label: 'Cobrado',
          value: formatRd(t.netCents / 100),
          sublabel: t.refundedCents > 0
              ? '${t.count} pagos · ${formatRd(t.refundedCents / 100)} reembolsado'
              : '${t.count} pagos',
          highlight: true,
        ),
        _TotalTile(
          label: 'Con tarjeta',
          value: formatRd(t.cardCents / 100),
          sublabel: 'Azul, automático',
        ),
        _TotalTile(
          label: 'Manual',
          value: formatRd(t.manualCents / 100),
          sublabel: 'Transferencia, efectivo…',
        ),
        if (review > 0)
          _TotalTile(
            label: 'Revisar',
            value: '$review',
            sublabel: [
              if (t.duplicated > 0)
                t.duplicated == 1
                    ? '1 cobrado 2 veces'
                    : '${t.duplicated} cobrados 2 veces',
              if (t.missingInvoice > 0)
                t.missingInvoice == 1
                    ? '1 sin factura'
                    : '${t.missingInvoice} sin factura',
            ].join(' · '),
            warning: true,
          ),
      ],
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.value,
    required this.sublabel,
    this.highlight = false,
    this.warning = false,
  });

  final String label;
  final String value;
  final String sublabel;
  final bool highlight;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final accent = warning ? AppColors.destructive : AppColors.primary;
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: highlight || warning
            ? accent.withValues(alpha: 0.06)
            : AppColors.card,
        border: Border.all(
          color: highlight || warning
              ? accent.withValues(alpha: 0.25)
              : AppColors.border,
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: warning ? AppColors.destructive : AppColors.foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila
// ---------------------------------------------------------------------------

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.onPickBusiness});

  final PaymentRecord payment;
  final VoidCallback onPickBusiness;

  static const _muted = TextStyle(
    fontSize: 12,
    color: AppColors.mutedForeground,
  );

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;

        final business = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InkWell(
                onTap: onPickBusiness,
                child: Text(
                  p.businessName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Abrir negocio',
              visualDensity: VisualDensity.compact,
              onPressed: () => context.go('/negocios/${p.businessId}'),
              icon: const Icon(HugeIcons.strokeRoundedArrowUpRight01, size: 14),
            ),
          ],
        );

        final when = Text(
          '${_fmtDate(p.paidAt)} · ${DateFormat('HH:mm').format(p.paidAt.toLocal())}',
          style: _muted,
        );

        final period = p.periodStart == null
            ? null
            : Text(
                'Período ${_fmtDate(p.periodStart)} → ${_fmtDate(p.periodEnd)}',
                style: _muted,
              );

        final method = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Pill(
              label: p.methodLabel.toUpperCase(),
              color: p.isCard ? AppColors.primary : AppColors.mutedForeground,
            ),
            if (p.isCard && p.cardLabel != null)
              Text(p.cardLabel!, style: _muted),
            if (p.reference != null && p.reference!.isNotEmpty)
              Text(
                p.isCard ? 'Azul #${p.reference}' : p.reference!,
                style: _muted,
              ),
          ],
        );

        final invoice = p.invoiceNumber != null
            ? Text(
                'Factura ${p.invoiceNumber}'
                '${p.invoiceStatus != null && p.invoiceStatus != InvoiceStatus.paid ? ' (${p.invoiceStatus!.name})' : ''}',
                style: _muted,
              )
            : Text(
                'Sin factura',
                style: _muted.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              );

        final amount = Column(
          crossAxisAlignment: wide
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatRd(p.amountCents / 100),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
                color: AppColors.foreground,
              ),
            ),
            if (p.refundedCents > 0)
              Text(
                'Reembolsado ${formatRd(p.refundedCents / 100)}',
                style: _muted.copyWith(color: AppColors.accent),
              ),
            if (p.isDuplicated)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _Pill(
                  label: 'COBRADO ${p.salesCount} VECES',
                  color: AppColors.destructive,
                ),
              ),
          ],
        );

        if (!wide) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                business,
                when,
                ?period,
                const SizedBox(height: 6),
                method,
                const SizedBox(height: 4),
                invoice,
                const SizedBox(height: 6),
                amount,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [business, when],
                ),
              ),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    method,
                    if (period != null) ...[const SizedBox(height: 4), period],
                  ],
                ),
              ),
              Expanded(flex: 3, child: invoice),
              Expanded(flex: 3, child: amount),
            ],
          ),
        );
      },
    );
  }
}

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

class _Message extends StatelessWidget {
  const _Message(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
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

String _fmtDate(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy').format(d.toLocal());
