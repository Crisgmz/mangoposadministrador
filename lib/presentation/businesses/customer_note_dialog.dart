import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../domain/models/customer_note.dart';

/// Resultado del dialog. Si `noteId == null`, es creación; si no, edición.
class CustomerNoteResult {
  const CustomerNoteResult({
    this.noteId,
    required this.category,
    required this.body,
    required this.pinned,
  });

  final String? noteId;
  final NoteCategory category;
  final String body;
  final bool pinned;
}

/// Dialog para crear o editar una nota interna.
class CustomerNoteDialog extends StatefulWidget {
  const CustomerNoteDialog({super.key, this.existing});

  /// Si se provee, el dialog edita; si es null, crea.
  final CustomerNote? existing;

  @override
  State<CustomerNoteDialog> createState() => _CustomerNoteDialogState();
}

class _CustomerNoteDialogState extends State<CustomerNoteDialog> {
  late NoteCategory _category;
  late bool _pinned;
  late TextEditingController _bodyCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = e?.category ?? NoteCategory.general;
    _pinned = e?.pinned ?? false;
    _bodyCtrl = TextEditingController(text: e?.body ?? '');
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool get _enabled => _bodyCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            HugeIcons.strokeRoundedNote,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(isEdit ? 'Editar nota' : 'Nueva nota'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Label('Categoría'),
              const SizedBox(height: 6),
              DropdownButtonFormField<NoteCategory>(
                initialValue: _category,
                isExpanded: true,
                items: [
                  for (final c in NoteCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              const SizedBox(height: 16),
              const _Label('Contenido'),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyCtrl,
                autofocus: true,
                maxLines: 6,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Escribe el contexto que el equipo debe saber…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
                title: const Text(
                  'Fijar al inicio',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Las notas fijas aparecen primero en el detalle.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enabled
              ? () => Navigator.of(context).pop(
                    CustomerNoteResult(
                      noteId: widget.existing?.id,
                      category: _category,
                      body: _bodyCtrl.text.trim(),
                      pinned: _pinned,
                    ),
                  )
              : null,
          child: Text(isEdit ? 'Guardar' : 'Crear nota'),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.mutedForeground,
      ),
    );
  }
}
