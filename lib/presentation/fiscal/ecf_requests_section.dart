import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/ecf_onboarding_repository.dart';
import '../../domain/models/ecf_onboarding.dart';

/// Solicitudes de facturación electrónica que hicieron los clientes desde la
/// POS. Las que ya están activas se ocultan: esto es la bandeja de trabajo.
/// Cada fila lleva al detalle del negocio, donde se sigue el alta.
class EcfRequestsSection extends ConsumerWidget {
  const EcfRequestsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(ecfRequestsProvider);

    return requestsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(
          'No se pudieron leer las solicitudes de facturación electrónica: $e',
          style: const TextStyle(color: AppColors.destructive, fontSize: 13),
        ),
      ),
      data: (all) {
        final pending = all.where((r) => !r.isActive).toList(growable: false);
        if (pending.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SOLICITUDES DE FACTURACIÓN ELECTRÓNICA (${pending.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 10),
              for (final r in pending) _RequestRow(request: r),
            ],
          ),
        );
      },
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});

  final EcfRequestSummary request;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM, h:mm a', 'es');
    final r = request;
    final color = r.stage == 'company' ? AppColors.accent : AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/negocios/${r.businessId}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(HugeIcons.strokeRoundedInvoice03, size: 18, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.businessName ?? r.legalName ?? r.businessId,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (r.rnc != null) 'RNC ${r.rnc}',
                        if (r.contactName != null)
                          '${r.contactName}${r.contactPhone != null ? ' · ${r.contactPhone}' : ''}',
                        if (r.alreadyAuthorized == true) 'dice que ya está autorizado',
                        if (r.requestedAt != null) df.format(r.requestedAt!.toLocal()),
                      ].join('  ·  '),
                      style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  r.stageLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(HugeIcons.strokeRoundedArrowRight01, size: 16, color: AppColors.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
