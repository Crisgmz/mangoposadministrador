import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../domain/models/business_overview.dart';

class _BadgeStyle {
  const _BadgeStyle(this.background, this.foreground, this.border);
  final Color background;
  final Color foreground;
  final Color border;
}

/// Pill genérico usado por las tres variantes de badge.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.style,
    this.dotPulse = false,
  });

  final String label;
  final _BadgeStyle style;
  final bool dotPulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.background,
        border: Border.all(color: style.border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotPulse) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: style.foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: style.foreground,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge para el estado del agente de impresión.
class AgentBadge extends StatelessWidget {
  const AgentBadge({required this.status, super.key});
  final AgentStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case AgentStatus.online:
        return _Pill(
          label: 'En línea',
          style: _BadgeStyle(
            AppColors.success.withValues(alpha: 0.10),
            AppColors.success,
            AppColors.success.withValues(alpha: 0.25),
          ),
          dotPulse: true,
        );
      case AgentStatus.late:
        return _Pill(
          label: 'Tardío',
          style: _BadgeStyle(
            AppColors.warning.withValues(alpha: 0.15),
            AppColors.warning,
            AppColors.warning.withValues(alpha: 0.30),
          ),
        );
      case AgentStatus.offline:
        return _Pill(
          label: 'Desconectado',
          style: _BadgeStyle(
            AppColors.destructive.withValues(alpha: 0.10),
            AppColors.destructive,
            AppColors.destructive.withValues(alpha: 0.25),
          ),
        );
      case AgentStatus.none:
        return _Pill(
          label: 'Sin agente',
          style: _BadgeStyle(
            AppColors.muted,
            AppColors.mutedForeground,
            AppColors.border,
          ),
        );
    }
  }
}

/// Badge para el estado de las secuencias NCF.
class NcfBadge extends StatelessWidget {
  const NcfBadge({required this.status, super.key});
  final NcfStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case NcfStatus.ok:
        return _Pill(
          label: 'OK',
          style: _BadgeStyle(
            AppColors.success.withValues(alpha: 0.10),
            AppColors.success,
            AppColors.success.withValues(alpha: 0.25),
          ),
        );
      case NcfStatus.warning:
        return _Pill(
          label: 'BAJO',
          style: _BadgeStyle(
            AppColors.warning.withValues(alpha: 0.15),
            AppColors.warning,
            AppColors.warning.withValues(alpha: 0.30),
          ),
        );
      case NcfStatus.critical:
        return _Pill(
          label: 'CRÍTICO',
          style: _BadgeStyle(
            AppColors.destructive.withValues(alpha: 0.10),
            AppColors.destructive,
            AppColors.destructive.withValues(alpha: 0.25),
          ),
        );
    }
  }
}

/// Badge del plan de membresía del negocio.
class PlanBadge extends StatelessWidget {
  const PlanBadge({required this.plan, super.key});
  final PlanType plan;

  @override
  Widget build(BuildContext context) {
    final label = plan.label.toUpperCase();
    switch (plan) {
      case PlanType.pro:
        return _Pill(
          label: label,
          style: _BadgeStyle(
            AppColors.accent.withValues(alpha: 0.10),
            AppColors.accent,
            AppColors.accent.withValues(alpha: 0.25),
          ),
        );
      case PlanType.basic:
        return _Pill(
          label: label,
          style: _BadgeStyle(
            AppColors.primary.withValues(alpha: 0.10),
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.25),
          ),
        );
      case PlanType.trial:
        return _Pill(
          label: label,
          style: _BadgeStyle(
            AppColors.warning.withValues(alpha: 0.15),
            AppColors.warning,
            AppColors.warning.withValues(alpha: 0.30),
          ),
        );
      case PlanType.free:
      case PlanType.unknown:
        return _Pill(
          label: plan == PlanType.unknown ? '—' : label,
          style: _BadgeStyle(
            AppColors.muted,
            AppColors.mutedForeground,
            AppColors.border,
          ),
        );
    }
  }
}
