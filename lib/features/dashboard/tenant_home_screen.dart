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
import '../../repositories/annual_statement_repository.dart';
import '../../models/annual_statement.dart';
import '../../widgets/app_state_widgets.dart';
import '../auth/qr_scanner_screen.dart';

final _dateFmt = DateFormat('dd.MM.yy HH:mm');

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

          // ── Neue Jahresabrechnungen ────────────────────────────────
          _PendingStatementsSection(),

          // ── Live-Tracking aktiver Aufträge ─────────────────────────
          _LiveTrackingSection(),

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

// ─── Neue Jahresabrechnungen ──────────────────────────────────────────────────

class _PendingStatementsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider).valueOrNull?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    final stmtsAsync = ref.watch(tenantStatementsProvider(uid));
    return stmtsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (stmts) {
        final pending = stmts
            .where((s) => s.status != StatementStatus.acknowledged)
            .toList();
        if (pending.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Jahresabrechnungen',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      context.push(AppRoutes.tenantStatements),
                  child: Text('Alle (${stmts.length})'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...pending.take(2).map((s) => _StatementBanner(stmt: s)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _StatementBanner extends ConsumerWidget {
  const _StatementBanner({required this.stmt});
  final AnnualStatement stmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text('Abrechnung ${stmt.year}',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: const Text('Empfang noch nicht bestätigt',
            style: TextStyle(fontSize: 11)),
        trailing: FilledButton.tonal(
          onPressed: () => context.push(AppRoutes.tenantStatements),
          child: const Text('Ansehen'),
        ),
      ),
    );
  }
}

// ─── Live-Tracking aktiver Aufträge ──────────────────────────────────────────

class _LiveTrackingSection extends ConsumerWidget {
  static const _steps = ['open', 'in_progress', 'done'];
  static const _stepLabels = ['Offen', 'In Bearbeitung', 'Erledigt'];
  static const _stepIcons = [
    Icons.radio_button_unchecked,
    Icons.build_outlined,
    Icons.check_circle_outline,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(tenantTicketsProvider);
    return ticketsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (tickets) {
        final active = tickets
            .where((t) => t.status == 'in_progress' || t.status == 'open')
            .take(3)
            .toList();
        if (active.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aktive Aufträge',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...active.map((t) => _LiveTrackingCard(ticket: t, steps: _steps,
                stepLabels: _stepLabels, stepIcons: _stepIcons)),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _LiveTrackingCard extends StatelessWidget {
  const _LiveTrackingCard({
    required this.ticket,
    required this.steps,
    required this.stepLabels,
    required this.stepIcons,
  });

  final Ticket ticket;
  final List<String> steps;
  final List<String> stepLabels;
  final List<IconData> stepIcons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentStep = steps.indexOf(ticket.status).clamp(0, steps.length - 1);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.ticketDetailPath(ticket.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Titel + Icon ───────────────────────────────────────
              Row(
                children: [
                  Icon(ticket.categoryIcon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ticket.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),

              const SizedBox(height: 12),

              // ── Status-Stepper ─────────────────────────────────────
              Row(
                children: List.generate(steps.length * 2 - 1, (i) {
                  if (i.isOdd) {
                    final stepIndex = i ~/ 2;
                    final done = stepIndex < currentStep;
                    return Expanded(
                      child: Container(
                        height: 2,
                        color: done ? cs.primary : cs.outlineVariant,
                      ),
                    );
                  }
                  final stepIndex = i ~/ 2;
                  final isDone = stepIndex < currentStep;
                  final isCurrent = stepIndex == currentStep;
                  return Column(
                    children: [
                      Icon(
                        stepIcons[stepIndex],
                        size: 20,
                        color: isCurrent
                            ? cs.primary
                            : isDone
                                ? cs.primary.withValues(alpha: 0.5)
                                : cs.outlineVariant,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stepLabels[stepIndex],
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCurrent ? cs.primary : Colors.grey,
                        ),
                      ),
                    ],
                  );
                }),
              ),

              // ── Handwerker + Termin ────────────────────────────────
              if (ticket.assignedToName != null ||
                  ticket.scheduledAt != null) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (ticket.assignedToName != null) ...[
                      const Icon(Icons.handyman_outlined,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ticket.assignedToName!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (ticket.scheduledAt != null) ...[
                      const Icon(Icons.event_outlined,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _dateFmt.format(ticket.scheduledAt!),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
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
