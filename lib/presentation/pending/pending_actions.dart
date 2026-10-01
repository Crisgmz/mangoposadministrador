import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/pending_accounts_repository.dart';
import '../../domain/models/pending_business.dart';
import 'pending_detail_dialog.dart';

/// Abre el detalle de una cuenta pendiente y ejecuta lo que el operador elija
/// (aprobar / rechazar / abrir el negocio), refrescando todo lo que depende
/// del cambio.
///
/// Vive fuera de la página porque la bandeja "Requiere acción" de Vista
/// Global dispara exactamente el mismo flujo. Duplicarlo era garantía de que
/// una de las dos copias se quedara sin invalidar algún provider y mostrara
/// una cuenta ya aprobada como pendiente.
Future<void> openPendingDetail(
  BuildContext context,
  WidgetRef ref,
  PendingBusiness item,
) async {
  final result = await showDialog<PendingDetailResult>(
    context: context,
    builder: (_) => PendingDetailDialog(item: item),
  );
  if (result == null || !context.mounted) return;

  if (result.action == PendingDetailAction.openBusiness) {
    context.go('/negocios/${item.businessId}');
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(pendingAccountsRepositoryProvider);
  try {
    switch (result.action) {
      case PendingDetailAction.approve:
        await repo.approve(businessId: item.businessId, reason: result.reason);
      case PendingDetailAction.reject:
        await repo.reject(
          businessId: item.businessId,
          reason: result.reason ?? '',
        );
      case PendingDetailAction.openBusiness:
        return;
    }
    ref.invalidate(pendingAccountsListProvider);
    ref.invalidate(pendingAccountsCountProvider);
    ref.invalidate(platformOverviewProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.action == PendingDetailAction.approve
              ? '${item.businessName} aprobada.'
              : '${item.businessName} rechazada.',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
  }
}
