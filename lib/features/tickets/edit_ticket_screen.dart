import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ticket.dart';
import '../../repositories/activity_repository.dart';
import '../../ticket_provider.dart';

class EditTicketScreen extends ConsumerStatefulWidget {
  const EditTicketScreen({super.key, required this.ticket});
  final Ticket ticket;

  @override
  ConsumerState<EditTicketScreen> createState() => _EditTicketScreenState();
}

class _EditTicketScreenState extends ConsumerState<EditTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _category;
  late String _priority;
  DateTime? _scheduledAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.ticket.title);
    _descriptionController =
        TextEditingController(text: widget.ticket.description);
    _category = widget.ticket.category;
    _priority = widget.ticket.priority;
    _scheduledAt = widget.ticket.scheduledAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(ticketRepositoryProvider).updateTicket(
            widget.ticket.id,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            priority: _priority,
            category: _category,
            scheduledAt: _scheduledAt,
            activityRepo: ref.read(activityRepositoryProvider),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _scheduledAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket bearbeiten'),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('Speichern'),
                ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Kategorie ────────────────────────────────────────────────
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
              onSelectionChanged: (s) => setState(() {
                _category = s.first;
                if (_category != 'maintenance') _scheduledAt = null;
              }),
            ),
            const SizedBox(height: 16),

            // ── Priorität ────────────────────────────────────────────────
            const Text('Priorität',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'normal', label: Text('Normal')),
                ButtonSegment(value: 'high', label: Text('Hoch')),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 16),

            // ── Geplantes Datum (nur Wartung) ────────────────────────────
            if (_category == 'maintenance') ...[
              const Text('Geplantes Datum',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
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
              if (_scheduledAt != null)
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Datum entfernen'),
                  onPressed: () => setState(() => _scheduledAt = null),
                ),
              const SizedBox(height: 16),
            ],

            // ── Titel ────────────────────────────────────────────────────
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Titel',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Titel eingeben' : null,
            ),
            const SizedBox(height: 12),

            // ── Beschreibung ─────────────────────────────────────────────
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Beschreibung eingeben'
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
