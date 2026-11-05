import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../data/repositories/billing_matrix_repository.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../domain/models/membership_invoice.dart';

/// Edita una factura pendiente o vencida: total a cobrar, vencimiento y notas
/// (migración 0053). Las pagadas y anuladas no se editan: se anulan y se hace
/// otra.
///
/// Lee la factura de nuevo antes de abrir: la lista general no trae las notas
/// y el estado pudo cambiar. Devuelve true si se guardó.
Future<bool> showEditInvoiceDialog(
  BuildContext context,
  WidgetRef ref,
  MembershipInvoice invoice,
) async {
  MembershipInvoice fresh;
  try {
    ref.invalidate(businessInvoicesProvider(invoice.businessId));
    final rows = await ref.read(businessInvoicesProvider(invoice.businessId).future);
    fresh = rows.firstWhere((i) => i.id == invoice.id, orElse: () => invoice);
  } catch (_) {
    fresh = invoice;
  }
  if (!context.mounted) return false;
  if (!fresh.isPayable) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('La factura ${fresh.invoiceNumber} ya no está pendiente: no se puede editar.')),
    );
    return false;
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => EditInvoiceDialog(invoice: fresh),
  );
  if (saved != true) return false;

  ref.invalidate(billingOverviewProvider);
  ref.invalidate(billingMetricsProvider);
  ref.invalidate(billingMatrixProvider);
  ref.invalidate(businessInvoicesProvider(invoice.businessId));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Factura ${fresh.invoiceNumber} actualizada.')),
    );
  }
  return true;
}

class EditInvoiceDialog extends ConsumerStatefulWidget {
  const EditInvoiceDialog({required this.invoice, super.key});

  final MembershipInvoice invoice;

  @override
  ConsumerState<EditInvoiceDialog> createState() => _EditInvoiceDialogState();
}

class _EditInvoiceDialogState extends ConsumerState<EditInvoiceDialog> {
  late final _total = TextEditingController(text: widget.invoice.total.toStringAsFixed(2));
  late final _notes = TextEditingController(text: widget.invoice.notes ?? '');
  late DateTime _due = widget.invoice.dueDate.toLocal();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _total.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _parsedTotal => parseAmount(_total.text);

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: 'Vence',
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final inv = widget.invoice;
    final total = _parsedTotal;
    if (total == null || total < 0) {
      setState(() => _error = 'Escribe un monto válido.');
      return;
    }
    final totalChanged = (total - inv.total).abs() >= 0.005;
    final dueChanged = !_sameDay(_due, inv.dueDate.toLocal());
    final notesChanged = _notes.text.trim() != (inv.notes ?? '').trim();
    if (!totalChanged && !dueChanged && !notesChanged) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(billingRepositoryProvider).updateInvoice(
            inv.id,
            total: totalChanged ? total : null,
            dueDate: dueChanged ? _due : null,
            notes: notesChanged ? _notes.text.trim() : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final total = _parsedTotal;
    // Mismo criterio que el servidor: si la factura cobraba ITBIS aparte, el
    // total nuevo lo incluye.
    final taxed = inv.itbis > 0;
    return AlertDialog(
      title: Text('Editar factura ${inv.invoiceNumber}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${inv.businessName} · ${inv.planType.toUpperCase()} · '
                '${DateFormat('d MMM', 'es_DO').format(inv.periodStart)} → '
                '${DateFormat('d MMM yyyy', 'es_DO').format(inv.periodEnd)}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.mutedForeground),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _total,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Total a cobrar',
                  prefixText: 'RD\$ ',
                  helperText: total == null
                      ? 'Antes: ${formatRd(inv.total)}'
                      : taxed
                          ? 'Incluye ITBIS 18%: ${formatRd(itbisIncluded(total))} · antes ${formatRd(inv.total)}'
                          : 'ITBIS incluido en el precio · antes ${formatRd(inv.total)}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (inv.ecfOverageAmount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Incluye ${formatRd(inv.ecfOverageAmount)} de facturas electrónicas extra. '
                  'Si bajas el total, el descuento cae primero sobre el plan.',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
                ),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDue,
                  icon: const Icon(HugeIcons.strokeRoundedCalendar03, size: 14),
                  label: Text('Vence ${DateFormat('d MMM yyyy', 'es_DO').format(_due)}'),
                ),
              ),
              if (inv.status == InvoiceStatus.expired && _due.isAfter(DateTime.now()))
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Con el vencimiento en el futuro vuelve a quedar pendiente.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
                  ),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notas (salen en la factura)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.destructive)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// "1,500.50" o "1500.5" → 1500.5. Null si no es un monto. La coma es de
/// miles, como en todo el panel (RD$ 4,799.00).
double? parseAmount(String raw) {
  final s = raw.trim().replaceAll(',', '');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// ITBIS (18%) que ya trae un total que lo incluye, con el mismo redondeo que
/// el servidor: monto = total / 1.18 a 2 decimales, ITBIS = el resto.
double itbisIncluded(double total) {
  final amount = (total / 1.18 * 100).roundToDouble() / 100;
  return ((total - amount) * 100).roundToDouble() / 100;
}
