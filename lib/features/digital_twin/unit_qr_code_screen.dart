import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/unit.dart';

/// Displays and allows sharing/printing of a QR code for a unit.
/// The QR encodes:  wohnapp://report?unitId=ID&tenantId=TID&unitName=NAME
class UnitQrCodeScreen extends StatelessWidget {
  const UnitQrCodeScreen({super.key, required this.unit});
  final Unit unit;

  String get _qrData =>
      'wohnapp://report?unitId=${unit.id}'
      '&tenantId=${unit.tenantId}'
      '&unitName=${Uri.encodeComponent(unit.displayName)}';

  Future<void> _print(BuildContext context) async {
    final qrImage = await QrPainter(
      data: _qrData,
      version: QrVersions.auto,
    ).toImageData(512);

    if (qrImage == null) return;

    final doc = pw.Document();
    final image = pw.MemoryImage(qrImage.buffer.asUint8List());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'Schaden melden',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              unit.displayName,
              style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 24),
            pw.Image(image, width: 200, height: 200),
            pw.SizedBox(height: 24),
            pw.Text(
              'QR-Code mit der Wohnapp scannen\num einen Schaden zu melden.',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'QR_${unit.displayName.replaceAll(' ', '_')}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR-Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Drucken / Teilen',
            onPressed: () => _print(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Unit name ──────────────────────────────────────────────
            Text(
              unit.displayName,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Mieter können mit diesem Code\neinen Schaden melden – ohne Login.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 32),

            // ── QR code ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrData,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 32),

            // ── Print/Share button ─────────────────────────────────────
            FilledButton.icon(
              icon: const Icon(Icons.print_outlined),
              label: const Text('Drucken / Als PDF teilen'),
              onPressed: () => _print(context),
            ),

            const SizedBox(height: 12),

            // ── QR data hint ───────────────────────────────────────────
            Text(
              'Wohnungs-ID: ${unit.id}',
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ],
        ),
      ),
    );
  }
}
