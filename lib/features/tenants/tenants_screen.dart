import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../models/unit.dart';
import '../../repositories/building_repository.dart';
import '../../router.dart';
import '../../user_provider.dart';
import '../../widgets/app_state_widgets.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _allTenantsProvider = StreamProvider<List<AppUser>>((ref) {
  final tenantId = ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
  if (tenantId.isEmpty) return const Stream.empty();
  return ref.read(userRepositoryProvider).watchTenants(tenantId);
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class TenantsScreen extends ConsumerWidget {
  const TenantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantsAsync = ref.watch(_allTenantsProvider);
    final units = ref.watch(_allUnitsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mieter')),
      body: tenantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (tenants) {
          if (tenants.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline,
              title: 'Keine Mieter vorhanden',
              subtitle: 'Einladungen erstellen um Mieter hinzuzufügen.',
            );
          }

          final unitById = {for (final u in units) u.id: u};

          final assigned =
              tenants.where((t) => t.unitId != null && t.unitId!.isNotEmpty).toList();
          final unassigned =
              tenants.where((t) => t.unitId == null || t.unitId!.isEmpty).toList();

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (assigned.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Wohnung zugewiesen',
                  count: assigned.length,
                  color: Colors.green,
                ),
                ...assigned.map((t) => _TenantTile(
                      tenant: t,
                      unit: t.unitId != null ? unitById[t.unitId] : null,
                    )),
              ],
              if (unassigned.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Keine Wohnung',
                  count: unassigned.length,
                  color: Colors.orange,
                ),
                ...unassigned.map((t) => _TenantTile(tenant: t, unit: null)),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Provider: alle Units des Tenants ────────────────────────────────────────

/// Flat list of all units across all buildings for the current tenant.
/// Uses a regular Provider that watches each building's unitsProvider individually.
final _allUnitsProvider = Provider<List<Unit>>((ref) {
  final buildings = ref.watch(buildingsProvider).valueOrNull ?? [];
  return buildings
      .expand<Unit>((b) => ref.watch(unitsProvider(b.id)).valueOrNull ?? [])
      .toList();
});

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tenant tile ──────────────────────────────────────────────────────────────

class _TenantTile extends ConsumerWidget {
  const _TenantTile({required this.tenant, required this.unit});
  final AppUser tenant;
  final Unit? unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          tenant.name.isNotEmpty ? tenant.name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        tenant.name.isNotEmpty ? tenant.name : tenant.email,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        tenant.name.isNotEmpty ? tenant.email : '',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: unit != null
          ? _UnitChip(unit: unit!)
          : const _UnassignedChip(),
      onTap: unit != null
          ? () => context.push(AppRoutes.unitDetailPath(unit!.id))
          : null,
    );
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({required this.unit});
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.apartment_outlined,
              size: 12, color: Colors.green),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              unit.displayName,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.green,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnassignedChip extends StatelessWidget {
  const _UnassignedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: const Text(
        'Keine Wohnung',
        style: TextStyle(
            fontSize: 11,
            color: Colors.orange,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
