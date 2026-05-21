import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/building.dart';
import '../../models/invitation.dart';
import '../../models/unit.dart';
import '../../repositories/building_repository.dart';
import '../../repositories/invitation_repository.dart';
import '../../repositories/tenant_repository.dart';
import '../../services/rate_limiter.dart';
import '../../user_provider.dart';
import '../../utils/app_exception.dart';
import '../../widgets/app_state_widgets.dart';

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
        error: (e, _) => Center(child: Text(userMessage(e))),
        data: (invitations) => invitations.isEmpty
            ? const EmptyState(
                icon: Icons.mail_outlined,
                title: 'Noch keine Einladungen',
                subtitle:
                    'Tippe auf „Einladung erstellen" um Mieter oder Handwerker einzuladen.',
              )
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

class _InvitationCard extends ConsumerWidget {
  const _InvitationCard({required this.inv});
  final Invitation inv;

  static const _fallbackBaseUrl = 'https://wohnapp-mvp.web.app/register';

  String _registrationUrl(WidgetRef ref) {
    final tenant = ref.read(tenantProvider).valueOrNull;
    final base = (tenant?.registrationBaseUrl?.isNotEmpty == true)
        ? tenant!.registrationBaseUrl!
        : _fallbackBaseUrl;
    return '$base?code=${inv.code}';
  }

  void _showQrDialog(BuildContext context, WidgetRef ref) {
    final regUrl = _registrationUrl(ref);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Einladungs-QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: regUrl, version: QrVersions.auto, size: 220),
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
  Widget build(BuildContext context, WidgetRef ref) {
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
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Kopieren',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: inv.code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code kopiert')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.qr_code, size: 18),
              tooltip: 'QR-Code anzeigen',
              onPressed: () => _showQrDialog(context, ref),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${inv.roleLabel}'
                '${inv.unitName != null ? ' · ${inv.unitName}' : ''}'),
            if (inv.expiresAt != null)
              Text('Läuft ab: ${df.format(inv.expiresAt!)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
  String? _generatedUrl;

  // Unit selection (only relevant for tenantUser)
  Building? _selectedBuilding;
  Unit? _selectedUnit;
  List<Unit> _buildingUnits = [];

  Future<void> _onBuildingChanged(Building? b) async {
    if (b == null) {
      setState(() {
        _selectedBuilding = null;
        _selectedUnit = null;
        _buildingUnits = [];
      });
      return;
    }
    final tenantId =
        ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
    final units = await ref
        .read(buildingRepositoryProvider)
        .watchUnits(b.id, tenantId)
        .first;
    setState(() {
      _selectedBuilding = b;
      _selectedUnit = null;
      _buildingUnits = units;
    });
  }

  Future<void> _create() async {
    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      RateLimiter.instance.checkOrThrow(
        'create_invitation_${user?.uid}',
        cooldown: const Duration(seconds: 10),
      );
      final tenantId = user?.tenantId ?? 'tenant_1';

      final code = await ref.read(invitationRepositoryProvider).create(
            tenantId: tenantId,
            role: _role,
            validFor: Duration(days: _validDays),
            unitId: _selectedUnit?.id,
            unitName: _selectedUnit?.name,
          );

      // Build registration URL so the QR code is immediately scannable
      final tenant = ref.read(tenantProvider).valueOrNull;
      const fallback = 'https://wohnapp-mvp.web.app/register';
      final base = (tenant?.registrationBaseUrl?.isNotEmpty == true)
          ? tenant!.registrationBaseUrl!
          : fallback;

      setState(() {
        _generatedCode = code;
        _generatedUrl = '$base?code=$code';
      });
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage(e))),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final buildingsAsync = ref.watch(buildingsProvider);
    final buildings = buildingsAsync.valueOrNull ?? [];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _generatedCode != null
          ? _CodeResult(
              code: _generatedCode!,
              registrationUrl: _generatedUrl!,
              unitName: _selectedUnit?.name,
            )
          : _CreateForm(
              role: _role,
              validDays: _validDays,
              isLoading: _isLoading,
              buildings: buildings,
              buildingUnits: _buildingUnits,
              selectedBuilding: _selectedBuilding,
              selectedUnit: _selectedUnit,
              onRoleChanged: (r) => setState(() {
                _role = r;
                _selectedBuilding = null;
                _selectedUnit = null;
                _buildingUnits = [];
              }),
              onDaysChanged: (d) => setState(() => _validDays = d),
              onBuildingChanged: _onBuildingChanged,
              onUnitChanged: (u) => setState(() => _selectedUnit = u),
              onCreate: _create,
            ),
    );
  }
}

// ─── Create form ──────────────────────────────────────────────────────────────

class _CreateForm extends StatelessWidget {
  const _CreateForm({
    required this.role,
    required this.validDays,
    required this.isLoading,
    required this.buildings,
    required this.buildingUnits,
    required this.selectedBuilding,
    required this.selectedUnit,
    required this.onRoleChanged,
    required this.onDaysChanged,
    required this.onBuildingChanged,
    required this.onUnitChanged,
    required this.onCreate,
  });

  final InvitationRole role;
  final int validDays;
  final bool isLoading;
  final List<Building> buildings;
  final List<Unit> buildingUnits;
  final Building? selectedBuilding;
  final Unit? selectedUnit;
  final ValueChanged<InvitationRole> onRoleChanged;
  final ValueChanged<int> onDaysChanged;
  final ValueChanged<Building?> onBuildingChanged;
  final ValueChanged<Unit?> onUnitChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
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

          // ── Wohnungszuweisung (nur für Mieter) ──────────────────────
          if (role == InvitationRole.tenantUser) ...[
            const SizedBox(height: 20),
            const Text('Wohnung zuweisen',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Optional — der Mieter sieht nach Registrierung nur seine Wohnung.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            DropdownButton<Building?>(
              isExpanded: true,
              value: selectedBuilding,
              hint: const Text('Gebäude wählen (optional)'),
              items: [
                const DropdownMenuItem<Building?>(
                  value: null,
                  child: Text('— Kein Gebäude —'),
                ),
                ...buildings.map((b) => DropdownMenuItem<Building?>(
                      value: b,
                      child: Text(b.name),
                    )),
              ],
              onChanged: onBuildingChanged,
            ),
            if (selectedBuilding != null) ...[
              const SizedBox(height: 8),
              DropdownButton<Unit?>(
                key: ValueKey(selectedBuilding?.id),
                isExpanded: true,
                value: selectedUnit,
                hint: const Text('Wohnung wählen'),
                items: buildingUnits
                    .map((u) => DropdownMenuItem<Unit?>(
                          value: u,
                          child: Text(u.displayName),
                        ))
                    .toList(),
                onChanged: onUnitChanged,
              ),
            ],
          ],

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
      ),
    );
  }
}

// ─── Code result ──────────────────────────────────────────────────────────────

class _CodeResult extends StatelessWidget {
  const _CodeResult({
    required this.code,
    required this.registrationUrl,
    this.unitName,
  });
  final String code;
  final String registrationUrl;
  final String? unitName;

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
          if (unitName != null) ...[
            const SizedBox(height: 4),
            Text('Wohnung: $unitName',
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ],
          const SizedBox(height: 20),
          // QR-Code mit vollständiger Registrierungs-URL
          QrImageView(
            data: registrationUrl,
            version: QrVersions.auto,
            size: 200,
          ),
          const SizedBox(height: 8),
          Text(
            'Mieter scannt diesen Code mit der Kamera-App.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Link kopieren'),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: registrationUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link kopiert')),
                  );
                },
              ),
            ],
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
