import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/ecf_quota_repository.dart';
import '../../domain/models/ecf_quota_usage.dart';

/// Sección "Facturas electrónicas" del detalle de negocio.
///
/// Fija cuántas e-CF trae incluidas el negocio por período de cobro. Las que la
/// DGII acepte por encima se cobran a un precio por unidad (el propio del
/// negocio o el global de Configuración) y se suman al próximo cobro con
/// tarjeta o a la próxima factura (migración 0051).
class EcfQuotaSection extends ConsumerWidget {
  const EcfQuotaSection({
    required this.businessId,
    required this.businessName,
    super.key,
  });

  final String businessId;
  final String businessName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ecfQuotaUsageProvider(businessId));
    final usage = async.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              HugeIcons.strokeRoundedInvoice01,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Facturas electrónicas',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ),
            if (usage != null)
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (usage.hasQuota)
                      TextButton(
                        onPressed: () => _clear(context, ref),
                        child: const Text('Quitar cantidad'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _edit(context, ref, usage),
                      icon: const Icon(
                        HugeIcons.strokeRoundedSettings02,
                        size: 14,
                      ),
                      label: Text(
                        usage.hasQuota ? 'Editar' : 'Establecer cantidad',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => _Card(
            child: Text(
              'No se pudo cargar el uso de facturas electrónicas: $e',
              style: const TextStyle(color: AppColors.destructive),
            ),
          ),
          data: (u) => _UsageCard(usage: u),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    EcfQuotaUsage usage,
  ) async {
    final input = await showDialog<EcfQuotaInput>(
      context: context,
      builder: (_) => EcfQuotaDialog(businessName: businessName, usage: usage),
    );
    if (input == null || !context.mounted) return;
    await _run(
      context,
      ref,
      (repo) => repo.set(
        businessId: businessId,
        included: input.included,
        priceOverrideCents: input.priceOverrideCents,
        notes: input.notes,
      ),
      success: 'Cantidad de facturas electrónicas guardada.',
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar cantidad'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Las facturas electrónicas de $businessName dejarán de cobrarse '
            'aparte. Lo ya cobrado no cambia. Si vuelves a establecer una '
            'cantidad, se cuenta desde ese momento.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(
      context,
      ref,
      (repo) => repo.clear(businessId),
      success: 'Listo: las facturas electrónicas ya no se cobran aparte.',
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<EcfQuotaUsage> Function(EcfQuotaRepository repo) action, {
    required String success,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(ecfQuotaRepositoryProvider));
      ref.invalidate(ecfQuotaUsageProvider(businessId));
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      final message = e is PostgrestException ? e.message : '$e';
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $message')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de uso
// ---------------------------------------------------------------------------

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.usage});

  final EcfQuotaUsage usage;

  static const _muted = TextStyle(
    fontSize: 12,
    color: AppColors.mutedForeground,
  );

  @override
  Widget build(BuildContext context) {
    final u = usage;
    if (!u.hasQuota) {
      return _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sin cantidad configurada: las facturas electrónicas no se '
              'cobran aparte.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Aceptadas por la DGII en los últimos 30 días: '
              '${formatInt(u.last30Days)}',
              style: _muted,
            ),
          ],
        ),
      );
    }

    final included = u.included ?? 0;
    final current = u.current;
    final over = current.used > included;
    final progress = included == 0
        ? (current.used > 0 ? 1.0 : 0.0)
        : (current.used / included).clamp(0.0, 1.0);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('Incluidas por período', formatInt(included)),
          _row(
            'Precio por factura extra',
            u.unitPriceCents == 0
                ? 'RD\$ 0.00 — define el precio global en Configuración'
                : '${formatRd(u.unitPriceCents / 100)} '
                      '(${u.priceIsCustom ? 'precio propio' : 'precio global'})',
            warning: u.unitPriceCents == 0,
          ),
          _row(
            'Aceptadas en el período',
            '${formatInt(current.used)} de ${formatInt(included)}'
                '${current.usageFrom == null ? '' : ' · desde ${_fmtDate(current.usageFrom)}'}',
            warning: over,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.muted,
                color: over ? AppColors.destructive : AppColors.primary,
              ),
            ),
          ),
          _row(
            'Extra hasta hoy',
            current.extra == 0
                ? 'Ninguna'
                : '${formatInt(current.extra)} × ${formatRd(u.unitPriceCents / 100)} '
                      '= ${formatRd(current.overageCents / 100)}',
            warning: current.extra > 0,
          ),
          if (current.extra > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                u.nextChargeDate == null
                    ? 'Se suma a la próxima mensualidad.'
                    : 'Se suma al próximo cobro (${_fmtDate(u.nextChargeDate)}).',
                style: _muted,
              ),
            ),
          if (u.notes != null && u.notes!.isNotEmpty) _row('Notas', u.notes!),
          if (u.history.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'PERÍODOS COBRADOS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 6),
            for (final h in u.history)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${_fmtDate(h.usageFrom)} → ${_fmtDate(h.usageTo)} · '
                  '${formatInt(h.used)} aceptadas · '
                  '${h.extra == 0 ? 'sin extra' : '${formatInt(h.extra)} extra (${formatRd(h.overageCents / 100)})'}'
                  '${h.source == 'invoice' ? ' · factura' : ' · tarjeta'}',
                  style: _muted,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool warning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 190, child: Text(label, style: _muted)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: warning ? AppColors.destructive : AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogo
// ---------------------------------------------------------------------------

/// Lo que devuelve [EcfQuotaDialog].
class EcfQuotaInput {
  const EcfQuotaInput({
    required this.included,
    this.priceOverrideCents,
    this.notes,
  });

  final int included;

  /// `null` = usar el precio global.
  final int? priceOverrideCents;
  final String? notes;
}

class EcfQuotaDialog extends StatefulWidget {
  const EcfQuotaDialog({
    required this.businessName,
    required this.usage,
    super.key,
  });

  final String businessName;
  final EcfQuotaUsage usage;

  @override
  State<EcfQuotaDialog> createState() => _EcfQuotaDialogState();
}

class _EcfQuotaDialogState extends State<EcfQuotaDialog> {
  late final _included = TextEditingController(
    text: widget.usage.included?.toString() ?? '',
  );
  late final _price = TextEditingController(
    text: widget.usage.priceOverrideCents == null
        ? ''
        : (widget.usage.priceOverrideCents! / 100).toStringAsFixed(2),
  );
  late final _notes = TextEditingController(text: widget.usage.notes ?? '');
  late bool _useGlobal = widget.usage.priceOverrideCents == null;

  static final _amountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

  @override
  void dispose() {
    _included.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  int? get _includedValue => int.tryParse(_included.text.trim());

  int? get _priceCents {
    final raw = _price.text.trim().replaceAll(',', '');
    if (!_amountPattern.hasMatch(raw)) return null;
    return (double.parse(raw) * 100).round();
  }

  bool get _canSave =>
      _includedValue != null && (_useGlobal || _priceCents != null);

  @override
  Widget build(BuildContext context) {
    final global = widget.usage.globalPriceCents;
    return AlertDialog(
      title: Text('Facturas electrónicas — ${widget.businessName}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Las facturas electrónicas que la DGII acepte por encima de '
                'esta cantidad en cada período se cobran y se suman a la '
                'mensualidad.'
                '${widget.usage.hasQuota ? '' : ' Se empiezan a contar desde que guardes.'}',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _included,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Incluidas por período',
                  hintText: 'Ej: 500',
                  suffixText: 'e-CF',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _useGlobal,
                title: const Text('Usar el precio global'),
                subtitle: Text(
                  global > 0
                      ? '${formatRd(global / 100)} por factura extra'
                      : 'Todavía no hay precio global: defínelo en Configuración',
                ),
                onChanged: (v) => setState(() => _useGlobal = v),
              ),
              if (!_useGlobal)
                TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Precio por factura extra',
                    prefixText: 'RD\$ ',
                    helperText: 'Solo para este negocio',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  hintText: 'Ej: acordado con el cliente el 17/09',
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
          onPressed: _canSave
              ? () => Navigator.of(context).pop(
                  EcfQuotaInput(
                    included: _includedValue!,
                    priceOverrideCents: _useGlobal ? null : _priceCents,
                    notes: _notes.text.trim().isEmpty
                        ? null
                        : _notes.text.trim(),
                  ),
                )
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy').format(d.toLocal());
