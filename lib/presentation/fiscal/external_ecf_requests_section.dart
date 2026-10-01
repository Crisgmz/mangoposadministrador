import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/external_ecf_requests_repository.dart';
import '../../domain/models/external_ecf_request.dart';

/// Solicitudes de facturación electrónica que llegaron de otras apps que
/// comparten esta cuenta de Alanube (hoy Busi Pos Web).
///
/// Va junto a las de la POS porque es el mismo trabajo: contactar al cliente y
/// llevarlo por la certificación ante la DGII. La diferencia es que estas NO
/// son negocios de MangoPOS —viven en otra base— así que la fila abre un
/// cuadro con los datos en vez de llevar al detalle de un negocio.
///
/// Las atendidas y descartadas se ocultan: esto es bandeja de trabajo.
class ExternalEcfRequestsSection extends ConsumerWidget {
  const ExternalEcfRequestsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(externalEcfRequestsProvider);

    return requestsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(
          'No se pudieron leer las solicitudes de otras apps: $e',
          style: const TextStyle(color: AppColors.destructive, fontSize: 13),
        ),
      ),
      data: (all) {
        final open = all.where((r) => r.isOpen).toList(growable: false);
        if (open.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SOLICITUDES DE OTRAS APPS (${open.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 10),
              for (final r in open) _ExternalRequestRow(request: r),
            ],
          ),
        );
      },
    );
  }
}

class _ExternalRequestRow extends ConsumerWidget {
  const _ExternalRequestRow({required this.request});

  final ExternalEcfRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('d MMM, h:mm a', 'es');
    final r = request;
    // Sin registrar en el proveedor es lo urgente: el cliente ya mandó su
    // certificado y quedó trancado.
    final color = r.companyRegistered ? AppColors.primary : AppColors.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _ExternalRequestDialog.show(context, r),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(
                HugeIcons.strokeRoundedInvoice03,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SourceTag(source: r.source),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (r.rnc != null) 'RNC ${r.rnc}',
                        if (r.contactName != null)
                          '${r.contactName}'
                              '${r.contactPhone != null ? ' · ${r.contactPhone}' : ''}',
                        if (r.alreadyAuthorized == true)
                          'dice que ya está autorizado',
                        if (r.requestedAt != null)
                          df.format(r.requestedAt!.toLocal()),
                      ].join('  ·  '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  r.companyRegistered ? r.statusLabel : 'Sin registrar',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
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
      ),
    );
  }
}

class _SourceTag extends StatelessWidget {
  const _SourceTag({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.mutedForeground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        source == 'flutter_shop+' ? 'Busi Pos Web' : source,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.mutedForeground,
        ),
      ),
    );
  }
}

/// Datos de la solicitud y su seguimiento.
///
/// Solo seguimiento: el alta de esa empresa se sigue haciendo en SU app, que
/// es la que tiene que emitir. Acá se anota con quién se habló y en qué quedó.
class _ExternalRequestDialog extends ConsumerStatefulWidget {
  const _ExternalRequestDialog({required this.request});

  final ExternalEcfRequest request;

  static Future<void> show(BuildContext context, ExternalEcfRequest r) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ExternalRequestDialog(request: r),
    );
  }

  @override
  ConsumerState<_ExternalRequestDialog> createState() =>
      _ExternalRequestDialogState();
}

class _ExternalRequestDialogState
    extends ConsumerState<_ExternalRequestDialog> {
  late final TextEditingController _notes;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: widget.request.notes ?? '');
    _status = widget.request.status;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final df = DateFormat('d MMM y, h:mm a', 'es');

    return AlertDialog(
      title: Text(r.displayName),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (r.companyRegistered
                          ? AppColors.primary
                          : AppColors.accent)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.headline,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: r.companyRegistered
                        ? AppColors.primary
                        : AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _row('App', r.source == 'flutter_shop+' ? 'Busi Pos Web' : r.source),
              _row('Empresa (id allá)', r.externalId),
              if (r.rnc != null) _row('RNC', r.rnc!),
              if (r.legalName != null) _row('Razón social', r.legalName!),
              if (r.tradeName != null) _row('Nombre comercial', r.tradeName!),
              if (r.email != null) _row('Correo', r.email!),
              if (r.contactName != null) _row('Contacto', r.contactName!),
              if (r.contactPhone != null) _row('Teléfono', r.contactPhone!),
              _row(
                'Dice ser emisor autorizado',
                r.alreadyAuthorized == true ? 'Sí' : 'No',
              ),
              if (r.alanubeCompanyId != null)
                _row('Empresa en Alanube', r.alanubeCompanyId!),
              if (r.requestedAt != null)
                _row('Solicitada', df.format(r.requestedAt!.toLocal())),
              if (r.receivedAt != null)
                _row('Recibida acá', df.format(r.receivedAt!.toLocal())),

              const SizedBox(height: 16),
              const Text(
                'SEGUIMIENTO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: const [
                  DropdownMenuItem(value: 'new', child: Text('Nueva')),
                  DropdownMenuItem(
                    value: 'in_progress',
                    child: Text('En proceso'),
                  ),
                  DropdownMenuItem(value: 'done', child: Text('Atendida')),
                  DropdownMenuItem(
                    value: 'discarded',
                    child: Text('Descartada'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _status = v ?? 'new'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notas',
                  hintText: 'Con quién se habló y en qué quedó.',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'El alta de esta empresa se completa en su propia app: es la '
                'que tiene que emitir. Acá solo se lleva el seguimiento.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 170,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mutedForeground,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(externalEcfRequestsRepositoryProvider)
          .updateStatus(
            id: widget.request.id,
            status: _status,
            notes: _notes.text,
          );
      if (!mounted) return;
      ref.invalidate(externalEcfRequestsProvider);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }
}
