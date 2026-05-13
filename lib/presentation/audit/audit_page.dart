import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../domain/models/audit_log_entry.dart';
import '../shared/page_header.dart';

class AuditPage extends ConsumerWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(filteredAuditLogsProvider(null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          kicker: 'Auditoría',
          title: 'Acciones críticas',
          subtitle:
              'Registro de anulaciones, eliminaciones y cancelaciones en todos los negocios.',
        ),
        const SizedBox(height: 24),
        logsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Error cargando auditoría: $e',
              style: const TextStyle(color: AppColors.destructive),
            ),
          ),
          data: _List.new,
        ),
      ],
    );
  }
}

class _List extends StatelessWidget {
  const _List(this.logs);
  final List<AuditLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.shadowCard,
        ),
        alignment: Alignment.center,
        child: const Text(
          'Sin acciones críticas registradas. 🎉',
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < logs.length; i++) ...[
            _Row(log: logs[i]),
            if (i < logs.length - 1)
              const Divider(
                  height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.log});
  final AuditLogEntry log;

  Color get _badgeBg {
    switch (log.severity) {
      case AuditSeverity.critical:
        return AppColors.destructive.withValues(alpha: 0.10);
      case AuditSeverity.warning:
        return AppColors.warning.withValues(alpha: 0.15);
      case AuditSeverity.info:
        return AppColors.muted;
    }
  }

  Color get _badgeFg {
    switch (log.severity) {
      case AuditSeverity.critical:
        return AppColors.destructive;
      case AuditSeverity.warning:
        return AppColors.warning;
      case AuditSeverity.info:
        return AppColors.mutedForeground;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _badgeBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              log.action.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _badgeFg,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.businessName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                  ),
                ),
                if (log.reason != null && log.reason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      log.reason!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (log.refTable != null) log.refTable!,
                      if (log.userName != null) 'usuario: ${log.userName!}'
                      else if (log.userId != null) 'usuario: ${log.userId!.substring(0, 8)}',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatRelative(log.createdAt),
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
