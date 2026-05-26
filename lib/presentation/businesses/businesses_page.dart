import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../dashboard/widgets/business_table.dart';
import '../shared/page_header.dart';
import 'new_business_dialog.dart';

class BusinessesPage extends ConsumerWidget {
  const BusinessesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Negocios',
          title: 'Listado completo',
          subtitle: 'Todos los negocios registrados en la plataforma.',
          trailing: FilledButton.icon(
            onPressed: () => _onCreate(context, ref),
            icon: const Icon(HugeIcons.strokeRoundedAdd01, size: 16),
            label: const Text('Nuevo negocio'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const BusinessTable(),
      ],
    );
  }

  Future<void> _onCreate(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<NewBusinessResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NewBusinessDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      final id = await ref.read(dashboardRepositoryProvider).createBusiness(
            ownerEmail: result.ownerEmail,
            businessName: result.businessName,
            businessType: result.businessType,
            domain: result.domain,
            environment: result.environment,
            planType: result.planType,
            trialDays: result.trialDays,
          );
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.businessName} creado. Abriendo detalle…'),
        ),
      );
      context.go('/negocios/$id');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
