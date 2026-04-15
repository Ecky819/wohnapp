import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/building.dart';
import '../../models/unit.dart';
import '../../repositories/activity_repository.dart';
import '../../repositories/building_repository.dart';
import '../../services/routing_service.dart';
import '../../services/upload_retry_service.dart';
import '../../ticket_provider.dart';
import '../../user_provider.dart';

class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() =>
      _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  final List<File> _imageFiles = [];
  final List<PlatformFile> _documents = [];
  bool _isLoading = false;

  String _category = 'damage';
  String _priority = 'normal';
  Building? _selectedBuilding;
  Unit? _selectedUnit;
  DateTime? _scheduledAt;

  RankedContractor? _routingSuggestion;
  RankedContractor? _acceptedSuggestion;

  final _picker = ImagePicker();

  bool get _isManager =>
      ref.read(currentUserProvider).valueOrNull?.role == 'manager';

  // ─── Routing suggestion ───────────────────────────────────────────────────

  void _updateRoutingSuggestion() {
    if (!_isManager) return;
    final title = _titleController.text;
    final desc = _descriptionController.text;
    if (title.length < 3 && desc.length < 3) {
      if (_routingSuggestion != null) setState(() => _routingSuggestion = null);
      return;
    }

    final contractors = ref.read(contractorsProvider).valueOrNull ?? [];
    final allTickets = ref.read(allTicketsProvider).valueOrNull ?? [];
    final category = RoutingService.detectCategory(title, desc);

    final ranked = RoutingService.rankContractors(
      category: category,
      contractors: contractors,
      allTickets: allTickets,
    );

    setState(() {
      _routingSuggestion = ranked.isEmpty ? null : ranked.first;
      // Clear accepted if suggestion changed
      if (_acceptedSuggestion?.user.uid != _routingSuggestion?.user.uid) {
        _acceptedSuggestion = null;
      }
    });
  }

  // ─── Image ────────────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) setState(() => _imageFiles.add(File(picked.path)));
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Kamera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Documents ────────────────────────────────────────────────────────────

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
    );
    if (result != null) setState(() => _documents.addAll(result.files));
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final appUser = await ref.read(currentUserProvider.future);
      final tenantId = appUser?.tenantId ?? 'tenant_1';

      final ticketId = await ref.read(ticketRepositoryProvider).createTicket(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            tenantId: tenantId,
            category: _category,
            priority: _priority,
            unitId: _selectedUnit?.id,
            unitName: _selectedUnit != null
                ? '${_selectedBuilding?.name ?? ''} · ${_selectedUnit!.displayName}'
                : null,
            scheduledAt: _scheduledAt,
            images: _imageFiles,
            documents: _documents,
            activityRepo: ref.read(activityRepositoryProvider),
          );

      // Auto-assign if manager accepted routing suggestion
      if (_acceptedSuggestion != null) {
        await ref.read(ticketRepositoryProvider).assignContractor(
              ticketId,
              contractorId: _acceptedSuggestion!.user.uid,
              contractorName: _acceptedSuggestion!.user.name,
              ticketTitle: _titleController.text.trim(),
              activityRepo: ref.read(activityRepositoryProvider),
            );
      }

      if (mounted) Navigator.pop(context);
    } on UploadException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bilder konnten nicht hochgeladen werden '
              '(${e.attempts}× versucht). Bitte Verbindung prüfen.',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Erneut',
              onPressed: _submit,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buildingsAsync = ref.watch(buildingsProvider);
    final unitsAsync = _selectedBuilding != null
        ? ref.watch(unitsProvider(_selectedBuilding!.id))
        : const AsyncValue<List<Unit>>.data([]);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isManager ? 'Ticket anlegen' : 'Schaden melden'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Kategorie (nur Manager) ───────────────────────────────────
            if (_isManager) ...[
              const Text('Kategorie',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'damage',
                    label: Text('Schaden'),
                    icon: Icon(Icons.report_problem_outlined),
                  ),
                  ButtonSegment(
                    value: 'maintenance',
                    label: Text('Wartung'),
                    icon: Icon(Icons.build_circle_outlined),
                  ),
                ],
                selected: {_category},
                onSelectionChanged: (s) =>
                    setState(() => _category = s.first),
              ),
              const SizedBox(height: 16),

              const Text('Priorität',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'normal', label: Text('Normal')),
                  ButtonSegment(value: 'high', label: Text('Hoch')),
                ],
                selected: {_priority},
                onSelectionChanged: (s) =>
                    setState(() => _priority = s.first),
              ),
              const SizedBox(height: 16),

              // Geplantes Datum — nur bei Wartung
              if (_category == 'maintenance') ...[
                const Text('Geplantes Datum',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _scheduledAt ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    );
                    if (picked != null) setState(() => _scheduledAt = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(
                      _scheduledAt != null
                          ? '${_scheduledAt!.day.toString().padLeft(2, '0')}.${_scheduledAt!.month.toString().padLeft(2, '0')}.${_scheduledAt!.year}'
                          : 'Datum wählen (optional)',
                      style: TextStyle(
                        color: _scheduledAt != null ? null : Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],

            // ── Gebäude / Wohnung ────────────────────────────────────────
            const Text('Gebäude & Wohnung',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),

            buildingsAsync.when(
              loading: () =>
                  const LinearProgressIndicator(),
              error: (e, _) => Text('Gebäude konnten nicht geladen werden: $e',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
              data: (buildings) => buildings.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Noch keine Gebäude angelegt.\nManager kann Gebäude in Firestore hinzufügen.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : DropdownButtonFormField<Building>(
                      key: const ValueKey('building-dropdown'),
                      initialValue: _selectedBuilding,
                      hint: const Text('Gebäude wählen'),
                      decoration:
                          const InputDecoration(border: OutlineInputBorder()),
                      items: buildings
                          .map((b) => DropdownMenuItem(
                                value: b,
                                child: Text(b.name),
                              ))
                          .toList(),
                      onChanged: (b) => setState(() {
                        _selectedBuilding = b;
                        _selectedUnit = null;
                      }),
                    ),
            ),

            if (_selectedBuilding != null) ...[
              const SizedBox(height: 10),
              unitsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Fehler: $e',
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
                data: (units) => units.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Keine Wohnungen für dieses Gebäude vorhanden.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    : DropdownButtonFormField<Unit>(
                        // key changes when building changes → widget reconstructs with null initialValue
                        key: ValueKey(_selectedBuilding?.id ?? ''),
                        initialValue: _selectedUnit,
                        hint: const Text('Wohnung wählen'),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder()),
                        items: units
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u.displayName),
                                ))
                            .toList(),
                        onChanged: (u) => setState(() => _selectedUnit = u),
                      ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Titel & Beschreibung ─────────────────────────────────────
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                  labelText: 'Titel', border: OutlineInputBorder()),
              onChanged: (_) => _updateRoutingSuggestion(),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Titel eingeben' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                  labelText: 'Beschreibung', border: OutlineInputBorder()),
              maxLines: 3,
              onChanged: (_) => _updateRoutingSuggestion(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Beschreibung eingeben'
                  : null,
            ),

            // ── Routing suggestion (manager only) ─────────────────────
            if (_isManager && _routingSuggestion != null) ...[
              const SizedBox(height: 12),
              _RoutingSuggestionCard(
                suggestion: _routingSuggestion!,
                accepted: _acceptedSuggestion?.user.uid ==
                    _routingSuggestion!.user.uid,
                onAccept: () =>
                    setState(() => _acceptedSuggestion = _routingSuggestion),
                onDismiss: () => setState(() {
                  _routingSuggestion = null;
                  _acceptedSuggestion = null;
                }),
              ),
            ],

            const SizedBox(height: 16),

            // ── Fotos ─────────────────────────────────────────────────────
            if (_imageFiles.isNotEmpty) ...[
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _imageFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_imageFiles[i],
                            width: 100, height: 100, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _imageFiles.removeAt(i)),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_imageFiles.isEmpty
                  ? 'Foto hinzufügen'
                  : 'Weiteres Foto hinzufügen'),
              onPressed: _showImageSourceSheet,
            ),

            const SizedBox(height: 8),

            // ── Dokumente ────────────────────────────────────────────────
            if (_documents.isNotEmpty) ...[
              ..._documents.map((doc) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined,
                        color: Colors.blue),
                    title:
                        Text(doc.name, style: const TextStyle(fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          setState(() => _documents.remove(doc)),
                    ),
                  )),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file_outlined),
              label: const Text('Dokument anhängen (PDF, Bild)'),
              onPressed: _pickDocument,
            ),

            const SizedBox(height: 24),

            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Ticket erstellen'),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─── Routing suggestion card ──────────────────────────────────────────────────

class _RoutingSuggestionCard extends StatelessWidget {
  const _RoutingSuggestionCard({
    required this.suggestion,
    required this.accepted,
    required this.onAccept,
    required this.onDismiss,
  });

  final RankedContractor suggestion;
  final bool accepted;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final categoryLabel =
        routingCategories[suggestion.user.specializations.firstOrNull] ??
            'Allgemein';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: accepted
            ? Colors.green.shade50
            : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accepted ? Colors.green : Theme.of(context).colorScheme.primary,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            size: 18,
            color: accepted
                ? Colors.green
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  accepted ? 'Zugewiesen an' : 'Vorschlag: $categoryLabel',
                  style: TextStyle(
                    fontSize: 11,
                    color: accepted ? Colors.green : Colors.grey.shade700,
                  ),
                ),
                Text(
                  suggestion.user.name.isNotEmpty
                      ? suggestion.user.name
                      : suggestion.user.email,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${suggestion.activeTickets} aktive Tickets',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (!accepted)
            TextButton(
              onPressed: onAccept,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Übernehmen'),
            )
          else
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
