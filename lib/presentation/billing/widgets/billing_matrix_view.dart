import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../core/utils/debouncer.dart';
import '../../../data/repositories/billing_matrix_repository.dart';
import '../../../domain/models/billing_matrix.dart';
import '../../dashboard/widgets/metric_card.dart';
import '../../shared/business_avatar.dart';
import '../../shared/pill_toggle.dart';
import 'mark_paid_dialog.dart';
import 'open_invoice.dart';

/// Filtros rápidos de la matriz. Están pensados como preguntas operativas,
/// no como facetas de datos: "¿a quién no le puedo cobrar?" antes que
/// "negocios con billing_status = suspended".
enum MatrixFilter { all, withCard, withoutCard, ready, blocked, owing }

extension _MatrixFilterX on MatrixFilter {
  String get label {
    switch (this) {
      case MatrixFilter.all:
        return 'Todos';
      case MatrixFilter.withCard:
        return 'Con tarjeta';
      case MatrixFilter.withoutCard:
        return 'Sin tarjeta';
      case MatrixFilter.ready:
        return 'Cobro automático';
      case MatrixFilter.blocked:
        return 'Bloqueados';
      case MatrixFilter.owing:
        return 'Con deuda';
    }
  }

  bool matches(BillingMatrixRow r) {
    switch (this) {
      case MatrixFilter.all:
        return true;
      case MatrixFilter.withCard:
        return r.hasCard;
      case MatrixFilter.withoutCard:
        return !r.hasCard;
      case MatrixFilter.ready:
        return r.autoChargeReady;
      case MatrixFilter.blocked:
        return !r.autoChargeReady && r.isActiveBusiness;
      case MatrixFilter.owing:
        return r.unpaidMonths > 0;
    }
  }
}

final _matrixFilter =
    StateProvider.autoDispose<MatrixFilter>((ref) => MatrixFilter.all);
final _matrixQuery = StateProvider.autoDispose<String>((ref) => '');
final _showInactive = StateProvider.autoDispose<bool>((ref) => false);

/// Anchos fijos de las columnas congeladas (izquierda) y de cada mes.
const double _wBusiness = 250;
const double _wPlan = 118;
const double _wCard = 168;
const double _wNext = 132;
const double _wStatus = 104;
const double _wMonth = 54;
const double _hPad = 20;

class BillingMatrixView extends ConsumerWidget {
  const BillingMatrixView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(billingMatrixProvider);
    final months = ref.watch(billingMatrixMonthsProvider);
    final filter = ref.watch(_matrixFilter);
    final query = ref.watch(_matrixQuery).trim().toLowerCase();
    final showInactive = ref.watch(_showInactive);

    return async.when(
      loading: () => const _Loader(),
      error: (e, _) => _ErrorBox(message: '$e'),
      data: (rows) {
        final visible = rows.where((r) {
          if (!showInactive && !r.isActiveBusiness) return false;
          if (!filter.matches(r)) return false;
          if (query.isEmpty) return true;
          return r.businessName.toLowerCase().contains(query) ||
              r.domain.toLowerCase().contains(query);
        }).toList(growable: false);

        final scope =
            rows.where((r) => showInactive || r.isActiveBusiness).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MatrixKpis(rows: scope),
            const SizedBox(height: 22),
            _Toolbar(
              rows: scope,
              filter: filter,
              months: months,
              showInactive: showInactive,
            ),
            const SizedBox(height: 14),
            if (visible.isEmpty)
              const _EmptyBox(message: 'Ningún negocio con este filtro.')
            else
              _MatrixTable(rows: visible),
            const SizedBox(height: 12),
            const _Legend(),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// KPIs
// ---------------------------------------------------------------------------

class _MatrixKpis extends StatelessWidget {
  const _MatrixKpis({required this.rows});
  final List<BillingMatrixRow> rows;

  @override
  Widget build(BuildContext context) {
    final total = rows.length;
    final withCard = rows.where((r) => r.hasCard).length;
    final ready = rows.where((r) => r.autoChargeReady).length;
    final soon = rows.where((r) {
      final d = r.daysToNextCharge;
      return d != null && d >= 0 && d <= 7;
    }).toList();
    final soonAmount =
        soon.fold<double>(0, (sum, r) => sum + (r.monthlyFee ?? 0));
    final owing = rows.where((r) => r.unpaidMonths > 0).toList();
    final owingAmount =
        owing.fold<double>(0, (sum, r) => sum + r.unpaidInWindow);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final int cols;
        final double ratio;
        if (w >= 1100) {
          cols = 4;
          ratio = 1.55;
        } else if (w >= 640) {
          cols = 2;
          ratio = 1.6;
        } else {
          cols = 1;
          ratio = 2.8;
        }
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: ratio,
          children: [
            MetricCard(
              label: 'Con tarjeta',
              value: '$withCard / $total',
              sublabel: total == 0
                  ? 'Sin negocios'
                  : '${((withCard / total) * 100).round()}% de la cartera',
              icon: HugeIcons.strokeRoundedCreditCard,
              variant: MetricVariant.primary,
            ),
            MetricCard(
              label: 'Cobro automático listo',
              value: '$ready',
              sublabel: withCard == 0
                  ? 'Ninguna tarjeta registrada'
                  : ready == withCard
                      ? 'Todas las tarjetas elegibles'
                      : '${withCard - ready} con tarjeta pero bloqueados',
              icon: HugeIcons.strokeRoundedRefresh,
              variant: MetricVariant.success,
            ),
            MetricCard(
              label: 'Cobra en 7 días',
              value: '${soon.length}',
              sublabel: soon.isEmpty
                  ? 'Nada programado esta semana'
                  : '${formatRdShort(soonAmount)} proyectados',
              icon: HugeIcons.strokeRoundedCalendar03,
              variant: MetricVariant.accent,
            ),
            MetricCard(
              label: 'Con deuda',
              value: '${owing.length}',
              sublabel: owing.isEmpty
                  ? 'Ventana al día'
                  : '${formatRdShort(owingAmount)} sin cobrar',
              icon: HugeIcons.strokeRoundedAlert02,
              variant: owing.isEmpty
                  ? MetricVariant.neutral
                  : MetricVariant.destructive,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar: búsqueda + filtros + ventana de meses
// ---------------------------------------------------------------------------

class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar({
    required this.rows,
    required this.filter,
    required this.months,
    required this.showInactive,
  });

  final List<BillingMatrixRow> rows;
  final MatrixFilter filter;
  final int months;
  final bool showInactive;

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  final _debouncer = Debouncer(const Duration(milliseconds: 200));

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar negocio o dominio…',
                  prefixIcon: Icon(HugeIcons.strokeRoundedSearch01, size: 18),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => _debouncer.run(
                  () => ref.read(_matrixQuery.notifier).state = v,
                ),
              ),
            ),
            PillToggle<int>(
              options: const [
                (value: 3, label: '3 meses'),
                (value: 6, label: '6 meses'),
                (value: 12, label: '12 meses'),
              ],
              value: widget.months,
              onChanged: (v) =>
                  ref.read(billingMatrixMonthsProvider.notifier).state = v,
            ),
            _InactiveToggle(value: widget.showInactive),
            IconButton(
              tooltip: 'Recargar',
              onPressed: () => ref.invalidate(billingMatrixProvider),
              icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 18),
              style: IconButton.styleFrom(
                foregroundColor: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in MatrixFilter.values)
              _FilterChip(
                label: f.label,
                count: widget.rows.where((r) => f.matches(r)).length,
                value: f,
                current: widget.filter,
              ),
          ],
        ),
      ],
    );
  }
}

class _InactiveToggle extends ConsumerWidget {
  const _InactiveToggle({required this.value});
  final bool value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () => ref.read(_showInactive.notifier).state = !value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: value ? AppColors.secondary : Colors.transparent,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value
                  ? HugeIcons.strokeRoundedCheckmarkCircle02
                  : HugeIcons.strokeRoundedCancel01,
              size: 14,
              color: value ? AppColors.primary : AppColors.mutedForeground,
            ),
            const SizedBox(width: 6),
            const Text(
              'Incluir inactivos',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends ConsumerWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.value,
    required this.current,
  });

  final String label;
  final int count;
  final MatrixFilter value;
  final MatrixFilter current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = value == current;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () => ref.read(_matrixFilter.notifier).state = value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
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

// ---------------------------------------------------------------------------
// Tabla
// ---------------------------------------------------------------------------

class _MatrixTable extends StatelessWidget {
  const _MatrixTable({required this.rows});
  final List<BillingMatrixRow> rows;

  @override
  Widget build(BuildContext context) {
    final monthCount = rows.first.months.length;
    final minWidth = _wBusiness +
        _wPlan +
        _wCard +
        _wNext +
        _wStatus +
        (_wMonth * monthCount) +
        (_hPad * 2);

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
          final w = constraints.maxWidth >= minWidth
              ? constraints.maxWidth
              : minWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: w,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MatrixHeader(months: rows.first.months),
                  const Divider(
                      height: 1, thickness: 1, color: AppColors.border),
                  for (var i = 0; i < rows.length; i++) ...[
                    _MatrixRow(row: rows[i]),
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
}

class _MatrixHeader extends StatelessWidget {
  const _MatrixHeader({required this.months});
  final List<BillingMonthCell> months;

  @override
  Widget build(BuildContext context) {
    final monthFmt = DateFormat('MMM', 'es_DO');
    return Container(
      color: AppColors.muted.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 10),
      child: Row(
        children: [
          const Expanded(child: _HeadCell('Negocio')),
          const SizedBox(width: _wPlan, child: _HeadCell('Plan')),
          const SizedBox(width: _wCard, child: _HeadCell('Tarjeta')),
          const SizedBox(width: _wNext, child: _HeadCell('Próximo cobro')),
          const SizedBox(
            width: _wStatus,
            child: _HeadCell('Estado', align: TextAlign.center),
          ),
          for (var i = 0; i < months.length; i++)
            SizedBox(
              width: _wMonth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    monthFmt
                        .format(months[i].periodStart)
                        .replaceAll('.', '')
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  // El año solo aparece en la primera columna y cada vez que
                  // cambia, para que un salto de año no pase inadvertido.
                  if (i == 0 ||
                      months[i].periodStart.year != months[i - 1].periodStart.year)
                    Text(
                      "'${months[i].periodStart.year.toString().substring(2)}",
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                ],
              ),
            ),
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

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({required this.row});
  final BillingMatrixRow row;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/negocios/${row.businessId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 10),
        child: Row(
          children: [
            Expanded(child: _BusinessCell(row: row)),
            SizedBox(width: _wPlan, child: _PlanCell(row: row)),
            SizedBox(width: _wCard, child: _CardCell(row: row)),
            SizedBox(width: _wNext, child: _NextChargeCell(row: row)),
            SizedBox(
              width: _wStatus,
              child: Center(child: _SubscriptionBadge(row: row)),
            ),
            for (final m in row.months)
              SizedBox(
                width: _wMonth,
                child: Center(child: _MonthDot(cell: m, row: row)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BusinessCell extends StatelessWidget {
  const _BusinessCell({required this.row});
  final BillingMatrixRow row;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BusinessAvatar(
          businessId: row.businessId,
          businessName: row.businessName,
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
                  Flexible(
                    child: Text(
                      row.businessName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                      ),
                    ),
                  ),
                  if (!row.isActiveBusiness) ...[
                    const SizedBox(width: 6),
                    const _MiniTag(text: 'INACTIVO'),
                  ],
                ],
              ),
              Text(
                row.domain.isEmpty ? '—' : row.domain,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanCell extends StatelessWidget {
  const _PlanCell({required this.row});
  final BillingMatrixRow row;

  @override
  Widget build(BuildContext context) {
    final name = row.planName ?? row.planType?.toUpperCase() ?? '—';
    final fee = row.monthlyFee ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.foreground,
          ),
        ),
        if (row.hasPriceOverride)
          // El monto ya es el precio especial. La marca evita que alguien
          // "corrija" una tarifa que a simple vista parece mal cargada.
          Tooltip(
            message: row.listMonthlyFee == null
                ? 'Precio especial'
                : 'Precio especial · lista '
                    '${formatRdCompact(row.listMonthlyFee!)}/mes',
            child: Text(
              '${formatRdCompact(fee)}/mes · especial',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          )
        else
          Text(
            fee > 0 ? '${formatRdCompact(fee)}/mes' : 'Sin costo',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.mutedForeground,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// Columna central de la pantalla: si hay tarjeta, cuál, y si sirve para
/// cobrar. Una tarjeta sin verificar es, operativamente, no tener tarjeta.
class _CardCell extends StatelessWidget {
  const _CardCell({required this.row});
  final BillingMatrixRow row;

  @override
  Widget build(BuildContext context) {
    final card = row.card;
    if (card == null) {
      return Row(
        children: [
          Icon(
            HugeIcons.strokeRoundedCreditCard,
            size: 15,
            color: AppColors.mutedForeground.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            row.cardsCount > 0 ? 'Sin default' : 'Sin tarjeta',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.mutedForeground.withValues(alpha: 0.8),
            ),
          ),
        ],
      );
    }

    final verified = card.status == 'verified';
    final color = verified ? AppColors.primary : AppColors.warning;
    final masked = card.masked ?? '••••';
    final last4 =
        masked.length >= 4 ? masked.substring(masked.length - 4) : masked;

    return Tooltip(
      message: [
        '${card.brand ?? 'Tarjeta'} •••• $last4',
        'Estado: ${_cardStatusLabel(card.status)}',
        if (card.expiration != null) 'Vence: ${_formatExpiration(card.expiration!)}',
        if (row.cardsCount > 1) '${row.cardsCount} tarjetas registradas',
      ].join('\n'),
      child: Row(
        children: [
          Icon(HugeIcons.strokeRoundedCreditCard, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(card.brand ?? 'CARD').toUpperCase()} ••$last4',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  verified
                      ? (card.expiration != null
                          ? 'Vence ${_formatExpiration(card.expiration!)}'
                          : 'Verificada')
                      : _cardStatusLabel(card.status),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: verified ? FontWeight.w400 : FontWeight.w600,
                    color: verified ? AppColors.mutedForeground : color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _cardStatusLabel(String status) {
    switch (status) {
      case 'verified':
        return 'Verificada';
      case 'pending_verification':
        return 'Sin verificar';
      case 'failed_verification':
        return 'Verificación falló';
      case 'expired':
        return 'Vencida';
      case 'revoked':
        return 'Revocada';
      default:
        return status;
    }
  }

  /// La expiración viene en AAAAMM (ej. `202812`).
  static String _formatExpiration(String raw) {
    if (raw.length == 6) {
      return '${raw.substring(4)}/${raw.substring(2, 4)}';
    }
    return raw;
  }
}

class _NextChargeCell extends StatelessWidget {
  const _NextChargeCell({required this.row});
  final BillingMatrixRow row;

  @override
  Widget build(BuildContext context) {
    final date = row.nextBillingDate;
    if (date == null) {
      return Text(
        row.billingStatus == 'trial' && row.trialEndsAt != null
            ? 'Trial → ${DateFormat('dd MMM', 'es_DO').format(row.trialEndsAt!)}'
            : 'Sin programar',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.mutedForeground.withValues(alpha: 0.8),
        ),
      );
    }

    final days = row.daysToNextCharge ?? 0;
    final overdue = days < 0;
    final soon = days >= 0 && days <= 7;
    final color = overdue
        ? AppColors.destructive
        : soon
            ? AppColors.accent
            : AppColors.mutedForeground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('dd MMM yyyy', 'es_DO').format(date),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.foreground,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          overdue
              ? 'Atrasado ${days.abs()} d'
              : days == 0
                  ? 'Hoy'
                  : 'En $days d',
          style: TextStyle(
            fontSize: 11,
            fontWeight: overdue || soon ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SubscriptionBadge extends StatelessWidget {
  const _SubscriptionBadge({required this.row});
  final BillingMatrixRow row;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (row.billingStatus) {
      'active' => (
          'Activa',
          AppColors.success.withValues(alpha: 0.10),
          AppColors.success
        ),
      'trial' => (
          'Trial',
          AppColors.accent.withValues(alpha: 0.12),
          AppColors.accent
        ),
      'past_due' => (
          'Atrasada',
          AppColors.warning.withValues(alpha: 0.15),
          AppColors.warning
        ),
      'suspended' => (
          'Suspendida',
          AppColors.destructive.withValues(alpha: 0.10),
          AppColors.destructive
        ),
      'cancelled' => (
          'Cancelada',
          AppColors.muted,
          AppColors.mutedForeground
        ),
      _ => ('Sin membresía', AppColors.muted, AppColors.mutedForeground),
    };

    final blockers = row.autoChargeBlockers;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: fg,
        ),
      ),
    );

    return Tooltip(
      message: row.autoChargeReady
          ? 'Cobro automático activo${row.currentAttemptNumber > 0 ? ' · ${row.currentAttemptNumber} intento(s)' : ''}'
          : 'No se cobrará automáticamente:\n· ${blockers.join('\n· ')}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge,
          const SizedBox(height: 3),
          Icon(
            row.autoChargeReady
                ? HugeIcons.strokeRoundedRefresh
                : HugeIcons.strokeRoundedAlertCircle,
            size: 12,
            color: row.autoChargeReady
                ? AppColors.primary
                : AppColors.mutedForeground.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

/// La celda de mes. Un punto de color lee más rápido que un monto cuando la
/// pregunta es "¿pagó o no?"; el detalle vive en el tooltip.
class _MonthDot extends ConsumerWidget {
  const _MonthDot({required this.cell, required this.row});
  final BillingMonthCell cell;
  final BillingMatrixRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthFmt = DateFormat('MMMM yyyy', 'es_DO');
    // Un mes con factura pendiente o vencida se paga tocándolo: es donde el
    // operador ve la deuda, y antes tenía que ir a buscarla a otra pestaña.
    final payable = cell.invoiceId != null &&
        (cell.status == MonthCellStatus.pending ||
            cell.status == MonthCellStatus.expired);
    // Una factura ya pagada (o anulada) se abre tocándola: no hay nada que
    // cobrar, pero sí hay que poder verla o reenviarla.
    final viewable = cell.invoiceId != null &&
        (cell.status == MonthCellStatus.paid ||
            cell.status == MonthCellStatus.voided);
    final (color, filled) = switch (cell.status) {
      MonthCellStatus.paid => (AppColors.success, true),
      MonthCellStatus.pending => (AppColors.warning, true),
      MonthCellStatus.expired => (AppColors.destructive, true),
      MonthCellStatus.voided => (AppColors.mutedForeground, false),
      MonthCellStatus.none => (AppColors.border, false),
    };

    final lines = <String>[
      '${row.businessName} · ${monthFmt.format(cell.periodStart)}',
      cell.status.label,
    ];
    if (cell.invoiceNumber != null) lines.add('Factura ${cell.invoiceNumber}');
    if (cell.total != null) lines.add('Total ${formatRd(cell.total!)}');
    if (cell.dueDate != null) {
      lines.add('Vence ${DateFormat('dd MMM yyyy', 'es_DO').format(cell.dueDate!)}');
    }
    if (cell.paidAt != null) {
      lines.add(
        'Pagada ${DateFormat('dd MMM yyyy', 'es_DO').format(cell.paidAt!)}'
        '${cell.paymentMethod != null ? ' · ${cell.paymentMethod}' : ''}',
      );
    }
    if (!cell.hasInvoice) {
      lines.add('No se generó factura para este período');
    }
    if (payable) lines.add('Toca para marcarla como pagada');
    if (viewable) lines.add('Toca para ver la factura');

    final dot = Tooltip(
      message: lines.join('\n'),
      waitDuration: const Duration(milliseconds: 250),
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        child: Container(
          width: cell.hasInvoice ? 14 : 8,
          height: cell.hasInvoice ? 14 : 8,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: color, width: 1.4),
          ),
          child: cell.status == MonthCellStatus.paid
              ? const Icon(HugeIcons.strokeRoundedTick02,
                  size: 9, color: Colors.white)
              : null,
        ),
      ),
    );

    if (viewable) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openInvoicePdfById(
            context,
            businessId: row.businessId,
            invoiceId: cell.invoiceId!,
          ),
          child: dot,
        ),
      );
    }
    if (!payable) return dot;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showMarkPaidDialog(context, ref, [
          PayableInvoice(
            id: cell.invoiceId!,
            number: cell.invoiceNumber ?? '—',
            businessId: row.businessId,
            businessName: row.businessName,
            total: cell.total ?? 0,
          ),
        ]),
        child: dot,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: const [
        _LegendItem(color: AppColors.success, label: 'Pagada'),
        _LegendItem(color: AppColors.warning, label: 'Pendiente'),
        _LegendItem(color: AppColors.destructive, label: 'Vencida'),
        _LegendItem(
            color: AppColors.mutedForeground, label: 'Anulada', filled: false),
        _LegendItem(color: AppColors.border, label: 'Sin factura', filled: false),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.filled = true,
  });

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: color, width: 1.4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.mutedForeground,
        ),
      ),
    );
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
        'Error cargando la matriz: $message',
        style: const TextStyle(color: AppColors.destructive, fontSize: 13),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      alignment: Alignment.center,
      child: Text(
        message,
        style: const TextStyle(color: AppColors.mutedForeground),
      ),
    );
  }
}
