import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/invoice.dart';
import '../../models/ticket.dart';
import '../../repositories/invoice_repository.dart';
import '../../ticket_provider.dart';
import '../../user_provider.dart';

class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Export'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.confirmation_number_outlined), text: 'Tickets'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Rechnungen'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TicketExportTab(),
            _InvoiceExportTab(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — Tickets
// ═══════════════════════════════════════════════════════════════════════════════

class _TicketExportTab extends ConsumerWidget {
  const _TicketExportTab();

  static final _fmt = DateFormat('dd.MM.yyyy');

  static String _buildCsv(List<Ticket> tickets) {
    final rows = <List<dynamic>>[
      ['ID', 'Titel', 'Kategorie', 'Status', 'Priorität', 'Wohnung', 'Erstellt', 'Erledigt'],
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

  static Future<pw.Document> _buildPdf(List<Ticket> tickets) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('Ticket-Übersicht',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text(
            'Exportiert am ${_fmt.format(DateTime.now())}  ·  ${tickets.length} Tickets',
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
                      t.createdAt != null ? _fmt.format(t.createdAt!) : '–',
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellHeight: 22,
          ),
        ],
      ),
    );
    return doc;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(allTicketsProvider);
    return ticketsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (tickets) => _TicketExportBody(
        tickets: tickets,
        buildCsv: _buildCsv,
        buildPdf: _buildPdf,
      ),
    );
  }
}

class _TicketExportBody extends StatefulWidget {
  const _TicketExportBody({
    required this.tickets,
    required this.buildCsv,
    required this.buildPdf,
  });
  final List<Ticket> tickets;
  final String Function(List<Ticket>) buildCsv;
  final Future<pw.Document> Function(List<Ticket>) buildPdf;

  @override
  State<_TicketExportBody> createState() => _TicketExportBodyState();
}

class _TicketExportBodyState extends State<_TicketExportBody> {
  String _filter = 'all';
  bool _exporting = false;

  List<Ticket> get _filtered {
    if (_filter == 'all') return widget.tickets;
    return widget.tickets.where((t) => t.category == _filter).toList();
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = widget.buildCsv(_filtered);
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
      final doc = await widget.buildPdf(_filtered);
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
                  DropdownMenuItem(value: 'damage', child: Text('Schäden')),
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

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — Rechnungen / DATEV-CSV
// ═══════════════════════════════════════════════════════════════════════════════

class _InvoiceExportTab extends ConsumerStatefulWidget {
  const _InvoiceExportTab();

  @override
  ConsumerState<_InvoiceExportTab> createState() => _InvoiceExportTabState();
}

class _InvoiceExportTabState extends ConsumerState<_InvoiceExportTab> {
  DateTime? _from;
  DateTime? _to;
  bool _exporting = false;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _datevFmt = DateFormat('ddMMyyyy'); // DATEV date format

  // ── DATEV Buchungsstapel CSV ────────────────────────────────────────────────
  //
  // Simplified DATEV format (Buchungsstapel):
  // Umsatz (Betrag), Soll/Haben-Kennzeichen, WKZ Umsatz, Kurs, Basis-Umsatz,
  // WKZ Basis-Umsatz, Konto, Gegenkonto (ohne BU-Schlüssel), BU-Schlüssel,
  // Belegdatum, Belegfeld 1, Belegfeld 2, Skonto, Buchungstext
  static String _buildDatevCsv(List<Invoice> invoices) {
    // DATEV header line (simplified, without full DATEV preamble)
    final rows = <List<dynamic>>[
      [
        'Umsatz (netto)',
        'Soll/Haben',
        'WKZ',
        'Kurs',
        'Basis-Umsatz',
        'WKZ Basis',
        'Konto',
        'Gegenkonto',
        'BU-Schlüssel',
        'Belegdatum',
        'Belegfeld 1',
        'Buchungstext',
      ],
      ...invoices.map((inv) => [
            inv.amount.toStringAsFixed(2).replaceAll('.', ','),
            'S', // Soll (Aufwand)
            'EUR',
            '', // Kurs (nur Fremdwährung)
            '', // Basis-Umsatz
            '',
            '6300', // Instandhaltung/Reparaturen (Beispielkonto)
            '1600', // Verbindlichkeiten gegenüber Handwerkern
            '', // BU-Schlüssel (leer = Standard-Steuerschlüssel)
            inv.createdAt != null ? _datevFmt.format(inv.createdAt!) : '',
            inv.id.substring(0, inv.id.length.clamp(0, 12)), // Belegfeld 1 (max 12 Zeichen)
            '${inv.ticketTitle} – ${inv.contractorName}',
          ]),
    ];
    return const ListToCsvConverter(
      fieldDelimiter: ';',
      textDelimiter: '"',
      eol: '\r\n',
    ).convert(rows);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_from ?? DateTime(now.year, 1, 1)) : (_to ?? now),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _export(List<Invoice> invoices) async {
    if (invoices.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final csv = _buildDatevCsv(invoices);
      final bytes = Uint8List.fromList(csv.codeUnits);
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'datev_rechnungen_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      // Mark all exported invoices as 'exported'
      await ref
          .read(invoiceRepositoryProvider)
          .markExported(invoices.map((i) => i.id).toList());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantId =
        ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';

    return Column(
      children: [
        // ── Date range filter ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    _from != null ? _dateFmt.format(_from!) : 'Von',
                    style: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () => _pickDate(isFrom: true),
                ),
              ),
              const SizedBox(width: 8),
              const Text('–'),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    _to != null ? _dateFmt.format(_to!) : 'Bis',
                    style: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () => _pickDate(isFrom: false),
                ),
              ),
              if (_from != null || _to != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Filter zurücksetzen',
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                ),
            ],
          ),
        ),

        // ── Invoice list ───────────────────────────────────────────────
        if (tenantId.isNotEmpty)
          Expanded(
            child: _InvoiceList(
              tenantId: tenantId,
              from: _from,
              to: _to,
              exporting: _exporting,
              onExport: _export,
            ),
          )
        else
          const Expanded(
            child: Center(child: Text('Nicht angemeldet.')),
          ),
      ],
    );
  }
}

class _InvoiceList extends ConsumerWidget {
  const _InvoiceList({
    required this.tenantId,
    required this.from,
    required this.to,
    required this.exporting,
    required this.onExport,
  });

  final String tenantId;
  final DateTime? from;
  final DateTime? to;
  final bool exporting;
  final Future<void> Function(List<Invoice>) onExport;

  static final _fmt = DateFormat('dd.MM.yy');
  static final _currency =
      NumberFormat.currency(locale: 'de_DE', symbol: '€');

  List<Invoice> _filterInvoices(List<Invoice> all) {
    return all.where((inv) {
      if (inv.createdAt == null) return true;
      if (from != null && inv.createdAt!.isBefore(from!)) return false;
      if (to != null &&
          inv.createdAt!.isAfter(to!.add(const Duration(days: 1)))) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAsync = ref.watch(
      StreamProvider<List<Invoice>>((ref) =>
          ref.read(invoiceRepositoryProvider).watchAll(tenantId)),
    );

    return allAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (all) {
        final invoices = _filterInvoices(all);
        final exportable = invoices
            .where((i) =>
                i.status == InvoiceStatus.approved ||
                i.status == InvoiceStatus.exported)
            .toList();
        final total =
            exportable.fold<double>(0, (sum, i) => sum + i.amount);

        return Column(
          children: [
            // Summary row
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('${invoices.length} Rechnungen',
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13)),
                  const Spacer(),
                  Text(
                    'Gesamt: ${_currency.format(total)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),

            // List
            Expanded(
              child: invoices.isEmpty
                  ? const Center(
                      child: Text('Keine Rechnungen im Zeitraum.',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: invoices.length,
                      itemBuilder: (_, i) {
                        final inv = invoices[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.receipt_outlined,
                            size: 18,
                            color: inv.status == InvoiceStatus.approved ||
                                    inv.status == InvoiceStatus.exported
                                ? Colors.green
                                : inv.status == InvoiceStatus.rejected
                                    ? Colors.red
                                    : Colors.orange,
                          ),
                          title: Text(inv.contractorName,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(inv.ticketTitle,
                              style: const TextStyle(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                inv.amount > 0
                                    ? _currency.format(inv.amount)
                                    : '–',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12),
                              ),
                              Text(
                                inv.createdAt != null
                                    ? _fmt.format(inv.createdAt!)
                                    : '–',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Export button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: exporting
                    ? const Center(child: CircularProgressIndicator())
                    : FilledButton.icon(
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          exportable.isEmpty
                              ? 'DATEV-CSV exportieren'
                              : 'DATEV-CSV (${exportable.length}) exportieren',
                        ),
                        onPressed: exportable.isEmpty
                            ? null
                            : () => onExport(exportable),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
