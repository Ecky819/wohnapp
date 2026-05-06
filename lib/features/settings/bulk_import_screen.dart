import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/invitation.dart';
import '../../repositories/building_repository.dart';
import '../../repositories/invitation_repository.dart';
import '../../user_provider.dart';

// ─── Template strings shown as hints ─────────────────────────────────────────

const _unitsCsvTemplate =
    'Gebäude;Adresse;Wohnungsname;Etage\n'
    'Musterstraße 1;Musterstraße 1, 12345 Stadt;Wohnung 1;1\n'
    'Musterstraße 1;Musterstraße 1, 12345 Stadt;Wohnung 2;2';

const _invitesCsvTemplate =
    'Name;E-Mail;Rolle\n'
    'Max Mustermann;max@example.com;Mieter\n'
    'Lieschen Müller;lieschen@example.com;Mieter\n'
    'Hans Handwerker;hans@example.com;Handwerker';

// ─── Screen ───────────────────────────────────────────────────────────────────

class BulkImportScreen extends ConsumerWidget {
  const BulkImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bulk-Import'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.apartment_outlined), text: 'Wohnungen'),
              Tab(icon: Icon(Icons.group_add_outlined), text: 'Einladungen'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _UnitsImportTab(),
            _InvitesImportTab(),
          ],
        ),
      ),
    );
  }
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
  int _imported = 0;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _rows = null;
      _imported = 0;
    });
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    try {
      final content = utf8.decode(result.files.single.bytes!);
      final rows = const CsvToListConverter(
        fieldDelimiter: ';',
        eol: '\n',
      ).convert(content);

      // Skip header row
      final data = rows.skip(1).where((r) => r.length >= 3).toList();
      if (data.isEmpty) throw const FormatException('Keine Datenzeilen gefunden.');

      setState(() {
        _rows = data.map((r) => _UnitRow(
          buildingName: r[0].toString().trim(),
          buildingAddress: r.length > 1 ? r[1].toString().trim() : '',
          unitName: r[2].toString().trim(),
          floor: r.length > 3 ? int.tryParse(r[3].toString()) : null,
        )).where((row) => row.buildingName.isNotEmpty && row.unitName.isNotEmpty).toList();
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

    setState(() {
      _importing = true;
      _imported = 0;
    });

    try {
      // Group rows by building name to avoid duplicate creates
      final buildingIds = <String, String>{};
      final buildingRepo = ref.read(buildingRepositoryProvider);

      for (final row in rows) {
        if (!buildingIds.containsKey(row.buildingName)) {
          final id = await buildingRepo.createBuilding(
            name: row.buildingName,
            address: row.buildingAddress.isNotEmpty
                ? row.buildingAddress
                : row.buildingName,
            tenantId: tenantId,
          );
          buildingIds[row.buildingName] = id;
        }

        await buildingRepo.createUnit(
          buildingId: buildingIds[row.buildingName]!,
          name: row.unitName,
          tenantId: tenantId,
          floor: row.floor,
        );

        setState(() => _imported++);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_imported Wohnungen importiert.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _rows = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Import fehlgeschlagen: $e');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _CsvFormatHint(
          title: 'Format: Gebäude;Adresse;Wohnungsname;Etage',
          template: _unitsCsvTemplate,
        ),
        if (_error != null)
          _ErrorBanner(message: _error!),
        if (_rows != null) ...[
          _PreviewHeader(
            count: _rows!.length,
            label: 'Wohnungen vorschau',
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
                  leading: const Icon(Icons.apartment_outlined, size: 18),
                  title: Text('${r.buildingName} › ${r.unitName}',
                      style: const TextStyle(fontSize: 13)),
                  subtitle: r.buildingAddress.isNotEmpty
                      ? Text(r.buildingAddress,
                          style: const TextStyle(fontSize: 11))
                      : null,
                  trailing: r.floor != null
                      ? Text('${r.floor}. OG',
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
                      Text('$_imported / ${_rows?.length ?? 0} importiert…'),
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
                      if (_rows != null && _rows!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.download_done_outlined),
                            label: Text('${_rows!.length} importieren'),
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

class _UnitRow {
  const _UnitRow({
    required this.buildingName,
    required this.buildingAddress,
    required this.unitName,
    this.floor,
  });
  final String buildingName;
  final String buildingAddress;
  final String unitName;
  final int? floor;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — Einladungen
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
      final content = utf8.decode(result.files.single.bytes!);
      final rows = const CsvToListConverter(
        fieldDelimiter: ';',
        eol: '\n',
      ).convert(content);

      final data = rows.skip(1).where((r) => r.isNotEmpty).toList();
      if (data.isEmpty) throw const FormatException('Keine Datenzeilen gefunden.');

      setState(() {
        _rows = data.map((r) {
          final roleStr = r.length > 2 ? r[2].toString().trim().toLowerCase() : '';
          final isContractor =
              roleStr == 'handwerker' || roleStr == 'contractor';
          return _InviteRow(
            name: r[0].toString().trim(),
            email: r.length > 1 ? r[1].toString().trim() : '',
            isContractor: isContractor,
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

    setState(() {
      _importing = true;
      _imported = 0;
      _results.clear();
    });

    final invRepo = ref.read(invitationRepositoryProvider);

    for (final row in rows) {
      try {
        final code = await invRepo.create(
          tenantId: tenantId,
          role: row.isContractor
              ? InvitationRole.contractor
              : InvitationRole.tenantUser,
          validFor: const Duration(days: 30),
        );
        _results.add('✓ ${row.name} → $code');
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
          title: 'Format: Name;E-Mail;Rolle (Mieter/Handwerker)',
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
                Text('$_imported Einladungscodes erstellt:',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                ..._results.map((r) => Text(r,
                    style: TextStyle(
                        fontSize: 11,
                        color: r.startsWith('✓')
                            ? Colors.green.shade700
                            : Colors.red))),
              ],
            ),
          ),
        ],
        if (_rows != null && _results.isEmpty) ...[
          _PreviewHeader(
            count: _rows!.length,
            label: 'Einladungen vorschau',
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
                  subtitle: r.email.isNotEmpty
                      ? Text(r.email, style: const TextStyle(fontSize: 11))
                      : null,
                  trailing: Text(
                    r.isContractor ? 'Handwerker' : 'Mieter',
                    style: TextStyle(
                        fontSize: 11,
                        color: r.isContractor
                            ? Colors.orange
                            : Colors.blue),
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
  const _InviteRow(
      {required this.name,
      required this.email,
      required this.isContractor});
  final String name;
  final String email;
  final bool isContractor;
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _CsvFormatHint extends StatelessWidget {
  const _CsvFormatHint({required this.title, required this.template});
  final String title;
  final String template;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.info_outline, size: 18),
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
          Text('$count $label',
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13)),
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
      color: Colors.red.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 12, color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ─── Firestore batch helper ───────────────────────────────────────────────────

/// Write many invitation docs via batched writes (max 500 per batch).
Future<void> batchWriteInvitations(
  FirebaseFirestore db,
  List<Map<String, dynamic>> docs,
  String collection,
) async {
  const batchSize = 400;
  for (var i = 0; i < docs.length; i += batchSize) {
    final batch = db.batch();
    final chunk = docs.sublist(i, (i + batchSize).clamp(0, docs.length));
    for (final doc in chunk) {
      batch.set(db.collection(collection).doc(), doc);
    }
    await batch.commit();
  }
}
