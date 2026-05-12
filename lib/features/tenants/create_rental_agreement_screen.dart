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
  final _notesController = TextEditingController();

  Building? _selectedBuilding;
  Unit? _selectedUnit;
  List<Unit> _buildingUnits = [];

  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _indefinite = true;

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
      firstDate: _startDate,
      lastDate: DateTime(2100),
      locale: const Locale('de'),
    );
    if (picked != null) setState(() => _endDate = picked);
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBuilding == null || _selectedUnit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Gebäude und Wohnung auswählen.')),
      );
      return;
    }

    setState(() => _isSaving = true);
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

      if (mounted) Navigator.pop(context, true);
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
                      data: (buildings) => DropdownButtonFormField<Building>(
                        key: ValueKey(_selectedBuilding?.id),
                        decoration: const InputDecoration(
                          labelText: 'Gebäude *',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _selectedBuilding,
                        hint: const Text('Gebäude auswählen'),
                        items: buildings
                            .map((b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(b.name),
                                ))
                            .toList(),
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
                    DropdownButtonFormField<Unit>(
                      key: ValueKey('${_selectedBuilding?.id}_${_selectedUnit?.id}'),
                      decoration: const InputDecoration(
                        labelText: 'Wohnung *',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedUnit,
                      hint: Text(_selectedBuilding == null
                          ? 'Zuerst Gebäude wählen'
                          : 'Wohnung auswählen'),
                      items: _buildingUnits
                          .map((u) => DropdownMenuItem(
                                value: u,
                                child: Text(u.displayName),
                              ))
                          .toList(),
                      onChanged: _selectedBuilding == null
                          ? null
                          : (u) => setState(() => _selectedUnit = u),
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
                              labelText: 'Kaltmiete',
                              border: OutlineInputBorder(),
                              suffixText: '€',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
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
                              labelText: 'Kaution',
                              border: OutlineInputBorder(),
                              suffixText: '€',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
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
                ),
              ),
            ),
          ],
        ),
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
