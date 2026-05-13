import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/models/membership_invoice.dart';

/// Datos fijos del emisor (MangoPOS). Si en el futuro estos cambian, se
/// pueden mover a `business_settings` o a un row de configuración propio.
class _Issuer {
  static const name = 'MangoPOS Servicios SRL';
  static const address =
      'Av. Lope de Vega No. 13, Naco · Santo Domingo, RD';
  static const rnc = '1-31-23456-7';
  static const phone = '+1 (809) 555-0100';
  static const email = 'soporte@mangopos.do';
  static const website = 'mangopos.do';
}

/// Colores de marca usados en el PDF (espejo de `AppColors`).
class _Brand {
  static final primary = PdfColor.fromInt(0xFF32AE40);
  static final accent = PdfColor.fromInt(0xFFF7951A);
  static final foreground = PdfColor.fromInt(0xFF0F1F17);
  static final muted = PdfColor.fromInt(0xFFF4F4F5);
  static final mutedFg = PdfColor.fromInt(0xFF566159);
  static final border = PdfColor.fromInt(0xFFE5E7EB);
  static final destructive = PdfColor.fromInt(0xFFDC2626);
  static final warning = PdfColor.fromInt(0xFFF59E0B);
}

// Formato consistente con la app: "RD$ 13,000.00" (símbolo al inicio,
// coma de miles, punto decimal). Usamos patrón explícito con locale en_US
// porque `NumberFormat.currency('es_DO')` invierte ambos.
final _amount = NumberFormat('#,##0.00', 'en_US');
String _money(num n) => 'RD\$ ${_amount.format(n)}';

final _dateLong = DateFormat("d 'de' MMMM, yyyy", 'es');
final _dateShort = DateFormat('dd/MM/yyyy', 'es');

/// Genera los bytes de un PDF con la factura de membresía dada.
Future<Uint8List> buildInvoicePdf(MembershipInvoice invoice) async {
  final regular = await PdfGoogleFonts.dMSansRegular();
  final bold = await PdfGoogleFonts.dMSansBold();
  final medium = await PdfGoogleFonts.dMSansMedium();
  final display = await PdfGoogleFonts.spaceGroteskBold();
  final mono = await PdfGoogleFonts.jetBrainsMonoMedium();

  final doc = pw.Document(
    title: 'Factura ${invoice.invoiceNumber}',
    author: _Issuer.name,
    creator: 'MangoPOS Operator Console',
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 56),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(invoice, display: display, bold: bold, medium: medium),
          pw.SizedBox(height: 24),
          _customerAndPeriod(invoice, bold: bold, medium: medium, mono: mono),
          pw.SizedBox(height: 24),
          _amountTable(invoice, bold: bold, medium: medium, display: display),
          pw.SizedBox(height: 18),
          _paymentBlock(invoice, bold: bold, medium: medium, mono: mono),
          pw.Spacer(),
          _footer(bold: bold, medium: medium, mono: mono),
        ],
      ),
    ),
  );

  return doc.save();
}

/// Lanza el preview/impresión nativo del PDF generado.
Future<void> previewInvoicePdf(MembershipInvoice invoice) async {
  await Printing.layoutPdf(
    name: 'Factura_${invoice.invoiceNumber}',
    onLayout: (_) => buildInvoicePdf(invoice),
  );
}

/// Comparte el PDF (sheet del SO con WhatsApp, mail, drive, etc).
Future<void> shareInvoicePdf(MembershipInvoice invoice) async {
  final bytes = await buildInvoicePdf(invoice);
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'Factura_${invoice.invoiceNumber}.pdf',
  );
}

// ---------------------------------------------------------------------------
// Bloques de la factura
// ---------------------------------------------------------------------------

pw.Widget _header(
  MembershipInvoice inv, {
  required pw.Font display,
  required pw.Font bold,
  required pw.Font medium,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: _Brand.primary,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              'MangoPOS',
              style: pw.TextStyle(
                font: display,
                color: PdfColors.white,
                fontSize: 18,
                letterSpacing: -0.5,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            _Issuer.name,
            style: pw.TextStyle(font: bold, fontSize: 11),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'RNC ${_Issuer.rnc}',
            style: pw.TextStyle(
              font: medium,
              fontSize: 9,
              color: _Brand.mutedFg,
            ),
          ),
          pw.Text(
            _Issuer.address,
            style: pw.TextStyle(
              font: medium,
              fontSize: 9,
              color: _Brand.mutedFg,
            ),
          ),
        ],
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'FACTURA DE SERVICIOS',
            style: pw.TextStyle(
              font: bold,
              fontSize: 9,
              letterSpacing: 1.6,
              color: _Brand.accent,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            inv.invoiceNumber,
            style: pw.TextStyle(font: display, fontSize: 22),
          ),
          pw.SizedBox(height: 8),
          _statusPill(inv.status, bold: bold),
          pw.SizedBox(height: 14),
          _miniRow('Emisión', _dateLong.format(inv.issueDate),
              bold: bold, medium: medium),
          pw.SizedBox(height: 4),
          _miniRow('Vencimiento', _dateLong.format(inv.dueDate),
              bold: bold, medium: medium),
        ],
      ),
    ],
  );
}

pw.Widget _customerAndPeriod(
  MembershipInvoice inv, {
  required pw.Font bold,
  required pw.Font medium,
  required pw.Font mono,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _box(
          title: 'CLIENTE',
          bold: bold,
          children: [
            pw.Text(
              inv.businessName,
              style: pw.TextStyle(font: bold, fontSize: 13),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Plan ${inv.planType.toUpperCase()}',
              style: pw.TextStyle(
                font: medium,
                fontSize: 10,
                color: _Brand.mutedFg,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Expanded(
        child: _box(
          title: 'PERIODO FACTURADO',
          bold: bold,
          children: [
            pw.Text(
              '${_dateShort.format(inv.periodStart)} — '
              '${_dateShort.format(inv.periodEnd)}',
              style: pw.TextStyle(font: bold, fontSize: 12),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Servicio mensual de plataforma POS',
              style: pw.TextStyle(
                font: medium,
                fontSize: 10,
                color: _Brand.mutedFg,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _amountTable(
  MembershipInvoice inv, {
  required pw.Font bold,
  required pw.Font medium,
  required pw.Font display,
}) {
  pw.Widget row(String label, String value,
      {bool emphasis = false, bool isTotal = false}) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(
          horizontal: 14, vertical: isTotal ? 14 : 10),
      decoration: isTotal
          ? pw.BoxDecoration(color: _Brand.primary)
          : null,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: emphasis || isTotal ? bold : medium,
              fontSize: isTotal ? 13 : 11,
              color: isTotal ? PdfColors.white : _Brand.foreground,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: isTotal ? display : (emphasis ? bold : medium),
              fontSize: isTotal ? 16 : 11,
              color: isTotal ? PdfColors.white : _Brand.foreground,
            ),
          ),
        ],
      ),
    );
  }

  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _Brand.border),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(
            color: _Brand.muted,
            border: pw.Border(
              bottom: pw.BorderSide(color: _Brand.border),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'CONCEPTO',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 9,
                  letterSpacing: 1.4,
                  color: _Brand.mutedFg,
                ),
              ),
              pw.Text(
                'MONTO',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 9,
                  letterSpacing: 1.4,
                  color: _Brand.mutedFg,
                ),
              ),
            ],
          ),
        ),
        row('Membresía MangoPOS — Plan ${inv.planType.toUpperCase()}',
            _money(inv.amount)),
        pw.Divider(color: _Brand.border, height: 1),
        row('ITBIS (18%)', _money(inv.itbis)),
        row('TOTAL A PAGAR', _money(inv.total), isTotal: true),
      ],
    ),
  );
}

pw.Widget _paymentBlock(
  MembershipInvoice inv, {
  required pw.Font bold,
  required pw.Font medium,
  required pw.Font mono,
}) {
  if (inv.status == InvoiceStatus.paid) {
    return _box(
      title: 'PAGADA',
      bold: bold,
      borderColor: _Brand.primary,
      children: [
        pw.Text(
          'Recibida el ${inv.paidAt != null ? _dateLong.format(inv.paidAt!) : "—"}',
          style: pw.TextStyle(font: bold, fontSize: 11),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          [
            if (inv.paymentMethod != null) 'Método: ${inv.paymentMethod}',
            if (inv.paymentReference != null) 'Ref: ${inv.paymentReference}',
          ].join('  ·  '),
          style: pw.TextStyle(
              font: medium, fontSize: 10, color: _Brand.mutedFg),
        ),
      ],
    );
  }
  if (inv.status == InvoiceStatus.voided) {
    return _box(
      title: 'ANULADA',
      bold: bold,
      borderColor: _Brand.destructive,
      children: [
        pw.Text(
          'Esta factura fue anulada y no requiere pago.',
          style: pw.TextStyle(font: medium, fontSize: 10),
        ),
      ],
    );
  }

  // Pending o expired
  return _box(
    title: 'INSTRUCCIONES DE PAGO',
    bold: bold,
    borderColor: inv.status == InvoiceStatus.expired
        ? _Brand.destructive
        : _Brand.accent,
    children: [
      pw.Text(
        inv.status == InvoiceStatus.expired
            ? 'Factura vencida. Por favor regularizar a la brevedad para evitar interrupción del servicio.'
            : 'Vence el ${_dateLong.format(inv.dueDate)}.',
        style: pw.TextStyle(font: bold, fontSize: 11),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Métodos aceptados: transferencia bancaria, efectivo o tarjeta.\n'
        'Confirmar pago vía WhatsApp o email a ${_Issuer.email}.',
        style:
            pw.TextStyle(font: medium, fontSize: 10, color: _Brand.mutedFg),
      ),
    ],
  );
}

pw.Widget _footer({
  required pw.Font bold,
  required pw.Font medium,
  required pw.Font mono,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 14),
    decoration: pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _Brand.border)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _Issuer.website,
              style: pw.TextStyle(font: bold, fontSize: 10),
            ),
            pw.Text(
              _Issuer.email,
              style: pw.TextStyle(font: medium, fontSize: 9),
            ),
            pw.Text(
              _Issuer.phone,
              style: pw.TextStyle(font: mono, fontSize: 9),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Esta factura corresponde a servicios de plataforma SaaS prestados por MangoPOS '
          'al negocio identificado arriba. No constituye comprobante fiscal de la operación '
          'comercial del negocio con sus propios clientes.',
          style: pw.TextStyle(
            font: medium,
            fontSize: 8,
            color: _Brand.mutedFg,
            lineSpacing: 1.4,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Helpers visuales
// ---------------------------------------------------------------------------

pw.Widget _box({
  required String title,
  required pw.Font bold,
  required List<pw.Widget> children,
  PdfColor? borderColor,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: borderColor ?? _Brand.border),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: bold,
            fontSize: 9,
            letterSpacing: 1.4,
            color: _Brand.mutedFg,
          ),
        ),
        pw.SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

pw.Widget _statusPill(InvoiceStatus status, {required pw.Font bold}) {
  final (bg, fg, label) = switch (status) {
    InvoiceStatus.paid => (_Brand.primary, PdfColors.white, 'PAGADA'),
    InvoiceStatus.pending => (_Brand.warning, PdfColors.white, 'PENDIENTE'),
    InvoiceStatus.expired =>
      (_Brand.destructive, PdfColors.white, 'VENCIDA'),
    InvoiceStatus.voided => (_Brand.muted, _Brand.mutedFg, 'ANULADA'),
  };
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: pw.BoxDecoration(
      color: bg,
      borderRadius: pw.BorderRadius.circular(99),
    ),
    child: pw.Text(
      label,
      style: pw.TextStyle(
        font: bold,
        fontSize: 9,
        letterSpacing: 1.4,
        color: fg,
      ),
    ),
  );
}

pw.Widget _miniRow(String label, String value,
    {required pw.Font bold, required pw.Font medium}) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Text(
        '$label: ',
        style: pw.TextStyle(font: medium, fontSize: 9, color: _Brand.mutedFg),
      ),
      pw.Text(
        value,
        style: pw.TextStyle(font: bold, fontSize: 9.5),
      ),
    ],
  );
}
