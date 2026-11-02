import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/ecf_onboarding_repository.dart';
import '../../data/repositories/external_ecf_requests_repository.dart';
import '../../domain/models/ecf_onboarding.dart';
import '../../domain/models/external_ecf_request.dart';
import '../shared/page_header.dart';

/// Facturación electrónica de negocios nuevos: las solicitudes que hacen los
/// clientes desde la POS de MangoPOS y desde Busi Pos Web, en una sola bandeja.
///
/// Es el mismo trabajo para las dos: contactar al cliente y llevarlo por la
/// certificación ante la DGII. Cambia adónde lleva la fila: un negocio de
/// MangoPOS abre su detalle (ahí está el alta e-CF); una empresa de Busi Pos
/// Web no es un negocio de esta base y abre su propia página de alta, con el
/// seguimiento a un botón.
class EcfRequestsPage extends ConsumerStatefulWidget {
  const EcfRequestsPage({super.key});

  @override
  ConsumerState<EcfRequestsPage> createState() => _EcfRequestsPageState();
}

class _EcfRequestsPageState extends ConsumerState<EcfRequestsPage> {
  /// null = todos los orígenes.
  String? _origin;
  bool _onlyOpen = true;

  @override
  Widget build(BuildContext context) {
    final posAsync = ref.watch(ecfRequestsProvider);
    final externalAsync = ref.watch(externalEcfRequestsProvider);

    // Cada origen carga y falla por su lado: que no se lleve al otro.
    final all = [
      ...?posAsync.valueOrNull?.map(EcfRequestEntry.fromPos),
      ...?externalAsync.valueOrNull?.map(EcfRequestEntry.fromExternal),
    ]..sort(EcfRequestEntry.newestFirst);
    final loading = posAsync.isLoading && externalAsync.isLoading;

    final scoped = _onlyOpen ? all.where((e) => e.isOpen).toList() : all;
    final origins = <String>{for (final e in all) e.origin}.toList()..sort();
    final shown = _origin == null ? scoped : scoped.where((e) => e.origin == _origin).toList();
    final unregistered = all.where((e) => e.isOpen && e.urgent && e.external != null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Facturación electrónica',
          title: 'Negocios nuevos',
          subtitle: 'Solicitudes de facturación electrónica de MangoPOS y Busi Pos Web.',
          trailing: OutlinedButton.icon(
            onPressed: () {
              ref.invalidate(ecfRequestsProvider);
              ref.invalidate(externalEcfRequestsProvider);
            },
            icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
            label: const Text('Actualizar'),
          ),
        ),
        const SizedBox(height: 20),
        if (posAsync.hasError)
          _error('No se pudieron leer las solicitudes de MangoPOS: ${posAsync.error}'),
        if (externalAsync.hasError)
          _error('No se pudieron leer las solicitudes de Busi Pos Web: ${externalAsync.error}'),
        if (unregistered > 0) ...[
          _Warning(
            '$unregistered de Busi Pos Web sin registrar en Alanube: casi siempre es la '
            'contraseña del certificado o un archivo que no es el de firma. Revísalas primero.',
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: Text('Todas (${scoped.length})'),
              selected: _origin == null,
              onSelected: (_) => setState(() => _origin = null),
            ),
            for (final o in origins)
              ChoiceChip(
                label: Text('$o (${scoped.where((e) => e.origin == o).length})'),
                selected: _origin == o,
                onSelected: (_) => setState(() => _origin = o),
              ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Solo pendientes'),
              selected: _onlyOpen,
              onSelected: (v) => setState(() => _onlyOpen = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _onlyOpen ? 'No hay solicitudes pendientes.' : 'No hay solicitudes.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.mutedForeground),
            ),
          )
        else
          for (final e in shown) _RequestRow(entry: e),
      ],
    );
  }

  Widget _error(String msg) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(msg, style: const TextStyle(color: AppColors.destructive, fontSize: 13)),
      );
}

/// Una solicitud, venga de donde venga, con lo que la bandeja necesita para
/// ordenarla, filtrarla y pintarla.
class EcfRequestEntry {
  const EcfRequestEntry({
    required this.origin,
    required this.name,
    required this.isOpen,
    required this.stateLabel,
    required this.urgent,
    this.rnc,
    this.contactName,
    this.contactPhone,
    this.saysAuthorized = false,
    this.requestedAt,
    this.pos,
    this.external,
  });

  /// "MangoPOS", "Busi Pos Web"…
  final String origin;
  final String name;
  final String? rnc;
  final String? contactName;
  final String? contactPhone;
  final bool saysAuthorized;
  final DateTime? requestedAt;

  /// Falta trabajo: en MangoPOS, todavía no emite; en otras apps, nueva o en
  /// proceso.
  final bool isOpen;
  final String stateLabel;

  /// Lo que hay que mirar primero: sin empresa en Alanube.
  final bool urgent;

  final EcfRequestSummary? pos;
  final ExternalEcfRequest? external;

  factory EcfRequestEntry.fromPos(EcfRequestSummary r) => EcfRequestEntry(
        origin: 'MangoPOS',
        name: r.businessName ?? r.legalName ?? r.businessId,
        rnc: r.rnc,
        contactName: r.contactName,
        contactPhone: r.contactPhone,
        saysAuthorized: r.alreadyAuthorized == true,
        requestedAt: r.requestedAt,
        isOpen: !r.isActive,
        stateLabel: r.stageLabel,
        urgent: r.stage == 'company',
        pos: r,
      );

  factory EcfRequestEntry.fromExternal(ExternalEcfRequest r) => EcfRequestEntry(
        origin: r.source == 'flutter_shop+' ? 'Busi Pos Web' : r.source,
        name: r.displayName,
        rnc: r.rnc,
        contactName: r.contactName,
        contactPhone: r.contactPhone,
        saysAuthorized: r.alreadyAuthorized == true,
        requestedAt: r.requestedAt ?? r.receivedAt,
        isOpen: r.isOpen,
        stateLabel: r.companyRegistered ? r.statusLabel : 'Sin registrar',
        urgent: !r.companyRegistered,
        external: r,
      );

  /// Las más nuevas primero; sin fecha, al final.
  static int newestFirst(EcfRequestEntry a, EcfRequestEntry b) {
    final x = a.requestedAt, y = b.requestedAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.entry});

  final EcfRequestEntry entry;

  void _open(BuildContext context) {
    final pos = entry.pos;
    final external = entry.external;
    if (pos != null) {
      context.go('/negocios/${pos.businessId}');
    } else if (external != null) {
      context.go('/facturacion-electronica/externa/${external.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM, h:mm a', 'es');
    final e = entry;
    final color = !e.isOpen
        ? AppColors.mutedForeground
        : e.urgent
            ? AppColors.accent
            : AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _OriginTag(e.origin),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (e.rnc != null) 'RNC ${e.rnc}',
                        if (e.contactName != null)
                          '${e.contactName}${e.contactPhone != null ? ' · ${e.contactPhone}' : ''}',
                        if (e.saysAuthorized) 'dice que ya está autorizado',
                        if (e.requestedAt != null) df.format(e.requestedAt!.toLocal()),
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
                  e.stateLabel,
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

class _OriginTag extends StatelessWidget {
  const _OriginTag(this.origin);

  final String origin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.mutedForeground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        origin,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.mutedForeground),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.accent)),
    );
  }
}
