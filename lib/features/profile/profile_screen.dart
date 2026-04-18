import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../repositories/building_repository.dart';
import '../../router.dart';
import '../../services/routing_service.dart';
import '../../user_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Remove FCM token so no notifications reach this device after logout
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
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (user) {
          if (user == null) return const SizedBox.shrink();
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

        const SizedBox(height: 40),

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
            : OutlinedButton(
                onPressed: _save,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                child: const Text('Speichern'),
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
