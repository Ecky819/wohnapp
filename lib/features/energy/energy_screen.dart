import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../models/energy_reading.dart';
import '../../repositories/building_repository.dart';
import '../../repositories/energy_reading_repository.dart';
import '../../user_provider.dart';
import '../../widgets/app_state_widgets.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class EnergyScreen extends ConsumerStatefulWidget {
  const EnergyScreen({super.key});

  @override
  ConsumerState<EnergyScreen> createState() => _EnergyScreenState();
}

class _EnergyScreenState extends ConsumerState<EnergyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _types = EnergyType.values;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _types.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Energieverbrauch'),
        bottom: TabBar(
          controller: _tabs,
          tabs: _types
              .map((t) => Tab(icon: Icon(t.icon, size: 18), text: t.label))
              .toList(),
        ),
        actions: [_ImportButton(), _ExportButton()],
      ),
      body: TabBarView(
        controller: _tabs,
        children: _types.map((t) => _EnergyTab(type: t)).toList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Ablesung'),
        onPressed: () => _showAddDialog(context),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _AddReadingSheet(initialType: _types[_tabs.index]),
      ),
    );
  }
}

// ─── Tab: Ablesungen für einen Zählertyp ─────────────────────────────────────

class _EnergyTab extends ConsumerWidget {
  const _EnergyTab({required this.type});
  final EnergyType type;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _numFmt = NumberFormat('#,##0.00', 'de_DE');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
    final readingsAsync = ref.watch(energyReadingsByTenantProvider(tenantId));

    return readingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(message: e.toString()),
      data: (all) {
        final readings = all.where((r) => r.type == type).toList();

        if (readings.isEmpty) {
          return EmptyState(
            icon: type.icon,
            title: 'Keine ${type.label}-Ablesungen',
            subtitle: 'Tippe auf + um eine Ablesung hinzuzufügen.',
          );
        }

        // Gruppieren nach Wohnung für Verbrauchsberechnung
        final byUnit = <String, List<EnergyReading>>{};
        for (final r in readings) {
          byUnit.putIfAbsent(r.unitId, () => []).add(r);
        }
        // Innerhalb jeder Wohnung nach Datum aufsteigend
        for (final list in byUnit.values) {
          list.sort((a, b) => a.readingDate.compareTo(b.readingDate));
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // ── Zusammenfassung ────────────────────────────────────────
            _SummaryRow(byUnit: byUnit, type: type),
            const SizedBox(height: 12),

            // ── Ablesungen je Wohnung ──────────────────────────────────
            ...byUnit.entries.map((entry) {
              final unitReadings = entry.value.reversed.toList();
              return _UnitReadingCard(
                unitName: unitReadings.first.unitName,
                readings: unitReadings,
                type: type,
                dateFmt: _dateFmt,
                numFmt: _numFmt,
              );
            }),
          ],
        );
      },
    );
  }
}

// ─── Zusammenfassung oben im Tab ─────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.byUnit, required this.type});
  final Map<String, List<EnergyReading>> byUnit;
  final EnergyType type;

  @override
  Widget build(BuildContext context) {
    int unitCount = byUnit.length;
    double totalConsumption = 0;

    for (final list in byUnit.values) {
      if (list.length >= 2) {
        totalConsumption += list.last.value - list.first.value;
      }
    }

    final numFmt = NumberFormat('#,##0.0', 'de_DE');

    return Card(
      color: type.color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(type.icon, color: type.color, size: 28),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$unitCount ${unitCount == 1 ? 'Wohnung' : 'Wohnungen'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  totalConsumption > 0
                      ? '${numFmt.format(totalConsumption)} ${type.unit} gesamt'
                      : 'Noch keine Verbrauchsberechnung',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Karte je Wohnung ─────────────────────────────────────────────────────────

class _UnitReadingCard extends ConsumerWidget {
  const _UnitReadingCard({
    required this.unitName,
    required this.readings,
    required this.type,
    required this.dateFmt,
    required this.numFmt,
  });
  final String unitName;
  final List<EnergyReading> readings; // Neueste zuerst
  final EnergyType type;
  final DateFormat dateFmt;
  final NumberFormat numFmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = readings.first;
    // Verbrauch = Differenz zwischen neuester und zweitältester Ablesung
    final consumption = readings.length >= 2
        ? readings.first.value - readings.last.value
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: type.color.withValues(alpha: 0.12),
          child: Icon(type.icon, color: type.color, size: 18),
        ),
        title: Text(
          unitName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${numFmt.format(latest.value)} ${type.unit} · ${dateFmt.format(latest.readingDate)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: consumption != null
            ? Chip(
                label: Text(
                  '∆ ${numFmt.format(consumption)} ${type.unit}',
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor: type.color.withValues(alpha: 0.12),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )
            : null,
        children: readings
            .map(
              (r) => _ReadingTile(
                reading: r,
                dateFmt: dateFmt,
                numFmt: numFmt,
                type: type,
                onDelete: () => ref
                    .read(energyReadingRepositoryProvider)
                    .deleteReading(r.id),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({
    required this.reading,
    required this.dateFmt,
    required this.numFmt,
    required this.type,
    required this.onDelete,
  });
  final EnergyReading reading;
  final DateFormat dateFmt;
  final NumberFormat numFmt;
  final EnergyType type;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Text(
        dateFmt.format(reading.readingDate),
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      title: Text(
        '${numFmt.format(reading.value)} ${type.unit}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: reading.meterNumber != null || reading.note != null
          ? Text(
              [
                if (reading.meterNumber != null) 'Nr. ${reading.meterNumber}',
                if (reading.note != null) reading.note!,
              ].join(' · '),
              style: const TextStyle(fontSize: 11),
            )
          : null,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Ablesung löschen?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    'Löschen',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );
          if (confirmed == true) onDelete();
        },
      ),
    );
  }
}

// ─── Ablesung hinzufügen (Bottom Sheet) ──────────────────────────────────────

class _AddReadingSheet extends ConsumerStatefulWidget {
  const _AddReadingSheet({required this.initialType});
  final EnergyType initialType;

  @override
  ConsumerState<_AddReadingSheet> createState() => _AddReadingSheetState();
}

class _AddReadingSheetState extends ConsumerState<_AddReadingSheet> {
  final _formKey = GlobalKey<FormState>();
  late EnergyType _type;
  final _valueCtrl = TextEditingController();
  final _meterCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String? _selectedUnitId;
  String? _selectedUnitName;
  bool _saving = false;

  static final _dateFmt = DateFormat('dd.MM.yyyy');

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _meterCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine Wohnung auswählen')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final tenantId =
          ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
      final valueStr = _valueCtrl.text.trim().replaceAll(',', '.');
      final value = double.tryParse(valueStr) ?? 0;

      await ref
          .read(energyReadingRepositoryProvider)
          .addReading(
            EnergyReading(
              id: '',
              tenantId: tenantId,
              unitId: _selectedUnitId!,
              unitName: _selectedUnitName!,
              type: _type,
              value: value,
              readingDate: _date,
              meterNumber: _meterCtrl.text.trim().isEmpty
                  ? null
                  : _meterCtrl.text.trim(),
              note: _noteCtrl.text.trim().isEmpty
                  ? null
                  : _noteCtrl.text.trim(),
            ),
          );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildingsAsync = ref.watch(buildingsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ablesung hinzufügen',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 16),

              // Zählertyp
              SegmentedButton<EnergyType>(
                segments: EnergyType.values
                    .map(
                      (t) => ButtonSegment(
                        value: t,
                        icon: Icon(t.icon, size: 16),
                        label: Text(
                          t.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                    .toList(),
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),

              // Wohnung
              buildingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Fehler: $e'),
                data: (buildings) {
                  final units = <(String id, String name)>[];
                  for (final b in buildings) {
                    final uAsync = ref.watch(unitsProvider(b.id));
                    final uList = uAsync.valueOrNull ?? [];
                    for (final u in uList) {
                      units.add((u.id, '${b.name} · ${u.displayName}'));
                    }
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedUnitId,
                    decoration: const InputDecoration(
                      labelText: 'Wohnung *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.apartment_outlined),
                    ),
                    items: units
                        .map(
                          (u) => DropdownMenuItem(
                            value: u.$1,
                            child: Text(
                              u.$2,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      final match = units.firstWhere((u) => u.$1 == v);
                      setState(() {
                        _selectedUnitId = v;
                        _selectedUnitName = match.$2;
                      });
                    },
                    validator: (v) => v == null ? 'Pflichtfeld' : null,
                  );
                },
              ),
              const SizedBox(height: 14),

              // Zählerstand + Datum
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _valueCtrl,
                      decoration: InputDecoration(
                        labelText: 'Zählerstand (${_type.unit}) *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.speed_outlined),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Pflichtfeld';
                        }
                        if (double.tryParse(v.trim().replaceAll(',', '.')) ==
                            null) {
                          return 'Ungültige Zahl';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _date = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Datum',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(
                          _dateFmt.format(_date),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Zählernummer + Notiz
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _meterCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Zählernummer',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.tag_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notiz',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: _saving
                    ? const Center(child: CircularProgressIndicator())
                    : FilledButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Speichern'),
                        onPressed: _save,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── CSV-Import ───────────────────────────────────────────────────────────────

class _ImportButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends ConsumerState<_ImportButton> {
  bool _loading = false;

  static final _dateFmt = DateFormat('dd.MM.yyyy');

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.first.bytes == null) return;

    setState(() => _loading = true);
    try {
      final content = String.fromCharCodes(result.files.first.bytes!);
      final rows = const CsvToListConverter(
        fieldDelimiter: ';',
        eol: '\n',
      ).convert(content);

      if (rows.length < 2) throw Exception('Leere CSV');

      final tenantId =
          ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';

      final readings = <EnergyReading>[];
      for (final row in rows.skip(1)) {
        if (row.length < 5) continue;
        final dateStr = row[0].toString().trim();
        final typeStr = row[1].toString().trim();
        final unitId = row[2].toString().trim();
        final unitName = row[3].toString().trim();
        final valueStr = row[4].toString().trim().replaceAll(',', '.');
        final unit2 = row.length > 5 ? row[5].toString().trim() : '';
        final meterNo = row.length > 6 ? row[6].toString().trim() : '';
        final note = row.length > 7 ? row[7].toString().trim() : '';

        if (unitId.isEmpty || valueStr.isEmpty) continue;
        final value = double.tryParse(valueStr);
        if (value == null) continue;

        DateTime? date;
        try {
          date = _dateFmt.parse(dateStr);
        } catch (_) {
          continue;
        }

        readings.add(
          EnergyReading(
            id: '',
            tenantId: tenantId,
            unitId: unitId,
            unitName: unitName,
            type: EnergyTypeX.fromCsvLabel(typeStr),
            value: value,
            readingDate: date,
            meterNumber: meterNo.isNotEmpty ? meterNo : null,
            note: note.isNotEmpty ? note : null,
          ),
        );
      }

      if (readings.isEmpty) throw Exception('Keine gültigen Zeilen gefunden');

      await ref.read(energyReadingRepositoryProvider).addBatch(readings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${readings.length} Ablesungen importiert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import-Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: 'CSV importieren',
            onPressed: _import,
          );
  }
}

// ─── CSV-Export ───────────────────────────────────────────────────────────────

class _ExportButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<_ExportButton> {
  bool _loading = false;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _numFmt = NumberFormat('#,##0.000', 'de_DE');

  Future<void> _export() async {
    setState(() => _loading = true);
    try {
      final tenantId =
          ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
      final readings = await ref
          .read(energyReadingRepositoryProvider)
          .fetchByTenant(tenantId);

      // Verbrauch berechnen (Differenz zur vorherigen Ablesung je Einheit + Typ)
      final prev = <String, EnergyReading>{};
      final rows = <List<dynamic>>[
        [
          'Datum',
          'Zählerart',
          'Wohnungs-ID',
          'Wohnung',
          'Zählerstand',
          'Einheit',
          'Verbrauch',
          'Zählernummer',
          'Notiz',
        ],
      ];

      for (final r in readings) {
        final key = '${r.unitId}_${r.type.firestoreValue}';
        final consumption = prev.containsKey(key)
            ? _numFmt.format(r.value - prev[key]!.value)
            : '–';
        prev[key] = r;

        rows.add([
          _dateFmt.format(r.readingDate),
          r.type.label,
          r.unitId,
          r.unitName,
          _numFmt.format(r.value),
          r.type.unit,
          consumption,
          r.meterNumber ?? '',
          r.note ?? '',
        ]);
      }

      final csv = const ListToCsvConverter(
        fieldDelimiter: ';',
        eol: '\r\n',
      ).convert(rows);

      await Printing.sharePdf(
        bytes: Uint8List.fromList(csv.codeUnits),
        filename:
            'energie_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export-Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'CSV exportieren',
            onPressed: _export,
          );
  }
}
