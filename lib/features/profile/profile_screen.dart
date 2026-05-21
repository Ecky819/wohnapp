import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../models/notification_preferences.dart';
import '../../repositories/building_repository.dart';
import '../../router.dart';
import '../../services/routing_service.dart';
import '../../user_provider.dart';
import '../../utils/app_exception.dart';
import '../../widgets/app_state_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text('Möchtest du dich wirklich abmelden?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': FieldValue.delete()});
    }
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mein Profil')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: userMessage(e)),
        data: (user) {
          if (user == null) {
            return const ErrorState(
              message: 'Sitzung abgelaufen. Bitte neu anmelden.',
            );
          }
          return _ProfileBody(user: user, onLogout: () => _logout(context));
        },
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.user, required this.onLogout});
  final AppUser user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── Avatar ────────────────────────────────────────────────────
        Center(
          child: CircleAvatar(
            radius: 40,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 32),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // ── Info rows ────────────────────────────────────────────────
        _InfoRow(label: 'Name', value: user.name.isNotEmpty ? user.name : '–'),
        const Divider(),
        _InfoRow(label: 'E-Mail', value: user.email),
        const Divider(),
        _InfoRow(label: 'Rolle', value: user.roleLabel),

        // ── Assigned unit (tenant_user only) ──────────────────────────
        if (user.role == 'tenant_user') ...[
          const Divider(),
          _AssignedUnitSection(user: user),
        ],

        // ── Specializations (contractor only) ─────────────────────────
        if (user.role == 'contractor') ...[
          const Divider(),
          const SizedBox(height: 8),
          const Text('Fachgebiete',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 10),
          _SpecializationsEditor(user: user),
        ],

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 8),

        // ── Benachrichtigungseinstellungen ────────────────────────────
        _NotificationSettingsSection(user: user),

        const SizedBox(height: 32),

        // ── Logout ───────────────────────────────────────────────────
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Abmelden'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: onLogout,
        ),

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 8),

        // ── DSGVO ────────────────────────────────────────────────────
        _DsgvoSection(user: user),
      ],
    );
  }
}

// ─── Assigned unit section (tenant_user) ─────────────────────────────────────

class _AssignedUnitSection extends ConsumerWidget {
  const _AssignedUnitSection({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitId = user.unitId;

    if (unitId == null || unitId.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Wohnung', style: TextStyle(color: Colors.grey)),
            TextButton.icon(
              icon: const Icon(Icons.add_home_outlined, size: 16),
              label: const Text('Noch keine Wohnung'),
              onPressed: () => context.push(AppRoutes.buildings),
            ),
          ],
        ),
      );
    }

    final unitAsync = ref.watch(unitByIdProvider(unitId));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Wohnung', style: TextStyle(color: Colors.grey)),
          unitAsync.when(
            loading: () => const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, __) => const Text('–'),
            data: (unit) => GestureDetector(
              onTap: unit != null
                  ? () => context.push(AppRoutes.unitDetailPath(unit.id))
                  : null,
              child: Row(
                children: [
                  Text(
                    unit?.displayName ?? '–',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (unit != null)
                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Specializations editor ───────────────────────────────────────────────────

class _SpecializationsEditor extends ConsumerStatefulWidget {
  const _SpecializationsEditor({required this.user});
  final AppUser user;

  @override
  ConsumerState<_SpecializationsEditor> createState() =>
      _SpecializationsEditorState();
}

class _SpecializationsEditorState
    extends ConsumerState<_SpecializationsEditor> {
  late Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.user.specializations);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(userRepositoryProvider)
        .updateSpecializations(widget.user.uid, _selected.toList());
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fachgebiete gespeichert')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: routingCategories.entries.map((e) {
            final selected = _selected.contains(e.key);
            return FilterChip(
              label: Text(e.value),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _selected.add(e.key);
                  } else {
                    _selected.remove(e.key);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          _selected.isEmpty
              ? 'Kein Fachgebiet = für alle Kategorien verfügbar.'
              : '${_selected.length} Fachgebiet(e) gewählt.',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        _saving
            ? const Center(child: CircularProgressIndicator())
            : Row(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _selected =
                          Set<String>.from(widget.user.specializations);
                    }),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Zurücksetzen'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Speichern'),
                  ),
                ],
              ),
      ],
    );
  }
}

// ─── Helper ───────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── Benachrichtigungseinstellungen ──────────────────────────────────────────

class _NotificationSettingsSection extends ConsumerStatefulWidget {
  const _NotificationSettingsSection({required this.user});
  final AppUser user;

  @override
  ConsumerState<_NotificationSettingsSection> createState() =>
      _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState
    extends ConsumerState<_NotificationSettingsSection> {
  late NotificationPreferences _prefs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefs = widget.user.notificationPreferences;
  }

  Future<void> _toggle(NotificationPreferences updated) async {
    setState(() {
      _prefs = updated;
      _saving = true;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .updateNotificationPreferences(widget.user.uid, updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.user.role;

    // Welche Toggles pro Rolle anzeigen
    final items = <({String label, String subtitle, bool value, NotificationPreferences Function(bool) update})>[
      if (role == 'manager' || role == 'tenant_user' || role == 'contractor')
        (
          label: 'Ticket-Status geändert',
          subtitle: role == 'manager'
              ? 'Statuswechsel auf allen Tickets'
              : 'Mein Ticket hat sich geändert',
          value: _prefs.ticketStatusChanged,
          update: (v) => _prefs.copyWith(ticketStatusChanged: v),
        ),
      if (role == 'contractor')
        (
          label: 'Ticket zugewiesen',
          subtitle: 'Neues Ticket für mich',
          value: _prefs.ticketAssigned,
          update: (v) => _prefs.copyWith(ticketAssigned: v),
        ),
      if (role == 'manager' || role == 'tenant_user' || role == 'contractor')
        (
          label: 'Neuer Kommentar',
          subtitle: 'Kommentar auf einem meiner Tickets',
          value: _prefs.newComment,
          update: (v) => _prefs.copyWith(newComment: v),
        ),
      if (role == 'manager')
        (
          label: 'Neue Rechnung',
          subtitle: 'Handwerker reicht Rechnung ein',
          value: _prefs.invoiceSubmitted,
          update: (v) => _prefs.copyWith(invoiceSubmitted: v),
        ),
      if (role == 'manager')
        (
          label: 'Wartungsalert',
          subtitle: 'Gerät überfällig oder bald fällig',
          value: _prefs.maintenanceAlert,
          update: (v) => _prefs.copyWith(maintenanceAlert: v),
        ),
      if (role == 'tenant_user')
        (
          label: 'Neue Jahresabrechnung',
          subtitle: 'Betriebskostenabrechnung verfügbar',
          value: _prefs.statementCreated,
          update: (v) => _prefs.copyWith(statementCreated: v),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.notifications_outlined, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            const Text(
              'Benachrichtigungen',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            if (_saving) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Wähle welche Push-Benachrichtigungen du erhalten möchtest.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(item.label,
                style: const TextStyle(fontSize: 14)),
            subtitle: Text(item.subtitle,
                style: const TextStyle(fontSize: 12)),
            value: item.value,
            onChanged: _saving ? null : (v) => _toggle(item.update(v)),
          ),
        ),
      ],
    );
  }
}

// ─── DSGVO-Sektion ────────────────────────────────────────────────────────────

class _DsgvoSection extends ConsumerStatefulWidget {
  const _DsgvoSection({required this.user});
  final AppUser user;

  @override
  ConsumerState<_DsgvoSection> createState() => _DsgvoSectionState();
}

class _DsgvoSectionState extends ConsumerState<_DsgvoSection> {
  bool _isExporting = false;
  bool _isDeleting = false;

  // ── Datenexport ───────────────────────────────────────────────────────────

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final db = FirebaseFirestore.instance;

      final userDoc = await db.collection('users').doc(uid).get();
      final ticketsSnap = await db
          .collection('tickets')
          .where('createdBy', isEqualTo: uid)
          .limit(200)
          .get();

      final d = userDoc.data() ?? {};
      final buffer = StringBuffer()
        ..writeln('=== Meine Daten (DSGVO Art. 20) ===')
        ..writeln('Exportiert am: ${DateTime.now().toIso8601String()}')
        ..writeln()
        ..writeln('--- Profil ---')
        ..writeln('Name:    ${d['name'] ?? '–'}')
        ..writeln('E-Mail:  ${d['email'] ?? '–'}')
        ..writeln('Rolle:   ${d['role'] ?? '–'}')
        ..writeln('Mandant: ${d['tenantId'] ?? '–'}')
        ..writeln('Angelegt: ${(d['createdAt'] as dynamic)?.toDate() ?? '–'}')
        ..writeln()
        ..writeln('--- Meine Tickets (${ticketsSnap.docs.length}) ---');

      for (final doc in ticketsSnap.docs) {
        final t = doc.data();
        buffer.writeln(
          '• ${t['title'] ?? '–'} [${t['status'] ?? '–'}] '
          '${(t['createdAt'] as dynamic)?.toDate() ?? ''}',
        );
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Meine Daten (DSGVO Art. 20)'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                buffer.toString(),
                style:
                    const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Kopieren'),
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: buffer.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Daten kopiert')),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── Konto löschen ─────────────────────────────────────────────────────────

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Konto löschen?'),
        content: const Text(
          'Ihr Konto wird unwiderruflich gelöscht. '
          'Tickets und Aktivitäten bleiben aus Protokollgründen anonym erhalten.\n\n'
          'Dieser Vorgang kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Konto löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await _performDelete();
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _performDelete() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Nutzerdokument als gelöscht markieren (kein Hard-Delete: Audit-Trail)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'deletedAt': FieldValue.serverTimestamp(),
        'fcmToken': FieldValue.delete(),
      });

      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted) await _reauthAndDelete(user);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: ${e.message}')),
          );
        }
      }
    }
  }

  Future<void> _reauthAndDelete(User user) async {
    final passwordCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Passwort bestätigen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Für die Kontolöschung ist eine erneute Anmeldung erforderlich.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Passwort',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bestätigen & löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email ?? '',
        password: passwordCtrl.text,
      );
      await user.reauthenticateWithCredential(credential);
      await _performDelete();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Authentifizierung fehlgeschlagen: ${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.shield_outlined, size: 18, color: Colors.grey),
            SizedBox(width: 8),
            Text(
              'Datenschutz (DSGVO)',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Sie haben das Recht auf Auskunft und Löschung Ihrer Daten.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 16),
                label: const Text('Daten exportieren'),
                onPressed: _isExporting ? null : _exportData,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: _isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.red),
                      )
                    : const Icon(Icons.delete_forever_outlined,
                        size: 16, color: Colors.red),
                label: const Text('Konto löschen',
                    style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: _isDeleting ? null : _deleteAccount,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
