import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/app_user.dart';
import '../../models/invitation.dart';
import '../../repositories/invitation_repository.dart';
import '../../models/building.dart';
import '../../models/device.dart';
import '../../models/ticket.dart';
import '../../models/unit.dart';
import '../../repositories/building_repository.dart';
import '../../repositories/device_repository.dart';
import '../../repositories/ticket_repository.dart';
import '../../router.dart';
import '../../user_provider.dart';
import '../../widgets/app_state_widgets.dart';
import 'unit_qr_code_screen.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

/// Tenants (role=tenant_user) for the current user's tenant.
final _tenantsProvider = StreamProvider<List<AppUser>>((ref) {
  final tenantId = ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
  if (tenantId.isEmpty) return const Stream.empty();
  return ref.read(userRepositoryProvider).watchTenants(tenantId);
});

final _unitTicketsProvider = StreamProvider.family<List<Ticket>, String>((
  ref,
  unitId,
) {
  return ref.read(ticketRepositoryProvider).watchByUnit(unitId);
});

final _unitByIdProvider = FutureProvider.family<Unit?, String>((
  ref,
  unitId,
) async {
  final snap = await FirebaseFirestore.instance
      .collection('units')
      .doc(unitId)
      .get();
  if (!snap.exists) return null;
  return Unit.fromDoc(snap);
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class UnitDetailScreen extends ConsumerWidget {
  const UnitDetailScreen({super.key, required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitAsync = ref.watch(_unitByIdProvider(unitId));

    return Scaffold(
      appBar: AppBar(title: const Text('Wohnungsdetails')),
      body: unitAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (unit) => unit == null
            ? const ErrorState(message: 'Wohnung nicht gefunden.')
            : _UnitDetailBody(unit: unit),
      ),
      floatingActionButton: _AddDeviceFab(unitId: unitId),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _UnitDetailBody extends ConsumerWidget {
  const _UnitDetailBody({required this.unit});
  final Unit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider(unit.id));
    final ticketsAsync = ref.watch(_unitTicketsProvider(unit.id));
    final isManager =
        ref.watch(currentUserProvider).valueOrNull?.role == 'manager';

    final buildingsAsync = ref.watch(buildingsProvider);
    final buildingName =
        buildingsAsync.valueOrNull
            ?.firstWhere(
              (b) => b.id == unit.buildingId,
              orElse: () =>
                  const Building(id: '', name: '–', address: '', tenantId: ''),
            )
            .name ??
        '–';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Unit info card ────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.apartment_outlined,
                      size: 28,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        unit.displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isManager) ...[
                      IconButton(
                        icon: const Icon(Icons.qr_code_2_outlined),
                        tooltip: 'Gast-QR',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UnitQrCodeScreen(unit: unit),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_add_outlined),
                        tooltip: 'Einladungs-QR für Mieter',
                        onPressed: () => _showInviteQr(context, ref, unit),
                      ),
                    ],
                  ],
                ),
                const Divider(height: 24),
                _InfoRow(
                  icon: Icons.location_city_outlined,
                  label: 'Gebäude',
                  value: buildingName,
                ),
                if (unit.floor != null)
                  _InfoRow(
                    icon: Icons.stairs_outlined,
                    label: 'Etage',
                    value: '${unit.floor}. Obergeschoss',
                  ),
                if (unit.area != null)
                  _InfoRow(
                    icon: Icons.square_foot_outlined,
                    label: 'Fläche',
                    value: '${unit.area!.toStringAsFixed(1)} m²',
                  ),
                if (unit.buildYear != null)
                  _InfoRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Baujahr',
                    value: '${unit.buildYear}',
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Tenant assignment (manager only) ──────────────────────────
        if (isManager) _TenantAssignmentCard(unit: unit),

        const SizedBox(height: 20),

        // ── Maintenance alerts ────────────────────────────────────────
        _MaintenanceAlertsCard(devices: devicesAsync.valueOrNull ?? []),

        const SizedBox(height: 20),

        // ── Devices ───────────────────────────────────────────────────
        const Text(
          'Geräte & Installationen',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),

        devicesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(message: e.toString()),
          data: (devices) => devices.isEmpty
              ? EmptyState(
                  icon: Icons.devices_other_outlined,
                  title: 'Keine Geräte erfasst',
                  subtitle: isManager
                      ? 'Tippe auf + um ein Gerät hinzuzufügen.'
                      : null,
                )
              : Column(
                  children: devices
                      .map(
                        (d) => _DeviceTile(
                          device: d,
                          unitId: unit.id,
                          canEdit: isManager,
                        ),
                      )
                      .toList(),
                ),
        ),

        const SizedBox(height: 20),

        // ── Repair history ────────────────────────────────────────────
        const Text(
          'Reparaturhistorie',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),

        ticketsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(message: e.toString()),
          data: (tickets) => tickets.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Noch keine Tickets für diese Wohnung.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : Column(
                  children: tickets
                      .map((t) => _TicketHistoryTile(ticket: t))
                      .toList(),
                ),
        ),

        const SizedBox(height: 80),
      ],
    );
  }

  static const _regBaseUrl = 'https://wohnapp-mvp.web.app/register';

  Future<void> _showInviteQr(
      BuildContext context, WidgetRef ref, Unit unit) async {
    // Show loading while creating the invitation
    String? code;
    try {
      final tenantId =
          ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
      code = await ref.read(invitationRepositoryProvider).create(
            tenantId: tenantId,
            role: InvitationRole.tenantUser,
            validFor: const Duration(days: 365),
            unitId: unit.id,
            unitName: unit.displayName,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final regUrl = '$_regBaseUrl?code=$code';

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Einladungs-QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: regUrl, version: QrVersions.auto, size: 220),
            const SizedBox(height: 8),
            Text(code!,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4)),
            const SizedBox(height: 4),
            Text('Wohnung: ${unit.displayName}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text(
              'Mieter scannt diesen QR-Code mit der Kamera-App '
              'und registriert sich direkt für diese Wohnung.',
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
}

// ─── Tenant assignment card ───────────────────────────────────────────────────

class _TenantAssignmentCard extends ConsumerWidget {
  const _TenantAssignmentCard({required this.unit});
  final Unit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantsAsync = ref.watch(_tenantsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person_outlined, size: 18, color: Colors.grey),
                SizedBox(width: 8),
                Text('Mieter',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            tenantsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Fehler: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (tenants) {
                // Currently assigned tenant (if any)
                final assigned = tenants
                    .where((t) => t.unitId == unit.id)
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (assigned.isEmpty)
                      const Text('Keine Mieter zugewiesen',
                          style: TextStyle(color: Colors.grey))
                    else
                      ...assigned.map((t) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              child: Text(
                                t.name.isNotEmpty
                                    ? t.name[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(t.name.isNotEmpty ? t.name : t.email,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(t.email,
                                style: const TextStyle(fontSize: 11)),
                            trailing: IconButton(
                              icon: const Icon(Icons.person_remove_outlined,
                                  color: Colors.red, size: 18),
                              tooltip: 'Zuweisung aufheben',
                              onPressed: () => ref
                                  .read(userRepositoryProvider)
                                  .assignUnit(t.uid, null),
                            ),
                          )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: const Text('Mieter zuweisen'),
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        builder: (_) => _AssignTenantSheet(
                          unit: unit,
                          tenants: tenants,
                          onAssign: (uid) => ref
                              .read(userRepositoryProvider)
                              .assignUnit(uid, unit.id),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignTenantSheet extends StatefulWidget {
  const _AssignTenantSheet({
    required this.unit,
    required this.tenants,
    required this.onAssign,
  });
  final Unit unit;
  final List<AppUser> tenants;
  final Future<void> Function(String uid) onAssign;

  @override
  State<_AssignTenantSheet> createState() => _AssignTenantSheetState();
}

class _AssignTenantSheetState extends State<_AssignTenantSheet> {
  String? _selectedUid;
  bool _saving = false;

  List<AppUser> get _unassigned =>
      widget.tenants.where((t) => t.unitId == null || t.unitId!.isEmpty).toList();

  Future<void> _save() async {
    if (_selectedUid == null) return;
    setState(() => _saving = true);
    await widget.onAssign(_selectedUid!);
    if (mounted) Navigator.pop(context);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mieter zuweisen – ${widget.unit.displayName}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (_unassigned.isEmpty)
            const Text(
              'Alle Mieter sind bereits einer Wohnung zugewiesen.',
              style: TextStyle(color: Colors.grey),
            )
          else
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Mieter auswählen',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedUid,
              items: _unassigned
                  .map((t) => DropdownMenuItem(
                        value: t.uid,
                        child: Text(
                          t.name.isNotEmpty ? '${t.name} (${t.email})' : t.email,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedUid = v),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: _saving
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(
                    onPressed: _selectedUid != null ? _save : null,
                    child: const Text('Zuweisen'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Maintenance alerts card ──────────────────────────────────────────────────

class _MaintenanceAlertsCard extends StatelessWidget {
  const _MaintenanceAlertsCard({required this.devices});
  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    final alerts = devices
        .where((d) =>
            d.maintenanceStatus == MaintenanceStatus.overdue ||
            d.maintenanceStatus == MaintenanceStatus.dueSoon)
        .toList()
      ..sort((a, b) {
        final aDate = a.nextServiceDue ?? DateTime(9999);
        final bDate = b.nextServiceDue ?? DateTime(9999);
        return aDate.compareTo(bDate);
      });

    if (alerts.isEmpty) return const SizedBox.shrink();

    final hasOverdue =
        alerts.any((d) => d.maintenanceStatus == MaintenanceStatus.overdue);
    final color = hasOverdue ? Colors.red : Colors.orange;
    final df = DateFormat('dd.MM.yyyy');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            color.withValues(alpha: 0.08),
            Theme.of(context).colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                hasOverdue ? 'Wartung überfällig' : 'Wartung bald fällig',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...alerts.map((d) {
            final isOverdue = d.maintenanceStatus == MaintenanceStatus.overdue;
            final dueColor = isOverdue ? Colors.red : Colors.orange;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(d.category.icon, size: 16, color: dueColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(d.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                  Text(
                    d.nextServiceDue != null
                        ? df.format(d.nextServiceDue!)
                        : '–',
                    style: TextStyle(fontSize: 12, color: dueColor),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Device tile ──────────────────────────────────────────────────────────────

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({
    required this.device,
    required this.unitId,
    required this.canEdit,
  });
  final Device device;
  final String unitId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('dd.MM.yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            device.category.icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.category.label, style: const TextStyle(fontSize: 12)),
            if (device.manufacturer != null)
              Text(
                device.manufacturer!,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            if (device.lastServiceAt != null)
              Text(
                'Letzte Wartung: ${df.format(device.lastServiceAt!)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            _MaintenanceChip(device: device),
            if (device.warrantyUntil != null)
              _WarrantyChip(until: device.warrantyUntil!),
          ],
        ),
        trailing: canEdit
            ? PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'service') {
                    await ref
                        .read(deviceRepositoryProvider)
                        .updateLastService(unitId, device.id, DateTime.now());
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Wartungsdatum aktualisiert'),
                        ),
                      );
                    }
                  } else if (v == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Gerät löschen?'),
                        content: Text(
                          '„${device.name}" wird unwiderruflich entfernt.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Abbrechen'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Löschen'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref
                          .read(deviceRepositoryProvider)
                          .deleteDevice(unitId, device.id);
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'service',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.build_outlined),
                      title: Text('Wartung heute'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text(
                        'Löschen',
                        style: TextStyle(color: Colors.red),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _MaintenanceChip extends StatelessWidget {
  const _MaintenanceChip({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    final status = device.maintenanceStatus;
    if (status == MaintenanceStatus.ok) return const SizedBox.shrink();

    final (color, icon) = switch (status) {
      MaintenanceStatus.overdue => (Colors.red, Icons.warning_outlined),
      MaintenanceStatus.dueSoon => (Colors.orange, Icons.schedule_outlined),
      MaintenanceStatus.unknown => (Colors.grey, Icons.help_outline),
      _ => (Colors.grey, Icons.help_outline),
    };

    final df = DateFormat('dd.MM.yy');
    final dueLabel = device.nextServiceDue != null
        ? df.format(device.nextServiceDue!)
        : 'unbekannt';
    final text = status == MaintenanceStatus.unknown
        ? 'Keine Wartung erfasst'
        : '${status.label}: $dueLabel';

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _WarrantyChip extends StatelessWidget {
  const _WarrantyChip({required this.until});
  final DateTime until;

  @override
  Widget build(BuildContext context) {
    final active = DateTime.now().isBefore(until);
    final df = DateFormat('dd.MM.yyyy');
    return Row(
      children: [
        Icon(
          active ? Icons.verified_outlined : Icons.cancel_outlined,
          size: 12,
          color: active ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 4),
        Text(
          active ? 'Garantie bis ${df.format(until)}' : 'Garantie abgelaufen',
          style: TextStyle(
            fontSize: 11,
            color: active ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }
}

// ─── Ticket history tile ──────────────────────────────────────────────────────

class _TicketHistoryTile extends StatelessWidget {
  const _TicketHistoryTile({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yy');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(ticket.categoryIcon, size: 20, color: ticket.statusColor),
        title: Text(
          ticket.title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          ticket.createdAt != null ? df.format(ticket.createdAt!) : '–',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: AppStatusBadge(
          label: ticket.statusLabel,
          color: ticket.statusColor,
        ),
        onTap: () => context.push(AppRoutes.ticketDetailPath(ticket.id)),
      ),
    );
  }
}

// ─── Add device FAB ───────────────────────────────────────────────────────────

class _AddDeviceFab extends ConsumerWidget {
  const _AddDeviceFab({required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager =
        ref.watch(currentUserProvider).valueOrNull?.role == 'manager';
    if (!isManager) return const SizedBox.shrink();

    return FloatingActionButton(
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => _AddDeviceSheet(unitId: unitId),
      ),
      child: const Icon(Icons.add),
    );
  }
}

// ─── Add device sheet ─────────────────────────────────────────────────────────

class _AddDeviceSheet extends ConsumerStatefulWidget {
  const _AddDeviceSheet({required this.unitId});
  final String unitId;

  @override
  ConsumerState<_AddDeviceSheet> createState() => _AddDeviceSheetState();
}

class _AddDeviceSheetState extends ConsumerState<_AddDeviceSheet> {
  final _nameController = TextEditingController();
  final _manufacturerController = TextEditingController();
  DeviceCategory _category = DeviceCategory.general;
  int? _serviceIntervalMonths; // null = use category default
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _manufacturerController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _isLoading = true);

    final user = ref.read(currentUserProvider).valueOrNull;

    await ref.read(deviceRepositoryProvider).createDevice(
          unitId: widget.unitId,
          name: name,
          category: _category,
          tenantId: user?.tenantId,
          manufacturer: _manufacturerController.text.trim().isEmpty
              ? null
              : _manufacturerController.text.trim(),
          serviceIntervalMonths: _serviceIntervalMonths,
        );

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveInterval =
        _serviceIntervalMonths ?? _category.defaultIntervalMonths;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gerät hinzufügen',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          const Text('Kategorie',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<DeviceCategory>(
            showSelectedIcon: false,
            segments: DeviceCategory.values
                .map(
                  (c) => ButtonSegment(
                    value: c,
                    label: Text(c.label, style: const TextStyle(fontSize: 12)),
                    icon: Icon(c.icon, size: 16),
                  ),
                )
                .toList(),
            selected: {_category},
            onSelectionChanged: (s) => setState(() {
              _category = s.first;
              _serviceIntervalMonths = null; // reset to new category default
            }),
          ),

          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Bezeichnung',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _manufacturerController,
            decoration: const InputDecoration(
              labelText: 'Hersteller (optional)',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Wartungsintervall',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              DropdownButton<int>(
                value: effectiveInterval,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 6, child: Text('6 Monate')),
                  DropdownMenuItem(value: 12, child: Text('12 Monate')),
                  DropdownMenuItem(value: 24, child: Text('24 Monate')),
                  DropdownMenuItem(value: 36, child: Text('36 Monate')),
                ],
                onChanged: (v) =>
                    setState(() => _serviceIntervalMonths = v),
              ),
            ],
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Speichern'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Helper ───────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
