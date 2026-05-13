import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';

enum MetricVariant { neutral, primary, accent, warning, destructive, success }

/// Tarjeta de métrica del dashboard.
///
/// Estilo modernizado: sin borde, sombra suave, números grandes con
/// jerarquía clara, opcional barra de progreso al pie y variante
/// "featured" con fondo verde de marca + texto blanco.
class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    this.sublabel,
    required this.icon,
    this.variant = MetricVariant.neutral,
    this.trend,
    this.progress,
    this.featured = false,
    this.compact = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? sublabel;
  final IconData icon;
  final MetricVariant variant;

  /// Cambio porcentual (positivo o negativo) — pinta una flecha + valor.
  final double? trend;

  /// 0.0 .. 1.0 — pinta una barra de progreso al pie de la card.
  final double? progress;

  /// Si true, fondo verde de marca con texto blanco. Pisa el `variant`.
  final bool featured;

  /// Modo compacto: padding reducido, valor más pequeño, sin icono grande
  /// ni barra de progreso. Pensado para tarjetas secundarias.
  final bool compact;

  /// Callback opcional al tocar la card. Cuando se provee, la card se
  /// envuelve en un `InkWell` con feedback de tap.
  final VoidCallback? onTap;

  Color get _iconBg {
    if (featured) return Colors.white.withValues(alpha: 0.18);
    switch (variant) {
      case MetricVariant.primary:
        return AppColors.primary.withValues(alpha: 0.12);
      case MetricVariant.accent:
        return AppColors.accent.withValues(alpha: 0.12);
      case MetricVariant.warning:
        return AppColors.warning.withValues(alpha: 0.12);
      case MetricVariant.destructive:
        return AppColors.destructive.withValues(alpha: 0.12);
      case MetricVariant.success:
        return AppColors.success.withValues(alpha: 0.12);
      case MetricVariant.neutral:
        return AppColors.muted;
    }
  }

  Color get _iconFg {
    if (featured) return Colors.white;
    switch (variant) {
      case MetricVariant.primary:
        return AppColors.primary;
      case MetricVariant.accent:
        return AppColors.accent;
      case MetricVariant.warning:
        return AppColors.warning;
      case MetricVariant.destructive:
        return AppColors.destructive;
      case MetricVariant.success:
        return AppColors.success;
      case MetricVariant.neutral:
        return AppColors.mutedForeground;
    }
  }

  Color get _progressColor {
    if (featured) return Colors.white;
    switch (variant) {
      case MetricVariant.primary:
      case MetricVariant.success:
        return AppColors.primary;
      case MetricVariant.accent:
        return AppColors.accent;
      case MetricVariant.warning:
        return AppColors.warning;
      case MetricVariant.destructive:
        return AppColors.destructive;
      case MetricVariant.neutral:
        return AppColors.foreground;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trendValue = trend;
    final trendUp = trendValue != null && trendValue >= 0;

    final fg = featured ? Colors.white : AppColors.foreground;
    final mutedFg = featured
        ? Colors.white.withValues(alpha: 0.72)
        : AppColors.mutedForeground;

    final padding = compact ? 14.0 : 18.0;
    final valueFontSize = compact ? 18.0 : 26.0;
    final iconBoxSize = compact ? 28.0 : 34.0;
    final iconSize = compact ? 14.0 : 17.0;
    final showProgress = progress != null && !compact;
    final radius = BorderRadius.circular(compact ? 16 : 20);

    final card = Container(
      padding: EdgeInsets.all(padding),
      // ClipRRect en `clipBehavior` para que si el contenido excede por
      // fracciones de píxel se recorte limpio en vez de mostrar el banner
      // amarillo "BOTTOM OVERFLOWED".
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: featured ? AppColors.primary : AppColors.card,
        border: Border.all(
          color: featured
              ? Colors.white.withValues(alpha: 0.12)
              : AppColors.border,
          width: 0.6,
        ),
        borderRadius: radius,
        boxShadow: featured ? AppColors.shadowElegant : AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        // Quitamos `mainAxisSize: min` — choca con `spaceBetween` (que necesita
        // espacio que repartir) y produce overflow de fracciones de píxel.
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10 : 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: mutedFg,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  color: _iconBg,
                  borderRadius: BorderRadius.circular(compact ? 9 : 11),
                ),
                child: Icon(icon, size: iconSize, color: _iconFg),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: fg,
                  height: 1.05,
                ),
              ),
              if (sublabel != null || trendValue != null) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (sublabel != null) ...[
                      Flexible(
                        child: Text(
                          sublabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 10.5 : 11.5,
                            color: mutedFg,
                          ),
                        ),
                      ),
                      if (trendValue != null) const SizedBox(width: 6),
                    ],
                    if (trendValue != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            trendUp
                                ? HugeIcons.strokeRoundedArrowUp01
                                : HugeIcons.strokeRoundedArrowDown01,
                            size: 11,
                            color: featured
                                ? Colors.white
                                : (trendUp
                                    ? AppColors.success
                                    : AppColors.destructive),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${trendValue.abs().toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: compact ? 10.5 : 11.5,
                              fontWeight: FontWeight.w600,
                              color: featured
                                  ? Colors.white
                                  : (trendUp
                                      ? AppColors.success
                                      : AppColors.destructive),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              if (showProgress) ...[
                const SizedBox(height: 8),
                _ProgressBar(
                  value: progress!.clamp(0.0, 1.0),
                  color: _progressColor,
                  trackColor: featured
                      ? Colors.white.withValues(alpha: 0.18)
                      : AppColors.muted,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: (featured ? Colors.white : AppColors.primary)
            .withValues(alpha: 0.08),
        highlightColor: (featured ? Colors.white : AppColors.primary)
            .withValues(alpha: 0.04),
        child: card,
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  final double value;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        backgroundColor: trackColor,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
