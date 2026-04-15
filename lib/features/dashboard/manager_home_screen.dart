import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../models/ticket.dart';
import '../../repositories/activity_repository.dart';
import '../../repositories/ticket_repository.dart';
import '../../router.dart';
import '../../ticket_provider.dart';
import '../../user_provider.dart';
import '../../widgets/app_state_widgets.dart';

const _kPageSize = 20;

// ─── Screen ───────────────────────────────────────────────────────────────────

class ManagerHomeScreen extends ConsumerStatefulWidget {
  const ManagerHomeScreen({super.key});

  @override
  ConsumerState<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends ConsumerState<ManagerHomeScreen> {
  final List<Ticket> _tickets = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;

  String? _statusFilter;

  // ── Search ────────────────────────────────────────────────────────────────
  bool _searchActive = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

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
    _searchController.dispose();
    super.dispose();
  }

  void _activateSearch() => setState(() => _searchActive = true);

  void _deactivateSearch() {
    setState(() {
      _searchActive = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tenantId =
          ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
      final result = await ref.read(ticketRepositoryProvider).fetchManagerPage(
            tenantId: tenantId,
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

  void _showAssignSheet(Ticket ticket) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AssignSheet(
        ticket: ticket,
        onChanged: _refresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _searchActive ? _buildSearchBar() : _buildNormalAppBar(),
      floatingActionButton: _searchActive
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Ticket anlegen'),
              onPressed: () =>
                  context.push('/manager/${AppRoutes.managerCreateTicket}'),
            ),
      body: Column(
        children: [
          if (!_searchActive)
            _FilterBar(
              selected: _statusFilter,
              onSelected: _applyFilter,
            ),
          Expanded(child: _searchActive ? _buildSearchResults() : _buildBody()),
        ],
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: const Text('Ticket-Board'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Suchen',
          onPressed: _activateSearch,
        ),
        IconButton(
          icon: const Icon(Icons.bar_chart_outlined),
          tooltip: 'Analytics',
          onPressed: () => context.push(AppRoutes.analytics),
        ),
        IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: 'Kalender',
          onPressed: () => context.push(AppRoutes.calendar),
        ),
        IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Export',
          onPressed: () => context.push(AppRoutes.export),
        ),
        IconButton(
          icon: const Icon(Icons.people_outline),
          tooltip: 'Mieter',
          onPressed: () => context.push(AppRoutes.tenants),
        ),
        IconButton(
          icon: const Icon(Icons.location_city_outlined),
          tooltip: 'Gebäude',
          onPressed: () => context.push(AppRoutes.buildings),
        ),
        IconButton(
          icon: const Icon(Icons.mail_outline),
          tooltip: 'Einladungen',
          onPressed: () => context.push('/manager/${AppRoutes.invitations}'),
        ),
        IconButton(
          icon: const Icon(Icons.account_circle_outlined),
          tooltip: 'Profil',
          onPressed: () => context.push(AppRoutes.profile),
        ),
      ],
    );
  }

  AppBar _buildSearchBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _deactivateSearch,
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Ticket suchen …',
          border: InputBorder.none,
        ),
        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
      ),
      actions: [
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) {
      return const Center(
        child: Text('Suchbegriff eingeben …',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final allAsync = ref.watch(allTicketsProvider);
    return allAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(message: e.toString()),
      data: (all) {
        final q = _searchQuery;
        final results = all.where((t) {
          return t.title.toLowerCase().contains(q) ||
              t.description.toLowerCase().contains(q) ||
              (t.unitName?.toLowerCase().contains(q) ?? false) ||
              (t.assignedToName?.toLowerCase().contains(q) ?? false);
        }).toList();

        if (results.isEmpty) {
          return EmptyState(
            icon: Icons.search_off,
            title: 'Keine Ergebnisse',
            subtitle: 'Kein Ticket enthält „$_searchQuery".',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          itemCount: results.length,
          itemBuilder: (_, i) {
            final ticket = results[i];
            return _TicketCard(
              ticket: ticket,
              onTap: () => context.push(AppRoutes.ticketDetailPath(ticket.id)),
              onAssign: () => _showAssignSheet(ticket),
            );
          },
        );
      },
    );
  }

  Widget _buildBody() {
    if (_error != null && _tickets.isEmpty) {
      return ErrorState(message: _error!, onRetry: _refresh);
    }

    if (_tickets.isEmpty && !_isLoading) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Keine Tickets vorhanden',
        subtitle: _statusFilter != null
            ? 'Kein Ticket mit diesem Status.'
            : 'Noch keine Schadensmeldungen oder Wartungsaufträge.',
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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: _tickets.length + (_hasMore || _isLoading ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _tickets.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final ticket = _tickets[i];
          return _TicketCard(
            ticket: ticket,
            onTap: () => context.push(AppRoutes.ticketDetailPath(ticket.id)),
            onAssign: () => _showAssignSheet(ticket),
          );
        },
      ),
    );
  }
}

// ─── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});
  final String? selected;
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
              selected: selected == e.key,
              onSelected: (_) => onSelected(e.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Ticket card ──────────────────────────────────────────────────────────────

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.onTap,
    required this.onAssign,
  });
  final Ticket ticket;
  final VoidCallback onTap;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: ticket.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  ticket.imageUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              )
            : const Icon(Icons.report_problem_outlined, size: 36),
        title: Text(ticket.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ticket.description.isNotEmpty)
              Text(ticket.description,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                _StatusBadge(ticket: ticket),
                if (ticket.assignedToName != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.handyman_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 2),
                  Text(ticket.assignedToName!,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.assignment_ind_outlined),
          tooltip: 'Zuweisen',
          onPressed: onAssign,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) => AppStatusBadge(
        label: ticket.statusLabel,
        color: ticket.statusColor,
      );
}

// ─── Assign sheet ─────────────────────────────────────────────────────────────

class _AssignSheet extends ConsumerWidget {
  const _AssignSheet({required this.ticket, required this.onChanged});
  final Ticket ticket;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(ticketRepositoryProvider);
    final contractorsAsync = ref.watch(contractorsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ticket.title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _StatusBadge(ticket: ticket),
          const SizedBox(height: 20),

          const Text('Status ändern',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _statusChip(context, repo, 'open', 'Offen', Colors.orange),
              _statusChip(
                  context, repo, 'in_progress', 'In Bearbeitung', Colors.blue),
              _statusChip(context, repo, 'done', 'Erledigt', Colors.green),
            ],
          ),

          const SizedBox(height: 20),

          const Text('Handwerker zuweisen',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          contractorsAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Fehler: $e'),
            data: (contractors) => contractors.isEmpty
                ? const Text(
                    'Keine Handwerker vorhanden.',
                    style: TextStyle(color: Colors.grey),
                  )
                : Column(
                    children: contractors
                        .map((c) => _ContractorTile(
                              contractor: c,
                              isAssigned: ticket.assignedTo == c.uid,
                              onTap: () async {
                                await repo.assignContractor(
                                  ticket.id,
                                  contractorId: c.uid,
                                  contractorName: c.name,
                                  ticketTitle: ticket.title,
                                  createdBy: ticket.createdBy,
                                  activityRepo: ref.read(activityRepositoryProvider),
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  onChanged();
                                }
                              },
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, TicketRepository repo, String value,
      String label, Color color) {
    final isActive = ticket.status == value;
    return ActionChip(
      label: Text(label),
      backgroundColor: isActive ? color.withValues(alpha: 0.2) : null,
      side: isActive ? BorderSide(color: color) : null,
      labelStyle: isActive ? TextStyle(color: color) : null,
      onPressed: () async {
        await repo.updateStatus(ticket.id, value);
        if (context.mounted) {
          Navigator.pop(context);
          onChanged();
        }
      },
    );
  }
}

class _ContractorTile extends StatelessWidget {
  const _ContractorTile({
    required this.contractor,
    required this.isAssigned,
    required this.onTap,
  });
  final AppUser contractor;
  final bool isAssigned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(contractor.name.isNotEmpty
            ? contractor.name[0].toUpperCase()
            : '?'),
      ),
      title: Text(contractor.name),
      subtitle: Text(contractor.email),
      trailing: isAssigned
          ? const Icon(Icons.check_circle, color: Colors.green)
          : null,
      onTap: onTap,
    );
  }
}
