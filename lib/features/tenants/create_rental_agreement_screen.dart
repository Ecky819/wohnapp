import 'package:dropdown_search/dropdown_search.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/building.dart';
import '../../models/rental_agreement.dart';
import '../../models/unit.dart';
import '../../repositories/building_repository.dart';
import '../../repositories/rental_agreement_repository.dart';
import '../../user_provider.dart';

// ─── Lokale Hilfsklasse für das Formular ─────────────────────────────────────

class _PositionEintrag {
  _PositionEintrag({
    required this.bezeichnung,
    required this.betrag,
    required this.umlageschluessel,
  });
  String bezeichnung;
  double betrag;
  String umlageschluessel;
}

// ─── Provider: tenant users ───────────────────────────────────────────────────

final _tenantUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final tenantId =
      ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
  if (tenantId.isEmpty) return const Stream.empty();
  return ref.read(userRepositoryProvider).watchTenants(tenantId);
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class CreateRentalAgreementScreen extends ConsumerStatefulWidget {
  const CreateRentalAgreementScreen({super.key});

  @override
  ConsumerState<CreateRentalAgreementScreen> createState() =>
      _CreateRentalAgreementScreenState();
}

class _CreateRentalAgreementScreenState
    extends ConsumerState<CreateRentalAgreementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _rentController = TextEditingController();
  final _depositController = TextEditingController();
  final _heizkostenController = TextEditingController();
  final _notesController = TextEditingController();

  Building? _selectedBuilding;
  Unit? _selectedUnit;
  List<Unit> _buildingUnits = [];

  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _indefinite = true;

  // Betriebskostenpositionen (§2 BetrKV)
  final List<_PositionEintrag> _nebenkostenPositionen = [];

  Uint8List? _pickedFileBytes;
  String? _pickedFileName;

  AppUser? _linkedUser;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _rentController.dispose();
    _depositController.dispose();
    _heizkostenController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('de'),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 365)),
      firstDate: _startDate.add(const Duration(days: 1)),
      lastDate: DateTime(2100),
      locale: const Locale('de'),
    );
    if (picked != null) {
      if (picked.isBefore(_startDate) || picked.isAtSameMomentAs(_startDate)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mietende muss nach dem Mietbeginn liegen.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      setState(() => _endDate = picked);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _pickedFileBytes = result.files.single.bytes!;
        _pickedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _showUserPicker(List<AppUser> users) async {
    final picked = await showModalBottomSheet<AppUser>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UserPickerSheet(users: users),
    );
    if (picked != null) {
      setState(() {
        _linkedUser = picked;
        _nameController.text =
            picked.name.isNotEmpty ? picked.name : picked.email;
        _emailController.text = picked.email;
      });
    }
  }

  Future<void> _showAddPositionDialog() async {
    String selectedName =
        NebenkostenPosition.standardPositionen.first;
    bool isCustom = false;
    final customNameController = TextEditingController();
    final betragController = TextEditingController();
    String umlageschluessel = 'wohnflaeche';

    final result = await showDialog<_PositionEintrag>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: const Text('Betriebskostenposition'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Position', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  isExpanded: true,
                  value: isCustom ? '__custom__' : selectedName,
                  items: [
                    ...NebenkostenPosition.standardPositionen.map((p) =>
                        DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))),
                    const DropdownMenuItem(
                        value: '__custom__', child: Text('Sonstige (eigene Bezeichnung)')),
                  ],
                  onChanged: (v) => setDs(() {
                    if (v == '__custom__') {
                      isCustom = true;
                    } else {
                      isCustom = false;
                      selectedName = v!;
                    }
                  }),
                ),
                if (isCustom) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customNameController,
                    decoration: const InputDecoration(
                      labelText: 'Bezeichnung',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: betragController,
                  decoration: const InputDecoration(
                    labelText: 'Monatliche Vorauszahlung',
                    border: OutlineInputBorder(),
                    suffixText: '€/Monat',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Umlageschlüssel', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  isExpanded: true,
                  value: umlageschluessel,
                  items: const [
                    DropdownMenuItem(value: 'wohnflaeche', child: Text('Nach Wohnfläche')),
                    DropdownMenuItem(value: 'einheit', child: Text('Pro Wohneinheit')),
                    DropdownMenuItem(value: 'direkt', child: Text('Direkt / Verbrauch')),
                  ],
                  onChanged: (v) => setDs(() => umlageschluessel = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final name = isCustom
                    ? customNameController.text.trim()
                    : selectedName;
                final betrag = double.tryParse(
                    betragController.text.trim().replaceAll(',', '.'));
                if (name.isEmpty || betrag == null) return;
                Navigator.pop(
                  ctx,
                  _PositionEintrag(
                    bezeichnung: name,
                    betrag: betrag,
                    umlageschluessel: umlageschluessel,
                  ),
                );
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );

    if (result != null) setState(() => _nebenkostenPositionen.add(result));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBuilding == null || _selectedUnit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Gebäude und Wohnung auswählen.')),
      );
      return;
    }
    if (!_indefinite &&
        _endDate != null &&
        !_endDate!.isAfter(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mietende muss nach dem Mietbeginn liegen.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.lightImpact();
    try {
      final tenantId =
          ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
      final repo = ref.read(rentalAgreementRepositoryProvider);

      final agreement = RentalAgreement(
        id: '',
        tenantId: tenantId,
        tenantName: _nameController.text.trim(),
        tenantEmail: _emailController.text.trim(),
        userId: _linkedUser?.uid,
        unitId: _selectedUnit!.id,
        unitName: _selectedUnit!.name,
        buildingId: _selectedBuilding!.id,
        buildingName: _selectedBuilding!.name,
        startDate: _startDate,
        endDate: _indefinite ? null : _endDate,
        monthlyRent: _rentController.text.trim().isNotEmpty
            ? double.tryParse(
                _rentController.text.trim().replaceAll(',', '.'))
            : null,
        deposit: _depositController.text.trim().isNotEmpty
            ? double.tryParse(
                _depositController.text.trim().replaceAll(',', '.'))
            : null,
        nebenkostenPositionen: _nebenkostenPositionen
            .map((p) => NebenkostenPosition(
                  bezeichnung: p.bezeichnung,
                  monatlicheVorauszahlung: p.betrag,
                  umlageschluessel: p.umlageschluessel,
                ))
            .toList(),
        monthlyHeatingAdvance: _heizkostenController.text.trim().isNotEmpty
            ? double.tryParse(
                _heizkostenController.text.trim().replaceAll(',', '.'))
            : null,
        status: 'active',
        createdAt: DateTime.now(),
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      final id = await repo.create(agreement);

      if (_pickedFileBytes != null && _pickedFileName != null) {
        await repo.uploadContract(id, _pickedFileBytes!, _pickedFileName!);
      }

      if (mounted) {
        FocusScope.of(context).unfocus();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildingsAsync = ref.watch(buildingsProvider);
    final tenantsAsync = ref.watch(_tenantUsersProvider);
    final df = DateFormat('dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mietverhältnis anlegen'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          children: [
            // ── Mieter ──────────────────────────────────────────────────
            const _SectionTitle('Mieter'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    tenantsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (users) => users.isEmpty
                          ? const SizedBox.shrink()
                          : OutlinedButton.icon(
                              icon: const Icon(Icons.person_search_outlined),
                              label: Text(
                                _linkedUser != null
                                    ? 'Verknüpft: ${_linkedUser!.name.isNotEmpty ? _linkedUser!.name : _linkedUser!.email}'
                                    : 'Aus registrierten Mietern wählen',
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => _showUserPicker(users),
                            ),
                    ),
                    if (tenantsAsync.valueOrNull?.isNotEmpty == true)
                      const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name *',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Name erforderlich'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Wohnung ──────────────────────────────────────────────────
            const _SectionTitle('Wohnung'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    buildingsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('Fehler: $e'),
                      data: (buildings) => DropdownSearch<Building>(
                        key: ValueKey(_selectedBuilding?.id),
                        items: buildings,
                        selectedItem: _selectedBuilding,
                        itemAsString: (b) => b.name,
                        filterFn: (b, filter) =>
                            b.name.toLowerCase().contains(filter.toLowerCase()) ||
                            b.address
                                .toLowerCase()
                                .contains(filter.toLowerCase()),
                        compareFn: (a, b) => a.id == b.id,
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: 'Gebäude *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        popupProps: const PopupProps.menu(
                          showSearchBox: true,
                          searchFieldProps: TextFieldProps(
                            decoration: InputDecoration(
                              hintText: 'Gebäude suchen …',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        onChanged: (b) async {
                          if (b == null) return;
                          final tid = ref
                                  .read(currentUserProvider)
                                  .valueOrNull
                                  ?.tenantId ??
                              '';
                          final units = await ref
                              .read(buildingRepositoryProvider)
                              .watchUnits(b.id, tid)
                              .first;
                          setState(() {
                            _selectedBuilding = b;
                            _selectedUnit = null;
                            _buildingUnits = units;
                          });
                        },
                        validator: (v) =>
                            v == null ? 'Gebäude auswählen' : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownSearch<Unit>(
                      key: ValueKey(
                          '${_selectedBuilding?.id}_${_selectedUnit?.id}'),
                      items: _buildingUnits,
                      selectedItem: _selectedUnit,
                      itemAsString: (u) => u.displayName,
                      filterFn: (u, filter) =>
                          u.name.toLowerCase().contains(filter.toLowerCase()),
                      compareFn: (a, b) => a.id == b.id,
                      enabled: _selectedBuilding != null,
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: 'Wohnung *',
                          border: const OutlineInputBorder(),
                          hintText: _selectedBuilding == null
                              ? 'Zuerst Gebäude wählen'
                              : null,
                        ),
                      ),
                      popupProps: const PopupProps.menu(
                        showSearchBox: true,
                        searchFieldProps: TextFieldProps(
                          decoration: InputDecoration(
                            hintText: 'Wohnung suchen …',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ),
                      onChanged: (u) => setState(() => _selectedUnit = u),
                      validator: (v) =>
                          v == null ? 'Wohnung auswählen' : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Mietdaten ────────────────────────────────────────────────
            const _SectionTitle('Mietdaten'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Mietbeginn *',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(df.format(_startDate)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: _pickStartDate,
                          tooltip: 'Datum wählen',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Checkbox(
                          value: _indefinite,
                          onChanged: (v) => setState(() {
                            _indefinite = v!;
                            if (_indefinite) _endDate = null;
                          }),
                        ),
                        const Text('Unbefristet'),
                      ],
                    ),
                    if (!_indefinite) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Mietende',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(_endDate != null
                                  ? df.format(_endDate!)
                                  : 'Datum wählen'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: _pickEndDate,
                            tooltip: 'Datum wählen',
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _rentController,
                            decoration: const InputDecoration(
                              labelText: 'Kaltmiete (optional)',
                              border: OutlineInputBorder(),
                              suffixText: '€',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9,.]')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _depositController,
                            decoration: const InputDecoration(
                              labelText: 'Kaution (optional)',
                              border: OutlineInputBorder(),
                              suffixText: '€',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9,.]')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Nebenkosten ──────────────────────────────────────────────
            const _SectionTitle('Nebenkosten'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Heizkosten (HeizkostenVO — getrennte Abrechnung Pflicht)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _heizkostenController,
                            decoration: const InputDecoration(
                              labelText: 'Heizkosten-Vorauszahlung *',
                              helperText: 'Separat nach HeizkostenVO',
                              border: OutlineInputBorder(),
                              suffixText: '€/Monat',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9,.]')),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Pflichtfeld nach HeizkostenVO';
                              }
                              if (double.tryParse(
                                      v.trim().replaceAll(',', '.')) ==
                                  null) {
                                return 'Ungültiger Betrag';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Betriebskosten-Positionen
                    Row(
                      children: [
                        const Text('Betriebskosten (§2 BetrKV)',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Position'),
                          onPressed: _showAddPositionDialog,
                          style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                    if (_nebenkostenPositionen.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Noch keine Positionen. Tippe auf „+ Position".',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _nebenkostenPositionen.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = _nebenkostenPositionen[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.bezeichnung,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                              p.umlageschluessel == 'wohnflaeche'
                                  ? 'Wohnfläche'
                                  : p.umlageschluessel == 'einheit'
                                      ? 'Pro Einheit'
                                      : 'Direkt',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${p.betrag.toStringAsFixed(2)} €',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () => setState(() =>
                                      _nebenkostenPositionen.removeAt(i)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (_nebenkostenPositionen.isNotEmpty) ...[
                      const Divider(),
                      _NebenkostenSumme(
                        positionen: _nebenkostenPositionen,
                        heizkosten: double.tryParse(
                            _heizkostenController.text.replaceAll(',', '.')),
                        kaltmiete: double.tryParse(
                            _rentController.text.replaceAll(',', '.')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Mietvertrag ──────────────────────────────────────────────
            const _SectionTitle('Mietvertrag'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _pickedFileName != null
                    ? Row(
                        children: [
                          const Icon(Icons.picture_as_pdf, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _pickedFileName!,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Entfernen',
                            onPressed: () => setState(() {
                              _pickedFileBytes = null;
                              _pickedFileName = null;
                            }),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('PDF hochladen'),
                            onPressed: _pickFile,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Bestehenden Mietvertrag als PDF (optional).',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Notizen ──────────────────────────────────────────────────
            const _SectionTitle('Notizen'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    hintText: 'Interne Notizen (optional) …',
                    border: InputBorder.none,
                  ),
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).unfocus(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Nebenkosten-Summe ────────────────────────────────────────────────────────

class _NebenkostenSumme extends StatelessWidget {
  const _NebenkostenSumme({
    required this.positionen,
    required this.heizkosten,
    required this.kaltmiete,
  });
  final List<_PositionEintrag> positionen;
  final double? heizkosten;
  final double? kaltmiete;

  @override
  Widget build(BuildContext context) {
    final nkGesamt =
        positionen.fold(0.0, (s, p) => s + p.betrag);
    final hk = heizkosten ?? 0.0;
    final km = kaltmiete ?? 0.0;
    final warmmiete = km + nkGesamt + hk;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          _SumRow(label: 'Betriebskosten gesamt', value: nkGesamt),
          if (hk > 0) _SumRow(label: 'Heizkosten', value: hk),
          const Divider(height: 12),
          _SumRow(
            label: 'Warmmiete',
            value: warmmiete,
            bold: true,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });
  final String label;
  final double value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('${value.toStringAsFixed(2)} €/Monat', style: style),
        ],
      ),
    );
  }
}

// ─── Helper widget ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

// ─── User picker sheet ────────────────────────────────────────────────────────

class _UserPickerSheet extends StatelessWidget {
  const _UserPickerSheet({required this.users});
  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'Mieter auswählen',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              itemCount: users.length,
              itemBuilder: (_, i) {
                final u = users[i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      u.name.isNotEmpty
                          ? u.name[0].toUpperCase()
                          : u.email[0].toUpperCase(),
                    ),
                  ),
                  title: Text(u.name.isNotEmpty ? u.name : u.email),
                  subtitle: u.name.isNotEmpty ? Text(u.email) : null,
                  onTap: () => Navigator.pop(context, u),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
