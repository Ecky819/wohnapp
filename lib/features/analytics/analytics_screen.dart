import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../models/app_user.dart';
import '../../ticket_provider.dart';
import '../../widgets/app_state_widgets.dart';

// ─── Data models ──────────────────────────────────────────────────────────────

class _MonthlyBucket {
  const _MonthlyBucket({
    required this.label,
    required this.count,
    required this.avgDays,
  });
  final String label; // e.g. "Jan"
  final int count;
  final double? avgDays;
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

class _AnalyticsData {
  const _AnalyticsData({
    required this.openCount,
    required this.inProgressCount,
    required this.doneCount,
    required this.damageCount,
    required this.maintenanceCount,
    required this.avgResolutionDays,
    required this.contractorStats,
    required this.monthlyBuckets,
  });

  final int openCount;
  final int inProgressCount;
  final int doneCount;
  final int damageCount;
  final int maintenanceCount;
  final double? avgResolutionDays;
  final List<_ContractorStat> contractorStats;
  final List<_MonthlyBucket> monthlyBuckets;

  int get total => openCount + inProgressCount + doneCount;
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final _analyticsProvider = Provider<AsyncValue<_AnalyticsData>>((ref) {
  final ticketsAsync = ref.watch(allTicketsProvider);
  final contractorsAsync = ref.watch(contractorsProvider);

  return ticketsAsync.whenData((tickets) {
    final contractors = contractorsAsync.valueOrNull ?? <AppUser>[];
    final now = DateTime.now();

    // Status counts
    final open = tickets.where((t) => t.status == 'open').length;
    final inProgress = tickets.where((t) => t.status == 'in_progress').length;
    final done = tickets.where((t) => t.status == 'done').length;

    // Category counts
    final damage = tickets.where((t) => t.category == 'damage').length;
    final maintenance = tickets
        .where((t) => t.category == 'maintenance')
        .length;

    // Overall avg resolution time
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

    // Monthly buckets — letzte 6 Monate
    final buckets = <_MonthlyBucket>[];
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthTickets = tickets.where((t) {
        final d = t.createdAt;
        return d != null && d.year == month.year && d.month == month.month;
      }).toList();

      final monthResolved = monthTickets
          .where(
            (t) =>
                t.status == 'done' && t.createdAt != null && t.closedAt != null,
          )
          .toList();
      double? monthAvg;
      if (monthResolved.isNotEmpty) {
        final h = monthResolved.fold<double>(
          0,
          (s, t) => s + t.closedAt!.difference(t.createdAt!).inHours.toDouble(),
        );
        monthAvg = h / monthResolved.length / 24;
      }

      buckets.add(
        _MonthlyBucket(
          label: DateFormat('MMM', 'de_DE').format(month),
          count: monthTickets.length,
          avgDays: monthAvg,
        ),
      );
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
      monthlyBuckets: buckets,
    );
  });
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  bool _exporting = false;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _decFmt = NumberFormat('0.0', 'de_DE');

  String _buildCsv(_AnalyticsData data) {
    const conv = ListToCsvConverter(fieldDelimiter: ';', eol: '\r\n');

    final rows = <List<dynamic>>[
      // Header
      ['Analytics-Export', 'Erstellt am ${_dateFmt.format(DateTime.now())}'],
      [],

      // Monatsübersicht
      ['Monatsübersicht'],
      ['Monat', 'Tickets', 'Ø Bearbeitungszeit (Tage)'],
      ...data.monthlyBuckets.map(
        (b) => [
          b.label,
          b.count,
          b.avgDays != null ? _decFmt.format(b.avgDays) : '–',
        ],
      ),
      [],

      // Status
      ['Status-Verteilung'],
      ['Offen', 'In Bearbeitung', 'Erledigt', 'Gesamt'],
      [data.openCount, data.inProgressCount, data.doneCount, data.total],
      [],

      // Kategorie
      ['Kategorie'],
      ['Schäden', 'Wartungen'],
      [data.damageCount, data.maintenanceCount],
      [],

      // Handwerker
      if (data.contractorStats.isNotEmpty) ...[
        ['Handwerker-Auslastung'],
        ['Name', 'Aktive Tickets', 'Tickets gesamt'],
        ...data.contractorStats.map(
          (s) => [s.name, s.activeCount, s.totalCount],
        ),
      ],

      // Gesamt Ø
      [],
      ['Gesamt Ø Bearbeitungszeit (Tage)'],
      [
        data.avgResolutionDays != null
            ? _decFmt.format(data.avgResolutionDays)
            : '–',
      ],
    ];

    return conv.convert(rows);
  }

  Future<void> _export(_AnalyticsData data) async {
    setState(() => _exporting = true);
    try {
      final csv = _buildCsv(data);
      final bytes = Uint8List.fromList(csv.codeUnits);
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'analytics_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(_analyticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          dataAsync.whenOrNull(
                data: (data) => _exporting
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: 'Als CSV exportieren',
                        onPressed: () => _export(data),
                      ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (data) => _AnalyticsBody(data: data),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.data});
  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Tickets pro Monat ──────────────────────────────────────────
        const _SectionHeader('Tickets pro Monat'),
        const SizedBox(height: 12),
        _MonthlyBarChart(buckets: data.monthlyBuckets),

        const SizedBox(height: 24),

        // ── Status-Verteilung ──────────────────────────────────────────
        _SectionHeader('Status-Verteilung (${data.total} gesamt)'),
        const SizedBox(height: 12),
        _StatusDonutChart(data: data),

        const SizedBox(height: 24),

        // ── Ø Bearbeitungszeit pro Monat ───────────────────────────────
        const _SectionHeader('Ø Bearbeitungszeit pro Monat (Tage)'),
        const SizedBox(height: 12),
        _ResolutionLineChart(buckets: data.monthlyBuckets),

        const SizedBox(height: 24),

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

        const SizedBox(height: 24),

        // ── Handwerker-Auslastung ──────────────────────────────────────
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
          ...data.contractorStats.map((s) => _ContractorWorkloadTile(stat: s)),

        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Bar-Chart: Tickets pro Monat ─────────────────────────────────────────────

class _MonthlyBarChart extends StatelessWidget {
  const _MonthlyBarChart({required this.buckets});
  final List<_MonthlyBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final maxY = buckets.fold<double>(
      0,
      (m, b) => b.count > m ? b.count.toDouble() : m,
    );
    final chartMaxY = (maxY < 4 ? 4 : (maxY * 1.25)).ceilToDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
        child: SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: chartMaxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (chartMaxY / 4).ceilToDouble().clamp(
                  1,
                  double.infinity,
                ),
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.grey.withValues(alpha: 0.2),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: (chartMaxY / 4).ceilToDouble().clamp(
                      1,
                      double.infinity,
                    ),
                    getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= buckets.length)
                        return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          buckets[idx].label,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              barGroups: List.generate(buckets.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: buckets[i].count.toDouble(),
                      color: color,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: chartMaxY,
                        color: Colors.grey.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                  showingTooltipIndicators: buckets[i].count > 0 ? [0] : [],
                );
              }),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => color.withValues(alpha: 0.9),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    '${rod.toY.toInt()}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Donut-Chart: Status-Verteilung ───────────────────────────────────────────

class _StatusDonutChart extends StatefulWidget {
  const _StatusDonutChart({required this.data});
  final _AnalyticsData data;

  @override
  State<_StatusDonutChart> createState() => _StatusDonutChartState();
}

class _StatusDonutChartState extends State<_StatusDonutChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.total == 0) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Noch keine Tickets vorhanden.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    final sections = [
      (label: 'Offen', count: data.openCount, color: Colors.orange),
      (
        label: 'In Bearbeitung',
        count: data.inProgressCount,
        color: Colors.blue,
      ),
      (label: 'Erledigt', count: data.doneCount, color: Colors.green),
    ].where((s) => s.count > 0).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Row(
          children: [
            SizedBox(
              height: 160,
              width: 160,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 44,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            response == null ||
                            response.touchedSection == null) {
                          _touched = -1;
                        } else {
                          _touched =
                              response.touchedSection!.touchedSectionIndex;
                        }
                      });
                    },
                  ),
                  sections: List.generate(sections.length, (i) {
                    final s = sections[i];
                    final isTouched = i == _touched;
                    return PieChartSectionData(
                      value: s.count.toDouble(),
                      color: s.color,
                      radius: isTouched ? 52 : 44,
                      title: '${(s.count / data.total * 100).round()}%',
                      titleStyle: TextStyle(
                        fontSize: isTouched ? 14 : 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections
                    .map(
                      (s) => _LegendItem(
                        color: s.color,
                        label: s.label,
                        count: s.count,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
  });
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Linien-Chart: Ø Bearbeitungszeit pro Monat ───────────────────────────────

class _ResolutionLineChart extends StatelessWidget {
  const _ResolutionLineChart({required this.buckets});
  final List<_MonthlyBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    final spots = <FlSpot>[];
    for (int i = 0; i < buckets.length; i++) {
      final avg = buckets[i].avgDays;
      if (avg != null) spots.add(FlSpot(i.toDouble(), avg));
    }

    if (spots.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Noch keine erledigten Tickets für Auswertung.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final maxY = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    final chartMaxY = (maxY * 1.3).ceilToDouble().clamp(1.0, double.infinity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
        child: SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (buckets.length - 1).toDouble(),
              minY: 0,
              maxY: chartMaxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (chartMaxY / 4).ceilToDouble().clamp(
                  1,
                  double.infinity,
                ),
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.grey.withValues(alpha: 0.2),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: (chartMaxY / 4).ceilToDouble().clamp(
                      1,
                      double.infinity,
                    ),
                    getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= buckets.length)
                        return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          buckets[idx].label,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: color,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 4,
                      color: color,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => color.withValues(alpha: 0.9),
                  getTooltipItems: (spots) => spots
                      .map(
                        (s) => LineTooltipItem(
                          '${s.y.toStringAsFixed(1)} T',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

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
