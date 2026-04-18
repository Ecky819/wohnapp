import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/ticket.dart';
import '../../models/unit.dart';
import '../../repositories/building_repository.dart';
import '../../router.dart';
import '../../ticket_provider.dart';
import '../../user_provider.dart';
import '../../widgets/app_state_widgets.dart';
import '../auth/qr_scanner_screen.dart';

class TenantHomeScreen extends ConsumerWidget {
  const TenantHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final name = user?.name ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mieter Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            tooltip: 'QR-Code scannen',
            onPressed: () async {
              final result = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => const QrScannerScreen(),
                ),
              );
              if (result == null || !context.mounted) return;
              final uri = Uri.tryParse(result);
              if (uri == null) return;
              // Handle wohnapp://report?unitId=...&tenantId=...&unitName=...
              if (uri.scheme == 'wohnapp' && uri.host == 'report') {
                context.push(AppRoutes.guestReportPath(
                  unitId: uri.queryParameters['unitId'] ?? '',
                  tenantId: uri.queryParameters['tenantId'] ?? '',
                  unitName: Uri.decodeComponent(
                      uri.queryParameters['unitName'] ?? ''),
                ));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Wartungskalender',
            onPressed: () => context.push(AppRoutes.calendar),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profil',
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            name.isNotEmpty ? 'Willkommen, $name' : 'Willkommen',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          // ── Assigned unit card ─────────────────────────────────────
          if (user?.unitId != null && user!.unitId!.isNotEmpty)
            _AssignedUnitCard(unitId: user.unitId!),

          const SizedBox(height: 16),

          // ── Action buttons ─────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text('Schaden melden'),
                  onPressed: () => context
                      .push('${AppRoutes.tenant}/${AppRoutes.createTicket}')
                      .then((created) {
                    if (created == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ticket erfolgreich angelegt'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.list_outlined),
                  label: const Text('Meine Tickets'),
                  onPressed: () => context.push(
                      '${AppRoutes.tenant}/${AppRoutes.myTickets}'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Recent tickets ─────────────────────────────────────────
          const Text(
            'Zuletzt erstellt',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 10),
          _RecentTickets(),
        ],
      ),
    );
  }
}

// ─── Assigned unit card ───────────────────────────────────────────────────────

class _AssignedUnitCard extends ConsumerWidget {
  const _AssignedUnitCard({required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitAsync = ref.watch(unitByIdProvider(unitId));

    return unitAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
      data: (unit) {
        if (unit == null) return const SizedBox.shrink();
        return _UnitSummaryCard(unit: unit);
      },
    );
  }
}

class _UnitSummaryCard extends StatelessWidget {
  const _UnitSummaryCard({required this.unit});
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.apartment_outlined, size: 28),
        title: Text(unit.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unit.floor != null) Text('${unit.floor}. Obergeschoss'),
            if (unit.area != null)
              Text('${unit.area!.toStringAsFixed(0)} m²'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.unitDetailPath(unit.id)),
      ),
    );
  }
}

// ─── Recent tickets ───────────────────────────────────────────────────────────

class _RecentTickets extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(tenantTicketsProvider);

    return ticketsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) =>
          Text('Fehler: $e', style: const TextStyle(color: Colors.red)),
      data: (tickets) {
        final recent = tickets.take(3).toList();
        if (recent.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Noch keine Tickets erstellt.',
                style: TextStyle(color: Colors.grey)),
          );
        }
        return Column(
          children: [
            ...recent.map((t) => _TicketPreviewTile(ticket: t)),
            if (tickets.length > 3)
              TextButton(
                onPressed: () => context
                    .push('${AppRoutes.tenant}/${AppRoutes.myTickets}'),
                child: Text('Alle ${tickets.length} Tickets anzeigen'),
              ),
          ],
        );
      },
    );
  }
}

class _TicketPreviewTile extends StatelessWidget {
  const _TicketPreviewTile({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yy');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading:
            Icon(ticket.categoryIcon, color: ticket.statusColor, size: 22),
        title: Text(ticket.title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: Text(
          ticket.createdAt != null ? fmt.format(ticket.createdAt!) : '–',
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
