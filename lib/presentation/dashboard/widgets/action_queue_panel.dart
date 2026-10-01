import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';
import '../../pending/pending_actions.dart';
import '../../shared/business_avatar.dart';
import '../action_queue.dart';

/// Bandeja "Requiere acción": una sola cola priorizada con el botón de
/// resolución en la propia fila.
///
/// Reemplaza al panel de alertas pasivo. La diferencia no es cosmética: antes
/// el operador leía una alerta, abría el negocio, buscaba la pantalla
/// correcta y recién ahí actuaba. Acá el botón de la fila ya sabe a dónde va.
class ActionQueuePanel extends ConsumerWidget {
  const ActionQueuePanel({super.key, this.height, this.maxRows});

  /// Alto fijo cuando comparte fila con otra card. `null` = se ajusta al
  /// contenido (móvil).
  final double? height;

  /// Corta la lista y muestra un pie "Ver las N". En móvil la bandeja va
  /// arriba del todo: si se despliega entera, empuja el resto de la pantalla
  /// fuera de vista.
  final int? maxRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(filteredActionQueueProvider);
    final criticals = ref.watch(criticalActionCountProvider);

    // Con algo crítico en la cola el panel se pinta en rojo tenue. En móvil,
    // donde la bandeja es lo primero, ese tinte es la diferencia entre "hay
    // avisos" y "hay fuego".
    final alarmed = criticals > 0;

    final panel = Container(
      decoration: BoxDecoration(
        color: alarmed
            ? AppColors.destructive.withValues(alpha: 0.04)
            : AppColors.card,
        border: Border.all(
          color: alarmed
              ? AppColors.destructive.withValues(alpha: 0.30)
              : AppColors.border,
          width: alarmed ? 0.8 : 0.6,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _Header(criticals: criticals),
          const _FilterChips(),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          if (height == null)
            queueAsync.when(
              loading: () => const _Loading(),
              error: (e, _) => _Error(error: e),
              data: (items) {
                if (items.isEmpty) return const _Empty();
                final limit = maxRows;
                final visible = (limit != null && items.length > limit)
                    ? items.take(limit).toList(growable: false)
                    : items;
                return ColoredBox(
                  color: AppColors.card,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        _QueueRow(item: visible[i]),
                        if (i < visible.length - 1)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.border,
                          ),
                      ],
                      if (visible.length < items.length)
                        _SeeAll(total: items.length),
                    ],
                  ),
                );
              },
            )
          else
            Expanded(
              child: queueAsync.when(
                loading: () => const _Loading(),
                error: (e, _) => _Error(error: e),
                data: (items) => items.isEmpty
                    ? const _Empty()
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.border,
                        ),
                        itemBuilder: (_, i) => _QueueRow(item: items[i]),
                      ),
              ),
            ),
        ],
      ),
    );

    return height == null ? panel : SizedBox(height: height, child: panel);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.criticals});
  final int criticals;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Icon(
            HugeIcons.strokeRoundedInbox,
            color: AppColors.accent,
            size: 18,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Requiere acción',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                  ),
                ),
                Text(
                  'Ordenado por severidad y antigüedad · resuelve sin salir '
                  'de aquí',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (criticals > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.destructive.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$criticals ${criticals == 1 ? "crítica" : "críticas"}',
                style: const TextStyle(
                  color: AppColors.destructive,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  static const _labels = <ActionFilter, String>{
    ActionFilter.down: 'Caídos',
    ActionFilter.ncf: 'NCF',
    ActionFilter.pending: 'Pendientes',
    ActionFilter.dues: 'Cobros',
  };

  static const _colors = <ActionFilter, Color>{
    ActionFilter.down: AppColors.destructive,
    ActionFilter.ncf: AppColors.warning,
    ActionFilter.pending: AppColors.accent,
    ActionFilter.dues: AppColors.mutedForeground,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(actionQueueFilterProvider);
    final counts = ref.watch(actionQueueCountsProvider);

    void select(ActionFilter? f) =>
        ref.read(actionQueueFilterProvider.notifier).state = f;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _Chip(
            label: 'Todo',
            count: counts[null] ?? 0,
            active: active == null,
            color: AppColors.mutedForeground,
            onTap: () => select(null),
          ),
          for (final f in ActionFilter.values)
            if ((counts[f] ?? 0) > 0)
              _Chip(
                label: _labels[f]!,
                count: counts[f]!,
                active: active == f,
                color: _colors[f]!,
                // Volver a tocar el chip activo limpia el filtro: es el gesto
                // que la gente intenta primero para "ver todo otra vez".
                onTap: () => select(active == f ? null : f),
              ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.foreground : AppColors.muted,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Text(
            '$label · $count',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({required this.item});
  final ActionItem item;

  static const _severityColors = <ActionSeverity, Color>{
    ActionSeverity.critical: AppColors.destructive,
    ActionSeverity.high: AppColors.warning,
    ActionSeverity.medium: AppColors.accent,
  };

  static const _severityLabels = <ActionSeverity, String>{
    ActionSeverity.critical: 'CRÍTICO',
    ActionSeverity.high: 'ALTO',
    ActionSeverity.medium: 'MEDIO',
  };

  /// A dónde lleva tocar la fila (o el botón). Cada tipo de problema tiene
  /// una pantalla donde efectivamente se resuelve — mandarlos todos al
  /// detalle del negocio era el paso de más que hacía lenta la consola.
  void _resolve(BuildContext context, WidgetRef ref) {
    switch (item.kind) {
      case ActionKind.pending:
        final pending = item.pendingBusiness;
        if (pending != null) {
          openPendingDetail(context, ref, pending);
        } else {
          context.go('/pendientes');
        }
      case ActionKind.noHeartbeat:
        context.go('/cajas');
      case ActionKind.ncf:
        context.go('/fiscal');
      case ActionKind.dues:
        context.go('/facturacion');
      case ActionKind.printing:
        context.go('/impresion');
      case ActionKind.agentDown:
        context.go('/negocios/${item.businessId}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _severityColors[item.severity]!;
    final primaryAction = item.kind == ActionKind.pending;

    return InkWell(
      onTap: () => _resolve(context, ref),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 10,
            bottom: 10,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 13, 20, 13),
            child: Row(
              children: [
                BusinessAvatar(
                  businessId: item.businessId,
                  businessName: item.businessName,
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
                          Flexible(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.foreground,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _severityLabels[item.severity]!,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      if (item.meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _ActionButton(
                  label: item.actionLabel,
                  filled: primaryAction,
                  onPressed: () => _resolve(context, ref),
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
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      backgroundColor: filled ? AppColors.primary : AppColors.card,
      foregroundColor: filled ? Colors.white : AppColors.foreground,
      side: filled ? null : const BorderSide(color: AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
    );
    return TextButton(onPressed: onPressed, style: style, child: Text(label));
  }
}

/// Pie del panel en móvil: lleva a la lista completa de alertas.
class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        InkWell(
          onTap: () => context.go('/alertas'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Center(
              child: Text(
                'Ver las $total',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: Text(
        'Error cargando la bandeja: $error',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.destructive, fontSize: 13),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(28),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            HugeIcons.strokeRoundedCheckmarkCircle02,
            size: 28,
            color: AppColors.primary,
          ),
          SizedBox(height: 8),
          Text(
            'Nada pendiente por ahora',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.foreground,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Ningún negocio requiere intervención.',
            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
          ),
        ],
      ),
    ),
  );
}
