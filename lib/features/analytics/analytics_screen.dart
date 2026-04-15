import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../ticket_provider.dart';
import '../../widgets/app_state_widgets.dart';

// ─── Analytics data model ─────────────────────────────────────────────────────

class _AnalyticsData {
  const _AnalyticsData({
    required this.openCount,
    required this.inProgressCount,
    required this.doneCount,
    required this.damageCount,
    required this.maintenanceCount,
    required this.avgResolutionDays,
    required this.contractorStats,
  });

  final int openCount;
  final int inProgressCount;
  final int doneCount;
  final int damageCount;
  final int maintenanceCount;
  final double? avgResolutionDays;
  final List<_ContractorStat> contractorStats;

  int get total => openCount + inProgressCount + doneCount;
}

class _ContractorStat {
  const _ContractorStat({
    required this.name,
    required this.activeCount,
    required this.totalCount,
  });

  final String name;
  final int activeCount;
  final int totalCount;
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final _analyticsProvider = Provider<AsyncValue<_AnalyticsData>>((ref) {
  final ticketsAsync = ref.watch(allTicketsProvider);
  final contractorsAsync = ref.watch(contractorsProvider);

  return ticketsAsync.whenData((tickets) {
    final contractors = contractorsAsync.valueOrNull ?? <AppUser>[];

    // Status counts
    final open = tickets.where((t) => t.status == 'open').length;
    final inProgress = tickets.where((t) => t.status == 'in_progress').length;
    final done = tickets.where((t) => t.status == 'done').length;

    // Category counts
    final damage = tickets.where((t) => t.category == 'damage').length;
    final maintenance = tickets
        .where((t) => t.category == 'maintenance')
        .length;

    // Avg resolution time
    final resolved = tickets
        .where(
          (t) =>
              t.status == 'done' && t.createdAt != null && t.closedAt != null,
        )
        .toList();
    double? avgDays;
    if (resolved.isNotEmpty) {
      final totalHours = resolved.fold<double>(
        0,
        (sum, t) =>
            sum + t.closedAt!.difference(t.createdAt!).inHours.toDouble(),
      );
      avgDays = totalHours / resolved.length / 24;
    }

    // Contractor workload
    final stats = contractors.map((c) {
      final assigned = tickets.where((t) => t.assignedTo == c.uid);
      final active = assigned.where((t) => t.status != 'done').length;
      return _ContractorStat(
        name: c.name.isNotEmpty ? c.name : c.email,
        activeCount: active,
        totalCount: assigned.length,
      );
    }).toList()..sort((a, b) => b.activeCount.compareTo(a.activeCount));

    return _AnalyticsData(
      openCount: open,
      inProgressCount: inProgress,
      doneCount: done,
      damageCount: damage,
      maintenanceCount: maintenance,
      avgResolutionDays: avgDays,
      contractorStats: stats,
    );
  });
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_analyticsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (data) => _AnalyticsBody(data: data),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.data});
  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Status Overview ────────────────────────────────────────────
        _SectionHeader('Ticket-Status (${data.total} gesamt)'),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatCard(
              label: 'Offen',
              value: '${data.openCount}',
              color: Colors.orange,
              icon: Icons.inbox_outlined,
            ),
            const SizedBox(width: 10),
            _StatCard(
              label: 'In Bearbeitung',
              value: '${data.inProgressCount}',
              color: Colors.blue,
              icon: Icons.engineering_outlined,
            ),
            const SizedBox(width: 10),
            _StatCard(
              label: 'Erledigt',
              value: '${data.doneCount}',
              color: Colors.green,
              icon: Icons.check_circle_outline,
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ── Avg Resolution ─────────────────────────────────────────────
        const _SectionHeader('Ø Bearbeitungszeit'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 32,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 16),
                data.avgResolutionDays != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${data.avgResolutionDays!.toStringAsFixed(1)} Tage',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'aus ${data.doneCount} erledigten Tickets',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Noch keine erledigten Tickets',
                        style: TextStyle(color: Colors.grey),
                      ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Kategorie ─────────────────────────────────────────────────
        const _SectionHeader('Kategorie'),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatCard(
              label: 'Schäden',
              value: '${data.damageCount}',
              color: Colors.red,
              icon: Icons.report_problem_outlined,
            ),
            const SizedBox(width: 10),
            _StatCard(
              label: 'Wartungen',
              value: '${data.maintenanceCount}',
              color: Colors.teal,
              icon: Icons.build_circle_outlined,
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ── Contractor Workload ────────────────────────────────────────
        const _SectionHeader('Handwerker-Auslastung'),
        const SizedBox(height: 10),
        if (data.contractorStats.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Noch keine Handwerker im System.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ...data.contractorStats.map(
            (stat) => _ContractorWorkloadTile(stat: stat),
          ),

        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContractorWorkloadTile extends StatelessWidget {
  const _ContractorWorkloadTile({required this.stat});
  final _ContractorStat stat;

  @override
  Widget build(BuildContext context) {
    // Cap bar at 10 active tickets = 100 %
    final fraction = (stat.activeCount / 10).clamp(0.0, 1.0);
    final color = fraction < 0.4
        ? Colors.green
        : fraction < 0.7
        ? Colors.orange
        : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stat.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${stat.activeCount} aktiv / ${stat.totalCount} gesamt',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
