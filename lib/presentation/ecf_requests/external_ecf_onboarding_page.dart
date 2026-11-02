import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../data/repositories/external_ecf_requests_repository.dart';
import '../../domain/models/ecf_onboarding.dart';
import '../../domain/models/external_ecf_request.dart';
import '../businesses/ecf_onboarding_section.dart';
import '../shared/page_header.dart';
import 'external_ecf_request_dialog.dart';

/// Alta e-CF de una empresa de otra app (hoy Busi Pos Web): la misma
/// certificación ante la DGII que un negocio de MangoPOS, sobre la solicitud
/// que llegó a la bandeja. Las secuencias y el encendido los hace el cliente
/// en su app; la sección lo indica en esos pasos.
class ExternalEcfOnboardingPage extends ConsumerWidget {
  const ExternalEcfOnboardingPage({required this.requestId, super.key});

  /// `external_ecf_requests.id`.
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La bandeja ya trae la solicitud: datos del encabezado y del seguimiento.
    final request = ref.watch(externalEcfRequestsProvider).valueOrNull?.where((r) => r.id == requestId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Facturación electrónica · ${_origin(request)}',
          title: request?.displayName ?? 'Empresa de otra app',
          subtitle: [
            if (request?.rnc != null) 'RNC ${request!.rnc}',
            if (request != null) 'Empresa (id allá) ${request.externalId}',
            if (request != null) request.statusLabel,
          ].join('  ·  '),
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.go('/facturacion-electronica'),
                icon: const Icon(HugeIcons.strokeRoundedArrowLeft01, size: 16),
                label: const Text('Solicitudes'),
              ),
              FilledButton.icon(
                onPressed: request == null ? null : () => showExternalEcfRequestDialog(context, request),
                icon: const Icon(HugeIcons.strokeRoundedNote, size: 16),
                label: const Text('Datos y seguimiento'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        EcfOnboardingSection(owner: EcfOwner.external(requestId)),
      ],
    );
  }

  static String _origin(ExternalEcfRequest? r) =>
      r == null || r.source == 'flutter_shop+' ? 'Busi Pos Web' : r.source;
}
