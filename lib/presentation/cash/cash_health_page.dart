import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/cash_health_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../domain/models/business_overview.dart';
import '../../domain/models/cash_session_health.dart';
import '../shared/business_avatar.dart';
import '../shared/page_header.dart';

/// Pantalla principal de salud de cajas (PRD-12, Fase 1).
///
/// - KPIs arriba (abiertas, requieren atención, varianza).
/// - Selector de negocio (top-right) y pills de filtro de estado.
/// - Tabla de sesiones con drill-down a detalle.
class CashHealthPage extends ConsumerWidget {
  const CashHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(cashHealthQueryProvider);
    final overviewAsync = ref.watch(cashHealthOverviewProvider);
    final businessesAsync = ref.watch(filteredOverviewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Cajas',
          title: 'Salud de cajas',
          subtitle:
              'Sesiones abiertas, varianza, force-close. Cross-tenant.',
          trailing: OutlinedButton.icon(
            onPressed: () =>
                ref.invalidate(cashHealthOverviewProvider),
            icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
            label: const Text('Actualizar'),
          ),
        ),
        const SizedBox(height: 24),
        _Kpis(overviewAsync: overviewAsync),
        const SizedBox(height: 18),
        _Controls(
          query: query,
          businessesAsync: businessesAsync,
          onFilterChanged: (f) {
            ref.read(cashHealthQueryProvider.notifier).state =
                CashHealthQuery(filter: f, businessId: query.businessId);
          },
          onBusinessChanged: (id) {
            ref.read(cashHealthQueryProvider.notifier).state =
                CashHealthQuery(filter: query.filter, businessId: id);
          },
        ),
        const SizedBox(height: 14),
        overviewAsync.when(
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
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.destructive)),
          ),
          data: (rows) => _SessionsTable(rows: rows),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// KPIs
// ---------------------------------------------------------------------------

class _Kpis extends StatelessWidget {
  const _Kpis({required this.overviewAsync});
  final AsyncValue<List<CashSessionHealth>> overviewAsync;

  @override
  Widget build(BuildContext context) {
    final rows = overviewAsync.valueOrNull ?? const <CashSessionHealth>[];
    final open = rows.where((r) => r.isOpen).length;
    final attention = rows.where((r) => r.needsAttention).length;
    final variance = rows.where((r) => r.varianceFlagged).length;
    final totalEsperado = rows
        .where((r) => r.isOpen)
        .fold<double>(0, (s, r) => s + r.saldoEsperadoActual);

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: cols == 4 ? 2.6 : 2.4,
          children: [
            _KpiCard(
              label: 'Cajas abiertas',
              value: '$open',
              icon: HugeIcons.strokeRoundedDashboardCircle,
              color: AppColors.primary,
            ),
            _KpiCard(
              label: 'Requieren atención',
              value: '$attention',
              icon: HugeIcons.strokeRoundedAlert02,
              color: attention > 0 ? AppColors.warning : AppColors.success,
            ),
            _KpiCard(
              label: 'Con varianza',
              value: '$variance',
              icon: HugeIcons.strokeRoundedAlertCircle,
              color: variance > 0 ? AppColors.destructive : AppColors.success,
            ),
            _KpiCard(
              label: 'Saldo esperado',
              value: formatRd(totalEsperado),
              icon: HugeIcons.strokeRoundedDollarCircle,
              color: AppColors.accent,
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controles (filtros + selector de negocio)
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  const _Controls({
    required this.query,
    required this.businessesAsync,
    required this.onFilterChanged,
    required this.onBusinessChanged,
  });

  final CashHealthQuery query;
  final AsyncValue<List<BusinessOverview>> businessesAsync;
  final ValueChanged<CashHealthFilter> onFilterChanged;
  final ValueChanged<String?> onBusinessChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final stack = c.maxWidth < 760;
        final filters = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in CashHealthFilter.values)
              _FilterChip(
                label: f.label,
                selected: query.filter == f,
                onTap: () => onFilterChanged(f),
              ),
          ],
        );
        final selector = _BusinessSelector(
          businessId: query.businessId,
          businessesAsync: businessesAsync,
          onChanged: onBusinessChanged,
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [filters, const SizedBox(height: 10), selector],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: filters),
            const SizedBox(width: 12),
            selector,
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.foreground : AppColors.muted,
          border: Border.all(
            color: selected ? AppColors.foreground : AppColors.border,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.foreground,
          ),
        ),
      ),
    );
  }
}

class _BusinessSelector extends StatelessWidget {
  const _BusinessSelector({
    required this.businessId,
    required this.businessesAsync,
    required this.onChanged,
  });

  final String? businessId;
  final AsyncValue<List<BusinessOverview>> businessesAsync;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final rows = businessesAsync.valueOrNull ?? const <BusinessOverview>[];
    final selected = businessId == null
        ? null
        : rows.cast<BusinessOverview?>().firstWhere(
              (b) => b?.id == businessId,
              orElse: () => null,
            );

    return InkWell(
      onTap: () => _open(context, rows),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              HugeIcons.strokeRoundedBuilding03,
              size: 14,
              color: AppColors.mutedForeground,
            ),
            const SizedBox(width: 8),
            Text(
              selected?.name ?? 'Todos los negocios',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              HugeIcons.strokeRoundedArrowDown01,
              size: 14,
              color: AppColors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext ctx, List<BusinessOverview> rows) async {
    final picked = await showModalBottomSheet<String?>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final h = MediaQuery.sizeOf(sheetCtx).height * 0.75;
        return SizedBox(
          height: h,
          child: _BusinessPicker(rows: rows, current: businessId),
        );
      },
    );
    if (picked == '__null__') {
      onChanged(null);
    } else if (picked != null) {
      onChanged(picked);
    }
  }
}

class _BusinessPicker extends StatefulWidget {
  const _BusinessPicker({required this.rows, required this.current});

  final List<BusinessOverview> rows;
  final String? current;

  @override
  State<_BusinessPicker> createState() => _BusinessPickerState();
}

class _BusinessPickerState extends State<_BusinessPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.rows
        : widget.rows
            .where((b) =>
                b.name.toLowerCase().contains(_q.toLowerCase()) ||
                b.domain.toLowerCase().contains(_q.toLowerCase()))
            .toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 12),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Filtrar por negocio',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(HugeIcons.strokeRoundedCancel01, size: 18),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(
              prefixIcon: Icon(HugeIcons.strokeRoundedSearch01, size: 16),
              hintText: 'Buscar negocio...',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              _PickerRow(
                label: 'Todos los negocios',
                subtitle: '${widget.rows.length} negocios',
                selected: widget.current == null,
                onTap: () => Navigator.of(context).pop('__null__'),
              ),
              const Divider(height: 1, thickness: 1, color: AppColors.border),
              for (final b in filtered)
                _PickerRow(
                  avatar: BusinessAvatar(
                    businessId: b.id,
                    businessName: b.name,
                    size: 34,
                  ),
                  label: b.name,
                  subtitle: '${b.businessType ?? "—"} · ${b.domain}',
                  selected: widget.current == b.id,
                  onTap: () => Navigator.of(context).pop(b.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.avatar,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            avatar ??
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    HugeIcons.strokeRoundedBuilding03,
                    color: AppColors.mutedForeground,
                  ),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                HugeIcons.strokeRoundedTick02,
                size: 18,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tabla de sesiones
// ---------------------------------------------------------------------------

class _SessionsTable extends StatelessWidget {
  const _SessionsTable({required this.rows});
  final List<CashSessionHealth> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.shadowCard,
        ),
        alignment: Alignment.center,
        child: const Text(
          'Sin sesiones que coincidan con el filtro.',
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
        builder: (context, c) {
          // Mobile/tablet: cards apiladas, sin scroll horizontal.
          if (c.maxWidth < 760) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  _MobileSessionCard(s: rows[i]),
                  if (i < rows.length - 1)
                    const Divider(
                        height: 1, thickness: 1, color: AppColors.border),
                ],
              ],
            );
          }
          // Desktop: tabla. Scroll horizontal solo si no llega a 1000 px.
          final w = c.maxWidth >= 1000 ? c.maxWidth : 1000.0;
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
                  for (var i = 0; i < rows.length; i++) ...[
                    _SessionRow(s: rows[i]),
                    if (i < rows.length - 1)
                      const Divider(
                          height: 1, thickness: 1, color: AppColors.border),
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
          Expanded(flex: 3, child: _HeadCell('Negocio / Caja')),
          Expanded(flex: 2, child: _HeadCell('Cajero')),
          Expanded(flex: 2, child: _HeadCell('Duración')),
          Expanded(flex: 2, child: _HeadCell('Saldo esperado', align: TextAlign.right)),
          Expanded(flex: 2, child: _HeadCell('Estado', align: TextAlign.center)),
          SizedBox(width: 28),
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

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.s});
  final CashSessionHealth s;

  String _durationLabel() {
    final d = s.duracion;
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  Color _durationColor() {
    if (!s.isOpen) return AppColors.mutedForeground;
    final h = s.duracion.inHours;
    if (h >= 24) return AppColors.destructive;
    if (h >= 12) return AppColors.warning;
    return AppColors.foreground;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/cajas/${s.sessionId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  BusinessAvatar(
                    businessId: s.businessId,
                    businessName: s.businessName,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.businessName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          ),
                        ),
                        Text(
                          s.cajaNombre,
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
            ),
            Expanded(
              flex: 2,
              child: Text(
                s.cashierName ?? '—',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.foreground,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _durationLabel(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _durationColor(),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatRd(s.saldoEsperadoActual),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.foreground,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(child: _StatusBadge(s: s)),
            ),
            const SizedBox(
              width: 28,
              child: Icon(
                HugeIcons.strokeRoundedArrowRight01,
                size: 16,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.s});
  final CashSessionHealth s;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String text;
    if (!s.isOpen && s.varianceFlagged) {
      color = AppColors.destructive;
      text = 'VARIANZA';
    } else if (s.isOpen && s.needsAttention) {
      color = AppColors.warning;
      text = 'ATENCIÓN';
    } else if (s.isOpen) {
      color = AppColors.success;
      text = 'ABIERTA';
    } else {
      color = AppColors.mutedForeground;
      text = 'CERRADA';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.6),
      ),
      child: Text(
        text,
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

/// Versión mobile (< 760 px) de la fila de sesión — sin scroll horizontal.
class _MobileSessionCard extends StatelessWidget {
  const _MobileSessionCard({required this.s});
  final CashSessionHealth s;

  String _durationLabel() {
    final d = s.duracion;
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  Color _durationColor() {
    if (!s.isOpen) return AppColors.mutedForeground;
    final h = s.duracion.inHours;
    if (h >= 24) return AppColors.destructive;
    if (h >= 12) return AppColors.warning;
    return AppColors.foreground;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/cajas/${s.sessionId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BusinessAvatar(
              businessId: s.businessId,
              businessName: s.businessName,
              size: 40,
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
                          s.businessName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusBadge(s: s),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.cajaNombre} · ${s.cashierName ?? "—"}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Línea de métricas — visible siempre sin swipe.
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                            text: 'Saldo: ',
                            style: TextStyle(
                              color: AppColors.mutedForeground,
                              fontSize: 11,
                            ),
                          ),
                          TextSpan(
                            text: formatRd(s.saldoEsperadoActual),
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
                            text: 'Duración: ',
                            style: TextStyle(
                              color: AppColors.mutedForeground,
                              fontSize: 11,
                            ),
                          ),
                          TextSpan(
                            text: _durationLabel(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _durationColor(),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              HugeIcons.strokeRoundedArrowRight01,
              size: 16,
              color: AppColors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
