import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/pending_accounts_repository.dart';
import '../../domain/models/pending_business.dart';
import '../shared/page_header.dart';
import 'pending_actions.dart';

/// Lista de cuentas pendientes — la cola de trabajo del equipo de onboarding.
class PendingAccountsPage extends ConsumerWidget {
  const PendingAccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(pendingAccountsListProvider);
    final query = ref.watch(pendingAccountsQueryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Onboarding',
          title: 'Cuentas pendientes',
          subtitle:
              'Cuentas nuevas que esperan aprobación manual antes de poder usar el POS.',
          trailing: OutlinedButton.icon(
            onPressed: () {
              ref.invalidate(pendingAccountsListProvider);
              ref.invalidate(pendingAccountsCountProvider);
            },
            icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
            label: const Text('Actualizar'),
          ),
        ),
        const SizedBox(height: 24),
        _Filters(query: query),
        const SizedBox(height: 14),
        listAsync.when(
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
            child: Text(
              'Error: $e',
              style: const TextStyle(color: AppColors.destructive),
            ),
          ),
          data: (rows) => _PendingTable(rows: rows),
        ),
      ],
    );
  }
}

class _Filters extends ConsumerStatefulWidget {
  const _Filters({required this.query});
  final PendingAccountsQuery query;

  @override
  ConsumerState<_Filters> createState() => _FiltersState();
}

class _FiltersState extends ConsumerState<_Filters> {
  late TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.query.search ?? '');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _apply({String? search, bool? onlyWithCard}) {
    final current = widget.query;
    ref.read(pendingAccountsQueryProvider.notifier).state =
        PendingAccountsQuery(
      search: search ?? current.search,
      onlyWithCard: onlyWithCard ?? current.onlyWithCard,
      limit: current.limit,
      offset: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, email o ID…',
                prefixIcon: Icon(HugeIcons.strokeRoundedSearch01, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) =>
                  _apply(search: v.trim().isEmpty ? null : v.trim()),
            ),
          ),
          const SizedBox(width: 12),
          FilterChip(
            label: const Text('Solo con tarjeta verificada'),
            selected: widget.query.onlyWithCard,
            onSelected: (v) => _apply(onlyWithCard: v),
            avatar: Icon(
              widget.query.onlyWithCard
                  ? HugeIcons.strokeRoundedCheckmarkCircle02
                  : HugeIcons.strokeRoundedCreditCard,
              size: 14,
              color: widget.query.onlyWithCard
                  ? AppColors.success
                  : AppColors.mutedForeground,
            ),
            selectedColor: AppColors.success.withValues(alpha: 0.12),
            checkmarkColor: AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _PendingTable extends StatelessWidget {
  const _PendingTable({required this.rows});
  final List<PendingBusiness> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              HugeIcons.strokeRoundedCheckmarkCircle02,
              color: AppColors.success,
              size: 36,
            ),
            SizedBox(height: 8),
            Text(
              'No hay cuentas pendientes.',
              style: TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Cuando se registre alguien nuevo aparecerá acá.',
              style: TextStyle(
                color: AppColors.mutedForeground,
                fontSize: 12,
              ),
            ),
          ],
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
          for (var i = 0; i < rows.length; i++) ...[
            _PendingRow(item: rows[i]),
            if (i < rows.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _PendingRow extends ConsumerWidget {
  const _PendingRow({required this.item});
  final PendingBusiness item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RepaintBoundary aísla esta fila en su propio layer — al scrollear, el
    // engine no la re-pinta a menos que cambie su contenido. Crítico cuando
    // hay 50+ filas para que el scroll mantenga 60fps.
    return RepaintBoundary(
      child: InkWell(
        onTap: () => _open(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, c) {
            final wide = c.maxWidth >= 760;
            return Row(
              children: [
                // Avatar + nombres
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.businessName.isEmpty
                        ? '?'
                        : item.businessName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.businessName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                        ),
                      ),
                      Text(
                        [
                          item.ownerDisplayName,
                          if (item.ownerEmail != null &&
                              item.ownerEmail!.isNotEmpty &&
                              item.ownerEmail != item.ownerDisplayName)
                            item.ownerEmail!,
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (wide) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.planName ??
                              (item.planCode ?? '—').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          ),
                        ),
                        if (item.trialEndsAt != null)
                          Text(
                            item.trialDaysLeft! < 0
                                ? 'Trial venció hace ${-item.trialDaysLeft!}d'
                                : 'Trial: ${item.trialDaysLeft}d',
                            style: TextStyle(
                              fontSize: 11,
                              color: (item.trialDaysLeft ?? 0) < 0
                                  ? AppColors.destructive
                                  : AppColors.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                _CardBadge(verified: item.hasVerifiedCard),
                const SizedBox(width: 12),
                SizedBox(
                  width: wide ? 100 : 70,
                  child: Text(
                    formatRelative(item.createdAt),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  HugeIcons.strokeRoundedArrowRight01,
                  size: 14,
                  color: AppColors.mutedForeground,
                ),
              ],
            );
          },
        ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) =>
      openPendingDetail(context, ref, item);
}

class _CardBadge extends StatelessWidget {
  const _CardBadge({required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final (color, label) = verified
        ? (AppColors.success, 'TARJETA OK')
        : (AppColors.mutedForeground, 'SIN TARJETA');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: verified ? 0.10 : 0.06),
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

