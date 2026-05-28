import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../domain/models/plan.dart';

class PlanFormResult {
  const PlanFormResult({
    required this.code,
    required this.name,
    required this.description,
    required this.priceMonthly,
    required this.features,
    required this.displayOrder,
    required this.isActive,
    required this.taxIncluded,
  });

  final String code;
  final String name;
  final String? description;
  final double priceMonthly;
  final List<String> features;
  final int displayOrder;
  final bool isActive;
  final bool taxIncluded;
}

/// Dialog para crear o editar un plan.
/// Si `existing == null` crea uno nuevo (con `code` editable);
/// si se provee, edita (code en read-only).
class PlanFormDialog extends StatefulWidget {
  const PlanFormDialog({super.key, this.existing});

  final Plan? existing;

  @override
  State<PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends State<PlanFormDialog> {
  late TextEditingController _code;
  late TextEditingController _name;
  late TextEditingController _description;
  late TextEditingController _price;
  late TextEditingController _displayOrder;
  late TextEditingController _featureInput;
  late List<String> _features;
  late bool _isActive;
  late bool _taxIncluded;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _code = TextEditingController(text: e?.code ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _price = TextEditingController(
      text: e == null ? '' : e.priceMonthly.toStringAsFixed(2),
    );
    _displayOrder = TextEditingController(
      text: (e?.displayOrder ?? 10).toString(),
    );
    _featureInput = TextEditingController();
    _features = List<String>.from(e?.features ?? const <String>[]);
    _isActive = e?.isActive ?? true;
    _taxIncluded = e?.taxIncluded ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _displayOrder.dispose();
    _featureInput.dispose();
    super.dispose();
  }

  bool get _enabled {
    if (_name.text.trim().isEmpty) return false;
    if (!_isEdit) {
      final c = _code.text.trim();
      if (c.isEmpty) return false;
      // RPC valida formato; aquí solo check ligero.
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(c)) return false;
    }
    final p = double.tryParse(_price.text.trim());
    if (p == null || p < 0) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEdit
                ? HugeIcons.strokeRoundedEdit02
                : HugeIcons.strokeRoundedAdd01,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(_isEdit ? 'Editar plan' : 'Nuevo plan'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Label('Código (slug)'),
              const SizedBox(height: 6),
              TextField(
                controller: _code,
                readOnly: _isEdit,
                decoration: InputDecoration(
                  hintText: 'pro_plus',
                  helperText: _isEdit
                      ? 'No editable. Se conserva para no romper referencias.'
                      : 'Minúsculas, números y underscore. No se puede cambiar luego.',
                  border: const OutlineInputBorder(),
                  filled: _isEdit,
                  fillColor: _isEdit ? AppColors.muted : null,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                ],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              const _Label('Nombre visible'),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  hintText: 'Ej: Pro Plus',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              const _Label('Descripción (opcional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _description,
                maxLines: 2,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Para quién es este plan…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('Precio mensual (RD\$)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            hintText: '990.00',
                            prefixText: 'RD\$ ',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('Orden'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _displayOrder,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '10',
                            border: OutlineInputBorder(),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _Label('Features (uno por línea)'),
              const SizedBox(height: 6),
              _FeaturesEditor(
                features: _features,
                onChanged: (v) => setState(() => _features = v),
                input: _featureInput,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _taxIncluded,
                onChanged: (v) => setState(() => _taxIncluded = v),
                title: const Text(
                  'Precio incluye ITBIS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Si está activo, el precio mostrado ya incluye 18% ITBIS y la factura no desglosa impuesto. Si está apagado, la factura agrega ITBIS sobre el precio.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              SwitchListTile(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: const Text(
                  'Activo',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Si está inactivo no aparece en el selector de plan al crear / editar membresías.',
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
                    PlanFormResult(
                      code: _code.text.trim(),
                      name: _name.text.trim(),
                      description: _description.text.trim().isEmpty
                          ? null
                          : _description.text.trim(),
                      priceMonthly: double.parse(_price.text.trim()),
                      features: _features,
                      displayOrder:
                          int.tryParse(_displayOrder.text.trim()) ?? 0,
                      isActive: _isActive,
                      taxIncluded: _taxIncluded,
                    ),
                  )
              : null,
          child: Text(_isEdit ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}

class _FeaturesEditor extends StatelessWidget {
  const _FeaturesEditor({
    required this.features,
    required this.onChanged,
    required this.input,
  });

  final List<String> features;
  final ValueChanged<List<String>> onChanged;
  final TextEditingController input;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (features.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < features.length; i++)
                  Chip(
                    label: Text(features[i]),
                    onDeleted: () {
                      final next = List<String>.from(features)..removeAt(i);
                      onChanged(next);
                    },
                    deleteIconColor: AppColors.mutedForeground,
                    backgroundColor: AppColors.card,
                    side: const BorderSide(color: AppColors.border),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: input,
                decoration: const InputDecoration(
                  hintText: 'Ej: KDS multi-estación',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _add,
              child: const Text('Agregar'),
            ),
          ],
        ),
      ],
    );
  }

  void _add() {
    final v = input.text.trim();
    if (v.isEmpty) return;
    onChanged([...features, v]);
    input.clear();
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
