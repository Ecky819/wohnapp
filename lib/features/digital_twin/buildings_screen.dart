import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/building.dart';
import '../../models/unit.dart';
import '../../repositories/building_repository.dart';
import '../../router.dart';
import '../../widgets/app_state_widgets.dart';

class BuildingsScreen extends ConsumerWidget {
  const BuildingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildingsAsync = ref.watch(buildingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gebäude & Wohnungen')),
      body: buildingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (buildings) => buildings.isEmpty
            ? const EmptyState(
                icon: Icons.location_city_outlined,
                title: 'Keine Gebäude vorhanden',
                subtitle:
                    'Lege Gebäude und Wohnungen in Firestore an.',
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: buildings.length,
                itemBuilder: (_, i) =>
                    _BuildingSection(building: buildings[i]),
              ),
      ),
    );
  }
}

// ─── Building section (expandable) ───────────────────────────────────────────

class _BuildingSection extends ConsumerWidget {
  const _BuildingSection({required this.building});
  final Building building;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitsAsync = ref.watch(unitsProvider(building.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.location_city_outlined,
              color: Colors.indigo),
          title: Text(building.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(building.address,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          children: [
            unitsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Fehler: $e',
                    style: const TextStyle(color: Colors.red)),
              ),
              data: (units) => units.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Text('Keine Wohnungen in diesem Gebäude.',
                          style: TextStyle(color: Colors.grey)),
                    )
                  : Column(
                      children: units
                          .map((u) => _UnitListTile(unit: u))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitListTile extends StatelessWidget {
  const _UnitListTile({required this.unit});
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: const Icon(Icons.apartment_outlined, size: 20),
      title: Text(unit.displayName,
          style: const TextStyle(fontSize: 14)),
      subtitle: unit.area != null
          ? Text('${unit.area!.toStringAsFixed(0)} m²',
              style: const TextStyle(fontSize: 12, color: Colors.grey))
          : null,
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => context.push(AppRoutes.unitDetailPath(unit.id)),
    );
  }
}
