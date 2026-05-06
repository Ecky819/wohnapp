import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/invitation.dart';
import '../../repositories/invitation_repository.dart';
import '../../user_provider.dart';

final _invitationsStreamProvider = StreamProvider<List<Invitation>>((ref) {
  return ref.watch(invitationRepositoryProvider).watchAll();
});

class InvitationsScreen extends ConsumerWidget {
  const InvitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitationsAsync = ref.watch(_invitationsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einladungen')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Einladung erstellen'),
        onPressed: () => _showCreateSheet(context, ref),
      ),
      body: invitationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (invitations) => invitations.isEmpty
            ? const Center(child: Text('Noch keine Einladungen'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: invitations.length,
                itemBuilder: (_, i) => _InvitationCard(inv: invitations[i]),
              ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CreateInvitationSheet(),
    );
  }
}

// ─── Einladungs-Card ──────────────────────────────────────────────────────────

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({required this.inv});
  final Invitation inv;

  static const _regBaseUrl = 'https://wohnapp-mvp.web.app/register';

  void _showQrDialog(BuildContext context, Invitation inv) {
    final regUrl = '$_regBaseUrl?code=${inv.code}';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Einladungs-QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: regUrl,
              version: QrVersions.auto,
              size: 220,
            ),
            const SizedBox(height: 8),
            Text(
              inv.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            if (inv.unitName != null) ...[
              const SizedBox(height: 4),
              Text('Wohnung: ${inv.unitName}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 8),
            const Text(
              'Mieter scannt diesen QR-Code mit der Kamera-App\num sich direkt zu registrieren.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: regUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link kopiert')),
              );
            },
            child: const Text('Link kopieren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yy HH:mm');
    final statusColor = inv.used
        ? Colors.grey
        : inv.isExpired
            ? Colors.red
            : Colors.green;
    final statusLabel =
        inv.used ? 'Verwendet' : inv.isExpired ? 'Abgelaufen' : 'Aktiv';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(
            inv.role == InvitationRole.contractor
                ? Icons.handyman_outlined
                : Icons.home_outlined,
            color: statusColor,
          ),
        ),
        title: Row(
          children: [
            Text(inv.code,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Kopieren',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: inv.code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code kopiert')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.qr_code, size: 16),
              tooltip: 'QR-Code anzeigen',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _showQrDialog(context, inv),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${inv.roleLabel} · Tenant ${inv.tenantId}'),
            if (inv.expiresAt != null)
              Text('Läuft ab: ${df.format(inv.expiresAt!)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: statusColor),
          ),
          child: Text(statusLabel,
              style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ─── Einladung erstellen Sheet ────────────────────────────────────────────────

class _CreateInvitationSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CreateInvitationSheet> createState() =>
      _CreateInvitationSheetState();
}

class _CreateInvitationSheetState
    extends ConsumerState<_CreateInvitationSheet> {
  InvitationRole _role = InvitationRole.tenantUser;
  int _validDays = 7;
  bool _isLoading = false;
  String? _generatedCode;

  Future<void> _create() async {
    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      final tenantId = user?.tenantId ?? 'tenant_1';

      final code = await ref.read(invitationRepositoryProvider).create(
            tenantId: tenantId,
            role: _role,
            validFor: Duration(days: _validDays),
          );

      setState(() => _generatedCode = code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _generatedCode != null
          ? _CodeResult(code: _generatedCode!)
          : _CreateForm(
              role: _role,
              validDays: _validDays,
              isLoading: _isLoading,
              onRoleChanged: (r) => setState(() => _role = r),
              onDaysChanged: (d) => setState(() => _validDays = d),
              onCreate: _create,
            ),
    );
  }
}

class _CreateForm extends StatelessWidget {
  const _CreateForm({
    required this.role,
    required this.validDays,
    required this.isLoading,
    required this.onRoleChanged,
    required this.onDaysChanged,
    required this.onCreate,
  });

  final InvitationRole role;
  final int validDays;
  final bool isLoading;
  final ValueChanged<InvitationRole> onRoleChanged;
  final ValueChanged<int> onDaysChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Einladung erstellen',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),

        const Text('Rolle', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<InvitationRole>(
          segments: const [
            ButtonSegment(
              value: InvitationRole.tenantUser,
              label: Text('Mieter'),
              icon: Icon(Icons.home_outlined),
            ),
            ButtonSegment(
              value: InvitationRole.contractor,
              label: Text('Handwerker'),
              icon: Icon(Icons.handyman_outlined),
            ),
          ],
          selected: {role},
          onSelectionChanged: (s) => onRoleChanged(s.first),
        ),

        const SizedBox(height: 20),

        const Text('Gültig für',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1 Tag')),
            ButtonSegment(value: 7, label: Text('7 Tage')),
            ButtonSegment(value: 30, label: Text('30 Tage')),
          ],
          selected: {validDays},
          onSelectionChanged: (s) => onDaysChanged(s.first),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: onCreate,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Code generieren'),
                ),
        ),
      ],
    );
  }
}

class _CodeResult extends StatelessWidget {
  const _CodeResult({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 12),
          const Text('Einladungscode erstellt',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          // QR code
          QrImageView(
            data: code,
            version: QrVersions.auto,
            size: 200,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 6,
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Code kopieren'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code kopiert')),
              );
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }
}
