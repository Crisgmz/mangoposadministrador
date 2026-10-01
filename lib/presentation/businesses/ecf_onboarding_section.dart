import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/io/web_file_picker.dart';
import '../../data/repositories/ecf_onboarding_repository.dart';
import '../../domain/models/ecf_onboarding.dart';
import 'ecf_onboarding_dialogs.dart';

/// Sección "Facturación electrónica" del detalle de negocio.
///
/// El alta e-CF la hace MangoPOS, no el cliente: el operador captura los
/// datos del contribuyente, da de alta (o vincula) la empresa en Alanube con
/// el certificado del cliente, carga las secuencias del PDF de la DGII,
/// verifica y activa. Cada paso lo valida el servidor (`ecf-onboarding` y
/// `provision-ecf`); acá solo se presenta.
///
/// Para clientes que todavía no son emisores electrónicos, el paso de
/// certificación guía la postulación en la OFV: firma de los XML de la DGII y
/// set de pruebas. Subir los archivos a la OFV sigue siendo manual.
class EcfOnboardingSection extends ConsumerStatefulWidget {
  const EcfOnboardingSection({required this.businessId, super.key});

  final String businessId;

  @override
  ConsumerState<EcfOnboardingSection> createState() =>
      _EcfOnboardingSectionState();
}

class _EcfOnboardingSectionState extends ConsumerState<EcfOnboardingSection> {
  /// Qué está corriendo, para deshabilitar botones y decirlo.
  String? _busy;

  /// Último preflight. Se descarta al refrescar: los datos pudieron cambiar.
  EcfPreflightResult? _preflight;

  /// Datos de la postulación: no cambian en la sesión, se piden una vez.
  EcfPostulationInfo? _postulationInfo;

  EcfOnboardingRepository get _repo =>
      ref.read(ecfOnboardingRepositoryProvider);

  void _refresh() {
    setState(() => _preflight = null);
    ref.invalidate(ecfOnboardingStatusProvider(widget.businessId));
  }

  /// Corre [action] con el indicador de ocupado. Devuelve false si falló (el
  /// error ya se mostró).
  Future<bool> _run(
    String label,
    Future<void> Function() action, {
    String? success,
    bool refresh = true,
  }) async {
    setState(() => _busy = label);
    try {
      await action();
      if (refresh) _refresh();
      if (success != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
      return true;
    } catch (e) {
      if (mounted) await _showError(e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _showError(Object e) {
    final message = e is EcfOnboardingException ? e.message : '$e';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se pudo completar'),
        content: SizedBox(
          width: 460,
          child: SelectableText(message, style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    Color? color,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Text(body, style: const TextStyle(fontSize: 13, height: 1.45)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  Future<void> _editData(EcfOnboardingStatus s) async {
    // Primera vez: se precarga con lo que la POS ya tiene.
    final initial = s.draft ??
        EcfTaxpayerDraft(rnc: s.fiscal?.rnc, legalName: s.fiscal?.legalName);
    final result = await showDialog<EcfTaxpayerDraft>(
      context: context,
      builder: (_) => EcfTaxpayerDialog(
        initial: initial,
        rncLocked: s.draft?.alanubeCompanyId != null,
      ),
    );
    if (result == null) return;
    await _run(
      'Guardando datos…',
      () => _repo.saveData(widget.businessId, result),
      success: 'Datos guardados.',
    );
  }

  Future<void> _syncFiscal(EcfOnboardingStatus s) async {
    final ok = await _confirm(
      title: 'Copiar a la POS',
      body: 'Se reemplaza el RNC y la razón social de Ajustes → Fiscal de la POS '
          '(hoy: ${s.fiscal?.rnc ?? '—'} · ${s.fiscal?.legalName ?? '—'}) por '
          '${s.draft?.rnc ?? '—'} · ${s.draft?.legalName ?? '—'}.\n\n'
          'Es lo que se imprime en los comprobantes y lo que el preflight compara '
          'contra Alanube.',
      confirmLabel: 'Copiar',
    );
    if (!ok) return;
    await _run(
      'Copiando a la POS…',
      () => _repo.syncFiscal(widget.businessId),
      success: 'RNC y razón social actualizados en la POS.',
    );
  }

  Future<void> _findCompany(EcfOnboardingStatus s) async {
    setState(() => _busy = 'Buscando en Alanube…');
    List<EcfCompany> matches = const [];
    String? error;
    try {
      matches = await _repo.findCompany(widget.businessId);
    } catch (e) {
      error = e is EcfOnboardingException ? e.message : '$e';
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    final id = await showDialog<String>(
      context: context,
      builder: (_) => EcfFindCompanyDialog(
        businessId: widget.businessId,
        rnc: s.draft?.rnc ?? s.fiscal?.rnc,
        matches: matches,
        searchError: error,
      ),
    );
    if (id == null) return;
    await _run(
      'Vinculando empresa…',
      () => _repo.linkCompany(widget.businessId, id),
      success: 'Empresa vinculada.',
    );
  }

  Future<void> _registerCompany(EcfOnboardingStatus s) async {
    final input = await showDialog<EcfCertificateInput>(
      context: context,
      builder: (_) => EcfCertificateDialog(
        draft: s.draft!,
        isProduction: s.isProduction,
      ),
    );
    if (input == null) return;
    await _run(
      'Dando de alta en Alanube…',
      () => _repo.registerCompany(
        businessId: widget.businessId,
        certificateFilename: input.filename,
        certificateBytes: input.bytes,
        certificatePassword: input.password,
      ),
      success: 'Empresa creada en Alanube.',
    );
  }

  Future<void> _editSequence(EcfOnboardingStatus s, [EcfSequence? existing]) async {
    final input = await showDialog<EcfSequenceInput>(
      context: context,
      builder: (_) => EcfSequenceDialog(
        existing: existing,
        takenTypes: s.sequences.map((e) => e.ncfType).toSet(),
      ),
    );
    if (input == null) return;
    await _run(
      'Guardando secuencia…',
      () => _repo.saveSequence(
        businessId: widget.businessId,
        ncfType: input.ncfType,
        rangeStart: input.rangeStart,
        rangeEnd: input.rangeEnd,
        expirationDate: input.expirationDate,
        authorizationNumber: input.authorizationNumber,
        lastUsed: input.lastUsed,
      ),
      success: 'Secuencia ${input.ncfType} guardada.',
    );
  }

  Future<void> _verify(EcfOnboardingStatus s) async {
    EcfPreflightResult? result;
    final ok = await _run(
      'Verificando…',
      () async {
        result = await _repo.provision(
          businessId: widget.businessId,
          alanubeCompanyId: s.companyId!,
          dryRun: true,
        );
      },
      refresh: false,
    );
    if (ok && mounted) setState(() => _preflight = result);
  }

  Future<void> _activate(EcfOnboardingStatus s) async {
    final confirmed = await _confirm(
      title: 'Activar facturación electrónica',
      body: 'Se guarda la configuración de Alanube de ${s.businessName}. '
          'La POS todavía no emite serie E: eso pasa al encender la modalidad e-CF.',
      confirmLabel: 'Activar',
    );
    if (!confirmed) return;
    EcfPreflightResult? result;
    final ok = await _run(
      'Activando…',
      () async {
        result = await _repo.provision(
          businessId: widget.businessId,
          alanubeCompanyId: s.companyId!,
          dryRun: false,
        );
      },
    );
    if (!ok || !mounted) return;
    if (result != null && !result!.wrote) {
      // Algo cambió entre verificar y activar: el servidor no escribió.
      setState(() => _preflight = result);
      await _showError('No se activó: la verificación tiene puntos en rojo.');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activado. Falta encender la modalidad e-CF.')),
      );
    }
  }

  Future<void> _toggleEcf(EcfOnboardingStatus s, bool enable) async {
    final confirmed = await _confirm(
      title: enable ? 'Encender modalidad e-CF' : 'Apagar modalidad e-CF',
      body: enable
          ? 'Desde la próxima venta, la POS de ${s.businessName} emite comprobantes '
              'electrónicos (serie E) y los manda a la DGII.\n\n'
              'Haz enseguida una venta de prueba pequeña en E32 y confirma que la '
              'DGII la acepta. Cada rechazo gasta un número de la secuencia.'
          : 'La POS de ${s.businessName} vuelve a comprobantes de papel (serie B). '
              'Las facturas electrónicas ya emitidas no se tocan.',
      confirmLabel: enable ? 'Encender' : 'Apagar',
      color: enable ? AppColors.primary : AppColors.destructive,
    );
    if (!confirmed) return;
    await _run(
      enable ? 'Encendiendo…' : 'Apagando…',
      () => _repo.setEcfEnabled(widget.businessId, enable),
      success: enable ? 'Modalidad e-CF encendida.' : 'Modalidad e-CF apagada.',
    );
  }

  Future<EcfPostulationInfo?> _loadPostulationInfo() async {
    if (_postulationInfo != null) return _postulationInfo;
    EcfPostulationInfo? info;
    await _run(
      'Consultando a Alanube…',
      () async => info = await _repo.postulationInfo(widget.businessId),
      refresh: false,
    );
    if (info != null && mounted) setState(() => _postulationInfo = info);
    return info;
  }

  Future<void> _showPostulationInfo() async {
    final info = await _loadPostulationInfo();
    if (info == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => EcfPostulationInfoDialog(info: info),
    );
  }

  Future<void> _sign(EcfSignKind kind) async {
    final file = await showDialog<PickedImage>(
      context: context,
      builder: (_) => EcfSignDocumentDialog(kind: kind),
    );
    if (file == null) return;
    String? url;
    final ok = await _run(
      'Firmando ${kind.label.toLowerCase()}…',
      () async => url = await _repo.signDocument(
        businessId: widget.businessId,
        kind: kind,
        filename: file.filename,
        bytes: file.bytes,
      ),
    );
    if (!ok || url == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => EcfSignedDocumentDialog(kind: kind, url: url!),
    );
  }

  Future<void> _createSetTest(EcfOnboardingStatus s) async {
    final info = await _loadPostulationInfo();
    if (!mounted) return;
    final item = await showDialog<EcfItemExample>(
      context: context,
      builder: (_) => EcfItemExampleDialog(
        initial: info?.itemSuggestion,
        retrying: s.setTest?.isRejected ?? false,
      ),
    );
    if (item == null) return;
    await _run(
      'Generando set de pruebas…',
      () => _repo.createSetTest(widget.businessId, item),
      success: 'Set de pruebas generado. Alanube lo está enviando a la DGII.',
    );
  }

  Future<void> _setDgiiAuthorized(EcfOnboardingStatus s, bool authorized) async {
    final confirmed = await _confirm(
      title: authorized ? 'Marcar como autorizado' : 'Quitar la marca',
      body: authorized
          ? 'Confirma que la DGII ya autorizó a ${s.businessName} como emisor '
              'electrónico (o que ya lo estaba). Siguiente paso: cargar las '
              'secuencias e-NCF que la DGII le asigne.'
          : 'El paso de certificación vuelve a quedar pendiente.',
      confirmLabel: authorized ? 'Marcar' : 'Quitar',
    );
    if (!confirmed) return;
    await _run(
      'Guardando…',
      () => _repo.setDgiiAuthorized(widget.businessId, authorized),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(ecfOnboardingStatusProvider(widget.businessId));
    final status = statusAsync.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(HugeIcons.strokeRoundedInvoice03, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Facturación electrónica',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ),
            if (status != null) ...[
              _Pill(
                text: status.isProduction ? 'Alanube producción' : 'Alanube sandbox',
                color: status.isProduction ? AppColors.primary : AppColors.warning,
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: 'Refrescar',
              onPressed: _busy == null ? _refresh : null,
              icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_busy != null) ...[
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(_busy!, style: const TextStyle(fontSize: 12.5, color: AppColors.mutedForeground)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        statusAsync.when(
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
          error: (e, _) => EcfNote(
            color: AppColors.destructive,
            text: 'No se pudo leer el estado de facturación electrónica: '
                '${e is EcfOnboardingException ? e.message : e}',
          ),
          data: _buildSteps,
        ),
      ],
    );
  }

  Widget _buildSteps(EcfOnboardingStatus s) {
    final step = s.currentStep;
    final locked = _busy != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (step == 6)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: EcfNote(
              color: AppColors.primary,
              text: 'Este negocio ya emite comprobantes electrónicos.',
            ),
          ),
        _StepCard(
          number: 1,
          title: 'Datos del contribuyente',
          current: step,
          child: _dataStep(s, locked),
        ),
        _StepCard(
          number: 2,
          title: 'Empresa en Alanube',
          current: step,
          child: _companyStep(s, locked),
        ),
        _StepCard(
          number: 3,
          title: 'Certificación DGII',
          current: step,
          child: _certificationStep(s, locked),
        ),
        _StepCard(
          number: 4,
          title: 'Secuencias e-NCF',
          current: step,
          child: _sequencesStep(s, locked),
        ),
        _StepCard(
          number: 5,
          title: 'Verificar y activar',
          current: step,
          isLast: true,
          child: _activateStep(s, locked),
        ),
      ],
    );
  }

  Widget _dataStep(EcfOnboardingStatus s, bool locked) {
    final d = s.draft;
    final df = DateFormat('d MMM yyyy, h:mm a', 'es');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pedida por el cliente desde la POS: con quién coordinar y qué declaró.
        if (d?.requestedAt != null) ...[
          EcfNote(
            color: AppColors.primary,
            text: 'Solicitud del cliente desde la POS, ${df.format(d!.requestedAt!.toLocal())}. '
                'Contacto: ${d.contactName ?? '—'}${d.contactPhone != null ? ' · ${d.contactPhone}' : ''}. '
                '${d.alreadyAuthorized == true ? 'Dice que YA es emisor electrónico autorizado: confírmalo antes de certificar.' : 'Dice que todavía no es emisor electrónico.'}',
          ),
          const SizedBox(height: 10),
        ],
        if (d == null)
          Text(
            s.fiscal?.rnc?.isNotEmpty == true
                ? 'Sin capturar. La POS tiene RNC ${s.fiscal!.rnc} · ${s.fiscal!.legalName ?? '—'}.'
                : 'Sin capturar.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.mutedForeground),
          )
        else ...[
          EcfLine('RNC', d.rnc ?? '—'),
          EcfLine('Razón social', d.legalName ?? '—'),
          if (d.tradeName != null) EcfLine('Nombre comercial', d.tradeName!),
          EcfLine('Dirección fiscal', d.fiscalAddress ?? '—'),
          EcfLine(
            'Provincia / municipio',
            [d.province, d.municipality].whereType<String>().join(' · ').ifEmpty('—'),
          ),
          EcfLine('Correo', d.email ?? '—'),
          if (s.businessAddress != null &&
              d.fiscalAddress != null &&
              s.businessAddress!.trim().toUpperCase() != d.fiscalAddress!.trim().toUpperCase())
            EcfLine('Dirección del local', s.businessAddress!, valueColor: AppColors.mutedForeground),
          if (!s.fiscalInSync) ...[
            const SizedBox(height: 10),
            EcfNote(
              color: AppColors.warning,
              text: 'La POS tiene otro RNC o razón social '
                  '(${s.fiscal?.rnc ?? 'sin RNC'} · ${s.fiscal?.legalName ?? 'sin razón social'}). '
                  'La activación compara contra lo de la POS.',
            ),
          ],
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: locked ? null : () => _editData(s),
              icon: const Icon(HugeIcons.strokeRoundedEdit02, size: 14),
              label: Text(d == null ? 'Capturar datos' : 'Editar datos'),
            ),
            if (d != null && !s.fiscalInSync && d.rnc != null && d.legalName != null)
              OutlinedButton(
                onPressed: locked ? null : () => _syncFiscal(s),
                child: const Text('Copiar a la POS'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _companyStep(EcfOnboardingStatus s, bool locked) {
    final c = s.company;
    final df = DateFormat('d MMM yyyy', 'es');

    if (s.companyId == null) {
      final rnc = s.draft?.rnc ?? s.fiscal?.rnc;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Si el cliente ya existe en la cuenta de Alanube, vincúlalo. Si no, '
            'dalo de alta con su certificado .p12 y la contraseña.',
            style: TextStyle(fontSize: 12.5, color: AppColors.mutedForeground),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: locked || rnc == null ? null : () => _findCompany(s),
                icon: const Icon(HugeIcons.strokeRoundedSearch01, size: 14),
                label: const Text('Buscar por RNC'),
              ),
              FilledButton.icon(
                onPressed: locked || !s.hasData ? null : () => _registerCompany(s),
                icon: const Icon(HugeIcons.strokeRoundedShieldKey, size: 14),
                label: const Text('Dar de alta con certificado'),
              ),
            ],
          ),
          if (!s.hasData)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Para dar de alta faltan RNC, razón social y dirección fiscal.',
                style: TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: EcfLine('ID', s.companyId!)),
            IconButton(
              tooltip: 'Copiar ID',
              visualDensity: VisualDensity.compact,
              onPressed: () => Clipboard.setData(ClipboardData(text: s.companyId!)),
              icon: const Icon(HugeIcons.strokeRoundedCopy01, size: 14),
            ),
          ],
        ),
        if (s.companyError != null)
          EcfNote(color: AppColors.destructive, text: s.companyError!)
        else if (c != null) ...[
          EcfLine('Empresa', '${c.name ?? '—'} · RNC ${c.identification ?? '—'}'),
          EcfLine(
            'Certificado',
            !c.hasCertificate
                ? 'Sin certificado'
                : '${c.certificateName}'
                    '${c.certificateIssuer != null ? ' · ${c.certificateIssuer}' : ''}'
                    '${c.certificateEndDate != null ? ' · vence ${df.format(c.certificateEndDate!)}' : ''}',
            valueColor: !c.hasCertificate || c.certificateExpired ? AppColors.destructive : null,
          ),
          EcfLine(
            'Webhooks',
            c.webhooksOk == true ? 'Configurados' : 'Faltan (las facturas se quedarían en "enviado")',
            valueColor: c.webhooksOk == true ? null : AppColors.warning,
          ),
          if (c.certificationStep != null)
            EcfLine(
              'Paso en Alanube',
              '${c.certificationStep} (no es confiable: la prueba es la autorización de la DGII)',
              valueColor: AppColors.mutedForeground,
            ),
        ],
        if (s.draft?.companyLinkedVia != null)
          EcfLine(
            'Origen',
            s.draft!.companyLinkedVia == 'registered'
                ? 'Dada de alta desde el panel'
                : 'Ya existía en Alanube',
            valueColor: AppColors.mutedForeground,
          ),
      ],
    );
  }

  Widget _certificationStep(EcfOnboardingStatus s, bool locked) {
    final df = DateFormat('d MMM yyyy', 'es');
    if (!s.hasCompany) {
      return const Text(
        'Primero vincula o da de alta la empresa en Alanube.',
        style: TextStyle(fontSize: 12.5, color: AppColors.mutedForeground),
      );
    }
    final draft = s.draft;
    if (s.isCertified) {
      final marked = draft?.dgiiAuthorizedAt;
      return Row(
        children: [
          Expanded(
            child: Text(
              marked != null
                  ? 'Autorizado por la DGII (marcado el ${df.format(marked.toLocal())}).'
                  : 'Autorizado por la DGII: ya tiene secuencias electrónicas o está activado.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.mutedForeground),
            ),
          ),
          if (marked != null && !s.hasSequences && !s.isProvisioned)
            TextButton(
              onPressed: locked ? null : () => _setDgiiAuthorized(s, false),
              child: const Text('Quitar marca'),
            ),
        ],
      );
    }

    String signedText(DateTime? at, String pending) =>
        at == null ? pending : 'Firmado el ${df.format(at.toLocal())}. Súbelo a la OFV si no lo has hecho.';

    final t = s.setTest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Solo si el cliente todavía no es emisor electrónico. Los XML los '
          'genera la DGII y se suben en su Oficina Virtual; aquí se firman.',
          style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
        ),
        const SizedBox(height: 10),
        _SubStep(
          label: 'Postulación en la OFV',
          detail: 'Llena el formulario con los datos del proveedor y las URLs de la empresa.',
          done: draft?.postulationSignedAt != null,
          action: OutlinedButton(
            onPressed: locked ? null : _showPostulationInfo,
            child: const Text('Ver datos'),
          ),
        ),
        _SubStep(
          label: 'Firmar XML de postulación',
          detail: signedText(draft?.postulationSignedAt, 'La DGII lo genera al enviar la postulación.'),
          done: draft?.postulationSignedAt != null,
          action: OutlinedButton(
            onPressed: locked ? null : () => _sign(EcfSignKind.postulation),
            child: Text(draft?.postulationSignedAt == null ? 'Firmar XML' : 'Firmar otro'),
          ),
        ),
        _SubStep(
          label: 'Set de pruebas',
          detail: t == null
              ? (s.setTestError ??
                  (draft?.setTestId != null
                      ? 'Generado. Refresca para ver el avance.'
                      : 'Después de subir la postulación firmada. Alanube envía 20 comprobantes de prueba.'))
              : '${t.statusLabel} · ${t.processed ?? 0} de ${EcfSetTest.total} procesados'
                  '${t.retryNumber != null ? ' · intento ${t.retryNumber}' : ''}'
                  '${t.rejectedDocuments.isNotEmpty ? ' · rechazados: ${t.rejectedDocuments.map((d) => d.encf ?? d.type).join(', ')}' : ''}'
                  '${t.isAccepted ? '. Descarga los XML y PDF y súbelos a la OFV.' : ''}',
          detailColor: t?.isRejected == true || s.setTestError != null ? AppColors.destructive : null,
          done: t?.isAccepted ?? false,
          action: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (t == null && draft?.setTestId == null || (t?.isRejected ?? false))
                OutlinedButton(
                  onPressed: locked ? null : () => _createSetTest(s),
                  child: Text(t?.isRejected == true ? 'Generar de nuevo' : 'Generar'),
                ),
              if (t != null && !t.isFinal || t == null && draft?.setTestId != null)
                OutlinedButton(
                  onPressed: locked ? null : _refresh,
                  child: const Text('Consultar'),
                ),
              if (t?.documentsZipUrl != null)
                OutlinedButton(
                  onPressed: () => openEcfLink(context, t!.documentsZipUrl!),
                  child: const Text('Documentos'),
                ),
              if (t?.resumesZipUrl != null)
                OutlinedButton(
                  onPressed: () => openEcfLink(context, t!.resumesZipUrl!),
                  child: const Text('Resúmenes'),
                ),
            ],
          ),
        ),
        _SubStep(
          label: 'Firmar declaración jurada',
          detail: signedText(draft?.declarationSignedAt, 'La DGII la entrega al aprobar el set de pruebas.'),
          done: draft?.declarationSignedAt != null,
          action: OutlinedButton(
            onPressed: locked ? null : () => _sign(EcfSignKind.declaration),
            child: Text(draft?.declarationSignedAt == null ? 'Firmar XML' : 'Firmar otro'),
          ),
        ),
        _SubStep(
          label: 'Asignar roles a Alanube',
          detail: draft?.rolesSignedAt != null
              ? signedText(draft?.rolesSignedAt, '')
              : 'Lo hace el representante legal en la OFV. Si la DGII entrega un XML, se firma aquí.',
          done: draft?.rolesSignedAt != null,
          isLast: true,
          action: OutlinedButton(
            onPressed: locked ? null : () => _sign(EcfSignKind.roles),
            child: const Text('Firmar XML'),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: locked ? null : () => _setDgiiAuthorized(s, true),
            icon: const Icon(HugeIcons.strokeRoundedCheckmarkCircle02, size: 14),
            label: const Text('La DGII ya lo autorizó'),
          ),
        ),
      ],
    );
  }

  Widget _sequencesStep(EcfOnboardingStatus s, bool locked) {
    final df = DateFormat('d MMM yyyy', 'es');
    final types = s.sequences.map((e) => e.ncfType).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.sequences.isEmpty)
          const Text(
            'Sin secuencias electrónicas. Cárgalas del PDF de autorización de la DGII.',
            style: TextStyle(fontSize: 12.5, color: AppColors.mutedForeground),
          )
        else
          for (final q in s.sequences)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: q.isUsable ? AppColors.border : AppColors.destructive.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ecfTypeLabels[q.ncfType] ?? q.ncfType,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${q.rangeStart}–${q.rangeEnd} · quedan ${q.available}'
                          ' · ${q.expirationDate != null ? 'vence ${df.format(q.expirationDate!)}' : q.missingExpiration ? 'FALTA vencimiento' : 'vence N/A'}'
                          '${q.authorization != null ? ' · aut. ${q.authorization}' : ''}'
                          '${q.isActive ? '' : ' · inactiva'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: q.isUsable ? AppColors.mutedForeground : AppColors.destructive,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Corregir',
                    visualDensity: VisualDensity.compact,
                    onPressed: locked ? null : () => _editSequence(s, q),
                    icon: const Icon(HugeIcons.strokeRoundedEdit02, size: 14),
                  ),
                ],
              ),
            ),
        if (!types.contains('E32') || !types.contains('E34')) ...[
          const SizedBox(height: 4),
          EcfNote(
            color: AppColors.warning,
            text: [
              if (!types.contains('E32')) 'Sin E32 no hay factura de consumo.',
              if (!types.contains('E34'))
                'Sin E34 no se pueden anular ante la DGII facturas ya aceptadas.',
            ].join(' '),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: locked ? null : () => _editSequence(s),
            icon: const Icon(HugeIcons.strokeRoundedAdd01, size: 14),
            label: const Text('Cargar secuencia'),
          ),
        ),
      ],
    );
  }

  Widget _activateStep(EcfOnboardingStatus s, bool locked) {
    if (!s.hasCompany) {
      return const Text(
        'Primero vincula o da de alta la empresa en Alanube.',
        style: TextStyle(fontSize: 12.5, color: AppColors.mutedForeground),
      );
    }
    final pre = _preflight;
    final settings = s.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (settings != null)
          EcfLine(
            'Configuración',
            'Activada · modo ${settings.mode} · ${settings.environment}',
            valueColor: settings.mode == 'physical' ? AppColors.warning : null,
          ),
        if (pre != null) ...[
          const SizedBox(height: 6),
          for (final c in pre.checks) _CheckRow(check: c),
          const SizedBox(height: 6),
          if (pre.hasFailures)
            const EcfNote(
              color: AppColors.destructive,
              text: 'Hay puntos en rojo: corrígelos y vuelve a verificar.',
            )
          else if (pre.warnings > 0)
            EcfNote(
              color: AppColors.warning,
              text: '${pre.warnings} aviso(s): no bloquean, pero revísalos antes de activar.',
            ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: locked ? null : () => _verify(s),
              icon: const Icon(HugeIcons.strokeRoundedCheckmarkCircle02, size: 14),
              label: const Text('Verificar'),
            ),
            if (settings == null || settings.mode == 'physical')
              FilledButton.icon(
                onPressed: locked || pre == null || pre.hasFailures ? null : () => _activate(s),
                icon: const Icon(HugeIcons.strokeRoundedFlash, size: 14),
                label: const Text('Activar'),
              ),
          ],
        ),
        if (s.isProvisioned) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modalidad e-CF en la POS',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'El mismo switch de Ajustes → Fiscal.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.mutedForeground),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: s.ecfEnabled,
                  onChanged: locked ? null : (v) => _toggleEcf(s, v),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas chicas
// ---------------------------------------------------------------------------

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.current,
    required this.child,
    this.isLast = false,
  });

  final int number;
  final String title;

  /// Paso en curso del negocio (6 = todo listo).
  final int current;
  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final done = number < current;
    final active = number == current;
    final color = done
        ? AppColors.primary
        : active
            ? AppColors.accent
            : AppColors.mutedForeground;
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: done
                ? Icon(HugeIcons.strokeRoundedCheckmarkCircle02, size: 14, color: color)
                : Text(
                    '$number',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Subpaso de la certificación: estado, explicación y su botón.
class _SubStep extends StatelessWidget {
  const _SubStep({
    required this.label,
    required this.detail,
    required this.done,
    required this.action,
    this.detailColor,
    this.isLast = false,
  });

  final String label;
  final String detail;
  final bool done;
  final Widget action;
  final Color? detailColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              done ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedCircle,
              size: 14,
              color: done ? AppColors.primary : AppColors.mutedForeground,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: detailColor ?? AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: Align(alignment: Alignment.topRight, child: action)),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final EcfCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = check.isFail
        ? (HugeIcons.strokeRoundedCancelCircle, AppColors.destructive)
        : check.isWarn
            ? (HugeIcons.strokeRoundedAlert02, AppColors.warning)
            : (HugeIcons.strokeRoundedCheckmarkCircle02, AppColors.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              check.message,
              style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
