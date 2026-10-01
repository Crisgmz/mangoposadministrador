import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/business_access_repository.dart';
import '../../domain/models/business_access.dart';

/// Sección "Acceso al sistema" del detalle de negocio.
///
/// Es el control de cobranza: muestra si el POS de ese negocio está operando,
/// avisando o bloqueado, por qué, y da los cuatro botones del operador —
/// bloquear ya, desbloquear, programar el corte y dar prórroga — más el
/// mensaje que ve el dueño en la pantalla de bloqueo.
///
/// El estado lo calcula la BD (`fn_business_access_state`), así que lo que se
/// ve acá es exactamente lo que ve el POS.
class BusinessAccessSection extends ConsumerWidget {
  const BusinessAccessSection({
    required this.businessId,
    required this.businessName,
    super.key,
  });

  final String businessId;
  final String businessName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(businessAccessProvider(businessId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              HugeIcons.strokeRoundedSquareLock02,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Acceso al sistema',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refrescar',
              onPressed: () => ref.invalidate(businessAccessProvider(businessId)),
              icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        accessAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => _Note(
            color: AppColors.destructive,
            text: 'No se pudo leer el estado de acceso: $e',
          ),
          data: (access) {
            if (access == null) {
              return const _Note(
                color: AppColors.warning,
                text: 'Este negocio no tiene estado de acceso. Verifica que la '
                    'migración 20260825_0001 esté aplicada.',
              );
            }
            return _AccessCard(
              access: access,
              businessName: businessName,
              businessId: businessId,
            );
          },
        ),
      ],
    );
  }
}

class _AccessCard extends ConsumerWidget {
  const _AccessCard({
    required this.access,
    required this.businessName,
    required this.businessId,
  });

  final BusinessAccess access;
  final String businessName;
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('d MMM yyyy, HH:mm', 'es');
    final color = _stateColor(access.state);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Estado -------------------------------------------------------
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  access.stateLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  access.reasonLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),

          if (access.notEnforcedNote != null) ...[
            const SizedBox(height: 12),
            _Note(color: AppColors.mutedForeground, text: access.notEnforcedNote!),
          ],

          const SizedBox(height: 14),

          // ---- Detalle ------------------------------------------------------
          _Line('Suscripción', access.billingStatus ?? '—'),
          _Line('Cuenta', access.businessStatus ?? '—'),
          if (access.planName != null) _Line('Plan', access.planName!),
          _Line('Gracia', '${access.graceDays} días'),
          if (access.lockedAt != null)
            _Line('Bloqueado desde', df.format(access.lockedAt!)),
          if (access.graceEndsAt != null)
            _Line('Vence', df.format(access.graceEndsAt!)),
          if (access.scheduledLockAt != null)
            _Line('Corte programado', df.format(access.scheduledLockAt!)),
          if (access.overrideUntil != null)
            _Line('Prórroga hasta', df.format(access.overrideUntil!)),
          if (access.lockReason != null && access.lockReason!.isNotEmpty)
            _Line('Motivo interno', access.lockReason!),

          // ---- Mensaje al cliente -------------------------------------------
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mensaje que ve el dueño',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openMessageDialog(context, ref),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Editar'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  (access.customerMessage?.trim().isNotEmpty ?? false)
                      ? access.customerMessage!
                      : 'Sin mensaje propio — el POS muestra el texto por '
                          'defecto según el motivo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    fontStyle: (access.customerMessage?.trim().isNotEmpty ?? false)
                        ? FontStyle.normal
                        : FontStyle.italic,
                    color: AppColors.foreground,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ---- Acciones -----------------------------------------------------
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (access.isManuallyLocked)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  onPressed: () => _run(
                    context,
                    ref,
                    title: 'Desbloquear $businessName',
                    description:
                        'El negocio vuelve a modo automático. Si su suscripción '
                        'sigue suspendida o vencida, el POS se bloqueará solo de '
                        'nuevo — para darle acceso mientras paga, usa Prórroga.',
                    confirmLabel: 'Desbloquear',
                    action: (repo, reason) =>
                        repo.unlock(businessId: businessId, reason: reason),
                  ),
                  icon: const Icon(HugeIcons.strokeRoundedSquareUnlock02, size: 14),
                  label: const Text('Desbloquear'),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.destructive,
                  ),
                  onPressed: () => _openLockDialog(context, ref),
                  icon: const Icon(HugeIcons.strokeRoundedSquareLock02, size: 14),
                  label: const Text('Bloquear ahora'),
                ),

              OutlinedButton.icon(
                onPressed: () => _openDateDialog(
                  context,
                  ref,
                  mode: _DateMode.schedule,
                ),
                icon: const Icon(HugeIcons.strokeRoundedCalendar03, size: 14),
                label: Text(
                  access.hasSchedule ? 'Cambiar corte' : 'Programar corte',
                ),
              ),

              OutlinedButton.icon(
                onPressed: () => _openDateDialog(
                  context,
                  ref,
                  mode: _DateMode.extend,
                ),
                icon: const Icon(HugeIcons.strokeRoundedTime04, size: 14),
                label: Text(
                  access.hasExtension ? 'Cambiar prórroga' : 'Dar prórroga',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Diálogos
  // ---------------------------------------------------------------------------

  Future<void> _openLockDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_LockInput>(
      context: context,
      builder: (_) => _LockDialog(businessName: businessName),
    );
    if (result == null || !context.mounted) return;
    await _execute(
      context,
      ref,
      (repo) => repo.lock(
        businessId: businessId,
        reason: result.reason,
        customerMessage: result.message,
        contactName: result.contactName,
        contactPhone: result.contactPhone,
      ),
      successText: '$businessName quedó bloqueado.',
    );
  }

  Future<void> _openMessageDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_LockInput>(
      context: context,
      builder: (_) => _LockDialog(
        businessName: businessName,
        messageOnly: true,
        initialMessage: access.customerMessage,
        initialContactName: access.contactName,
        initialContactPhone: access.contactPhone,
      ),
    );
    if (result == null || !context.mounted) return;
    await _execute(
      context,
      ref,
      (repo) => repo.update(
        businessId: businessId,
        reason: result.reason,
        customerMessage: result.message,
        clearMessage: result.message == null || result.message!.trim().isEmpty,
        contactName: result.contactName,
        contactPhone: result.contactPhone,
      ),
      successText: 'Mensaje actualizado.',
    );
  }

  Future<void> _openDateDialog(
    BuildContext context,
    WidgetRef ref, {
    required _DateMode mode,
  }) async {
    final result = await showDialog<_DateInput>(
      context: context,
      builder: (_) => _DateDialog(
        mode: mode,
        businessName: businessName,
        initial: mode == _DateMode.schedule
            ? access.scheduledLockAt
            : access.overrideUntil,
      ),
    );
    if (result == null || !context.mounted) return;
    await _execute(
      context,
      ref,
      (repo) => mode == _DateMode.schedule
          ? repo.schedule(
              businessId: businessId,
              reason: result.reason,
              lockAt: result.date,
              customerMessage: result.message,
            )
          : repo.extend(
              businessId: businessId,
              reason: result.reason,
              until: result.date,
              customerMessage: result.message,
            ),
      successText: mode == _DateMode.schedule
          ? 'Corte programado.'
          : 'Prórroga concedida.',
    );
  }

  /// Confirmación simple con razón obligatoria + ejecución.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String description,
    required String confirmLabel,
    required Future<BusinessAccess?> Function(
      BusinessAccessRepository repo,
      String reason,
    ) action,
  }) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonOnlyDialog(
        title: title,
        description: description,
        confirmLabel: confirmLabel,
      ),
    );
    if (reason == null || !context.mounted) return;
    await _execute(
      context,
      ref,
      (repo) => action(repo, reason),
      successText: '$confirmLabel aplicado.',
    );
  }

  Future<void> _execute(
    BuildContext context,
    WidgetRef ref,
    Future<BusinessAccess?> Function(BusinessAccessRepository repo) action, {
    required String successText,
  }) async {
    try {
      await action(ref.read(businessAccessRepositoryProvider));
      ref.invalidate(businessAccessProvider(businessId));
      ref.invalidate(affectedBusinessesProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successText)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  static Color _stateColor(String state) {
    switch (state) {
      case 'locked':
        return AppColors.destructive;
      case 'grace':
        return AppColors.destructive;
      case 'warning':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }
}

// ---------------------------------------------------------------------------
// Diálogo de bloqueo / mensaje
// ---------------------------------------------------------------------------

class _LockInput {
  const _LockInput({
    required this.reason,
    this.message,
    this.contactName,
    this.contactPhone,
  });

  final String reason;
  final String? message;
  final String? contactName;
  final String? contactPhone;
}

class _LockDialog extends StatefulWidget {
  const _LockDialog({
    required this.businessName,
    this.messageOnly = false,
    this.initialMessage,
    this.initialContactName,
    this.initialContactPhone,
  });

  final String businessName;
  final bool messageOnly;
  final String? initialMessage;
  final String? initialContactName;
  final String? initialContactPhone;

  @override
  State<_LockDialog> createState() => _LockDialogState();
}

class _LockDialogState extends State<_LockDialog> {
  late final TextEditingController _reason = TextEditingController();
  late final TextEditingController _message =
      TextEditingController(text: widget.initialMessage ?? '');
  late final TextEditingController _contactName =
      TextEditingController(text: widget.initialContactName ?? '');
  late final TextEditingController _contactPhone =
      TextEditingController(text: widget.initialContactPhone ?? '');

  @override
  void dispose() {
    _reason.dispose();
    _message.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lock = !widget.messageOnly;
    return AlertDialog(
      title: Text(
        lock ? 'Bloquear ${widget.businessName}' : 'Mensaje al cliente',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lock)
                const _Note(
                  color: AppColors.destructive,
                  text: 'El POS queda inutilizable de inmediato: el cajero solo '
                      'verá la pantalla de bloqueo. Las cuentas abiertas NO se '
                      'pierden, pero no se podrán cobrar hasta desbloquear.',
                ),
              if (lock) const SizedBox(height: 14),
              TextField(
                controller: _reason,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Razón (interna, obligatoria)',
                  hintText: 'Ej. 3 meses sin pagar, acuerdo vencido',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mensaje que ve el dueño (opcional)',
                  hintText: 'Ej. Tu cuenta tiene 2 mensualidades pendientes. '
                      'Llama al 809-000-0000 para regularizar.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _contactName,
                      decoration: const InputDecoration(
                        labelText: 'Contacto (nombre)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _contactPhone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: lock
              ? FilledButton.styleFrom(backgroundColor: AppColors.destructive)
              : null,
          onPressed: () {
            final r = _reason.text.trim();
            if (r.isEmpty) return;
            Navigator.pop(
              context,
              _LockInput(
                reason: r,
                message: _message.text.trim(),
                contactName: _nullIfEmpty(_contactName.text),
                contactPhone: _nullIfEmpty(_contactPhone.text),
              ),
            );
          },
          child: Text(lock ? 'Bloquear' : 'Guardar'),
        ),
      ],
    );
  }

  static String? _nullIfEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }
}

// ---------------------------------------------------------------------------
// Diálogo de fecha (corte programado / prórroga)
// ---------------------------------------------------------------------------

enum _DateMode { schedule, extend }

class _DateInput {
  const _DateInput({required this.reason, required this.date, this.message});

  final String reason;
  final DateTime date;
  final String? message;
}

class _DateDialog extends StatefulWidget {
  const _DateDialog({
    required this.mode,
    required this.businessName,
    this.initial,
  });

  final _DateMode mode;
  final String businessName;
  final DateTime? initial;

  @override
  State<_DateDialog> createState() => _DateDialogState();
}

class _DateDialogState extends State<_DateDialog> {
  late DateTime _date =
      widget.initial ?? DateTime.now().add(const Duration(days: 7));
  final _reason = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _isSchedule => widget.mode == _DateMode.schedule;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'es');
    return AlertDialog(
      title: Text(_isSchedule ? 'Programar corte' : 'Dar prórroga'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Note(
              color: _isSchedule ? AppColors.warning : AppColors.primary,
              text: _isSchedule
                  ? 'El POS mostrará una cuenta regresiva hasta esa fecha y se '
                      'bloqueará solo al llegar.'
                  : 'El negocio tendrá acceso garantizado hasta esa fecha, '
                      'aunque su suscripción esté suspendida o vencida. Al '
                      'vencer, el estado vuelve a calcularse solo.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isSchedule
                        ? 'Se bloquea el ${df.format(_date)}'
                        : 'Acceso hasta el ${df.format(_date)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pick,
                  icon: const Icon(HugeIcons.strokeRoundedCalendar03, size: 15),
                  label: const Text('Cambiar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [3, 7, 15, 30]
                  .map(
                    (d) => ActionChip(
                      label: Text('+$d días'),
                      onPressed: () => setState(
                        () => _date = DateTime.now().add(Duration(days: d)),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Razón (interna, obligatoria)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Mensaje que ve el dueño (opcional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final r = _reason.text.trim();
            if (r.isEmpty) return;
            Navigator.pop(
              context,
              _DateInput(
                reason: r,
                date: _date,
                message: _message.text.trim().isEmpty
                    ? null
                    : _message.text.trim(),
              ),
            );
          },
          child: Text(_isSchedule ? 'Programar' : 'Conceder'),
        ),
      ],
    );
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      // Fin del día: un corte "el día 5" debe ejecutarse al terminar el 5.
      setState(
        () => _date = DateTime(picked.year, picked.month, picked.day, 23, 59),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Diálogo de razón simple
// ---------------------------------------------------------------------------

class _ReasonOnlyDialog extends StatefulWidget {
  const _ReasonOnlyDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
  });

  final String title;
  final String description;
  final String confirmLabel;

  @override
  State<_ReasonOnlyDialog> createState() => _ReasonOnlyDialogState();
}

class _ReasonOnlyDialogState extends State<_ReasonOnlyDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Razón (interna, obligatoria)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final r = _reason.text.trim();
            if (r.isEmpty) return;
            Navigator.pop(context, r);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas chicas
// ---------------------------------------------------------------------------

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, height: 1.42, color: color),
      ),
    );
  }
}
