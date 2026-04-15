import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/ticket.dart';
import '../../ticket_provider.dart';

class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  static final _fmt = DateFormat('dd.MM.yyyy');

  // ── CSV ─────────────────────────────────────────────────────────────────────

  static String _buildCsv(List<Ticket> tickets) {
    final rows = <List<dynamic>>[
      [
        'ID', 'Titel', 'Kategorie', 'Status',
        'Priorität', 'Wohnung', 'Erstellt', 'Erledigt'
      ],
      ...tickets.map((t) => [
            t.id,
            t.title,
            t.categoryLabel,
            t.statusLabel,
            t.priority == 'high' ? 'Hoch' : 'Normal',
            t.unitName ?? '–',
            t.createdAt != null ? _fmt.format(t.createdAt!) : '–',
            t.closedAt != null ? _fmt.format(t.closedAt!) : '–',
          ]),
    ];
    return const ListToCsvConverter().convert(rows);
  }

  // ── PDF ─────────────────────────────────────────────────────────────────────

  static Future<pw.Document> _buildPdf(List<Ticket> tickets) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Ticket-Übersicht',
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            'Exportiert am ${_fmt.format(DateTime.now())}'
            '  ·  ${tickets.length} Tickets',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Titel', 'Typ', 'Status', 'Wohnung', 'Erstellt'],
            data: tickets
                .map((t) => [
                      t.title,
                      t.categoryLabel,
                      t.statusLabel,
                      t.unitName ?? '–',
                      t.createdAt != null
                          ? _fmt.format(t.createdAt!)
                          : '–',
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellHeight: 22,
          ),
        ],
      ),
    );

    return doc;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(allTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ticketsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tickets) => _ExportBody(tickets: tickets),
      ),
    );
  }
}

// ─── Body ────────────────────────────────────────────────────────────────────

class _ExportBody extends StatefulWidget {
  const _ExportBody({required this.tickets});
  final List<Ticket> tickets;

  @override
  State<_ExportBody> createState() => _ExportBodyState();
}

class _ExportBodyState extends State<_ExportBody> {
  String _filter = 'all';
  bool _exporting = false;

  List<Ticket> get _filtered {
    if (_filter == 'all') return widget.tickets;
    return widget.tickets.where((t) => t.category == _filter).toList();
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = ExportScreen._buildCsv(_filtered);
      final bytes = Uint8List.fromList(csv.codeUnits);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'tickets_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final doc = await ExportScreen._buildPdf(_filtered);
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'tickets_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');
    final tickets = _filtered;

    return Column(
      children: [
        // ── Filter bar ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('Kategorie:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Alle')),
                  DropdownMenuItem(
                      value: 'damage', child: Text('Schäden')),
                  DropdownMenuItem(
                      value: 'maintenance', child: Text('Wartungen')),
                ],
                onChanged: (v) => setState(() => _filter = v ?? 'all'),
              ),
              const Spacer(),
              Text('${tickets.length} Tickets',
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),

        // ── Preview list ──────────────────────────────────────────────
        Expanded(
          child: tickets.isEmpty
              ? const Center(
                  child: Text('Keine Tickets',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: tickets.length,
                  itemBuilder: (_, i) {
                    final t = tickets[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(t.categoryIcon, size: 18),
                      title: Text(t.title,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${t.statusLabel}'
                        '${t.unitName != null ? ' · ${t.unitName}' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        t.createdAt != null ? fmt.format(t.createdAt!) : '–',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    );
                  },
                ),
        ),

        // ── Export buttons ────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _exporting
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.table_chart_outlined),
                          label: const Text('CSV'),
                          onPressed: _exportCsv,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('PDF'),
                          onPressed: _exportPdf,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
