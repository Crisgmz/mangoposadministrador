import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/infrastructure_repository.dart';
import '../../domain/models/vps_instance.dart';
import '../shared/page_header.dart';

class InfrastructurePage extends ConsumerWidget {
  const InfrastructurePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpsAsync = ref.watch(vpsStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Infraestructura',
          title: 'VPS de Hostinger',
          subtitle:
              'Status y métricas de los servidores donde corre la plataforma. Solo lectura.',
          trailing: OutlinedButton.icon(
            onPressed: () => ref.invalidate(vpsStatusProvider),
            icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
            label: const Text('Actualizar'),
          ),
        ),
        const SizedBox(height: 24),
        vpsAsync.when(
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
          error: (e, _) => _ErrorBox(message: '$e'),
          data: (rows) => _VpsGrid(rows: rows),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.destructive.withValues(alpha: 0.06),
        border: Border.all(
          color: AppColors.destructive.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              HugeIcons.strokeRoundedAlertCircle,
              size: 16,
              color: AppColors.destructive,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No se pudo cargar el status de los VPS.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.destructive,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.foreground,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Posibles causas: la Edge Function `hostinger-vps-status` '
                  'no está desplegada, o el secret `HOSTINGER_API_KEY` no '
                  'está configurado. Para desplegarla:',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.muted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const SelectableText(
                    'supabase secrets set HOSTINGER_API_KEY=<token>\n'
                    'supabase functions deploy hostinger-vps-status',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.foreground,
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

class _VpsGrid extends StatelessWidget {
  const _VpsGrid({required this.rows});
  final List<VpsInstance> rows;

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
        child: const Text(
          'No hay VPS asociados a este token de Hostinger.',
          style: TextStyle(color: AppColors.mutedForeground),
        ),
      );
    }
    // Wrap en lugar de GridView: cada card toma su altura natural sin huecos.
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 1100 ? 2 : 1;
        final spacing = 14.0;
        final cardWidth = (w - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final vps in rows)
              SizedBox(width: cardWidth, child: _VpsCard(vps: vps)),
          ],
        );
      },
    );
  }
}

class _VpsCard extends StatelessWidget {
  const _VpsCard({required this.vps});
  final VpsInstance vps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: icono + hostname + (plan) + state badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: vps.isRunning
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  HugeIcons.strokeRoundedCpu,
                  size: 15,
                  color: vps.isRunning
                      ? AppColors.success
                      : AppColors.warning,
                ),
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
                            vps.hostname,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.foreground,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (vps.plan != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.muted,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              vps.plan!,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      [
                        if (vps.ipAddress != null) vps.ipAddress!,
                        if (vps.template != null) vps.template!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: AppColors.mutedForeground,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StateBadge(state: vps.state),
            ],
          ),
          const SizedBox(height: 12),
          // Métricas en 3 columnas compactas
          if (vps.metrics != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MetricCompact(
                    label: 'CPU',
                    value: vps.metrics!.cpuPercent == null
                        ? '—'
                        : '${vps.metrics!.cpuPercent!.toStringAsFixed(1)}%',
                    progress: _ratio(vps.metrics!.cpuPercent, 100),
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCompact(
                    label: 'RAM',
                    value: _bytesMb(vps.metrics!.memoryUsedMb, vps.memoryMb),
                    progress: _ratio(
                      vps.metrics!.memoryUsedMb,
                      vps.memoryMb?.toDouble(),
                    ),
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCompact(
                    label: 'Disco',
                    value: _bytesGb(vps.metrics!.diskUsedGb, vps.diskGb),
                    progress: _ratio(
                      vps.metrics!.diskUsedGb,
                      vps.diskGb?.toDouble(),
                    ),
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ] else
            const Text(
              'Métricas no disponibles.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.mutedForeground,
              ),
            ),
          const SizedBox(height: 10),
          // Footer: specs + tráfico/uptime en una línea
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _Spec(
                  icon: HugeIcons.strokeRoundedCpu,
                  value: vps.cpuCores == null ? '—' : '${vps.cpuCores}c',
                ),
                const SizedBox(width: 10),
                _Spec(
                  icon: HugeIcons.strokeRoundedDatabase02,
                  value: vps.memoryMb == null
                      ? '—'
                      : '${(vps.memoryMb! / 1024).toStringAsFixed(0)}GB',
                ),
                const SizedBox(width: 10),
                _Spec(
                  icon: HugeIcons.strokeRoundedHardDrive,
                  value: vps.diskGb == null ? '—' : '${vps.diskGb}GB',
                ),
                const Spacer(),
                if (vps.metrics?.uptimeHuman != null)
                  Text(
                    '↑ ${vps.metrics!.uptimeHuman}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                if (vps.metrics?.bandwidthUsedGb != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${vps.metrics!.bandwidthUsedGb!.toStringAsFixed(2)} GB',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  double? _ratio(double? used, double? total) {
    if (used == null || total == null || total == 0) return null;
    return (used / total).clamp(0.0, 1.0);
  }

  String _bytesMb(double? used, int? totalMb) {
    if (used == null) return '—';
    final usedGb = used / 1024;
    if (totalMb == null) return '${usedGb.toStringAsFixed(1)} GB';
    final totalGb = totalMb / 1024;
    return '${usedGb.toStringAsFixed(1)}/${totalGb.toStringAsFixed(0)}GB';
  }

  String _bytesGb(double? used, int? totalGb) {
    if (used == null) return '—';
    if (totalGb == null) return '${used.toStringAsFixed(1)} GB';
    return '${used.toStringAsFixed(1)}/${totalGb}GB';
  }
}

/// Métrica compacta vertical: label arriba, valor grande, barra abajo.
class _MetricCompact extends StatelessWidget {
  const _MetricCompact({
    required this.label,
    required this.value,
    required this.color,
    this.progress,
  });
  final String label;
  final String value;
  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.mutedForeground,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.foreground,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          // Si `progress` es null, mostramos barra vacía (no la animación
          // indeterminada que parece "loading").
          child: LinearProgressIndicator(
            value: progress ?? 0,
            minHeight: 4,
            backgroundColor: AppColors.muted,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final lower = state.toLowerCase();
    final (color, label) = lower == 'running'
        ? (AppColors.success, 'EN LÍNEA')
        : lower == 'stopped'
            ? (AppColors.destructive, 'DETENIDO')
            : (AppColors.warning, state.toUpperCase());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
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

class _Spec extends StatelessWidget {
  const _Spec({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.mutedForeground),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.foreground,
          ),
        ),
      ],
    );
  }
}
