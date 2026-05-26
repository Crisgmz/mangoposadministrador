import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/table_health_repository.dart';
import '../../domain/models/table_health.dart';
import '../shared/business_avatar.dart';
import '../shared/page_header.dart';

/// NOC Mesas (PRD-12 Fase 4): sesiones zombi, pagos atascados y items
/// huérfanos. Cross-tenant con acciones del operador.
class TablesHealthPage extends ConsumerWidget {
  const TablesHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(tableHealthSummaryProvider);
    final zombiesAsync = ref.watch(zombieSessionsProvider);
    final stuckAsync = ref.watch(stuckPaymentsProvider);
    final orphansAsync = ref.watch(orphanItemsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Mesas',
          title: 'Salud de mesas',
          subtitle:
              'Sesiones abandonadas, pagos atascados y datos inconsistentes.',
          trailing: OutlinedButton.icon(
            onPressed: () {
              ref.invalidate(tableHealthSummaryProvider);
              ref.invalidate(zombieSessionsProvider);
              ref.invalidate(stuckPaymentsProvider);
              ref.invalidate(orphanItemsProvider);
            },
            icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
            label: const Text('Actualizar'),
          ),
        ),
        const SizedBox(height: 24),
        summaryAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error métricas: $e'),
          data: (s) => _KpisGrid(s: s),
        ),
        const SizedBox(height: 28),
        const _SectionTitle('Sesiones zombi (> 24 h sin cerrar)'),
        const SizedBox(height: 12),
        zombiesAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error: $e'),
          data: (rows) => _ZombiesList(rows: rows),
        ),
        const SizedBox(height: 28),
        const _SectionTitle('Pagos atascados (parcial > 1 h)'),
        const SizedBox(height: 12),
        stuckAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error: $e'),
          data: (rows) => _StuckList(rows: rows),
        ),
        const SizedBox(height: 28),
        const _SectionTitle('Items huérfanos'),
        const SizedBox(height: 12),
        orphansAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error: $e'),
          data: (rows) => _OrphansList(rows: rows),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

Widget _loader() => const Padding(
      padding: EdgeInsets.all(20),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );

Widget _err(String msg) => Padding(
      padding: const EdgeInsets.all(16),
      child: Text(msg,
          style: const TextStyle(color: AppColors.destructive, fontSize: 13)),
    );

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: AppColors.mutedForeground,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPIs
// ---------------------------------------------------------------------------

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.s});
  final TableHealthSummary s;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final double maxW = c.maxWidth;
        final int cols;
        final double ratio;
        if (maxW >= 1100) {
          cols = 4;
          ratio = 2.6;
        } else if (maxW >= 640) {
          cols = 2;
          ratio = 2.4;
        } else {
          cols = 1;
          ratio = 4.0;
        }
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: ratio,
          children: [
            _Kpi(
              label: 'Sesiones zombi',
              value: '${s.zombieSessions}',
              sublabel: '> 24 h abiertas',
              icon: HugeIcons.strokeRoundedClock04,
              color: s.zombieSessions > 0
                  ? AppColors.destructive
                  : AppColors.success,
            ),
            _Kpi(
              label: 'Pagos atascados',
              value: '${s.stuckPayments}',
              sublabel: 'parcial > 1 h',
              icon: HugeIcons.strokeRoundedCreditCard,
              color: s.stuckPayments > 0
                  ? AppColors.warning
                  : AppColors.success,
            ),
            _Kpi(
              label: 'Items huérfanos',
              value: '${s.orphanItems}',
              sublabel: 'KDS inconsistente',
              icon: HugeIcons.strokeRoundedAlertCircle,
              color: s.orphanItems > 0
                  ? AppColors.destructive
                  : AppColors.success,
            ),
            _Kpi(
              label: 'Sin cobrar',
              value: formatRd(s.totalUnpaid),
              sublabel: 'en pagos atascados',
              icon: HugeIcons.strokeRoundedDollarCircle,
              color: s.totalUnpaid > 0
                  ? AppColors.accent
                  : AppColors.success,
            ),
          ],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final String sublabel;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.shadowCard,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.foreground,
                  ),
                ),
                Text(
                  sublabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zombies
// ---------------------------------------------------------------------------

class _ZombiesList extends StatelessWidget {
  const _ZombiesList({required this.rows});
  final List<ZombieTableSession> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _emptyCard('Sin sesiones zombi. 🎉');
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _ZombieRow(z: rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _ZombieRow extends ConsumerWidget {
  const _ZombieRow({required this.z});
  final ZombieTableSession z;

  String _ageLabel() {
    final d = z.age;
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    return '${d.inHours}h';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BusinessAvatar(
            businessId: z.businessId,
            businessName: z.businessName,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        z.businessName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.destructive.withValues(alpha: 0.10),
                        border: Border.all(
                            color: AppColors.destructive
                                .withValues(alpha: 0.25),
                            width: 0.6),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        _ageLabel(),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.destructive,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Mesa ${z.tableDisplay}  ·  ${z.customerName ?? "—"}  ·  ${z.waiterName ?? "Sin mesero"}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '${z.ordersCount} órdenes',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.foreground,
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${z.openOrders} abiertas  ·  ',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    TextSpan(
                      text: formatRd(z.totalUnpaidEstimated),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ]),
                ),
                Text(
                  'Abierta ${DateFormat('dd MMM HH:mm', 'es_DO').format(z.openedAt)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Cerrar sesión',
            icon: const Icon(
              HugeIcons.strokeRoundedPowerSocket02,
              size: 16,
              color: AppColors.destructive,
            ),
            onPressed: () => _confirmClose(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context, WidgetRef ref) async {
    final reasonCtl = TextEditingController();
    var voidOrders = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Cerrar sesión de ${z.businessName}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mesa: ${z.tableDisplay}  ·  Abierta hace ${_ageLabel()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtl,
                  minLines: 2,
                  maxLines: 4,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Razón (mínimo 5 caracteres)',
                    hintText: 'Ej: mesa abandonada, cliente se fue, etc.',
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: voidOrders,
                  onChanged: (v) =>
                      setState(() => voidOrders = v ?? true),
                  title: Text(
                    'Anular ${z.openOrders} ${z.openOrders == 1 ? "orden abierta" : "órdenes abiertas"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
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
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final reason = reasonCtl.text.trim();
    if (reason.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Razón requerida (5+ caracteres).')),
      );
      return;
    }
    try {
      await ref.read(tableHealthRepositoryProvider).closeZombieSession(
            sessionId: z.sessionId,
            reason: reason,
            voidOpenOrders: voidOrders,
          );
      ref.invalidate(tableHealthSummaryProvider);
      ref.invalidate(zombieSessionsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sesión cerrada · ${z.tableDisplay}')),
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
// Stuck payments
// ---------------------------------------------------------------------------

class _StuckList extends StatelessWidget {
  const _StuckList({required this.rows});
  final List<StuckPayment> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _emptyCard('Sin pagos atascados. 🎉');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _StuckRow(p: rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _StuckRow extends StatelessWidget {
  const _StuckRow({required this.p});
  final StuckPayment p;

  String _ageLabel() {
    final s = p.ageSeconds;
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h';
    return '${s ~/ 86400}d';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/negocios/${p.businessId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BusinessAvatar(
              businessId: p.businessId,
              businessName: p.businessName,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.businessName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.foreground,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.10),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.25),
                              width: 0.6),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          _ageLabel(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.warning,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mesa ${p.tableDisplay}  ·  ${p.orderStatus}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Línea: Total / pagado / falta
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                            text: 'Total: ',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                          TextSpan(
                            text: formatRd(p.total),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.foreground,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ]),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                            text: 'Pagado: ',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                          TextSpan(
                            text: formatRd(p.paidSoFar),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.success,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ]),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                            text: 'Falta: ',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                          TextSpan(
                            text: formatRd(p.remaining),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.destructive,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Orphan items
// ---------------------------------------------------------------------------

class _OrphansList extends StatelessWidget {
  const _OrphansList({required this.rows});
  final List<OrphanOrderItem> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _emptyCard('Sin items huérfanos. 🎉');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _OrphanRow(o: rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _OrphanRow extends ConsumerWidget {
  const _OrphanRow({required this.o});
  final OrphanOrderItem o;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BusinessAvatar(
            businessId: o.businessId,
            businessName: o.businessName,
            size: 30,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.10),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.25),
                            width: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        o.itemStatus.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        o.productName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${o.businessName}  ·  Mesa ${o.tableCode ?? "—"}  ·  orden ${o.orderStatus}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Anular',
            icon: const Icon(
              HugeIcons.strokeRoundedCancel01,
              size: 16,
              color: AppColors.destructive,
            ),
            onPressed: () async {
              final reason = await _askReason(context);
              if (reason == null || !context.mounted) return;
              try {
                await ref.read(tableHealthRepositoryProvider).voidOrphanItem(
                      itemId: o.itemId,
                      reason: reason,
                    );
                ref.invalidate(tableHealthSummaryProvider);
                ref.invalidate(orphanItemsProvider);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Item "${o.productName}" anulado.')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _askReason(BuildContext context) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular item'),
        content: TextField(
          controller: ctl,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Razón (mínimo 3 caracteres)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.destructive),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    final v = ctl.text.trim();
    if (v.length < 3) return null;
    return v;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _emptyCard(String text) => Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(color: AppColors.mutedForeground)),
    );
