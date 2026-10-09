import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/io/web_file_picker.dart';
import '../../data/repositories/ecf_onboarding_repository.dart';
import '../../data/services/ecf_print_pdf.dart';
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
/// el set de pruebas que entrega la DGII (un Excel que se carga aquí, se firma
/// con el certificado del cliente y se manda a su ambiente de certificación).
/// Bajar y subir archivos en el portal de la DGII sigue siendo manual.
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

  /// Lotes de `send_test_set` antes de rendirse (cada uno trabaja ~30 s).
  static const _maxSendBatches = 12;

  /// Carga un Excel de la DGII en su paso: [kind] `ecf` (pruebas de datos
  /// e-CF) o `acecf` (aprobaciones comerciales).
  Future<void> _importTestSet(EcfTestSet? current, String kind) async {
    final approvals = kind == 'acecf';
    if (current != null && current.cases.any((c) => c.status != 'pending')) {
      final ok = await _confirm(
        title: approvals ? 'Cargar otras aprobaciones comerciales' : 'Cargar otro set de pruebas',
        body: 'Se reemplazan ${approvals ? 'las ${current.cases.length} aprobaciones cargadas' : 'los ${current.cases.length} comprobantes cargados'} '
            'y lo que respondió la DGII. Hazlo si reiniciaste ese paso en el portal de la '
            'DGII y descargaste el archivo nuevo.',
        confirmLabel: 'Reemplazar',
        color: AppColors.destructive,
      );
      if (!ok) return;
    }
    final PickedImage? file;
    try {
      file = await pickFileFromWeb(
        accept: '.xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv',
        maxBytes: 5 * 1024 * 1024,
      );
    } catch (e) {
      if (mounted) await _showError(e);
      return;
    }
    if (file == null || !mounted) return;
    if (file.extension != 'xlsx' && file.extension != 'csv') {
      await _showError('Tiene que ser el .xlsx que da la DGII o un .csv de su hoja.');
      return;
    }
    EcfTestSet? loaded;
    final ok = await _run(
      'Leyendo el archivo de la DGII…',
      () async => loaded = await _repo.importTestSet(
        businessId: widget.businessId,
        setKind: kind,
        filename: file!.filename,
        bytes: file.bytes,
      ),
    );
    if (!ok || loaded == null || !mounted) return;
    final l = loaded!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(approvals
          ? 'Aprobaciones comerciales cargadas: ${l.cases.length}.'
          : 'Set cargado: ${l.cases.length} comprobantes'
              '${l.summaries > 0 ? ' (${l.summaries} de consumo van como resumen)' : ''}.'),
    ));
  }

  Future<void> _sendTestSet(EcfTestSet t) async {
    final approvals = t.isApprovals;
    final cert = await showDialog<EcfCertificateInput>(
      context: context,
      builder: (_) => EcfSigningCertificateDialog(
        title: approvals ? 'Enviar las aprobaciones a la DGII' : 'Enviar el set a la DGII',
        intro: approvals
            ? 'Se firman ${t.toSend} aprobación(es) comercial(es) con el certificado del '
                'contribuyente, que aprueba como comprador, y se mandan al ambiente de '
                'certificación de la DGII tal cual el archivo. La DGII responde en el acto.'
            : 'Se firman ${t.toSend} comprobante(s) con el certificado del contribuyente '
                'y se mandan al ambiente de certificación de la DGII, tal cual el archivo: '
                'primero las facturas y al final las notas que las modifican. Puede tardar '
                'unos minutos; no cierres esta página.',
        confirmLabel: 'Firmar y enviar',
      ),
    );
    if (cert == null || !mounted) return;

    setState(() => _busy = 'Firmando y enviando a la DGII…');
    String? notice;
    var sent = 0;
    var failed = false;
    var renewedSession = false;
    try {
      for (var batch = 0; batch < _maxSendBatches; batch++) {
        final EcfTestSetSendResult r;
        try {
          r = await _repo.sendTestSet(
            businessId: widget.businessId,
            setKind: t.kind,
            certificateFilename: cert.filename,
            certificateBytes: cert.bytes,
            certificatePassword: cert.password,
          );
        } on EcfOnboardingException catch (e) {
          // La DGII cerró la sesión guardada: el servidor ya la olvidó y el
          // siguiente lote abre otra con el mismo certificado.
          if (e.code == 'dgii_session_expired' && !renewedSession) {
            renewedSession = true;
            continue;
          }
          rethrow;
        }
        sent += r.sent;
        final ts = r.testSet;
        if (mounted) {
          setState(() => _busy = 'Enviando a la DGII… ${ts.accepted} de ${ts.cases.length} '
              '${approvals ? 'aceptadas' : 'aceptados'}'
              '${ts.inProcess > 0 ? ', ${ts.inProcess} en proceso' : ''}');
        }
        notice = r.stoppedReason;
        if (!r.more) break;
        if (batch == _maxSendBatches - 1) {
          notice = 'La DGII sigue procesando. Usa Consultar en un momento y, si quedan '
              'comprobantes por enviar, Enviar otra vez.';
        }
      }
    } catch (e) {
      failed = true;
      if (mounted) await _showError(e);
    } finally {
      if (mounted) setState(() => _busy = null);
      _refresh();
    }
    if (failed || !mounted) return;
    if (notice != null) {
      await _showError(notice);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approvals
            ? 'Se mandaron $sent aprobación(es) comercial(es) a la DGII.'
            : 'Se mandaron $sent comprobante(s) a la DGII.'),
      ));
    }
  }

  Future<void> _checkTestSet(String kind) async {
    setState(() => _busy = 'Consultando a la DGII…');
    try {
      await _repo.checkTestSet(widget.businessId, setKind: kind);
      _refresh();
      return;
    } on EcfOnboardingException catch (e) {
      if (e.code != 'dgii_session_expired') {
        if (mounted) await _showError(e);
        return;
      }
    } catch (e) {
      if (mounted) await _showError(e);
      return;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    // La sesión con la DGII (una hora) venció: se abre otra con el certificado.
    final cert = await showDialog<EcfCertificateInput>(
      context: context,
      builder: (_) => const EcfSigningCertificateDialog(
        title: 'Consultar a la DGII',
        intro: 'La sesión con la DGII del último envío venció (dura una hora). Elige el '
            'certificado del contribuyente para abrir otra y consultar.',
        confirmLabel: 'Consultar',
      ),
    );
    if (cert == null) return;
    await _run(
      'Consultando a la DGII…',
      () => _repo.checkTestSet(
        widget.businessId,
        setKind: kind,
        certificateFilename: cert.filename,
        certificateBytes: cert.bytes,
        certificatePassword: cert.password,
      ),
    );
  }

  Future<void> _downloadTestCase(EcfTestCase c) async {
    try {
      final file = await _repo.testCaseXml(widget.businessId, c.id);
      downloadTextFileFromWeb(file.xml, file.filename, mimeType: 'application/xml');
    } catch (e) {
      if (mounted) await _showError(e);
    }
  }

  /// Paso 4: arma los e-CF de la simulación con el set de datos como modelo.
  Future<void> _generateSimulation(EcfOnboardingStatus s) async {
    final current = s.simulationSet;
    if (current != null && current.cases.isNotEmpty) {
      final ok = await _confirm(
        title: 'Generar la simulación de nuevo',
        body: 'Se descartan los ${current.cases.length} e-CF actuales y se arman otros con '
            'números nuevos (la DGII no deja reusar los ya enviados). Hazlo solo si la '
            'DGII rechazó alguno y reiniciaste las pruebas de simulación en su portal.',
        confirmLabel: 'Generar de nuevo',
        color: AppColors.destructive,
      );
      if (!ok) return;
    }
    EcfTestSet? built;
    final ok = await _run(
      'Generando los e-CF de la simulación…',
      () async => built = await _repo.generateSimulationSet(widget.businessId),
    );
    if (!ok || built == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Simulación lista: ${built!.cases.length} e-CF con los datos del contribuyente y fecha de hoy.'),
    ));
  }

  /// Representación impresa (PDF) de un e-CF ya firmado.
  Future<void> _printTestCase(EcfTestCase c) async {
    try {
      final file = await _repo.testCaseXml(widget.businessId, c.id);
      final model = file.print;
      if (model == null) {
        throw const EcfOnboardingException('El servidor no devolvió los datos de la representación impresa.');
      }
      final pdf = await buildEcfPrintPdf(model);
      downloadBytesFromWeb(pdf, file.filename.replaceFirst(RegExp(r'\.xml$'), '.pdf'), mimeType: 'application/pdf');
    } catch (e) {
      if (mounted) await _showError(e);
    }
  }

  /// Todas las representaciones impresas del set (las que ya se firmaron).
  Future<void> _printAll(EcfTestSet t) async {
    final signed = t.cases.where((c) => c.hasXml && !c.isApproval).toList();
    var done = 0;
    String? failure;
    try {
      for (final c in signed) {
        if (!mounted) return;
        setState(() => _busy = 'Generando representaciones impresas… ${done + 1} de ${signed.length}');
        final file = await _repo.testCaseXml(widget.businessId, c.id);
        final model = file.print;
        if (model == null) {
          failure = '${c.encf}: el servidor no devolvió los datos de la representación impresa.';
          break;
        }
        final pdf = await buildEcfPrintPdf(model);
        downloadBytesFromWeb(pdf, file.filename.replaceFirst(RegExp(r'\.xml$'), '.pdf'), mimeType: 'application/pdf');
        done++;
      }
    } catch (e) {
      failure = e is EcfOnboardingException ? e.message : '$e';
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    if (failure != null) {
      await _showError('Se descargaron $done de ${signed.length}. $failure');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Se descargaron $done representaciones impresas. Si el navegador pregunta, '
            'permite descargar varios archivos.'),
      ));
    }
  }

  Future<void> _showTestSet(EcfTestSet t) {
    return showDialog<void>(
      context: context,
      builder: (_) => EcfTestSetDialog(
        testSet: t,
        onDownload: _downloadTestCase,
        onPrint: t.isApprovals ? null : _printTestCase,
      ),
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

    final t = s.testSet;
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
          label: 'Pruebas de datos e-CF',
          detail: _testSetDetail(t),
          detailColor: t != null && (t.rejected.isNotEmpty || t.failed.isNotEmpty)
              ? AppColors.destructive
              : null,
          done: t?.isComplete ?? false,
          action: _testSetActions(t, 'ecf', locked),
        ),
        _SubStep(
          label: 'Pruebas de aprobación comercial',
          detail: _approvalSetDetail(s.approvalSet),
          detailColor: (s.approvalSet?.failed.isNotEmpty ?? false) ? AppColors.destructive : null,
          done: s.approvalSet?.isComplete ?? false,
          action: _testSetActions(s.approvalSet, 'acecf', locked),
        ),
        _SubStep(
          label: 'Pruebas de simulación e-CF',
          detail: _simulationDetail(s),
          detailColor: (s.simulationSet?.rejected.isNotEmpty ?? false) || (s.simulationSet?.failed.isNotEmpty ?? false)
              ? AppColors.destructive
              : null,
          done: s.simulationSet?.isComplete ?? false,
          action: _testSetActions(s.simulationSet, 'sim', locked, status: s),
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

  /// Botones de un set de la DGII: enviar, consultar, ver y cargar (o, en la
  /// simulación, generar y bajar las representaciones impresas).
  Widget _testSetActions(EcfTestSet? t, String kind, bool locked, {EcfOnboardingStatus? status}) {
    final simulation = kind == 'sim';
    final canGenerate = !simulation || (status?.testSet?.cases.isNotEmpty ?? false);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        if (t != null && t.canSend)
          FilledButton(
            onPressed: locked ? null : () => _sendTestSet(t),
            child: Text(
              t.cases.every((c) => c.status == 'pending') ? 'Enviar a la DGII' : 'Continuar envío',
            ),
          ),
        if (t != null && t.canCheck)
          OutlinedButton(
            onPressed: locked ? null : () => _checkTestSet(kind),
            child: const Text('Consultar'),
          ),
        if (t != null && !t.isEmpty)
          OutlinedButton(
            onPressed: () => _showTestSet(t),
            child: Text(kind == 'acecf' ? 'Ver aprobaciones' : 'Ver comprobantes'),
          ),
        if (simulation && t != null && t.cases.any((c) => c.hasXml))
          OutlinedButton(
            onPressed: locked ? null : () => _printAll(t),
            child: const Text('Representaciones (PDF)'),
          ),
        if (simulation)
          OutlinedButton(
            onPressed: locked || !canGenerate ? null : () => _generateSimulation(status!),
            child: Text(t == null || t.isEmpty ? 'Generar comprobantes' : 'Generar de nuevo'),
          )
        else
          OutlinedButton(
            onPressed: locked ? null : () => _importTestSet(t, kind),
            child: Text(t == null || t.isEmpty ? 'Cargar archivo' : 'Cargar otro'),
          ),
      ],
    );
  }

  String _simulationDetail(EcfOnboardingStatus s) {
    final t = s.simulationSet;
    if (t == null || t.isEmpty) {
      if (s.testSet == null || s.testSet!.isEmpty) {
        return 'Se arma con el set de pruebas de e-CF que aceptó la DGII: cárgalo primero.';
      }
      return 'La DGII pide e-CF de la operación real (paso 4 del portal). Se generan '
          'con el set ya aceptado de modelo, los datos del contribuyente, fecha de hoy y '
          'e-NCF nuevos. Después de enviarlos, baja las representaciones impresas (PDF) '
          'para el paso 5.';
    }
    final text = StringBuffer(_testSetDetail(t));
    if (t.isComplete) {
      text.write(' Baja las representaciones impresas (PDF) para el paso 5'
          '${t.summaries > 0 ? ' y sube en el portal los XML de las de consumo menores de 250 mil' : ''}.');
    }
    return text.toString();
  }

  String _approvalSetDetail(EcfTestSet? a) {
    if (a == null || a.isEmpty) {
      return 'Después de las pruebas de e-CF, el portal da otro Excel (Pruebas de datos '
          'aprobación comercial): el contribuyente aprueba, como comprador, e-CF que le '
          '"emitió" la DGII. Súbelo tal cual.';
    }
    final text = StringBuffer([
      '${a.cases.length} aprobaciones',
      '${a.accepted} aceptadas',
      if (a.toSend > 0) '${a.toSend} por enviar',
    ].join(' · '));
    text.write('.');
    if (a.failed.isNotEmpty) {
      text.write(' No se pudieron enviar ${a.failed.map((c) => c.encf).join(', ')} '
          '(detalle en Ver aprobaciones).');
    }
    return text.toString();
  }

  String _testSetDetail(EcfTestSet? t) {
    if (t == null || t.isEmpty) {
      return 'Después de subir la postulación firmada, la DGII da en su portal de '
          'certificación (Pruebas de datos e-CF) un Excel con los comprobantes a probar. '
          'Súbelo tal cual (.xlsx) o su hoja ECF en .csv.';
    }
    final text = StringBuffer([
      '${t.cases.length} comprobantes'
          '${t.summaries > 0 ? ' (${t.summaries} de consumo van como resumen)' : ''}',
      '${t.accepted} aceptados',
      if (t.inProcess > 0) '${t.inProcess} en proceso',
      if (t.toSend > 0) '${t.toSend} por enviar',
    ].join(' · '));
    text.write('.');
    if (t.rejected.isNotEmpty) {
      text.write(' La DGII rechazó ${t.rejected.map((c) => c.encf).join(', ')}: reinicia esas '
          'pruebas en su portal y ${t.isSimulation ? 'genera la simulación de nuevo' : 'carga el archivo nuevo'}.');
    } else if (t.failed.isNotEmpty) {
      text.write(' No se pudieron enviar ${t.failed.map((c) => c.encf).join(', ')} '
          '(detalle en Ver comprobantes).');
    } else if (t.isComplete && t.summaries > 0 && !t.isSimulation) {
      text.write(' Falta subir en el portal los XML de las facturas de consumo menores '
          'de 250 mil (Ver comprobantes → descargar).');
    }
    return text.toString();
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
