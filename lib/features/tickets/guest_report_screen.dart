import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../repositories/activity_repository.dart';
import '../../repositories/ticket_repository.dart';
import '../../services/upload_retry_service.dart';

/// Anonymous damage-report form — no account required.
/// Signs in the user anonymously, creates the ticket, then shows a confirmation.
class GuestReportScreen extends ConsumerStatefulWidget {
  const GuestReportScreen({
    super.key,
    required this.unitId,
    required this.tenantId,
    required this.unitName,
  });

  final String unitId;
  final String tenantId;
  final String unitName;

  @override
  ConsumerState<GuestReportScreen> createState() => _GuestReportScreenState();
}

class _GuestReportScreenState extends ConsumerState<GuestReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final List<File> _images = [];
  bool _loading = false;
  bool _submitted = false;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) setState(() => _images.add(File(picked.path)));
  }

  void _showImageSheet() {
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      // 1. Sign in anonymously if not already signed in
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      final uid = auth.currentUser!.uid;

      // 2. Create ticket
      await ref.read(ticketRepositoryProvider).createTicket(
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            tenantId: widget.tenantId,
            category: 'damage',
            priority: 'normal',
            unitId: widget.unitId,
            unitName: widget.unitName,
            images: _images,
            documents: const [],
            activityRepo: ref.read(activityRepositoryProvider),
            guestUid: uid,
          );

      if (mounted) setState(() => _submitted = true);
    } on UploadException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Bilder konnten nicht hochgeladen werden (${e.attempts}× versucht).'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return const _SuccessView();

    return Scaffold(
      appBar: AppBar(title: const Text('Schaden melden')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Unit banner ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.apartment_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.unitName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Info text ───────────────────────────────────────────────
            const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Kein Login erforderlich. Deine Meldung wird direkt '
                    'an die Hausverwaltung weitergeleitet.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Title ───────────────────────────────────────────────────
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Kurzbeschreibung *',
                border: OutlineInputBorder(),
                hintText: 'z.B. Wasserhahn tropft',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Bitte ausfüllen' : null,
            ),

            const SizedBox(height: 12),

            // ── Description ─────────────────────────────────────────────
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Detailbeschreibung *',
                border: OutlineInputBorder(),
                hintText: 'Wo genau? Seit wann? Wie schlimm?',
              ),
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Bitte ausfüllen' : null,
            ),

            const SizedBox(height: 16),

            // ── Photos ──────────────────────────────────────────────────
            if (_images.isNotEmpty) ...[
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_images[i],
                            width: 96, height: 96, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.removeAt(i)),
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
              label: Text(_images.isEmpty
                  ? 'Foto hinzufügen (optional)'
                  : 'Weiteres Foto'),
              onPressed: _showImageSheet,
            ),

            const SizedBox(height: 28),

            // ── Submit ──────────────────────────────────────────────────
            _loading
                ? const Center(child: CircularProgressIndicator())
                : FilledButton.icon(
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Schaden melden'),
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─── Success view ─────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 72,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Meldung eingegangen!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Die Hausverwaltung wurde informiert\nund wird sich um den Schaden kümmern.',
                style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.outline),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Schließen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
