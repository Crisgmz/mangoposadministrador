import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import '../../core/io/web_file_picker.dart';
import '../../domain/models/ecf_onboarding.dart';

/// Diálogos del alta e-CF (ver `ecf_onboarding_section.dart`). Solo capturan
/// y devuelven lo que escribió el operador; las reglas las valida el servidor.

const ecfTypeLabels = <String, String>{
  'E31': 'E31 · Crédito fiscal',
  'E32': 'E32 · Consumo',
  'E34': 'E34 · Nota de crédito',
  'E44': 'E44 · Regímenes especiales',
  'E45': 'E45 · Gubernamental',
};

// ---------------------------------------------------------------------------
// Datos del contribuyente
// ---------------------------------------------------------------------------

class EcfTaxpayerDialog extends StatefulWidget {
  const EcfTaxpayerDialog({
    required this.initial,
    required this.rncLocked,
    super.key,
  });

  final EcfTaxpayerDraft initial;

  /// Con la empresa ya vinculada en Alanube el RNC no se cambia.
  final bool rncLocked;

  @override
  State<EcfTaxpayerDialog> createState() => _EcfTaxpayerDialogState();
}

class _EcfTaxpayerDialogState extends State<EcfTaxpayerDialog> {
  late final _rnc = TextEditingController(text: widget.initial.rnc ?? '');
  late final _legal = TextEditingController(text: widget.initial.legalName ?? '');
  late final _trade = TextEditingController(text: widget.initial.tradeName ?? '');
  late final _address =
      TextEditingController(text: widget.initial.fiscalAddress ?? '');
  late final _province =
      TextEditingController(text: widget.initial.province ?? '');
  late final _municipality =
      TextEditingController(text: widget.initial.municipality ?? '');
  late final _email = TextEditingController(text: widget.initial.email ?? '');
  String? _error;

  @override
  void dispose() {
    for (final c in [_rnc, _legal, _trade, _address, _province, _municipality, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _submit() {
    final digits = _rnc.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && digits.length != 9 && digits.length != 11) {
      setState(() => _error = 'El RNC debe tener 9 dígitos (u 11 si es cédula).');
      return;
    }
    Navigator.pop(
      context,
      EcfTaxpayerDraft(
        rnc: digits.isEmpty ? null : digits,
        legalName: _clean(_legal),
        tradeName: _clean(_trade),
        fiscalAddress: _clean(_address),
        province: _clean(_province),
        municipality: _clean(_municipality),
        email: _clean(_email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Datos del contribuyente'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfNote(
                color: AppColors.mutedForeground,
                text: 'Cópialos tal como aparecen en la DGII (consulta de RNC o '
                    'la autorización de secuencias), no como el cliente llama '
                    'a su negocio.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _rnc,
                enabled: !widget.rncLocked,
                autofocus: !widget.rncLocked,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'RNC',
                  helperText: widget.rncLocked
                      ? 'La empresa ya está vinculada en Alanube con este RNC.'
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _legal,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Razón social'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _trade,
                decoration: const InputDecoration(
                  labelText: 'Nombre comercial (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _address,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Dirección fiscal',
                  helperText: 'La registrada en la DGII. Puede no ser la del local.',
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _province,
                      decoration: const InputDecoration(labelText: 'Provincia'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _municipality,
                      decoration: const InputDecoration(labelText: 'Municipio'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Correo'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                EcfNote(color: AppColors.destructive, text: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Alta con certificado
// ---------------------------------------------------------------------------

class EcfCertificateInput {
  const EcfCertificateInput({
    required this.filename,
    required this.bytes,
    required this.password,
  });

  final String filename;
  final Uint8List bytes;
  final String password;
}

class EcfCertificateDialog extends StatefulWidget {
  const EcfCertificateDialog({
    required this.draft,
    required this.isProduction,
    super.key,
  });

  final EcfTaxpayerDraft draft;
  final bool isProduction;

  @override
  State<EcfCertificateDialog> createState() => _EcfCertificateDialogState();
}

class _EcfCertificateDialogState extends State<EcfCertificateDialog> {
  final _password = TextEditingController();
  PickedImage? _file;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await pickFileFromWeb(
        accept: '.p12,.pfx,application/x-pkcs12',
        maxBytes: 100 * 1024,
      );
      if (picked == null || !mounted) return;
      final ext = picked.extension;
      if (ext != 'p12' && ext != 'pfx') {
        setState(() => _error = 'El certificado tiene que ser .p12 o .pfx.');
        return;
      }
      setState(() {
        _file = picked;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final ready = _file != null && _password.text.isNotEmpty;
    return AlertDialog(
      title: const Text('Dar de alta en Alanube'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EcfNote(
                color: widget.isProduction ? AppColors.warning : AppColors.mutedForeground,
                text: '${widget.isProduction ? 'Esto crea la empresa en Alanube PRODUCCIÓN' : 'Esto crea la empresa en Alanube (sandbox)'} '
                    'dentro de la cuenta de MangoPOS. El certificado y la '
                    'contraseña van directo a Alanube: MangoPOS no los guarda.',
              ),
              const SizedBox(height: 14),
              EcfLine('Razón social', d.legalName ?? '—'),
              EcfLine('RNC', d.rnc ?? '—'),
              EcfLine('Dirección fiscal', d.fiscalAddress ?? '—'),
              if (d.email != null) EcfLine('Correo', d.email!),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(HugeIcons.strokeRoundedFileUpload, size: 15),
                label: Text(_file == null ? 'Elegir certificado (.p12)' : _file!.filename),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Contraseña del certificado',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? HugeIcons.strokeRoundedView : HugeIcons.strokeRoundedViewOff,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'El certificado tiene que estar a nombre del contribuyente o de '
                'su representante autorizado ante la DGII. El de MangoPOS no sirve.',
                style: TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                EcfNote(color: AppColors.destructive, text: _error!),
              ],
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
          onPressed: !ready
              ? null
              : () => Navigator.pop(
                    context,
                    EcfCertificateInput(
                      filename: _file!.filename,
                      bytes: _file!.bytes,
                      password: _password.text,
                    ),
                  ),
          child: const Text('Dar de alta'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Buscar / vincular empresa existente
// ---------------------------------------------------------------------------

class EcfFindCompanyDialog extends StatefulWidget {
  const EcfFindCompanyDialog({
    required this.businessId,
    required this.rnc,
    required this.matches,
    this.searchError,
    super.key,
  });

  final String businessId;
  final String? rnc;
  final List<EcfCompany> matches;
  final String? searchError;

  @override
  State<EcfFindCompanyDialog> createState() => _EcfFindCompanyDialogState();
}

class _EcfFindCompanyDialogState extends State<EcfFindCompanyDialog> {
  final _manualId = TextEditingController();

  @override
  void dispose() {
    _manualId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'es');
    return AlertDialog(
      title: const Text('Empresa existente en Alanube'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.searchError != null)
                EcfNote(color: AppColors.destructive, text: widget.searchError!)
              else if (widget.matches.isEmpty)
                EcfNote(
                  color: AppColors.mutedForeground,
                  text: 'No hay empresas con RNC ${widget.rnc ?? '—'} en la cuenta '
                      'de Alanube. Dala de alta con su certificado.',
                ),
              for (final c in widget.matches) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        c.name ?? '(sin nombre)',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      EcfLine('RNC', c.identification ?? '—'),
                      EcfLine('ID', c.id),
                      EcfLine(
                        'Certificado',
                        c.hasCertificate
                            ? '${c.certificateName}'
                                '${c.certificateEndDate != null ? ' · vence ${df.format(c.certificateEndDate!)}' : ''}'
                            : 'Sin certificado',
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: c.assignedToBusinessId != null &&
                                c.assignedToBusinessId != widget.businessId
                            ? const Text(
                                'Ya la usa otro negocio',
                                style: TextStyle(fontSize: 12, color: AppColors.destructive),
                              )
                            : FilledButton(
                                onPressed: () => Navigator.pop(context, c.id),
                                child: const Text('Vincular'),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '¿Tienes el ID de la empresa (portal de Alanube)?',
                style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualId,
                      decoration: const InputDecoration(
                        labelText: 'ID de Alanube',
                        hintText: '01M11V7B6J4X6FQ5SRAFPVPATV',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      final id = _manualId.text.trim();
                      if (id.isNotEmpty) Navigator.pop(context, id);
                    },
                    child: const Text('Vincular'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Se verifica que el RNC de esa empresa sea el de este negocio antes de vincular.',
                style: TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Secuencia e-NCF
// ---------------------------------------------------------------------------

class EcfSequenceInput {
  const EcfSequenceInput({
    required this.ncfType,
    required this.rangeStart,
    required this.rangeEnd,
    this.expirationDate,
    this.authorizationNumber,
    this.lastUsed,
  });

  final String ncfType;
  final int rangeStart;
  final int rangeEnd;
  final DateTime? expirationDate;
  final String? authorizationNumber;
  final int? lastUsed;
}

class EcfSequenceDialog extends StatefulWidget {
  const EcfSequenceDialog({this.existing, this.takenTypes = const {}, super.key});

  /// Si viene, se corrige esa secuencia (el tipo no cambia).
  final EcfSequence? existing;

  /// Tipos ya cargados: al agregar se sugiere el primero que falte.
  final Set<String> takenTypes;

  @override
  State<EcfSequenceDialog> createState() => _EcfSequenceDialogState();
}

class _EcfSequenceDialogState extends State<EcfSequenceDialog> {
  late String _type = widget.existing?.ncfType ??
      ecfTypeLabels.keys.firstWhere(
        (t) => !widget.takenTypes.contains(t),
        orElse: () => 'E32',
      );
  late final _start =
      TextEditingController(text: '${widget.existing?.rangeStart ?? 1}');
  late final _end = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.rangeEnd}',
  );
  late final _auth =
      TextEditingController(text: widget.existing?.authorization ?? '');
  final _lastUsed = TextEditingController();
  late DateTime? _expiration = widget.existing?.expirationDate;
  String? _error;

  bool get _requiresExpiration =>
      EcfSequence.typesRequiringExpiration.contains(_type);

  @override
  void dispose() {
    for (final c in [_start, _end, _auth, _lastUsed]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Una secuencia ya vencida trae una fecha anterior a `firstDate`, y
    // showDatePicker revienta si la inicial queda fuera del rango.
    final current = _expiration;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null
          ? DateTime(now.year + 1, 12, 31)
          : current.isBefore(today)
              ? today
              : current,
      firstDate: today,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiration = picked);
  }

  void _submit() {
    final start = int.tryParse(_start.text.trim());
    final end = int.tryParse(_end.text.trim());
    final lastRaw = _lastUsed.text.trim();
    final last = lastRaw.isEmpty ? null : int.tryParse(lastRaw);
    String? error;
    if (start == null || start < 1) {
      error = 'El rango tiene que empezar en 1 o más.';
    } else if (end == null || end < start) {
      error = 'El fin del rango tiene que ser mayor o igual al inicio.';
    } else if (_requiresExpiration && _expiration == null) {
      error = '$_type exige la fecha de vencimiento de la autorización '
          '(sin ella la DGII rechaza con el código 145).';
    } else if (lastRaw.isNotEmpty && (last == null || last < 0 || last > end)) {
      error = 'El último número usado no es válido.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final auth = _auth.text.trim();
    Navigator.pop(
      context,
      EcfSequenceInput(
        ncfType: _type,
        rangeStart: start!,
        rangeEnd: end!,
        expirationDate: _expiration,
        authorizationNumber: auth.isEmpty ? null : auth,
        lastUsed: last,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'es');
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Corregir secuencia ${widget.existing!.ncfType}' : 'Cargar secuencia e-NCF'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfNote(
                color: AppColors.mutedForeground,
                text: 'Cópiala del PDF de autorización de la DGII. No cargues '
                    'rangos de palabra: a Tropella se le cargó E31 hasta 1000 '
                    'y la DGII solo autorizó 100.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final e in ecfTypeLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: editing ? null : (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _start,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Desde'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _end,
                      autofocus: !editing,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Hasta'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _expiration != null
                          ? 'Vence: ${df.format(_expiration!)}'
                          : _requiresExpiration
                              ? 'Vence: falta (obligatoria)'
                              : 'Vence: N/A',
                      style: TextStyle(
                        fontSize: 13,
                        color: _expiration == null && _requiresExpiration
                            ? AppColors.destructive
                            : AppColors.foreground,
                      ),
                    ),
                  ),
                  if (_expiration != null && !_requiresExpiration)
                    TextButton(
                      onPressed: () => setState(() => _expiration = null),
                      child: const Text('Quitar'),
                    ),
                  OutlinedButton(
                    onPressed: _pickDate,
                    child: const Text('Elegir fecha'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _auth,
                decoration: const InputDecoration(
                  labelText: 'Número de autorización (opcional)',
                  hintText: '6005460440',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lastUsed,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Último número ya usado (opcional)',
                  helperText: editing
                      ? 'Hoy va en ${widget.existing!.currentNumber}. Solo se puede adelantar.'
                      : 'Si ya se gastaron números fuera del sistema (rechazos, otro software).',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                EcfNote(color: AppColors.destructive, text: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Certificación DGII
// ---------------------------------------------------------------------------

/// Abre un enlace de Alanube (XML firmado, zips del set) en otra pestaña.
Future<void> openEcfLink(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  if (!ok && context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir: el enlace quedó copiado.')),
      );
    }
  }
}

/// Datos que pide el formulario de postulación de la OFV.
class EcfPostulationInfoDialog extends StatelessWidget {
  const EcfPostulationInfoDialog({required this.info, super.key});

  final EcfPostulationInfo info;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Datos para la postulación'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfNote(
                color: AppColors.mutedForeground,
                text: 'Se copian en el formulario de postulación como emisor '
                    'electrónico de la Oficina Virtual de la DGII. Al enviarlo, la '
                    'DGII genera el XML de postulación que se firma en el paso siguiente.',
              ),
              const SizedBox(height: 14),
              const _GroupTitle('Software / proveedor'),
              _CopyLine('Tipo de software', info.softwareType),
              _CopyLine('Nombre del software', info.softwareName),
              _CopyLine('Versión', info.softwareVersion),
              _CopyLine('RNC del proveedor', info.providerRnc),
              _CopyLine('Razón social del proveedor', info.providerName),
              _CopyLine('Nombre comercial', info.providerTradeName),
              const SizedBox(height: 12),
              const _GroupTitle('URLs de la empresa'),
              if (info.companyError != null)
                EcfNote(color: AppColors.destructive, text: info.companyError!)
              else ...[
                _CopyLine('Recepción', info.receptionUrl),
                _CopyLine('Aprobación comercial', info.approvalUrl),
                _CopyLine('Autenticación', info.authenticationUrl),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.mutedForeground),
      ),
    );
  }
}

class _CopyLine extends StatelessWidget {
  const _CopyLine(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Row(
      children: [
        Expanded(child: EcfLine(label, v ?? '—')),
        IconButton(
          tooltip: 'Copiar',
          visualDensity: VisualDensity.compact,
          onPressed: v == null ? null : () => Clipboard.setData(ClipboardData(text: v)),
          icon: const Icon(HugeIcons.strokeRoundedCopy01, size: 14),
        ),
      ],
    );
  }
}

/// Elige el XML que dio la DGII para que Alanube lo firme.
class EcfSignDocumentDialog extends StatefulWidget {
  const EcfSignDocumentDialog({required this.kind, super.key});

  final EcfSignKind kind;

  @override
  State<EcfSignDocumentDialog> createState() => _EcfSignDocumentDialogState();
}

class _EcfSignDocumentDialogState extends State<EcfSignDocumentDialog> {
  PickedImage? _file;
  String? _error;

  String get _help {
    switch (widget.kind) {
      case EcfSignKind.postulation:
        return 'La DGII lo genera al enviar la postulación en la OFV. Firmado, se '
            'sube en la misma OFV para activar el ambiente de certificación.';
      case EcfSignKind.declaration:
        return 'La DGII la entrega cuando aprueba el set de pruebas. Firmada, se '
            'sube a la OFV.';
      case EcfSignKind.roles:
        return 'Solo si la DGII lo pide al asignar los roles a Alanube. Firmado, '
            'se sube a la OFV.';
    }
  }

  Future<void> _pick() async {
    try {
      final picked = await pickFileFromWeb(
        accept: '.xml,text/xml,application/xml',
        maxBytes: 2 * 1024 * 1024,
      );
      if (picked == null || !mounted) return;
      if (picked.extension != 'xml') {
        setState(() => _error = 'Tiene que ser el archivo .xml de la DGII.');
        return;
      }
      setState(() {
        _file = picked;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Firmar ${widget.kind.label.toLowerCase()}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EcfNote(color: AppColors.mutedForeground, text: _help),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(HugeIcons.strokeRoundedFileUpload, size: 15),
              label: Text(_file == null ? 'Elegir XML' : _file!.filename),
            ),
            const SizedBox(height: 8),
            const Text(
              'Se firma con el certificado que la empresa tiene cargado en Alanube.',
              style: TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              EcfNote(color: AppColors.destructive, text: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _file == null ? null : () => Navigator.pop(context, _file),
          child: const Text('Firmar'),
        ),
      ],
    );
  }
}

/// Resultado de la firma: el enlace al XML firmado para subirlo a la OFV.
class EcfSignedDocumentDialog extends StatelessWidget {
  const EcfSignedDocumentDialog({required this.kind, required this.url, super.key});

  final EcfSignKind kind;
  final String url;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${kind.label} firmado'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EcfNote(
              color: AppColors.primary,
              text: 'Descárgalo y súbelo a la Oficina Virtual de la DGII. Hazlo '
                  'enseguida: el enlace de Alanube puede vencer.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              url,
              style: const TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          child: const Text('Copiar enlace'),
        ),
        FilledButton.icon(
          onPressed: () => openEcfLink(context, url),
          icon: const Icon(HugeIcons.strokeRoundedDownload04, size: 14),
          label: const Text('Descargar'),
        ),
      ],
    );
  }
}

/// Certificado .p12 del contribuyente para firmar el set de pruebas. Viaja en
/// la petición y el servidor no lo guarda.
class EcfSigningCertificateDialog extends StatefulWidget {
  const EcfSigningCertificateDialog({
    required this.title,
    required this.intro,
    required this.confirmLabel,
    super.key,
  });

  final String title;
  final String intro;
  final String confirmLabel;

  @override
  State<EcfSigningCertificateDialog> createState() =>
      _EcfSigningCertificateDialogState();
}

class _EcfSigningCertificateDialogState extends State<EcfSigningCertificateDialog> {
  final _password = TextEditingController();
  PickedImage? _file;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await pickFileFromWeb(
        accept: '.p12,.pfx,application/x-pkcs12',
        maxBytes: 100 * 1024,
      );
      if (picked == null || !mounted) return;
      final ext = picked.extension;
      if (ext != 'p12' && ext != 'pfx') {
        setState(() => _error = 'El certificado tiene que ser .p12 o .pfx.');
        return;
      }
      setState(() {
        _file = picked;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _file != null && _password.text.isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EcfNote(color: AppColors.mutedForeground, text: widget.intro),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(HugeIcons.strokeRoundedFileUpload, size: 15),
                label: Text(_file == null ? 'Elegir certificado (.p12)' : _file!.filename),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Contraseña del certificado',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? HugeIcons.strokeRoundedView : HugeIcons.strokeRoundedViewOff,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'El mismo certificado con que se firmó la postulación. MangoPOS no lo guarda.',
                style: TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                EcfNote(color: AppColors.destructive, text: _error!),
              ],
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
          onPressed: !ready
              ? null
              : () => Navigator.pop(
                    context,
                    EcfCertificateInput(
                      filename: _file!.filename,
                      bytes: _file!.bytes,
                      password: _password.text,
                    ),
                  ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Nombre de cada tipo de e-CF del set de pruebas.
const ecfTestTypeLabels = <String, String>{
  '31': 'Crédito fiscal',
  '32': 'Consumo',
  '33': 'Nota de débito',
  '34': 'Nota de crédito',
  '41': 'Compras',
  '43': 'Gastos menores',
  '44': 'Regímenes especiales',
  '45': 'Gubernamental',
  '46': 'Exportaciones',
  '47': 'Pagos al exterior',
};

/// Los comprobantes del set con lo que respondió la DGII.
class EcfTestSetDialog extends StatelessWidget {
  const EcfTestSetDialog({
    required this.testSet,
    required this.onDownload,
    this.onPrint,
    super.key,
  });

  final EcfTestSet testSet;

  /// Descarga el XML firmado de un caso (lo hace la sección: usa el repo).
  final Future<void> Function(EcfTestCase c) onDownload;

  /// Descarga la representación impresa (PDF). Solo para e-CF, no para
  /// aprobaciones comerciales.
  final Future<void> Function(EcfTestCase c)? onPrint;

  Color _statusColor(EcfTestCase c) {
    switch (c.status) {
      case 'accepted':
        return AppColors.primary;
      case 'conditional':
      case 'sent':
        return AppColors.warning;
      case 'rejected':
      case 'error':
        return AppColors.destructive;
      default:
        return AppColors.mutedForeground;
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00', 'en_US');
    final summaries = testSet.cases.where((c) => c.isSummary).toList();
    return AlertDialog(
      title: Text(testSet.filename ?? (testSet.isSimulation ? 'Simulación e-CF' : 'Set de pruebas')),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (summaries.isNotEmpty) ...[
                EcfNote(
                  color: AppColors.mutedForeground,
                  text: 'Las facturas de consumo menores de RD\$250 mil '
                      '(${summaries.map((c) => c.encf).join(', ')}) van a la DGII como '
                      'resumen. Cuando el resumen quede aceptado, descarga su XML y '
                      'súbelo en "Facturas de consumo < 250Mil" del portal de certificación.',
                ),
                const SizedBox(height: 12),
              ],
              for (final c in testSet.cases)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c.encf} · ${ecfTestTypeLabels[c.ecfType] ?? 'E${c.ecfType}'}'
                              '${c.isSummary ? ' · resumen' : ''}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (c.total != null) 'RD\$${money.format(c.total)}',
                                if (c.modifies != null) 'modifica ${c.modifies}',
                                if (c.securityCode != null && c.isSummary) 'código ${c.securityCode}',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                            ),
                            for (final m in c.messages)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: SelectableText(
                                  '${m.code != null ? '[${m.code}] ' : ''}${m.message}',
                                  style: TextStyle(fontSize: 11.5, height: 1.3, color: _statusColor(c)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        c.statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(c),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Descargar XML firmado',
                        visualDensity: VisualDensity.compact,
                        onPressed: c.hasXml ? () => onDownload(c) : null,
                        icon: const Icon(HugeIcons.strokeRoundedDownload04, size: 15),
                      ),
                      if (onPrint != null && !c.isApproval)
                        IconButton(
                          tooltip: 'Representación impresa (PDF)',
                          visualDensity: VisualDensity.compact,
                          onPressed: c.hasXml ? () => onPrint!(c) : null,
                          icon: const Icon(HugeIcons.strokeRoundedPdf01, size: 15),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas compartidas con la sección
// ---------------------------------------------------------------------------

class EcfLine extends StatelessWidget {
  const EcfLine(this.label, this.value, {this.valueColor, super.key});

  final String label;
  final String value;
  final Color? valueColor;

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
              style: const TextStyle(fontSize: 12.5, color: AppColors.mutedForeground),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EcfNote extends StatelessWidget {
  const EcfNote({required this.color, required this.text, super.key});

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
