import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/business_access_repository.dart';
import '../../domain/models/business_access.dart';

/// Tarjeta "Bloqueo por falta de pago" de Configuración.
///
/// El motor de acceso calcula el estado de cada negocio (ok / aviso / gracia /
/// bloqueado) y APARTE decide si se aplica, con este interruptor global. Nació
/// apagado para pilotear el cobro, y mientras siga así los bloqueos
/// automáticos —suspensión por cobros fallidos, pago vencido, trial vencido—
/// no bloquean nada: el POS recibe el estado pero lo ignora.
///
/// Hasta ahora no había forma de verlo ni de encenderlo desde la consola.
class AccessPolicyCard extends ConsumerStatefulWidget {
  const AccessPolicyCard({super.key});

  @override
  ConsumerState<AccessPolicyCard> createState() => _AccessPolicyCardState();
}

class _AccessPolicyCardState extends ConsumerState<AccessPolicyCard> {
  // Borrador: se arma con lo que hay guardado y se manda todo junto al guardar.
  bool? _enforcement;
  bool? _pastDue;
  bool? _trial;
  final _grace = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _grace.dispose();
    super.dispose();
  }

  void _seed(AccessPolicy p) {
    _enforcement = p.enforcementEnabled;
    _pastDue = p.lockOnPastDue;
    _trial = p.lockOnTrialExpired;
    _grace.text = p.defaultGraceDays.toString();
  }

  int? get _graceValue => int.tryParse(_grace.text.trim());

  bool _dirty(AccessPolicy p) =>
      _enforcement != p.enforcementEnabled ||
      _pastDue != p.lockOnPastDue ||
      _trial != p.lockOnTrialExpired ||
      (_graceValue != null && _graceValue != p.defaultGraceDays);

  Future<void> _save(AccessPolicy saved) async {
    final turningOn = _enforcement == true && !saved.enforcementEnabled;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: turningOn
            ? 'Encender el bloqueo automático'
            : 'Guardar política de bloqueo',
        description: turningOn
            ? 'Desde que lo enciendas, los negocios con la suscripción '
                  'suspendida o el pago vencido (pasada la gracia) van a '
                  'quedar bloqueados: el POS lo aplica apenas inician sesión.'
            : 'El cambio queda registrado en auditoría.',
        initialReason: turningOn
            ? 'Activación del bloqueo automático'
            : 'Ajuste de política de bloqueo',
        confirmLabel: turningOn ? 'Encender' : 'Guardar',
        danger: turningOn,
      ),
    );
    if (reason == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(businessAccessRepositoryProvider)
          .setPolicy(
            reason: reason,
            enforcementEnabled: _enforcement,
            lockOnPastDue: _pastDue,
            lockOnTrialExpired: _trial,
            defaultGraceDays: _graceValue,
          );
      ref.invalidate(accessPolicyProvider);
      ref.invalidate(affectedBusinessesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _enforcement == true
                ? 'Bloqueo automático activo: se aplica al iniciar sesión.'
                : 'Política guardada.',
          ),
        ),
      );
    } catch (e) {
      final message = e is PostgrestException ? e.message : '$e';
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $message')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policyAsync = ref.watch(accessPolicyProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      // Material transparente DENTRO de la tarjeta: los SwitchListTile pintan
      // su efecto sobre el Material más cercano, y el fondo decorado de arriba
      // lo taparía (Flutter lo avisa con un assert).
      child: Material(
        color: Colors.transparent,
        child: policyAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Text(
            'No se pudo cargar la política de bloqueo: $e',
            style: const TextStyle(color: AppColors.destructive),
          ),
          data: (policy) {
            if (policy == null) {
              return const Text(
                'No hay política de bloqueo configurada en la base.',
                style: TextStyle(color: AppColors.mutedForeground),
              );
            }
            if (_enforcement == null) _seed(policy);
            final on = _enforcement ?? policy.enforcementEnabled;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Bloqueo por falta de pago',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                    _Pill(
                      label: policy.enforcementEnabled ? 'ACTIVO' : 'APAGADO',
                      color: policy.enforcementEnabled
                          ? AppColors.success
                          : AppColors.mutedForeground,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Con esto encendido, el POS bloquea solo a quien tenga la '
                  'suscripción suspendida o el pago vencido, y lo aplica apenas '
                  'el usuario inicia sesión. Apagado, el sistema calcula el '
                  'estado pero no bloquea a nadie; solo valen los bloqueos '
                  'manuales de cada negocio.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  title: const Text('Aplicar bloqueos automáticamente'),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _enforcement = v),
                ),
                const Divider(height: 24, color: AppColors.border),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _pastDue ?? policy.lockOnPastDue,
                  title: const Text('Bloquear por pago vencido'),
                  subtitle: const Text(
                    'Después de los días de gracia desde la fecha de cobro.',
                  ),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _pastDue = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _trial ?? policy.lockOnTrialExpired,
                  title: const Text('Bloquear al vencer el período de prueba'),
                  onChanged: _saving ? null : (v) => setState(() => _trial = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _grace,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Días de gracia',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Se cuentan desde la fecha de cobro. Antes de que se '
                        'cumplan, el POS muestra avisos; después, bloquea.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _AffectedPreview(enforcementOn: policy.enforcementEnabled),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _saving || !_dirty(policy)
                        ? null
                        : () => _save(policy),
                    child: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A quién afecta
// ---------------------------------------------------------------------------

class _AffectedPreview extends ConsumerWidget {
  const _AffectedPreview({required this.enforcementOn});

  final bool enforcementOn;

  static const _max = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(affectedBusinessesProvider);
    return async.when(
      loading: () => const SizedBox(
        height: 2,
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (e, _) => Text(
        'No se pudo cargar a quiénes afecta: $e',
        style: const TextStyle(fontSize: 12, color: AppColors.destructive),
      ),
      data: (rows) {
        final locked = rows.where((r) => r.state == 'locked').toList();
        final grace = rows.where((r) => r.state == 'grace').length;
        final warning = rows.where((r) => r.state == 'warning').length;

        if (rows.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Hoy ningún negocio quedaría bloqueado: están todos al día.',
              style: TextStyle(fontSize: 12, color: AppColors.foreground),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (enforcementOn ? AppColors.primary : AppColors.warning)
                .withValues(alpha: 0.07),
            border: Border.all(
              color: (enforcementOn ? AppColors.primary : AppColors.warning)
                  .withValues(alpha: 0.25),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                enforcementOn
                    ? 'Bloqueados ahora: ${locked.length}'
                    : 'Si lo enciendes, hoy quedarían bloqueados: ${locked.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
              Text(
                'En gracia: $grace · Con aviso: $warning',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 8),
              for (final r in locked.take(_max))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${r.businessName} · ${_reasonLabel(r.reason)}'
                    '${r.billingStatus == null ? '' : ' · ${r.billingStatus}'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
              if (locked.length > _max)
                Text(
                  'y ${locked.length - _max} más',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
              if (grace > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Los que están en gracia se bloquean solos al vencerse '
                    '(el más próximo: ${_nextGrace(rows)}).',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _nextGrace(List<AffectedBusiness> rows) {
    final dates =
        rows
            .where((r) => r.state == 'grace' && r.graceEndsAt != null)
            .map((r) => r.graceEndsAt!)
            .toList()
          ..sort();
    if (dates.isEmpty) return '—';
    return DateFormat('dd/MM/yyyy').format(dates.first.toLocal());
  }
}

String _reasonLabel(String reason) => switch (reason) {
  'manual_lock' => 'bloqueo manual',
  'account_inactive' => 'cuenta desactivada',
  'subscription_suspended' => 'suscripción suspendida',
  'subscription_cancelled' => 'suscripción cancelada',
  'scheduled_cutoff' => 'corte programado',
  'payment_overdue' => 'pago vencido',
  'trial_expired' => 'prueba vencida',
  _ => reason,
};

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.description,
    required this.initialReason,
    required this.confirmLabel,
    this.danger = false,
  });

  final String title;
  final String description;
  final String initialReason;
  final String confirmLabel;
  final bool danger;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final _reason = TextEditingController(text: widget.initialReason);

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final can = _reason.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.description,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Razón (queda en auditoría)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: widget.danger
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.destructive,
                  foregroundColor: AppColors.destructiveForeground,
                )
              : null,
          onPressed: can
              ? () => Navigator.of(context).pop(_reason.text.trim())
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}
