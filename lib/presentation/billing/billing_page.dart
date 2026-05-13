import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/services/invoice_pdf.dart';
import '../../domain/models/membership_invoice.dart';
import '../dashboard/widgets/metric_card.dart';
import '../shared/page_header.dart';

final _selectedStatusFilter =
    StateProvider.autoDispose<InvoiceStatus?>((ref) => null);

class BillingPage extends ConsumerWidget {
  const BillingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(filteredBillingOverviewProvider);
    final metricsAsync = ref.watch(billingMetricsProvider);
    final filter = ref.watch(_selectedStatusFilter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Facturación',
          title: 'Cobros y membresías',
          subtitle:
              'Genera facturas de plan, registra pagos y marca cuentas vencidas.',
          trailing: FilledButton.icon(
            onPressed: () => _bulkGenerate(context, ref),
            icon: const Icon(HugeIcons.strokeRoundedFile02, size: 16),
            label: const Text('Generar facturas del mes'),
          ),
        ),
        const SizedBox(height: 28),
        _MetricsRow(metricsAsync: metricsAsync),
        const SizedBox(height: 22),
        invoicesAsync.when(
          loading: () => const _Loader(),
          error: (e, _) => _ErrorBox(message: 'Error: $e'),
          data: (invoices) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Filters(invoices: invoices, current: filter),
                const SizedBox(height: 14),
                _InvoicesTable(
                  invoices: filter == null
                      ? invoices
                      : invoices.where((i) => i.status == filter).toList(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _bulkGenerate(BuildContext context, WidgetRef ref) async {
    final overview = await ref.read(platformOverviewProvider.future);
    final repo = ref.read(billingRepositoryProvider);
    var created = 0;
    var skipped = 0;
    var errors = 0;
    for (final b in overview.where((b) => b.isActive)) {
      try {
        final invoice = await repo.generate(b.id);
        if (invoice.issueDate
                .difference(DateTime.now())
                .inSeconds
                .abs() <
            60) {
          created++;
        } else {
          skipped++;
        }
      } catch (_) {
        // Plan sin costo o membresía inexistente: contamos como saltado.
        skipped++;
        if (overview.where((x) => x.id == b.id).isEmpty) errors++;
      }
    }
    ref.invalidate(billingOverviewProvider);
    ref.invalidate(billingMetricsProvider);
    if (!context.mounted) return;
    final msg = created > 0
        ? 'Generadas $created facturas (saltadas $skipped por plan sin costo o ya existían).'
        : 'No había facturas pendientes este mes.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errors > 0 ? '$msg ($errors errores)' : msg),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.metricsAsync});
  final AsyncValue<BillingMetrics> metricsAsync;

  @override
  Widget build(BuildContext context) {
    return metricsAsync.when(
      loading: () => const _Loader(),
      error: (e, _) => _ErrorBox(message: 'Error métricas: $e'),
      data: (m) => LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final cols = w >= 1100 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: cols == 4 ? 1.55 : 1.6,
            children: [
              MetricCard(
                label: 'MRR activo',
                value: formatRd(m.mrr),
                sublabel: 'Mensualidad recurrente',
                icon: HugeIcons.strokeRoundedDollarCircle,
                variant: MetricVariant.primary,
              ),
              MetricCard(
                label: 'Cobrado',
                value: formatRd(m.totalPaid),
                sublabel: 'Histórico',
                icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                variant: MetricVariant.success,
              ),
              MetricCard(
                label: 'Por cobrar',
                value: formatRd(m.totalPending),
                sublabel: '${m.countPending} facturas pendientes',
                icon: HugeIcons.strokeRoundedFile02,
                variant: MetricVariant.accent,
              ),
              MetricCard(
                label: 'Vencido',
                value: formatRd(m.totalExpired),
                sublabel: m.countExpired > 0
                    ? '${m.countExpired} requieren acción'
                    : 'Sin vencidas',
                icon: HugeIcons.strokeRoundedAlert02,
                variant: m.totalExpired > 0
                    ? MetricVariant.destructive
                    : MetricVariant.neutral,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.invoices, required this.current});
  final List<MembershipInvoice> invoices;
  final InvoiceStatus? current;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(label: 'Todas', count: invoices.length, value: null, current: current),
        for (final s in InvoiceStatus.values)
          _Chip(
            label: '${s.label}s',
            count: invoices.where((i) => i.status == s).length,
            value: s,
            current: current,
          ),
      ],
    );
  }
}

class _Chip extends ConsumerWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.value,
    required this.current,
  });
  final String label;
  final int count;
  final InvoiceStatus? value;
  final InvoiceStatus? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = value == current;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () =>
          ref.read(_selectedStatusFilter.notifier).state = value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.primaryForeground
                    : AppColors.foreground,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? AppColors.primaryForeground.withValues(alpha: 0.8)
                    : AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicesTable extends ConsumerWidget {
  const _InvoicesTable({required this.invoices});
  final List<MembershipInvoice> invoices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (invoices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.shadowCard,
        ),
        alignment: Alignment.center,
        child: const Text(
          'No hay facturas con este filtro.',
          style: TextStyle(color: AppColors.mutedForeground),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w =
              constraints.maxWidth >= 1100 ? constraints.maxWidth : 1100.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: w,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tableHeader(),
                  const Divider(
                      height: 1, thickness: 1, color: AppColors.border),
                  for (var i = 0; i < invoices.length; i++) ...[
                    _InvoiceRow(invoice: invoices[i]),
                    if (i < invoices.length - 1)
                      const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.border),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      color: AppColors.muted.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 2, child: _HeadCell('Factura')),
          Expanded(flex: 3, child: _HeadCell('Negocio')),
          Expanded(flex: 1, child: _HeadCell('Plan')),
          Expanded(flex: 2, child: _HeadCell('Total', align: TextAlign.right)),
          Expanded(flex: 2, child: _HeadCell('Vence')),
          Expanded(flex: 2, child: _HeadCell('Estado', align: TextAlign.center)),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.text, {this.align = TextAlign.left});
  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: align,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.mutedForeground,
      ),
    );
  }
}

class _InvoiceRow extends ConsumerWidget {
  const _InvoiceRow({required this.invoice});
  final MembershipInvoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              invoice.invoiceNumber,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => context.go('/negocios/${invoice.businessId}'),
              child: Text(
                invoice.businessName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.foreground,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              invoice.planType.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatRd(invoice.total),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
                color: AppColors.foreground,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd MMM', 'es_DO').format(invoice.dueDate),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(child: _StatusBadge(status: invoice.status)),
          ),
          SizedBox(
            width: 40,
            child: _ActionMenu(invoice: invoice),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      InvoiceStatus.paid => (
          AppColors.success.withValues(alpha: 0.10),
          AppColors.success
        ),
      InvoiceStatus.pending => (
          AppColors.warning.withValues(alpha: 0.15),
          AppColors.warning
        ),
      InvoiceStatus.expired => (
          AppColors.destructive.withValues(alpha: 0.10),
          AppColors.destructive
        ),
      InvoiceStatus.voided => (
          AppColors.muted,
          AppColors.mutedForeground
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: fg,
        ),
      ),
    );
  }
}

class _ActionMenu extends ConsumerWidget {
  const _ActionMenu({required this.invoice});
  final MembershipInvoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(
        HugeIcons.strokeRoundedMoreVertical,
        size: 18,
        color: AppColors.mutedForeground,
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'pdf', child: Text('Ver PDF')),
        const PopupMenuItem(value: 'share', child: Text('Compartir / WhatsApp')),
        const PopupMenuDivider(),
        if (invoice.status == InvoiceStatus.pending ||
            invoice.status == InvoiceStatus.expired)
          const PopupMenuItem(
            value: 'pay',
            child: Text('Marcar como pagada'),
          ),
        if (invoice.status != InvoiceStatus.voided)
          const PopupMenuItem(
            value: 'void',
            child: Text('Anular factura'),
          ),
      ],
      onSelected: (action) async {
        switch (action) {
          case 'pdf':
            await previewInvoicePdf(invoice);
          case 'share':
            await shareInvoicePdf(invoice);
          case 'pay':
            await _payDialog(context, ref);
          case 'void':
            await _voidDialog(context, ref);
        }
      },
    );
  }

  Future<void> _payDialog(BuildContext context, WidgetRef ref) async {
    final method = TextEditingController();
    final reference = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Factura ${invoice.invoiceNumber} · ${formatRd(invoice.total)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: method,
              decoration: const InputDecoration(
                labelText: 'Método (cash, transfer, card…)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(billingRepositoryProvider).markPaid(
            invoice.id,
            method: method.text.trim().isEmpty ? 'cash' : method.text.trim(),
            reference: reference.text.trim().isEmpty
                ? null
                : reference.text.trim(),
          );
      ref.invalidate(billingOverviewProvider);
      ref.invalidate(billingMetricsProvider);
      ref.invalidate(businessInvoicesProvider(invoice.businessId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura ${invoice.invoiceNumber} pagada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _voidDialog(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular factura'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Factura ${invoice.invoiceNumber}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Razón de la anulación',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.destructive),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La razón es requerida.')),
      );
      return;
    }
    try {
      await ref.read(billingRepositoryProvider).voidInvoice(
            invoice.id,
            reason: reason.text.trim(),
          );
      ref.invalidate(billingOverviewProvider);
      ref.invalidate(billingMetricsProvider);
      ref.invalidate(businessInvoicesProvider(invoice.businessId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura ${invoice.invoiceNumber} anulada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.destructive, fontSize: 13),
      ),
    );
  }
}

