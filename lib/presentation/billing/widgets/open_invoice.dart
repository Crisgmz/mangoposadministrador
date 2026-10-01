import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/company_settings_repository.dart';
import '../../../data/services/invoice_pdf.dart';
import '../../../domain/models/company_settings.dart';
import '../../../domain/models/membership_invoice.dart';

/// Abre el PDF de una factura (preview/impresión) tocándola en una lista.
///
/// El PDF se genera detrás de un "Abriendo factura…": la primera vez descarga
/// fuentes y logo y tarda un par de segundos, y sin aviso el clic parece no
/// hacer nada.
Future<void> openInvoicePdf(BuildContext context, MembershipInvoice invoice) {
  return _open(context, (_) async => invoice);
}

/// Igual que [openInvoicePdf], pero desde un lugar que solo tiene el id de la
/// factura (la matriz de facturación): la busca entre las del negocio.
Future<void> openInvoicePdfById(
  BuildContext context, {
  required String businessId,
  required String invoiceId,
}) {
  return _open(context, (container) async {
    final invoices = await container.read(billingRepositoryProvider).forBusiness(businessId);
    for (final i in invoices) {
      if (i.id == invoiceId) return i;
    }
    return null;
  });
}

Future<void> _open(
  BuildContext context,
  Future<MembershipInvoice?> Function(ProviderContainer container) load,
) async {
  // Contenedor y navigator antes de cualquier await: la celda o fila que
  // disparó esto puede reconstruirse mientras se genera el PDF.
  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Expanded(child: Text('Abriendo factura…')),
          ],
        ),
      ),
    ),
  );

  MembershipInvoice? invoice;
  Uint8List? bytes;
  CompanySettings company = CompanySettings.fallback;
  String? error;
  try {
    invoice = await load(container);
    if (invoice == null) {
      error = 'No se encontró la factura.';
    } else {
      company = await container
          .read(companySettingsProvider.future)
          .catchError((_) => CompanySettings.fallback);
      bytes = await buildInvoicePdf(invoice, company: company);
    }
  } catch (e) {
    error = 'No se pudo abrir la factura: $e';
  } finally {
    navigator.pop();
  }

  if (error != null || invoice == null || bytes == null) {
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'No se pudo abrir la factura.')));
    return;
  }
  await previewInvoicePdf(invoice, company: company, bytes: bytes);
}
