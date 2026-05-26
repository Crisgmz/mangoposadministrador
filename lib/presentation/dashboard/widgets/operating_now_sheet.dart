import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../domain/models/business_overview.dart';
import '../../shared/business_avatar.dart';

/// Modal que muestra los negocios con actividad reciente, agrupados por
/// estado: EN LÍNEA / TARDÍO / RECIENTE. Cada fila navega al detalle.
///
/// En desktop (≥ 760 px) se renderiza como diálogo centrado para que aparezca
/// donde el usuario está mirando; en móvil sigue siendo bottom sheet.
Future<void> showOperatingNowSheet(
  BuildContext context,
  List<BusinessOverview> overview,
) {
  final size = MediaQuery.sizeOf(context);
  final isDesktop = size.width >= 760;

  if (isDesktop) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (dialogCtx) {
        final s = MediaQuery.sizeOf(dialogCtx);
        // Ancho cómodo para lista vertical; alto que no se coma la pantalla.
        final w = s.width < 720 ? s.width - 32 : 560.0;
        final h = (s.height * 0.78).clamp(420.0, 720.0);
        return Dialog(
          backgroundColor: AppColors.card,
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            width: w,
            height: h,
            child: _OperatingNowSheet(overview: overview),
          ),
        );
      },
    );
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) {
      // Altura fija = 75% pantalla. Sin esto, `Expanded` interno colapsa a 0
      // porque `isScrollControlled: true` da constraints verticales abiertas.
      final h = MediaQuery.sizeOf(sheetCtx).height * 0.75;
      return SizedBox(
        height: h,
        child: _OperatingNowSheet(overview: overview),
      );
    },
  );
}

class _OperatingNowSheet extends StatelessWidget {
  const _OperatingNowSheet({required this.overview});

  final List<BusinessOverview> overview;

  @override
  Widget build(BuildContext context) {
    final actives = overview.where((b) => b.isActive).toList();
    final online = actives
        .where((b) => b.activityStatus == ActivityStatus.online)
        .toList();
    final late_ = actives
        .where((b) => b.activityStatus == ActivityStatus.late)
        .toList();
    final recent = actives
        .where((b) => b.activityStatus == ActivityStatus.recent)
        .toList();

    final hasAny = online.isNotEmpty || late_.isNotEmpty || recent.isNotEmpty;

    // El padre (SizedBox del caller) ya define la altura. Column con
    // `mainAxisSize.max` (default) llena ese alto y `Expanded` adentro
    // funciona correctamente.
    return Column(
      children: [
        // Header compacto — handle + título + contadores en línea + cerrar.
        Container(
          margin: const EdgeInsets.only(top: 6, bottom: 8),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  HugeIcons.strokeRoundedWifi01,
                  size: 15,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'En operación ahora',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  HugeIcons.strokeRoundedCancel01,
                  size: 18,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        // Contadores con dots — visible siempre sin scroll, ayuda a localizar
        // dónde está la actividad.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              _Counter(
                label: 'En línea',
                count: online.length,
                color: AppColors.success,
                emphasize: true,
              ),
              const SizedBox(width: 8),
              _Counter(
                label: 'Tardío',
                count: late_.length,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              _Counter(
                label: 'Hoy',
                count: recent.length,
                color: AppColors.mutedForeground,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        Expanded(
          child: hasAny
              ? ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    // EN LÍNEA primero y abierto sin separador — para que se
                    // vea inmediatamente sin scroll.
                    if (online.isNotEmpty)
                      for (final b in online)
                        _BusinessRow(business: b, dotColor: AppColors.success),
                    if (late_.isNotEmpty) ...[
                      if (online.isNotEmpty)
                        const Divider(height: 1, color: AppColors.border),
                      _SectionLabel(
                        label: 'Tardío (≤ 1 h)',
                        count: late_.length,
                        color: AppColors.warning,
                      ),
                      for (final b in late_)
                        _BusinessRow(business: b, dotColor: AppColors.warning),
                    ],
                    if (recent.isNotEmpty) ...[
                      if (online.isNotEmpty || late_.isNotEmpty)
                        const Divider(height: 1, color: AppColors.border),
                      _SectionLabel(
                        label: 'Hoy (≤ 24 h)',
                        count: recent.length,
                        color: AppColors.mutedForeground,
                      ),
                      for (final b in recent)
                        _BusinessRow(
                          business: b,
                          dotColor: AppColors.mutedForeground,
                        ),
                    ],
                    const SizedBox(height: 8),
                  ],
                )
                  : const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          'Ningún negocio con actividad reciente.',
                          style: TextStyle(
                            color: AppColors.mutedForeground,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
            ),
      ],
    );
  }
}

/// Píldora compacta con un conteo coloreado por estado de actividad.
/// El `emphasize=true` la pinta sólida (fondo lleno) — usado para "En línea".
class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.count,
    required this.color,
    this.emphasize = false,
  });

  final String label;
  final int count;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final bg = emphasize ? color : color.withValues(alpha: 0.10);
    final fg = emphasize ? Colors.white : color;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: color.withValues(alpha: emphasize ? 0 : 0.25),
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: emphasize ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: fg.withValues(alpha: emphasize ? 0.95 : 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessRow extends StatelessWidget {
  const _BusinessRow({required this.business, required this.dotColor});

  final BusinessOverview business;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        context.go('/negocios/${business.id}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            BusinessAvatar(
              businessId: business.id,
              businessName: business.name,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    business.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Última actividad ${formatRelative(business.lastActivityAt)}'
                    ' · ${business.plan.label}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
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
