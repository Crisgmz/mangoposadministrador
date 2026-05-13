import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/cash_health_repository.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/cash_payment_breakdown.dart';
import '../../domain/models/cash_session_health.dart';
import '../../domain/models/cash_transaction.dart';
import '../shared/business_avatar.dart';

/// Detalle de una sesión de caja: header con info del negocio + caja,
/// resumen de saldos, kardex de movimientos y botón force-close.
class CashSessionDetailPage extends ConsumerWidget {
  const CashSessionDetailPage({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(cashSessionDetailProvider(sessionId));
    final kardexAsync = ref.watch(cashSessionKardexProvider(sessionId));
    final breakdownAsync =
        ref.watch(cashSessionPaymentBreakdownProvider(sessionId));

    return sessionAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error: $e',
            style: const TextStyle(color: AppColors.destructive)),
      ),
      data: (session) {
        if (session == null) return const _NotFound();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(session: session),
            const SizedBox(height: 24),
            _IdentityStrip(session: session),
            const SizedBox(height: 24),
            _BalanceCard(session: session),
            const SizedBox(height: 24),
            // Desglose de pagos por método (efectivo + tarjeta + transferencia)
            // Solo el efectivo afecta el saldo físico — los demás son
            // informativos para validar el total facturado de la sesión.
            const _SectionTitle('Ventas por método de pago'),
            const SizedBox(height: 12),
            breakdownAsync.when(
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
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error desglose: $e',
                    style:
                        const TextStyle(color: AppColors.destructive)),
              ),
              data: (rows) => _PaymentBreakdown(rows: rows),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('Movimientos del turno'),
            const SizedBox(height: 12),
            kardexAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error kardex: $e',
                    style:
                        const TextStyle(color: AppColors.destructive)),
              ),
              data: (rows) => _Kardex(items: rows),
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends ConsumerWidget {
  const _Header({required this.session});
  final CashSessionHealth session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => context.go('/cajas'),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                HugeIcons.strokeRoundedArrowLeft01,
                size: 14,
                color: AppColors.mutedForeground,
              ),
              SizedBox(width: 4),
              Text(
                'Salud de cajas',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final stack = c.maxWidth < 720;
            final left = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                BusinessAvatar(
                  businessId: session.businessId,
                  businessName: session.businessName,
                  size: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        session.businessName,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${session.cajaNombre} · ${session.cashierName ?? "—"}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final right = Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _SessionStatusPill(s: session),
                _EnvPill(env: session.environment),
                if (session.isOpen)
                  FilledButton.icon(
                    onPressed: () => _confirmForceClose(context, ref),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.destructive,
                    ),
                    icon: const Icon(
                      HugeIcons.strokeRoundedPowerSocket02,
                      size: 14,
                    ),
                    label: const Text('Force-close'),
                  ),
              ],
            );
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [left, const SizedBox(height: 14), right],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Expanded(child: left), right],
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmForceClose(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({double endAmount, String reason})?>(
      context: context,
      builder: (_) => _ForceCloseDialog(saldoEsperado: session.saldoEsperadoActual),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(cashHealthRepositoryProvider).forceClose(
            sessionId: session.sessionId,
            endAmount: result.endAmount,
            reason: result.reason,
          );
      ref.invalidate(cashHealthOverviewProvider);
      ref.invalidate(cashSessionDetailProvider(session.sessionId));
      ref.invalidate(cashSessionKardexProvider(session.sessionId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Caja cerrada · ${session.cajaNombre}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _SessionStatusPill extends StatelessWidget {
  const _SessionStatusPill({required this.s});
  final CashSessionHealth s;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String text;
    if (!s.isOpen && s.varianceFlagged) {
      color = AppColors.destructive;
      text = 'CERRADA · VARIANZA';
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.6),
        borderRadius: BorderRadius.circular(99),
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

class _EnvPill extends StatelessWidget {
  const _EnvPill({required this.env});
  final BusinessEnvironment env;

  @override
  Widget build(BuildContext context) {
    final isProd = env == BusinessEnvironment.production;
    final color = isProd ? AppColors.success : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.6),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        env.label.toUpperCase(),
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

// ---------------------------------------------------------------------------
// Identity strip
// ---------------------------------------------------------------------------

class _IdentityStrip extends StatelessWidget {
  const _IdentityStrip({required this.session});
  final CashSessionHealth session;

  String _fmtDate(DateTime d) => DateFormat('dd MMM, HH:mm', 'es_DO').format(d);

  @override
  Widget build(BuildContext context) {
    final dur = session.duracion;
    final durLabel = dur.inDays > 0
        ? '${dur.inDays}d ${dur.inHours.remainder(24)}h'
        : dur.inHours > 0
            ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m'
            : '${dur.inMinutes}m';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 720 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 12,
            childAspectRatio: cols == 4 ? 3.6 : 4.0,
            children: [
              _Field(label: 'Apertura', value: _fmtDate(session.openedAt)),
              _Field(
                label: 'Duración',
                value: durLabel,
                highlight: session.needsAttention,
              ),
              _Field(
                label: 'Cierre',
                value: session.closedAt == null
                    ? '—'
                    : _fmtDate(session.closedAt!),
              ),
              _Field(
                label: 'Session ID',
                value: session.sessionId.substring(0, 8),
                monospace: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.monospace = false,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool monospace;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: monospace ? 'monospace' : null,
            color: highlight ? AppColors.warning : AppColors.foreground,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Balance card
// ---------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.session});
  final CashSessionHealth session;

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
          const Text(
            'SALDO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 6),
          _Row(
            label: 'Apertura',
            value: formatRd(session.startAmount),
          ),
          _Row(
            label: '+ Ventas en efectivo',
            value: formatRd(session.ventasEfectivo),
            color: AppColors.success,
          ),
          _Row(
            label: '+ Depósitos',
            value: formatRd(session.depositos),
            color: AppColors.success,
          ),
          _Row(
            label: '− Retiros',
            value: '−${formatRd(session.retiros)}',
            color: AppColors.destructive,
          ),
          _Row(
            label: '− Gastos',
            value: '−${formatRd(session.gastos)}',
            color: AppColors.destructive,
          ),
          const Divider(height: 22, color: AppColors.border),
          _Row(
            label: session.isOpen ? 'Saldo esperado actual' : 'Saldo esperado al cierre',
            value: formatRd(session.saldoEsperadoActual),
            emphasize: true,
          ),
          if (!session.isOpen && session.endAmount != null) ...[
            _Row(
              label: 'Contado físicamente',
              value: formatRd(session.endAmount!),
            ),
            _Row(
              label: 'Diferencia',
              value:
                  '${(session.difference ?? 0) >= 0 ? "+" : ""}${formatRd(session.difference ?? 0)}',
              color: (session.difference ?? 0).abs() > 0.01
                  ? AppColors.destructive
                  : AppColors.success,
              emphasize: true,
            ),
          ],
          if (session.notes != null && session.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.muted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                session.notes!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.foreground,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.color,
    this.emphasize = false,
  });
  final String label;
  final String value;
  final Color? color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: emphasize ? 13 : 12.5,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.foreground,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 15 : 13,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              color: color ?? AppColors.foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kardex
// ---------------------------------------------------------------------------

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
// Payment breakdown — desglose por método (efectivo / tarjeta / transferencia)
// ---------------------------------------------------------------------------

class _PaymentBreakdown extends StatelessWidget {
  const _PaymentBreakdown({required this.rows});
  final List<CashPaymentBreakdownEntry> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.shadowCard,
        ),
        alignment: Alignment.center,
        child: const Text(
          'Sin ventas registradas en esta sesión.',
          style: TextStyle(color: AppColors.mutedForeground, fontSize: 13),
        ),
      );
    }

    final total = rows.fold<double>(0, (s, r) => s + r.totalAmount);
    final totalTx = rows.fold<int>(0, (s, r) => s + r.txnCount);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
              const Expanded(
                child: Text(
                  'Total facturado en la sesión',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
              Text(
                formatRd(total),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$totalTx ${totalTx == 1 ? "transacción" : "transacciones"}',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          for (final r in rows) _BreakdownRow(entry: r),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  HugeIcons.strokeRoundedInformationCircle,
                  size: 14,
                  color: AppColors.mutedForeground,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Solo las ventas en efectivo afectan el saldo físico de la caja. '
                    'Tarjeta y transferencia se reportan aparte porque no modifican el cajón.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedForeground,
                      height: 1.4,
                    ),
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

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.entry});
  final CashPaymentBreakdownEntry entry;

  IconData get _icon {
    if (entry.isCash) return HugeIcons.strokeRoundedDollarCircle;
    final c = (entry.methodCode ?? entry.methodName ?? '').toLowerCase();
    if (c.contains('card') || c.contains('tarjeta')) {
      return HugeIcons.strokeRoundedCreditCard;
    }
    if (c.contains('transfer') || c.contains('wire')) {
      return HugeIcons.strokeRoundedExchange01;
    }
    return HugeIcons.strokeRoundedInvoice03;
  }

  @override
  Widget build(BuildContext context) {
    final color = entry.isCash ? AppColors.success : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_icon, size: 15, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                    if (entry.isCash) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AFECTA CAJA',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${entry.txnCount} ${entry.txnCount == 1 ? "transacción" : "transacciones"}  ·  ${entry.pctOfTotal.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatRd(entry.totalAmount),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kardex extends StatelessWidget {
  const _Kardex({required this.items});
  final List<CashTransaction> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.shadowCard,
        ),
        alignment: Alignment.center,
        child: const Text(
          'Sin movimientos registrados en este turno.',
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _KardexRow(t: items[i]),
            if (i < items.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _KardexRow extends StatelessWidget {
  const _KardexRow({required this.t});
  final CashTransaction t;

  Color get _tone => t.type.isInflow ? AppColors.success : AppColors.destructive;
  IconData get _icon {
    switch (t.type) {
      case CashTxType.sale:
        return HugeIcons.strokeRoundedShoppingCart01;
      case CashTxType.deposit:
        return HugeIcons.strokeRoundedArrowDown01;
      case CashTxType.withdrawal:
        return HugeIcons.strokeRoundedArrowUp01;
      case CashTxType.expense:
        return HugeIcons.strokeRoundedDollarCircle;
      case CashTxType.refund:
        return HugeIcons.strokeRoundedRefresh;
      case CashTxType.other:
        return HugeIcons.strokeRoundedDashboardCircle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, size: 16, color: _tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.type.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                  ),
                ),
                if (t.description != null && t.description!.isNotEmpty)
                  Text(
                    t.description!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                Text(
                  DateFormat('HH:mm:ss', 'es_DO').format(t.createdAt),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${t.type.isInflow ? "+" : "−"}${formatRd(t.amount)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Force-close dialog
// ---------------------------------------------------------------------------

class _ForceCloseDialog extends StatefulWidget {
  const _ForceCloseDialog({required this.saldoEsperado});
  final double saldoEsperado;

  @override
  State<_ForceCloseDialog> createState() => _ForceCloseDialogState();
}

class _ForceCloseDialogState extends State<_ForceCloseDialog> {
  late final TextEditingController _amount;
  final _reason = TextEditingController();
  bool _noPhysicalCount = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cerrar caja por fuerza'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Saldo esperado: ${formatRd(widget.saldoEsperado)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              enabled: !_noPhysicalCount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Monto contado físicamente (RD\$)',
                hintText: '0.00',
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _noPhysicalCount,
              onChanged: (v) {
                setState(() {
                  _noPhysicalCount = v == true;
                  if (_noPhysicalCount) _amount.text = '0';
                });
              },
              title: const Text(
                'No se hizo arqueo físico (cerrar con 0)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Razón (mínimo 5 caracteres)',
                hintText: 'Ej: cajero no respondió a 3 llamadas',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.destructive),
          onPressed: () {
            final amt = double.tryParse(_amount.text.trim()) ?? 0;
            final reason = _reason.text.trim();
            if (reason.length < 5) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Razón requerida (5+ caracteres).')),
              );
              return;
            }
            Navigator.of(context).pop((endAmount: amt, reason: reason));
          },
          child: const Text('Cerrar caja'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Not found
// ---------------------------------------------------------------------------

class _NotFound extends StatelessWidget {
  const _NotFound();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sesión no encontrada.',
              style: TextStyle(color: AppColors.mutedForeground, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => GoRouter.of(context).go('/cajas'),
              child: const Text('Volver al listado'),
            ),
          ],
        ),
      ),
    );
  }
}
