import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/business_overview.dart';

/// Resultado del wizard. Lo consume `BusinessesPage._onCreate` y se envía
/// directo al RPC `admin_create_business` vía `DashboardRepository`.
class NewBusinessResult {
  const NewBusinessResult({
    required this.ownerEmail,
    required this.businessName,
    required this.businessType,
    required this.domain,
    required this.environment,
    required this.planType,
    required this.trialDays,
  });

  final String ownerEmail;
  final String businessName;
  final String? businessType;
  final String? domain;
  final String environment; // 'production' | 'sandbox'
  final String planType;    // 'trial' | 'free' | 'basic' | 'pro'
  final int trialDays;
}

/// Wizard de 3 pasos para crear un negocio manualmente.
/// Paso 1: email del owner (debe existir en `auth.users`).
/// Paso 2: datos del negocio.
/// Paso 3: plan + días de trial.
class NewBusinessDialog extends StatefulWidget {
  const NewBusinessDialog({super.key});

  @override
  State<NewBusinessDialog> createState() => _NewBusinessDialogState();
}

class _NewBusinessDialogState extends State<NewBusinessDialog> {
  int _step = 0;

  final _ownerEmail = TextEditingController();
  final _businessName = TextEditingController();
  final _businessType = TextEditingController();
  final _domain = TextEditingController();
  BusinessEnvironment _env = BusinessEnvironment.sandbox;
  PlanType _plan = PlanType.trial;
  int _trialDays = 30;

  @override
  void dispose() {
    _ownerEmail.dispose();
    _businessName.dispose();
    _businessType.dispose();
    _domain.dispose();
    super.dispose();
  }

  bool get _step1Valid {
    final v = _ownerEmail.text.trim();
    return v.contains('@') && v.contains('.');
  }

  bool get _step2Valid => _businessName.text.trim().isNotEmpty;

  bool get _canSubmit => _step1Valid && _step2Valid;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            HugeIcons.strokeRoundedAdd01,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Text('Nuevo negocio'),
          const Spacer(),
          _StepIndicator(current: _step, total: 3),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 380),
        child: SingleChildScrollView(
          child: switch (_step) {
            0 => _StepOwner(
                controller: _ownerEmail,
                onChanged: () => setState(() {}),
              ),
            1 => _StepBusiness(
                nameCtrl: _businessName,
                typeCtrl: _businessType,
                domainCtrl: _domain,
                env: _env,
                onEnvChanged: (e) => setState(() => _env = e),
                onChanged: () => setState(() {}),
              ),
            _ => _StepPlan(
                plan: _plan,
                onPlanChanged: (p) => setState(() => _plan = p),
                trialDays: _trialDays,
                onTrialDaysChanged: (d) => setState(() => _trialDays = d),
                summary: _Summary(
                  ownerEmail: _ownerEmail.text.trim(),
                  businessName: _businessName.text.trim(),
                  businessType: _businessType.text.trim(),
                  domain: _domain.text.trim(),
                  env: _env,
                ),
              ),
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (_step > 0)
          TextButton(
            onPressed: () => setState(() => _step -= 1),
            child: const Text('Atrás'),
          ),
        FilledButton(
          onPressed: _nextEnabled() ? _onNext : null,
          child: Text(_step == 2 ? 'Crear negocio' : 'Continuar'),
        ),
      ],
    );
  }

  bool _nextEnabled() {
    switch (_step) {
      case 0:
        return _step1Valid;
      case 1:
        return _step2Valid;
      default:
        return _canSubmit;
    }
  }

  void _onNext() {
    if (_step < 2) {
      setState(() => _step += 1);
      return;
    }
    Navigator.of(context).pop(
      NewBusinessResult(
        ownerEmail: _ownerEmail.text.trim(),
        businessName: _businessName.text.trim(),
        businessType: _nullIfEmpty(_businessType.text),
        domain: _nullIfEmpty(_domain.text),
        environment: _env.raw,
        planType: _plan.raw,
        trialDays: _trialDays,
      ),
    );
  }
}

String? _nullIfEmpty(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------

class _StepOwner extends StatelessWidget {
  const _StepOwner({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepTitle('Owner del negocio'),
        const SizedBox(height: 6),
        const Text(
          'El usuario debe existir en MangoPOS (registro público). '
          'Si no se ha registrado, pídele que lo haga en mangopos.do/signup y vuelve aquí.',
          style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
        ),
        const SizedBox(height: 14),
        const _Label('Email del owner'),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'cliente@dominio.com',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class _StepBusiness extends StatelessWidget {
  const _StepBusiness({
    required this.nameCtrl,
    required this.typeCtrl,
    required this.domainCtrl,
    required this.env,
    required this.onEnvChanged,
    required this.onChanged,
  });

  final TextEditingController nameCtrl;
  final TextEditingController typeCtrl;
  final TextEditingController domainCtrl;
  final BusinessEnvironment env;
  final ValueChanged<BusinessEnvironment> onEnvChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepTitle('Datos del negocio'),
        const SizedBox(height: 14),
        const _Label('Nombre del negocio'),
        const SizedBox(height: 6),
        TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej: La Cocina Mexicana',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 14),
        const _Label('Tipo (opcional)'),
        const SizedBox(height: 6),
        TextField(
          controller: typeCtrl,
          decoration: const InputDecoration(
            hintText: 'Restaurante, Cafetería, Tienda…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        const _Label('Dominio / subdominio (opcional)'),
        const SizedBox(height: 6),
        TextField(
          controller: domainCtrl,
          decoration: const InputDecoration(
            hintText: 'cocina-mexicana',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        const _Label('Entorno'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _Pill(
              label: 'Sandbox',
              color: AppColors.accent,
              selected: env == BusinessEnvironment.sandbox,
              onTap: () => onEnvChanged(BusinessEnvironment.sandbox),
            ),
            _Pill(
              label: 'Producción',
              color: AppColors.success,
              selected: env == BusinessEnvironment.production,
              onTap: () => onEnvChanged(BusinessEnvironment.production),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepPlan extends StatelessWidget {
  const _StepPlan({
    required this.plan,
    required this.onPlanChanged,
    required this.trialDays,
    required this.onTrialDaysChanged,
    required this.summary,
  });

  final PlanType plan;
  final ValueChanged<PlanType> onPlanChanged;
  final int trialDays;
  final ValueChanged<int> onTrialDaysChanged;
  final Widget summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepTitle('Plan inicial'),
        const SizedBox(height: 14),
        const _Label('Plan'),
        const SizedBox(height: 6),
        DropdownButtonFormField<PlanType>(
          initialValue: plan,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: PlanType.trial, child: Text('Trial')),
            DropdownMenuItem(value: PlanType.free, child: Text('Free')),
            DropdownMenuItem(value: PlanType.basic, child: Text('Basic')),
            DropdownMenuItem(value: PlanType.pro, child: Text('Pro')),
          ],
          onChanged: (v) {
            if (v != null) onPlanChanged(v);
          },
        ),
        const SizedBox(height: 14),
        const _Label('Días hasta el corte'),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in const [7, 14, 30, 60, 90])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  label: '$d días',
                  color: AppColors.primary,
                  selected: trialDays == d,
                  onTap: () => onTrialDaysChanged(d),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const _Label('Resumen'),
        const SizedBox(height: 6),
        summary,
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.ownerEmail,
    required this.businessName,
    required this.businessType,
    required this.domain,
    required this.env,
  });

  final String ownerEmail;
  final String businessName;
  final String businessType;
  final String domain;
  final BusinessEnvironment env;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SummaryRow(label: 'Owner', value: ownerEmail),
          _SummaryRow(label: 'Negocio', value: businessName),
          if (businessType.isNotEmpty)
            _SummaryRow(label: 'Tipo', value: businessType),
          if (domain.isNotEmpty) _SummaryRow(label: 'Dominio', value: domain),
          _SummaryRow(label: 'Entorno', value: env.label),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
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

// ---------------------------------------------------------------------------
// Helpers UI
// ---------------------------------------------------------------------------

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
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

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 18,
              height: 4,
              decoration: BoxDecoration(
                color: i <= current
                    ? AppColors.primary
                    : AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
      ],
    );
  }
}
