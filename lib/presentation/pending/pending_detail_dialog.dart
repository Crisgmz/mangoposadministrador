import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../domain/models/pending_business.dart';

/// Acción seleccionada en el dialog de detalle.
enum PendingDetailAction { approve, reject, openBusiness }

class PendingDetailResult {
  const PendingDetailResult({required this.action, this.reason});
  final PendingDetailAction action;
  final String? reason;
}

/// Dialog con todos los datos del negocio pendiente + botones de acción.
class PendingDetailDialog extends StatefulWidget {
  const PendingDetailDialog({super.key, required this.item});

  final PendingBusiness item;

  @override
  State<PendingDetailDialog> createState() => _PendingDetailDialogState();
}

class _PendingDetailDialogState extends State<PendingDetailDialog> {
  final _rejectReason = TextEditingController();
  bool _rejectMode = false;

  @override
  void dispose() {
    _rejectReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              HugeIcons.strokeRoundedClock04,
              size: 16,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.businessName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Cuenta pendiente · registrada ${formatRelative(item.createdAt)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, minWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Block(
                title: 'Owner',
                children: [
                  if (item.ownerFullName != null &&
                      item.ownerFullName!.isNotEmpty)
                    _Kv(label: 'Nombre', value: item.ownerFullName!),
                  if (item.ownerEmail != null)
                    _Kv(
                      label: 'Email',
                      value: item.ownerEmail!,
                      selectable: true,
                      badge: item.emailVerified ? null : 'No verificado',
                    ),
                  if (item.phone != null && item.phone!.isNotEmpty)
                    _Kv(
                      label: 'Teléfono',
                      value: item.phone!,
                      selectable: true,
                    ),
                  if (item.lastSignInAt != null)
                    _Kv(
                      label: 'Último login',
                      value: formatRelative(item.lastSignInAt),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _Block(
                title: 'Negocio',
                children: [
                  if (item.branchName != null && item.branchName!.isNotEmpty)
                    _Kv(label: 'Sucursal', value: item.branchName!),
                  if (item.businessType != null &&
                      item.businessType!.isNotEmpty)
                    _Kv(label: 'Tipo', value: item.businessType!),
                  if (item.country != null && item.country!.isNotEmpty)
                    _Kv(label: 'País', value: item.country!),
                  if (item.address != null && item.address!.isNotEmpty)
                    _Kv(label: 'Dirección', value: item.address!),
                  if (item.domain != null && item.domain!.isNotEmpty)
                    _Kv(
                      label: 'Subdominio',
                      value: item.domain!,
                      selectable: true,
                    ),
                  _Kv(
                    label: 'ID',
                    value: item.businessId,
                    selectable: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Block(
                title: 'Plan & billing',
                children: [
                  _Kv(
                    label: 'Plan',
                    value: item.planName ??
                        item.planCode?.toUpperCase() ??
                        '—',
                  ),
                  if (item.planMonthlyPrice != null)
                    _Kv(
                      label: 'Precio mensual',
                      value: formatRd(item.planMonthlyPrice!),
                    ),
                  if (item.membershipBillingStatus != null)
                    _Kv(
                      label: 'Estado billing',
                      value: item.membershipBillingStatus!,
                    ),
                  if (item.trialEndsAt != null)
                    _Kv(
                      label: 'Trial vence',
                      value: formatRelative(item.trialEndsAt),
                      badge: (item.trialDaysLeft ?? 0) < 0 ? 'Vencido' : null,
                    ),
                  _Kv(
                    label: 'Método de pago',
                    value: item.hasVerifiedCard
                        ? 'Tarjeta verificada'
                        : 'Sin tarjeta verificada',
                    badge: item.hasVerifiedCard ? null : 'Sin tarjeta',
                  ),
                ],
              ),
              if (_rejectMode) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.destructive.withValues(alpha: 0.06),
                    border: Border.all(
                      color: AppColors.destructive.withValues(alpha: 0.25),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Razón del rechazo (mínimo 10 caracteres)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.destructive,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _rejectReason,
                        autofocus: true,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(
                          hintText:
                              'Ej: datos del negocio inválidos, cuenta duplicada, etc.',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: _buildActions(context),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_rejectMode) {
      final canConfirm = _rejectReason.text.trim().length >= 10;
      return [
        TextButton(
          onPressed: () => setState(() {
            _rejectMode = false;
            _rejectReason.clear();
          }),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(
                    PendingDetailResult(
                      action: PendingDetailAction.reject,
                      reason: _rejectReason.text.trim(),
                    ),
                  )
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.destructive,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirmar rechazo'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(
          const PendingDetailResult(action: PendingDetailAction.openBusiness),
        ),
        child: const Text('Ver detalle completo'),
      ),
      const Spacer(),
      OutlinedButton.icon(
        onPressed: () => setState(() => _rejectMode = true),
        icon: const Icon(HugeIcons.strokeRoundedDelete02, size: 14),
        label: const Text('Rechazar'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.destructive,
          side: const BorderSide(color: AppColors.destructive),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(
          const PendingDetailResult(action: PendingDetailAction.approve),
        ),
        icon: const Icon(HugeIcons.strokeRoundedCheckmarkCircle02, size: 14),
        label: const Text('Aprobar cuenta'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
        ),
      ),
    ];
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({
    required this.label,
    required this.value,
    this.selectable = false,
    this.badge,
  });
  final String label;
  final String value;
  final bool selectable;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: selectable
                ? SelectableText(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  )
                : Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
