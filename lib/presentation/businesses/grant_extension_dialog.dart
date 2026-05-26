import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../domain/models/business_extension.dart';

/// Resultado del dialog. La UI lo consume y llama
/// `DashboardRepository.grantExtension`.
class GrantExtensionResult {
  const GrantExtensionResult({
    required this.type,
    required this.reason,
    this.days,
    this.amount,
    this.customerMessage,
  });

  final ExtensionType type;
  final String reason;
  final int? days;
  final double? amount;
  final String? customerMessage;
}

/// Dialog para otorgar prórroga, gracia o crédito al negocio.
class GrantExtensionDialog extends StatefulWidget {
  const GrantExtensionDialog({super.key, required this.businessName});

  final String businessName;

  @override
  State<GrantExtensionDialog> createState() => _GrantExtensionDialogState();
}

class _GrantExtensionDialogState extends State<GrantExtensionDialog> {
  ExtensionType _type = ExtensionType.trialExtension;
  int _days = 7;
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  bool get _enabled {
    if (_reasonCtrl.text.trim().isEmpty) return false;
    if (_type == ExtensionType.freeCredit) {
      final amt = double.tryParse(_amountCtrl.text.trim());
      return amt != null && amt > 0;
    }
    return _days > 0;
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = _type == ExtensionType.freeCredit;
    return AlertDialog(
      title: Row(
        children: const [
          Icon(
            HugeIcons.strokeRoundedCalendar03,
            color: AppColors.primary,
            size: 18,
          ),
          SizedBox(width: 8),
          Text('Dar prórroga / crédito'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Se aplicará a ${widget.businessName}.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 16),
              const _Label('Tipo'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TypeChip(
                    label: 'Extensión de trial',
                    selected: _type == ExtensionType.trialExtension,
                    color: AppColors.accent,
                    onTap: () => setState(
                      () => _type = ExtensionType.trialExtension,
                    ),
                  ),
                  _TypeChip(
                    label: 'Gracia de pago',
                    selected: _type == ExtensionType.paymentGrace,
                    color: AppColors.warning,
                    onTap: () => setState(
                      () => _type = ExtensionType.paymentGrace,
                    ),
                  ),
                  _TypeChip(
                    label: 'Crédito (RD\$)',
                    selected: _type == ExtensionType.freeCredit,
                    color: AppColors.success,
                    onTap: () => setState(
                      () => _type = ExtensionType.freeCredit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (isCredit) ...[
                const _Label('Monto (RD\$)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: '500.00',
                    prefixText: 'RD\$ ',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                const _Label('Días'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in const [3, 7, 14, 30])
                      _TypeChip(
                        label: '$d días',
                        selected: _days == d,
                        color: AppColors.primary,
                        onTap: () => setState(() => _days = d),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const _Label('Razón (obligatoria)'),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Ej: caída de Azul el 15/05, ajuste retroactivo…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              const _Label('Mensaje opcional al cliente'),
              const SizedBox(height: 6),
              TextField(
                controller: _msgCtrl,
                maxLines: 2,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Texto que verá el dueño del negocio.',
                  border: OutlineInputBorder(),
                ),
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
          onPressed: _enabled ? _onConfirm : null,
          child: const Text('Otorgar'),
        ),
      ],
    );
  }

  void _onConfirm() {
    Navigator.of(context).pop(
      GrantExtensionResult(
        type: _type,
        reason: _reasonCtrl.text.trim(),
        days: _type == ExtensionType.freeCredit ? null : _days,
        amount: _type == ExtensionType.freeCredit
            ? double.parse(_amountCtrl.text.trim())
            : null,
        customerMessage: _msgCtrl.text.trim().isEmpty
            ? null
            : _msgCtrl.text.trim(),
      ),
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

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : AppColors.muted,
          border: Border.all(
            color:
                selected ? color.withValues(alpha: 0.45) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? color : AppColors.foreground,
          ),
        ),
      ),
    );
  }
}
