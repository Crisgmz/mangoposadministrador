import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/external_ecf_requests_repository.dart';
import '../../domain/models/external_ecf_request.dart';

/// Abre los datos y el seguimiento de una solicitud de otra app (hoy Busi Pos
/// Web). Esas empresas NO son negocios de MangoPOS —viven en otra base—: su
/// alta e-CF está en su propia página y este cuadro se abre desde ahí.
Future<void> showExternalEcfRequestDialog(BuildContext context, ExternalEcfRequest r) =>
    _ExternalRequestDialog.show(context, r);

/// Datos de la solicitud y su seguimiento: con quién se habló y en qué quedó.
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
              if (r.phone != null) _row('Teléfono empresa', r.phone!),
              if (r.legalRepName != null)
                _row('Representante legal', r.legalRepName!),
              for (final b in r.branches) _row('Sucursal', b.label),
              if (r.ecfTypes.isNotEmpty)
                _row('Comprobantes', r.ecfTypes.join(', ')),
              if (r.ofvUser != null)
                _row('Usuario OFV', '${r.ofvUser!} (la clave se pide aparte)'),
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
                'La certificación ante la DGII se hace en esta página, como la '
                'de un negocio de MangoPOS. Las secuencias e-NCF y el encendido '
                'los hace el cliente en su app, que es la que emite.',
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
