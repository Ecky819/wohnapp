import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/ticket.dart';
import '../../router.dart';
import '../../ticket_provider.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// Returns only maintenance tickets, grouped by date (day precision).
  Map<DateTime, List<Ticket>> _buildEventMap(List<Ticket> tickets) {
    final map = <DateTime, List<Ticket>>{};
    for (final t in tickets) {
      if (t.category != 'maintenance') continue;
      // prefer scheduledAt; fall back to createdAt so older tickets still show
      final date = t.scheduledAt ?? t.createdAt;
      if (date == null) continue;
      final key = DateTime(date.year, date.month, date.day);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  List<Ticket> _eventsForDay(Map<DateTime, List<Ticket>> map, DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return map[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(allTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wartungskalender')),
      body: ticketsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tickets) {
          final eventMap = _buildEventMap(tickets);

          if (eventMap.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Keine Wartungstermine',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lege ein Ticket der Kategorie „Wartung" an und setze ein geplantes Datum.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            );
          }

          final selectedEvents = _selectedDay != null
              ? _eventsForDay(eventMap, _selectedDay!)
              : _eventsForDay(eventMap, _focusedDay);

          return Column(
            children: [
              TableCalendar<Ticket>(
                firstDay: DateTime.utc(2020),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                eventLoader: (day) => _eventsForDay(eventMap, day),
                calendarFormat: CalendarFormat.month,
                startingDayOfWeek: StartingDayOfWeek.monday,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
                calendarStyle: CalendarStyle(
                  markerDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                ),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                onPageChanged: (focused) {
                  _focusedDay = focused;
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: selectedEvents.isEmpty
                    ? const Center(
                        child: Text('Keine Wartungstermine',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        itemCount: selectedEvents.length,
                        itemBuilder: (context, i) {
                          final t = selectedEvents[i];
                          final fmt = DateFormat('dd.MM.yyyy');
                          final dateStr = t.scheduledAt != null
                              ? fmt.format(t.scheduledAt!)
                              : null;
                          return ListTile(
                            leading: const Icon(Icons.build_circle_outlined,
                                color: Colors.blue),
                            title: Text(t.title),
                            subtitle: Text(
                              [
                                if (t.unitName != null) t.unitName!,
                                t.statusLabel,
                                if (dateStr != null) dateStr,
                              ].join(' · '),
                            ),
                            trailing: _StatusDot(color: t.statusColor),
                            onTap: () =>
                                context.push(AppRoutes.ticketDetailPath(t.id)),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
