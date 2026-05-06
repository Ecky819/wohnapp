import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/annual_statement.dart';
import '../../models/statement_position.dart';

/// Generates a legally-compliant Betriebskostenabrechnung PDF.
/// [imageBytes]: position label → list of image bytes for receipt attachments.
class StatementPdfGenerator {
  static final _currency =
      NumberFormat.currency(locale: 'de_DE', symbol: '€');
  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _pct = NumberFormat('##0.##', 'de_DE');

  static Future<Uint8List> generate(
    AnnualStatement stmt, {
    String orgName = '',
    Map<String, List<Uint8List>> imageBytes = const {},
  }) async {
    final ttf = await PdfGoogleFonts.notoSansRegular();
    final ttfBold = await PdfGoogleFonts.notoSansBold();
    final ttfItalic = await PdfGoogleFonts.notoSansItalic();

    final theme = pw.ThemeData.withFont(
      base: ttf,
      bold: ttfBold,
      italic: ttfItalic,
    );

    final doc = pw.Document(theme: theme);

    // ── Page 1: Abrechnung ─────────────────────────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (_) => _buildHeader(stmt, orgName),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          _buildAddressBlock(stmt),
          pw.SizedBox(height: 24),
          _buildTitle(stmt),
          pw.SizedBox(height: 16),
          _buildPositionsTable(stmt),
          pw.SizedBox(height: 16),
          _buildSummaryBox(stmt),
          pw.SizedBox(height: 24),
          _buildLegalNote(stmt),
        ],
      ),
    );

    // ── Pages 2+: Belegbilder ──────────────────────────────────────────────────
    for (final pos in stmt.positions) {
      final imgs = imageBytes[pos.label] ?? [];
      if (imgs.isEmpty) continue;
      for (int i = 0; i < imgs.length; i++) {
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(40),
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Anlage: ${pos.label}${imgs.length > 1 ? ' (${i + 1}/${imgs.length})' : ''}',
                  style: pw.TextStyle(
                      font: ttfBold, fontSize: 11),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Abrechnung ${stmt.year} · ${stmt.recipientName} · ${stmt.unitName}',
                  style: pw.TextStyle(
                      font: ttfItalic,
                      fontSize: 9,
                      color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 12),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Image(
                      pw.MemoryImage(imgs[i]),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return doc.save();
  }

  // ── Helper widgets ──────────────────────────────────────────────────────────

  static pw.Widget _buildHeader(AnnualStatement stmt, String orgName) =>
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              orgName.isNotEmpty ? orgName : 'Hausverwaltung',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Text(
              'Betriebskostenabrechnung ${stmt.year}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      );

  static pw.Widget _buildFooter(pw.Context ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Gemäß § 556 BGB ist diese Abrechnung rechtlich bindend.',
              style:
                  pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
            pw.Text(
              'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
              style:
                  pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ],
        ),
      );

  static pw.Widget _buildAddressBlock(AnnualStatement stmt) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('An:', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                pw.SizedBox(height: 2),
                pw.Text(stmt.recipientName,
                    style: pw.TextStyle(fontSize: 11)),
                if (stmt.unitName.isNotEmpty)
                  pw.Text(stmt.unitName,
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Erstellt am ${_dateFmt.format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ],
      );

  static pw.Widget _buildTitle(AnnualStatement stmt) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Betriebskostenabrechnung ${stmt.year}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Abrechnungszeitraum: ${_dateFmt.format(stmt.periodStart)} – ${_dateFmt.format(stmt.periodEnd)}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      );

  static pw.Widget _buildPositionsTable(AnnualStatement stmt) {
    final rows = stmt.positions.map((p) => [
          p.label,
          _currency.format(p.totalCost),
          p.distributionKey.label,
          '${_pct.format(p.tenantPercent)} %',
          _currency.format(p.tenantAmount),
        ]).toList();

    return pw.TableHelper.fromTextArray(
      headers: [
        'Kostenart',
        'Gesamtkosten',
        'Umlageschlüssel',
        'Ihr Anteil',
        'Betrag',
      ],
      data: rows,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: pw.TextStyle(fontSize: 9),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.centerRight,
      },
      cellHeight: 20,
    );
  }

  static pw.Widget _buildSummaryBox(AnnualStatement stmt) {
    final isNachzahlung = stmt.balance > 0;

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: isNachzahlung
            ? PdfColors.orange50
            : PdfColors.green50,
        border: pw.Border.all(
          color: isNachzahlung ? PdfColors.orange300 : PdfColors.green300,
          width: 0.8,
        ),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _summaryRow('Summe Betriebskosten (Ihr Anteil)',
              _currency.format(stmt.totalTenantCosts)),
          pw.Divider(color: PdfColors.grey400, height: 12),
          _summaryRow('Ihre Vorauszahlungen',
              '– ${_currency.format(stmt.advancePayments)}'),
          pw.SizedBox(height: 6),
          _summaryRow(
            isNachzahlung ? 'Nachzahlung' : 'Rückerstattung',
            _currency.format(stmt.balance.abs()),
            bold: true,
            color: isNachzahlung ? PdfColors.red700 : PdfColors.green700,
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    PdfColor color = PdfColors.black,
  }) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      );

  static pw.Widget _buildLegalNote(AnnualStatement stmt) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Rechtliche Hinweise',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '• Gemäß § 556 Abs. 3 BGB ist diese Abrechnung innerhalb von 12 Monaten '
              'nach Ende des Abrechnungszeitraums zu erteilen.\n'
              '• ${isNachzahlung(stmt) ? 'Der Nachzahlungsbetrag ist innerhalb von 30 Tagen '
                  'nach Zugang dieser Abrechnung fällig.' : 'Der Rückerstattungsbetrag wird '
                  'innerhalb von 30 Tagen auf Ihr Konto überwiesen.'}\n'
              '• Die Belege zu den Einzelpositionen sind als Anlage beigefügt. '
              'Sie haben das Recht, die Originalbelege einzusehen (§ 259 BGB).',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      );

  static bool isNachzahlung(AnnualStatement stmt) => stmt.balance > 0;
}
