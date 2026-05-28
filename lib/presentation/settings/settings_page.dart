import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/io/web_file_picker.dart';
import '../../data/repositories/company_settings_repository.dart';
import '../../domain/models/company_settings.dart';
import '../shared/page_header.dart';

/// Configuración general del panel administrador.
/// V1: solo edición de datos de empresa (emisor de facturas).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(companySettingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          kicker: 'Configuración',
          title: 'Datos de la empresa',
          subtitle:
              'Información del emisor que aparece en las facturas de membresía y comunicación con clientes.',
        ),
        const SizedBox(height: 24),
        settingsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error: $e',
              style: const TextStyle(color: AppColors.destructive),
            ),
          ),
          data: (settings) => _CompanyForm(settings: settings),
        ),
      ],
    );
  }
}

class _CompanyForm extends ConsumerStatefulWidget {
  const _CompanyForm({required this.settings});
  final CompanySettings settings;

  @override
  ConsumerState<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends ConsumerState<_CompanyForm> {
  late TextEditingController _legalName;
  late TextEditingController _rnc;
  late TextEditingController _address;
  late TextEditingController _city;
  late TextEditingController _country;
  late TextEditingController _phone;
  late TextEditingController _email;
  late TextEditingController _website;
  late TextEditingController _logoUrl;
  late TextEditingController _payment;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _legalName = _ctrl(s.legalName);
    _rnc = _ctrl(s.rnc);
    _address = _ctrl(s.address);
    _city = _ctrl(s.city);
    _country = _ctrl(s.country);
    _phone = _ctrl(s.phone);
    _email = _ctrl(s.email);
    _website = _ctrl(s.website);
    _logoUrl = _ctrl(s.logoUrl);
    _payment = _ctrl(s.paymentInstructions);
  }

  TextEditingController _ctrl(String? v) {
    final c = TextEditingController(text: v ?? '');
    c.addListener(_markDirty);
    return c;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in [
      _legalName,
      _rnc,
      _address,
      _city,
      _country,
      _phone,
      _email,
      _website,
      _logoUrl,
      _payment,
    ]) {
      c.removeListener(_markDirty);
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _dirty && !_saving && _legalName.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(companySettingsRepositoryProvider).update(
            legalName: _legalName.text.trim(),
            rnc: _rnc.text.trim().isEmpty ? null : _rnc.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            country:
                _country.text.trim().isEmpty ? null : _country.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            website:
                _website.text.trim().isEmpty ? null : _website.text.trim(),
            logoUrl:
                _logoUrl.text.trim().isEmpty ? null : _logoUrl.text.trim(),
            paymentInstructions: _payment.text.trim().isEmpty
                ? null
                : _payment.text.trim(),
          );
      ref.invalidate(companySettingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos de empresa guardados.')),
      );
      setState(() {
        _dirty = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Identidad'),
          const SizedBox(height: 8),
          _Field(label: 'Nombre legal *', controller: _legalName),
          _Field(label: 'RNC', controller: _rnc),
          const SizedBox(height: 16),
          const _SectionLabel('Dirección'),
          const SizedBox(height: 8),
          _Field(label: 'Calle y número', controller: _address),
          Row(
            children: [
              Expanded(
                  child: _Field(label: 'Ciudad', controller: _city)),
              const SizedBox(width: 12),
              Expanded(
                  child: _Field(label: 'País', controller: _country)),
            ],
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Contacto'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _Field(label: 'Teléfono', controller: _phone)),
              const SizedBox(width: 12),
              Expanded(child: _Field(label: 'Email', controller: _email)),
            ],
          ),
          _Field(label: 'Website', controller: _website),
          const SizedBox(height: 16),
          const _SectionLabel('Logo'),
          const SizedBox(height: 8),
          _LogoUploader(
            currentUrl: _logoUrl.text.trim().isEmpty
                ? null
                : _logoUrl.text.trim(),
            onChanged: (url) {
              _logoUrl.text = url ?? '';
              _markDirty();
            },
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Instrucciones de pago'),
          const SizedBox(height: 8),
          _Field(
            label: 'Texto en la sección "Instrucciones de pago" del PDF',
            controller: _payment,
            maxLines: 4,
            helper:
                'Aparece al pie de las facturas pendientes. Soporta varias líneas.',
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Text(
                    'Hay cambios sin guardar',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _canSave ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        HugeIcons.strokeRoundedTick01,
                        size: 16,
                      ),
                label: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: maxLines > 1 ? maxLines : 1,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: helper,
              helperMaxLines: 2,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: AppColors.accent,
      ),
    );
  }
}

/// Uploader del logo de la empresa. Selecciona archivo de la PC, sube a
/// Supabase Storage (bucket `company-assets`) y devuelve la URL pública al
/// padre vía `onChanged`. Si `currentUrl` está set, muestra preview y un
/// botón para reemplazar o quitar.
class _LogoUploader extends ConsumerStatefulWidget {
  const _LogoUploader({required this.currentUrl, required this.onChanged});

  final String? currentUrl;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<_LogoUploader> createState() => _LogoUploaderState();
}

class _LogoUploaderState extends ConsumerState<_LogoUploader> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    PickedImage? picked;
    try {
      picked = await pickImageFromWeb(maxBytes: 1024 * 1024);
    } catch (e) {
      _err('$e');
      return;
    }
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      // El mime que da el browser a veces viene vacío (ej. SVG en algunos
      // navegadores) — caemos a deducirlo de la extensión.
      final mime = picked.mimeType.isNotEmpty
          ? picked.mimeType
          : _mimeFromExt(picked.extension) ?? 'application/octet-stream';
      final url = await ref
          .read(companySettingsRepositoryProvider)
          .uploadLogo(
            bytes: picked.bytes,
            filename: picked.filename,
            mimeType: mime,
          );
      widget.onChanged(url);
    } catch (e) {
      _err('Error subiendo logo: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String? _mimeFromExt(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return null;
    }
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.currentUrl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.muted,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: url == null
                ? const Icon(
                    HugeIcons.strokeRoundedImage01,
                    color: AppColors.mutedForeground,
                    size: 22,
                  )
                : Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      HugeIcons.strokeRoundedAlertCircle,
                      color: AppColors.warning,
                      size: 22,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  url == null
                      ? 'Sin logo configurado'
                      : 'Logo activo',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'PNG, JPG, WebP o SVG. Máx 1 MB. Aparece en el header de las facturas.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_uploading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: _pickAndUpload,
              icon: const Icon(HugeIcons.strokeRoundedUpload01, size: 14),
              label: Text(url == null ? 'Subir' : 'Reemplazar'),
            ),
            if (url != null) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Quitar logo',
                onPressed: () => widget.onChanged(null),
                icon: const Icon(
                  HugeIcons.strokeRoundedDelete02,
                  size: 16,
                  color: AppColors.destructive,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
