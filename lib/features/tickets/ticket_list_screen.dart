import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/ticket.dart';
import '../../router.dart';
import '../../ticket_provider.dart';
import '../../widgets/app_state_widgets.dart';

class TicketListScreen extends ConsumerWidget {
  const TicketListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(tenantTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Tickets')),
      body: ticketsAsync.when(
        loading: () => const TicketSkeletonList(count: 5),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (tickets) {
          if (tickets.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Noch keine Tickets',
              subtitle: 'Melde einen Schaden über "Schaden melden".',
            );
          }
          return _LiveTicketList(tickets: tickets);
        },
      ),
    );
  }
}

class _LiveTicketList extends StatelessWidget {
  const _LiveTicketList({required this.tickets});
  final List<Ticket> tickets;

  static final _fmt = DateFormat('dd.MM.yy');

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: tickets.length,
      itemBuilder: (_, i) => _TicketListTile(
        ticket: tickets[i],
        fmt: _fmt,
      ),
    );
  }
}

class _TicketListTile extends StatelessWidget {
  const _TicketListTile({required this.ticket, required this.fmt});
  final Ticket ticket;
  final DateFormat fmt;

  // Maps status to step index (0–3) for the mini-progress bar
  int get _stepIndex {
    if (ticket.status == 'done') return 3;
    if (ticket.status == 'in_progress') return 2;
    if (ticket.assignedTo != null) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.ticketDetailPath(ticket.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail or icon
                  _Thumbnail(ticket: ticket),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (ticket.unitName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            ticket.unitName!,
                            style: TextStyle(
                                fontSize: 11, color: cs.outline),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AppStatusBadge(
                        label: ticket.statusLabel,
                        color: ticket.statusColor,
                      ),
                      if (ticket.createdAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          fmt.format(ticket.createdAt!),
                          style: TextStyle(
                              fontSize: 10, color: cs.outline),
                        ),
                      ],
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Mini progress bar ────────────────────────────────────
              _MiniProgressBar(stepIndex: _stepIndex),

              // ── Handwerker-Zeile ─────────────────────────────────────
              if (ticket.assignedToName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.handyman_outlined,
                        size: 13, color: cs.outline),
                    const SizedBox(width: 4),
                    Text(
                      ticket.assignedToName!,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ],
                ),
              ],

              // ── Termin-Zeile ─────────────────────────────────────────
              if (ticket.scheduledAt != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.event_outlined,
                        size: 13, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      'Termin: ${fmt.format(ticket.scheduledAt!)}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.blue),
                    ),
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

// ─── Thumbnail ────────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.ticket});
  final Ticket ticket;

  String? get _imageUrl =>
      ticket.imageUrls.isNotEmpty ? ticket.imageUrls.first : ticket.imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = _imageUrl;
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          placeholder: (_, __) => const SizedBox(
            width: 52,
            height: 52,
            child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
          ),
          errorWidget: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined, size: 36),
        ),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(ticket.categoryIcon,
          size: 26,
          color: Theme.of(context).colorScheme.primary),
    );
  }
}

// ─── Mini progress bar ────────────────────────────────────────────────────────

class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar({required this.stepIndex});
  final int stepIndex; // 0 = Gemeldet, 1 = Zugewiesen, 2 = In Bearbeitung, 3 = Erledigt

  static const _labels = ['Gemeldet', 'Zugewiesen', 'In Bearb.', 'Erledigt'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _labels.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step dots + connectors
        Row(
          children: List.generate(total, (i) {
            final done = i <= stepIndex;
            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? cs.primary : cs.outlineVariant,
                    ),
                  ),
                  if (i < total - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i < stepIndex ? cs.primary : cs.outlineVariant,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 3),
        // Current step label
        Text(
          _labels[stepIndex],
          style: TextStyle(
              fontSize: 10,
              color: cs.primary,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
