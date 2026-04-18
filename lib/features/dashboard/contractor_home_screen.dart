import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/ticket.dart';
import '../../router.dart';
import '../../ticket_provider.dart';
import '../../widgets/app_state_widgets.dart';

const _kPageSize = 20;

class ContractorHomeScreen extends ConsumerStatefulWidget {
  const ContractorHomeScreen({super.key});

  @override
  ConsumerState<ContractorHomeScreen> createState() =>
      _ContractorHomeScreenState();
}

class _ContractorHomeScreenState extends ConsumerState<ContractorHomeScreen> {
  final List<Ticket> _tickets = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  String? _statusFilter;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_isLoading || !_hasMore) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result =
          await ref.read(ticketRepositoryProvider).fetchContractorPage(
                uid: uid,
                statusFilter: _statusFilter,
                limit: _kPageSize,
                startAfter: _lastDoc,
              );
      setState(() {
        _tickets.addAll(result.tickets);
        _lastDoc = result.lastDoc;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _tickets.clear();
      _lastDoc = null;
      _hasMore = true;
      _error = null;
    });
    await _loadPage();
  }

  void _applyFilter(String? status) {
    if (_statusFilter == status) return;
    setState(() => _statusFilter = status);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Aufträge'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profil',
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: Column(
        children: [
          _NewAssignmentsSection(
              onTap: (t) => context.push(AppRoutes.ticketDetailPath(t.id))),
          _FilterBar(filter: _statusFilter, onSelected: _applyFilter),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && _tickets.isEmpty) {
      return ErrorState(message: _error!, onRetry: _refresh);
    }

    // First load: show skeleton instead of blank screen
    if (_tickets.isEmpty && _isLoading) {
      return const TicketSkeletonList();
    }

    if (_tickets.isEmpty && !_isLoading) {
      return EmptyState(
        icon: Icons.handyman_outlined,
        title: 'Keine Aufträge vorhanden',
        subtitle: _statusFilter != null
            ? 'Kein Auftrag mit diesem Status.'
            : 'Dir wurden noch keine Tickets zugewiesen.',
        action: TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
          onPressed: _refresh,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _tickets.length + (_hasMore || _isLoading ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _tickets.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final ticket = _tickets[i];
          return _ContractorTicketCard(
            ticket: ticket,
            onTap: () => context.push(AppRoutes.ticketDetailPath(ticket.id)),
          );
        },
      ),
    );
  }
}

// ─── New assignments section ──────────────────────────────────────────────────

class _NewAssignmentsSection extends ConsumerWidget {
  const _NewAssignmentsSection({required this.onTap});
  final ValueChanged<Ticket> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(contractorTicketsProvider);

    return ticketsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (tickets) {
        final newAssignments =
            tickets.where((t) => t.status == 'open').toList();
        if (newAssignments.isEmpty) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
                Colors.orange.withValues(alpha: 0.1), cs.surface),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notification_important_outlined,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Neue Aufträge (${newAssignments.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.orange),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...newAssignments.map(
                (t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_outlined,
                      color: Colors.orange),
                  title: Text(t.title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: t.unitName != null
                      ? Text(t.unitName!,
                          style: const TextStyle(fontSize: 11))
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onTap(t),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onSelected});
  final String? filter;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = <String?, String>{
      null: 'Alle',
      'open': 'Offen',
      'in_progress': 'In Bearbeitung',
      'done': 'Erledigt',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: filters.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(e.value),
              selected: filter == e.key,
              onSelected: (_) => onSelected(e.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Ticket card ──────────────────────────────────────────────────────────────

class _ContractorTicketCard extends StatelessWidget {
  const _ContractorTicketCard({required this.ticket, required this.onTap});
  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: ticket.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: ticket.imageUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 1.5)),
                  ),
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined, size: 36),
                ),
              )
            : const Icon(Icons.handyman_outlined, size: 36),
        title: Text(ticket.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ticket.description.isNotEmpty)
              Text(ticket.description,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            _StatusBadge(ticket: ticket),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) => AppStatusBadge(
        label: ticket.statusLabel,
        color: ticket.statusColor,
      );
}
