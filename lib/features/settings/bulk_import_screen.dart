import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/invitation.dart';
import '../../models/rental_agreement.dart';
import '../../repositories/building_repository.dart';
import '../../repositories/invitation_repository.dart';
import '../../repositories/rental_agreement_repository.dart';
import '../../user_provider.dart';

// ─── CSV templates ────────────────────────────────────────────────────────────

const _unitsCsvTemplate =
    'Gebäude;Adresse;Wohnungsname;Etage;Fläche (m²);Zimmer;Baujahr\n'
    'Musterstraße 1;Musterstraße 1, 12345 Stadt;Wohnung 01;EG;52.5;2;1972\n'
    'Musterstraße 1;Musterstraße 1, 12345 Stadt;Wohnung 02;1;68;3;1972\n'
    'Gartenweg 4;Gartenweg 4, 12345 Stadt;App. A;1;45;;';

const _invitesCsvTemplate =
    'Name;E-Mail;Rolle;Gebäude;Wohnung\n'
    'Max Mustermann;max@example.com;Mieter;Musterstraße 1;Wohnung 01\n'
    'Lieschen Müller;lieschen@example.com;Mieter;Gartenweg 4;App. A\n'
    'Hans Handwerker;hans@example.com;Handwerker;;';

const _agreementsCsvTemplate =
    'Name;E-Mail;Gebäude;Wohnung;Mietbeginn;Mietende;Kaltmiete;Kaution\n'
    'Max Mustermann;max@example.com;Musterstraße 1;Wohnung 01;01.01.2024;;850;2550\n'
    'Anna Schmidt;anna@example.com;Gartenweg 4;App. A;15.03.2023;31.12.2025;720;2160\n'
    'Peter Meier;peter@example.com;Musterstraße 1;Wohnung 02;01.06.2022;;;';

// ─── Screen ───────────────────────────────────────────────────────────────────

class BulkImportScreen extends ConsumerWidget {
  const BulkImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bulk-Import'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.apartment_outlined), text: 'Wohnungen'),
              Tab(icon: Icon(Icons.description_outlined), text: 'Mietverträge'),
              Tab(icon: Icon(Icons.group_add_outlined), text: 'Einladungen'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _UnitsImportTab(),
            _AgreementsImportTab(),
            _InvitesImportTab(),
          ],
        ),
      ),
    );
  }
}

// ─── Gemeinsamer Bestätigungsdialog vor jedem Import ─────────────────────────

Future<bool> _confirmImport(
  BuildContext context, {
  required int count,
  required String label,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Import bestätigen'),
      content: Text(
        '$count $label werden importiert. '
        'Dieser Vorgang kann nicht rückgängig gemacht werden.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Importieren'),
        ),
      ],
    ),
  );
  return result == true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — Wohnungen
// ═══════════════════════════════════════════════════════════════════════════════

class _UnitsImportTab extends ConsumerStatefulWidget {
  const _UnitsImportTab();

  @override
  ConsumerState<_UnitsImportTab> createState() => _UnitsImportTabState();
}

class _UnitsImportTabState extends ConsumerState<_UnitsImportTab> {
  List<_UnitRow>? _rows;
  String? _error;
  bool _importing = false;
  // Progress tracking for batch writes
  int _done = 0;
  int _total = 0;

  // ── Parse ──────────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _rows = null;
      _done = 0;
      _total = 0;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    try {
      // Try UTF-8 first; fall back to Latin-1 (common in Windows/ERP exports)
      String content;
      try {
        content = utf8.decode(result.files.single.bytes!);
      } catch (_) {
        content = latin1.decode(result.files.single.bytes!);
      }

      final rows = const CsvToListConverter(
        fieldDelimiter: ';',
        eol: '\n',
      ).convert(content);

      final data = rows.skip(1).where((r) => r.length >= 3).toList();
      if (data.isEmpty) {
        throw const FormatException('Keine Datenzeilen gefunden.');
      }

      final parsed = data
          .map((r) => _UnitRow.fromCsvRow(r))
          .where((row) =>
              row.buildingName.isNotEmpty && row.unitName.isNotEmpty)
          .toList();

      if (parsed.isEmpty) {
        throw const FormatException(
            'Alle Zeilen haben leere Gebäude- oder Wohnungsnamen.');
      }

      setState(() => _rows = parsed);
    } catch (e) {
      setState(() => _error = 'Fehler beim Einlesen: $e');
    }
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;

    final tenantId =
        ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
    if (tenantId.isEmpty) return;

    final buildingCount = rows.map((r) => r.buildingName).toSet().length;
    final confirmed = await _confirmImport(
      context,
      count: rows.length,
      label: 'Wohnungen in $buildingCount Gebäude(n)',
    );
    if (!confirmed) return;

    // Group rows by building name → deduplicate buildings
    final buildingMap = <String, _BuildingAccumulator>{};
    for (final row in rows) {
      buildingMap.putIfAbsent(
        row.buildingName,
        () => _BuildingAccumulator(
          name: row.buildingName,
          address: row.buildingAddress.isNotEmpty
              ? row.buildingAddress
              : row.buildingName,
        ),
      ).addUnit(row);
    }

    final importBuildings = buildingMap.values
        .map((b) => ImportBuilding(
              key: b.name,
              name: b.name,
              address: b.address,
              units: b.units
                  .map((u) => ImportUnit(
                        name: u.unitName,
                        floor: u.floor,
                        area: u.area,
                        rooms: u.rooms,
                        buildYear: u.buildYear,
                      ))
                  .toList(),
            ))
        .toList();

    final totalOps =
        importBuildings.length +
        importBuildings.fold<int>(0, (s, b) => s + b.units.length);

    setState(() {
      _importing = true;
      _done = 0;
      _total = totalOps;
    });

    try {
      final repo = ref.read(buildingRepositoryProvider);
      final unitCount = await repo.batchImport(
        buildings: importBuildings,
        tenantId: tenantId,
        onProgress: (done, total) {
          if (mounted) setState(() => _done = done);
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$unitCount Wohnungen in '
              '${importBuildings.length} Gebäuden importiert.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _rows = null);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Import fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final buildingCount = rows == null
        ? 0
        : rows.map((r) => r.buildingName).toSet().length;

    return Column(
      children: [
        const _CsvFormatHint(
          title:
              'Format: Gebäude;Adresse;Wohnungsname;Etage;Fläche (m²);Zimmer;Baujahr',
          template: _unitsCsvTemplate,
        ),
        if (_error != null) _ErrorBanner(message: _error!),
        if (rows != null) ...[
          _ImportSummaryHeader(
            unitCount: rows.length,
            buildingCount: buildingCount,
            importing: _importing,
            done: _done,
            total: _total,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.apartment_outlined, size: 18),
                  title: Text(
                    '${r.buildingName} › ${r.unitName}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: r.buildingAddress.isNotEmpty
                      ? Text(r.buildingAddress,
                          style: const TextStyle(fontSize: 11))
                      : null,
                  trailing: _UnitDetailChip(row: r),
                );
              },
            ),
          ),
        ] else
          const Expanded(
            child: Center(
              child: Text(
                'Noch keine CSV geladen.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _importing
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: _total > 0 ? _done / _total : null,
                      ),
                      const SizedBox(height: 8),
                      Text('$_done / $_total Schreibvorgänge…'),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('CSV auswählen'),
                          onPressed: _pickFile,
                        ),
                      ),
                      if (rows != null && rows.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.download_done_outlined),
                            label: Text(
                              '${rows.length} Wohnungen importieren',
                            ),
                            onPressed: _import,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class _UnitRow {
  const _UnitRow({
    required this.buildingName,
    required this.buildingAddress,
    required this.unitName,
    this.floor,
    this.area,
    this.rooms,
    this.buildYear,
  });

  final String buildingName;
  final String buildingAddress;
  final String unitName;
  final int? floor;      // Etage (numeric; "EG" → 0)
  final double? area;    // m²
  final int? rooms;      // Zimmer
  final int? buildYear;  // Baujahr

  factory _UnitRow.fromCsvRow(List<dynamic> r) {
    final area = r.length > 4 ? _parseDouble(r[4].toString()) : null;
    final year = r.length > 6 ? int.tryParse(r[6].toString().trim()) : null;
    return _UnitRow(
      buildingName: _clip(r[0].toString(), 100),
      buildingAddress: r.length > 1 ? _clip(r[1].toString(), 200) : '',
      unitName: r.length > 2 ? _clip(r[2].toString(), 100) : '',
      floor: r.length > 3 ? _parseFloor(r[3].toString()) : null,
      area: (area != null && area > 0) ? area : null,
      rooms: r.length > 5 ? int.tryParse(r[5].toString().trim()) : null,
      buildYear: (year != null && year >= 1800 && year <= 2100) ? year : null,
    );
  }

  static String _clip(String s, int max) {
    final t = s.trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  static int? _parseFloor(String s) {
    final t = s.trim().toUpperCase();
    if (t == 'EG' || t == '0' || t == 'G') return 0;
    if (t == 'KG' || t == 'UG' || t == '-1') return -1;
    return int.tryParse(t);
  }

  static double? _parseDouble(String s) {
    if (s.trim().isEmpty) return null;
    // Accept both "68.5" (en) and "68,5" (de)
    return double.tryParse(s.trim().replaceAll(',', '.'));
  }
}

class _BuildingAccumulator {
  _BuildingAccumulator({required this.name, required this.address});
  final String name;
  final String address;
  final List<_UnitRow> units = [];
  void addUnit(_UnitRow u) => units.add(u);
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _ImportSummaryHeader extends StatelessWidget {
  const _ImportSummaryHeader({
    required this.unitCount,
    required this.buildingCount,
    required this.importing,
    required this.done,
    required this.total,
  });
  final int unitCount;
  final int buildingCount;
  final bool importing;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$unitCount Wohnungen in $buildingCount Gebäuden',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          const Spacer(),
          if (importing)
            Text(
              '$done/$total geschrieben',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}

class _UnitDetailChip extends StatelessWidget {
  const _UnitDetailChip({required this.row});
  final _UnitRow row;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (row.floor != null) {
      parts.add(row.floor == 0 ? 'EG' : '${row.floor}. OG');
    }
    if (row.rooms != null) parts.add('${row.rooms} Zi.');
    if (row.area != null) parts.add('${row.area!.toStringAsFixed(0)} m²');
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: const TextStyle(fontSize: 11, color: Colors.grey),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — Mietverhältnisse
// ═══════════════════════════════════════════════════════════════════════════════

class _AgreementsImportTab extends ConsumerStatefulWidget {
  const _AgreementsImportTab();

  @override
  ConsumerState<_AgreementsImportTab> createState() =>
      _AgreementsImportTabState();
}

class _AgreementsImportTabState
    extends ConsumerState<_AgreementsImportTab> {
  List<_AgreementRow>? _rows;
  String? _error;
  bool _importing = false;
  int _done = 0;
  int _total = 0;
  final _importErrors = <String>[];
  final _failedRows  = <_AgreementRow>[];

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _rows = null;
      _done = 0;
      _total = 0;
      _importErrors.clear();
      _failedRows.clear();
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    try {
      String content;
      try {
        content = utf8.decode(result.files.single.bytes!);
      } catch (_) {
        content = latin1.decode(result.files.single.bytes!);
      }

      final rows = const CsvToListConverter(
        fieldDelimiter: ';',
        eol: '\n',
      ).convert(content);

      final data = rows.skip(1).where((r) => r.length >= 4).toList();
      if (data.isEmpty) {
        throw const FormatException('Keine Datenzeilen gefunden.');
      }

      final parsed = data
          .map(_AgreementRow.fromCsvRow)
          .where((r) => r.name.isNotEmpty && r.buildingName.isNotEmpty && r.unitName.isNotEmpty)
          .toList();

      if (parsed.isEmpty) {
        throw const FormatException('Alle Zeilen fehlen Name, Gebäude oder Wohnung.');
      }

      setState(() => _rows = parsed);
    } catch (e) {
      setState(() => _error = 'Fehler beim Einlesen: $e');
    }
  }

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;

    final tenantId =
        ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
    if (tenantId.isEmpty) return;

    final confirmed = await _confirmImport(
      context,
      count: rows.length,
      label: 'Mietverhältnisse',
    );
    if (!confirmed) return;

    setState(() {
      _importing = true;
      _done = 0;
      _total = rows.length;
      _importErrors.clear();
      _failedRows.clear();
    });

    try {
      // Load all buildings + units for matching
      final buildings = await ref
          .read(buildingRepositoryProvider)
          .watchBuildings(tenantId)
          .first;

      final buildingByName = <String, dynamic>{
        for (final b in buildings) b.name.toLowerCase().trim(): b,
      };

      final unitsByBuilding = <String, List<dynamic>>{};
      for (final b in buildings) {
        final units = await ref
            .read(buildingRepositoryProvider)
            .watchUnits(b.id, tenantId)
            .first;
        unitsByBuilding[b.id] = units;
      }

      final agreements = <RentalAgreement>[];
      final errors = <String>[];

      for (final row in rows) {
        final building =
            buildingByName[row.buildingName.toLowerCase().trim()];
        if (building == null) {
          errors.add('Gebäude nicht gefunden: "${row.buildingName}"');
          _failedRows.add(row);
          continue;
        }

        final units = unitsByBuilding[building.id] ?? [];
        final unit = units.cast<dynamic>().firstWhere(
              (u) =>
                  (u.name as String).toLowerCase().trim() ==
                  row.unitName.toLowerCase().trim(),
              orElse: () => null,
            );
        if (unit == null) {
          errors.add(
              'Wohnung nicht gefunden: "${row.unitName}" in "${row.buildingName}"');
          _failedRows.add(row);
          continue;
        }

        agreements.add(RentalAgreement(
          id: '',
          tenantId: tenantId,
          tenantName: row.name,
          tenantEmail: row.email,
          unitId: unit.id as String,
          unitName: unit.name as String,
          buildingId: building.id as String,
          buildingName: building.name as String,
          startDate: row.startDate ?? DateTime.now(),
          endDate: row.endDate,
          monthlyRent: row.monthlyRent,
          deposit: row.deposit,
          status: 'active',
          createdAt: DateTime.now(),
        ));
      }

      if (agreements.isNotEmpty) {
        await ref.read(rentalAgreementRepositoryProvider).batchCreate(
          agreements,
          onProgress: (done, total) {
            if (mounted) setState(() => _done = done);
          },
        );
      }

      setState(() => _importErrors.addAll(errors));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${agreements.length} Mietverhältnisse importiert'
              '${errors.isNotEmpty ? ', ${errors.length} übersprungen' : ''}.',
            ),
            backgroundColor:
                errors.isEmpty ? Colors.green : Colors.orange,
          ),
        );
        if (errors.isEmpty) setState(() => _rows = null);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Import fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _exportFailedRows() {
    if (_failedRows.isEmpty) return;
    final df = DateFormat('dd.MM.yyyy');
    final buf = StringBuffer(
        'Name;E-Mail;Gebäude;Wohnung;Mietbeginn;Mietende;Kaltmiete;Kaution\n');
    for (final r in _failedRows) {
      buf.writeln([
        r.name,
        r.email,
        r.buildingName,
        r.unitName,
        r.startDate != null ? df.format(r.startDate!) : '',
        r.endDate   != null ? df.format(r.endDate!)   : '',
        r.monthlyRent?.toStringAsFixed(2) ?? '',
        r.deposit?.toStringAsFixed(2)     ?? '',
      ].join(';'));
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${_failedRows.length} fehlerhafte Zeile(n) in Zwischenablage kopiert')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(
      children: [
        const _CsvFormatHint(
          title:
              'Format: Name;E-Mail;Gebäude;Wohnung;Mietbeginn;Mietende;Kaltmiete;Kaution',
          template: _agreementsCsvTemplate,
        ),
        if (_error != null) _ErrorBanner(message: _error!),
        if (_importErrors.isNotEmpty)
          Builder(
            builder: (context) => Container(
              color: Color.alphaBlend(
                Colors.orange.withValues(alpha: 0.1),
                Theme.of(context).colorScheme.surface,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_importErrors.length} Zeilen übersprungen:',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.copy_outlined, size: 14),
                        label: const Text('CSV kopieren',
                            style: TextStyle(fontSize: 12)),
                        onPressed: _exportFailedRows,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ..._importErrors.map((e) => Text(e,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.orange))),
                ],
              ),
            ),
          ),
        if (rows != null) ...[
          _PreviewHeader(
            count: rows.length,
            label: 'Mietverhältnisse',
            importing: _importing,
            imported: _done,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined, size: 18),
                  title: Text(r.name,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    '${r.buildingName} › ${r.unitName}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: r.monthlyRent != null
                      ? Text('${r.monthlyRent!.toStringAsFixed(0)} €',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey))
                      : null,
                );
              },
            ),
          ),
        ] else
          const Expanded(
            child: Center(
              child: Text('Noch keine CSV geladen.',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _importing
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: _total > 0 ? _done / _total : null,
                      ),
                      const SizedBox(height: 8),
                      Text('$_done / $_total importiert…'),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('CSV auswählen'),
                          onPressed: _pickFile,
                        ),
                      ),
                      if (rows != null && rows.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.download_done_outlined),
                            label: Text('${rows.length} importieren'),
                            onPressed: _import,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── Agreement data class ─────────────────────────────────────────────────────

class _AgreementRow {
  const _AgreementRow({
    required this.name,
    required this.email,
    required this.buildingName,
    required this.unitName,
    this.startDate,
    this.endDate,
    this.monthlyRent,
    this.deposit,
  });

  final String name;
  final String email;
  final String buildingName;
  final String unitName;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? monthlyRent;
  final double? deposit;

  factory _AgreementRow.fromCsvRow(List<dynamic> r) {
    final rent = r.length > 6 ? _parseDouble(r[6].toString()) : null;
    final dep  = r.length > 7 ? _parseDouble(r[7].toString()) : null;
    return _AgreementRow(
      name:         _clip(r[0].toString(), 200),
      email:        r.length > 1 ? _clip(r[1].toString(), 200) : '',
      buildingName: r.length > 2 ? _clip(r[2].toString(), 100) : '',
      unitName:     r.length > 3 ? _clip(r[3].toString(), 100) : '',
      startDate:    r.length > 4 ? _parseDate(r[4].toString()) : null,
      endDate:      r.length > 5 ? _parseDate(r[5].toString()) : null,
      monthlyRent:  (rent != null && rent > 0) ? rent : null,
      deposit:      (dep  != null && dep  > 0) ? dep  : null,
    );
  }

  static String _clip(String s, int max) {
    final t = s.trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  static final _df = DateFormat('dd.MM.yyyy');

  static DateTime? _parseDate(String s) {
    if (s.trim().isEmpty) return null;
    try {
      return _df.parseStrict(s.trim());
    } catch (_) {
      return null;
    }
  }

  static double? _parseDouble(String s) {
    if (s.trim().isEmpty) return null;
    return double.tryParse(s.trim().replaceAll(',', '.'));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — Einladungen
// ═══════════════════════════════════════════════════════════════════════════════

class _InvitesImportTab extends ConsumerStatefulWidget {
  const _InvitesImportTab();

  @override
  ConsumerState<_InvitesImportTab> createState() => _InvitesImportTabState();
}

class _InvitesImportTabState extends ConsumerState<_InvitesImportTab> {
  List<_InviteRow>? _rows;
  String? _error;
  bool _importing = false;
  int _imported = 0;
  final _results = <String>[];

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _rows = null;
      _imported = 0;
      _results.clear();
    });
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    try {
      String content;
      try {
        content = utf8.decode(result.files.single.bytes!);
      } catch (_) {
        content = latin1.decode(result.files.single.bytes!);
      }

      final rows = const CsvToListConverter(
        fieldDelimiter: ';',
        eol: '\n',
      ).convert(content);

      final data = rows.skip(1).where((r) => r.isNotEmpty).toList();
      if (data.isEmpty) throw const FormatException('Keine Datenzeilen gefunden.');

      setState(() {
        _rows = data.map((r) {
          final roleStr =
              r.length > 2 ? r[2].toString().trim().toLowerCase() : '';
          final isContractor =
              roleStr == 'handwerker' || roleStr == 'contractor';
          return _InviteRow(
            name: r[0].toString().trim(),
            email: r.length > 1 ? r[1].toString().trim() : '',
            isContractor: isContractor,
            buildingName: r.length > 3 ? r[3].toString().trim() : '',
            unitName: r.length > 4 ? r[4].toString().trim() : '',
          );
        }).where((row) => row.name.isNotEmpty).toList();
      });
    } catch (e) {
      setState(() => _error = 'Fehler beim Einlesen: $e');
    }
  }

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;

    final tenantId =
        ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
    if (tenantId.isEmpty) return;

    final confirmed = await _confirmImport(
      context,
      count: rows.length,
      label: 'Einladungen',
    );
    if (!confirmed) return;

    setState(() {
      _importing = true;
      _imported = 0;
      _results.clear();
    });

    // Load buildings+units once for unit name → ID resolution
    final buildings = await ref
        .read(buildingRepositoryProvider)
        .watchBuildings(tenantId)
        .first;
    final buildingByName = {
      for (final b in buildings) b.name.toLowerCase().trim(): b,
    };
    final unitsByBuilding = <String, List<dynamic>>{};
    for (final b in buildings) {
      unitsByBuilding[b.id] = await ref
          .read(buildingRepositoryProvider)
          .watchUnits(b.id, tenantId)
          .first;
    }

    final invRepo = ref.read(invitationRepositoryProvider);

    for (final row in rows) {
      try {
        // Try to resolve unit for tenant rows that have building+unit names
        String? unitId;
        String? unitName;
        if (!row.isContractor &&
            row.buildingName.isNotEmpty &&
            row.unitName.isNotEmpty) {
          final building =
              buildingByName[row.buildingName.toLowerCase().trim()];
          if (building != null) {
            final units = unitsByBuilding[building.id] ?? [];
            final unit = units.cast<dynamic>().firstWhere(
                  (u) =>
                      (u.name as String).toLowerCase().trim() ==
                      row.unitName.toLowerCase().trim(),
                  orElse: () => null,
                );
            unitId = unit?.id as String?;
            unitName = unit?.name as String?;
          }
        }

        final code = await invRepo.create(
          tenantId: tenantId,
          role: row.isContractor
              ? InvitationRole.contractor
              : InvitationRole.tenantUser,
          validFor: const Duration(days: 30),
          unitId: unitId,
          unitName: unitName,
        );
        final unitInfo =
            unitName != null ? ' ($unitName)' : '';
        _results.add('✓ ${row.name}$unitInfo → $code');
        setState(() => _imported++);
      } catch (e) {
        _results.add('✗ ${row.name}: $e');
      }
    }

    setState(() => _importing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_imported Einladungen erstellt.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _CsvFormatHint(
          title: 'Format: Name;E-Mail;Rolle;Gebäude;Wohnung',
          template: _invitesCsvTemplate,
        ),
        if (_error != null) _ErrorBanner(message: _error!),
        if (_results.isNotEmpty) ...[
          Container(
            color: Colors.green.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_imported Einladungscodes erstellt:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                ..._results.map((r) => Text(
                      r,
                      style: TextStyle(
                        fontSize: 11,
                        color: r.startsWith('✓')
                            ? Colors.green.shade700
                            : Colors.red,
                      ),
                    )),
              ],
            ),
          ),
        ],
        if (_rows != null && _results.isEmpty) ...[
          _PreviewHeader(
            count: _rows!.length,
            label: 'Einladungen',
            importing: _importing,
            imported: _imported,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _rows!.length,
              itemBuilder: (_, i) {
                final r = _rows![i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    r.isContractor
                        ? Icons.construction_outlined
                        : Icons.person_outlined,
                    size: 18,
                  ),
                  title: Text(r.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    [
                      if (r.email.isNotEmpty) r.email,
                      if (r.buildingName.isNotEmpty && r.unitName.isNotEmpty)
                        '${r.buildingName} › ${r.unitName}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    r.isContractor ? 'Handwerker' : 'Mieter',
                    style: TextStyle(
                      fontSize: 11,
                      color: r.isContractor ? Colors.orange : Colors.blue,
                    ),
                  ),
                );
              },
            ),
          ),
        ] else if (_rows == null)
          const Expanded(
            child: Center(
              child: Text(
                'Noch keine CSV geladen.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _importing
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: _rows != null && _rows!.isNotEmpty
                            ? _imported / _rows!.length
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text('$_imported / ${_rows?.length ?? 0} erstellt…'),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('CSV auswählen'),
                          onPressed: _pickFile,
                        ),
                      ),
                      if (_rows != null &&
                          _rows!.isNotEmpty &&
                          _results.isEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.send_outlined),
                            label: Text('${_rows!.length} erstellen'),
                            onPressed: _import,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _InviteRow {
  const _InviteRow({
    required this.name,
    required this.email,
    required this.isContractor,
    this.buildingName = '',
    this.unitName = '',
  });
  final String name;
  final String email;
  final bool isContractor;
  final String buildingName;
  final String unitName;
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _CsvFormatHint extends StatelessWidget {
  const _CsvFormatHint({required this.title, required this.template});
  final String title;
  final String template;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.info_outlined, size: 18),
      title: Text(title, style: const TextStyle(fontSize: 12)),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              template,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.count,
    required this.label,
    required this.importing,
    required this.imported,
  });
  final int count;
  final String label;
  final bool importing;
  final int imported;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$count $label',
            style:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          const Spacer(),
          if (importing)
            Text('$imported importiert',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color.alphaBlend(
        Colors.red.withValues(alpha: 0.1),
        Theme.of(context).colorScheme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
