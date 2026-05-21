import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../models/ticket.dart';
import '../../repositories/activity_repository.dart';
import '../../models/device.dart';
import '../../repositories/device_repository.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/tenant_repository.dart';
import '../../repositories/ticket_repository.dart';
import '../../router.dart';
import '../../ticket_provider.dart';
import '../../user_provider.dart';
import '../../services/onboarding_service.dart';
import '../../widgets/app_state_widgets.dart';
import '../../widgets/onboarding_tooltip.dart';
import '../../widgets/tenant_logo.dart';

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
      drawer: _searchActive ? null : const _AppDrawer(),
      floatingActionButton: _searchActive
          ? null
          : OnboardingTooltip(
              hintKey: OnboardingKeys.managerCreateTicketFab,
              message: 'Tippe hier, um dein erstes Ticket anzulegen',
              child: FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text('Ticket anlegen'),
                onPressed: () =>
                    context
                        .push('/manager/${AppRoutes.managerCreateTicket}')
                        .then((created) {
                      if (created == true && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ticket erfolgreich angelegt'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                        _refresh();
                      }
                    }),
              ),
            ),
      body: Column(
        children: [
          // MaintenanceBanner nur im normalen Modus — kein Platz beim Suchen
          if (!_searchActive)
            _MaintenanceBanner(
              onTap: () => context.push(AppRoutes.buildings),
            ),
          // FilterBar ist immer sichtbar, auch beim Suchen
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
    final tenant = ref.watch(tenantProvider).valueOrNull;
    return AppBar(
      title: tenant != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TenantLogoAvatar(
                  name: tenant.name,
                  primaryColor: tenant.primaryColor,
                  logoUrl: tenant.logoUrl,
                  radius: 14,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    tenant.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            )
          : const Text('Ticket-Board'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Suchen',
          onPressed: _activateSearch,
        ),
        _PendingInvoiceButton(
          onTap: () => context.push(AppRoutes.export),
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
      return Center(
        child: Text(
          _statusFilter != null
              ? 'Suchbegriff eingeben (Filter: ${_statusFilterLabel()} aktiv) …'
              : 'Suchbegriff eingeben …',
          style: const TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    final allAsync = ref.watch(allTicketsProvider);
    return allAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(message: e.toString()),
      data: (all) {
        final q = _searchQuery;
        final results = all.where((t) {
          final matchesText = t.title.toLowerCase().contains(q) ||
              t.description.toLowerCase().contains(q) ||
              (t.unitName?.toLowerCase().contains(q) ?? false) ||
              (t.assignedToName?.toLowerCase().contains(q) ?? false);
          // Respects the active status filter, same as the main list
          final matchesFilter =
              _statusFilter == null || t.status == _statusFilter;
          return matchesText && matchesFilter;
        }).toList();

        if (results.isEmpty) {
          return EmptyState(
            icon: Icons.search_off,
            title: 'Keine Ergebnisse',
            subtitle: _statusFilter != null
                ? 'Kein „${_statusFilterLabel()}"-Ticket enthält „$_searchQuery".'
                : 'Kein Ticket enthält „$_searchQuery".',
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

  String _statusFilterLabel() {
    return switch (_statusFilter) {
      'open' => 'Offen',
      'in_progress' => 'In Bearbeitung',
      'done' => 'Erledigt',
      _ => '',
    };
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

    return Column(
      children: [
        // Fehler-Banner wenn nachfolgende Seite fehlschlägt (Tickets bereits geladen)
        if (_error != null)
          _LoadErrorBanner(
            message: _error!,
            onRetry: () {
              setState(() => _error = null);
              _loadPage();
            },
            onDismiss: () => setState(() => _error = null),
          ),
        Expanded(
          child: RefreshIndicator(
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
                  onTap: () => context
                      .push(AppRoutes.ticketDetailPath(ticket.id))
                      .then((_) => _refresh()),
                  onAssign: () => _showAssignSheet(ticket),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Inline-Fehler-Banner ─────────────────────────────────────────────────────

class _LoadErrorBanner extends StatelessWidget {
  const _LoadErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.red.withValues(alpha: 0.08),
          Theme.of(context).colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                visualDensity: VisualDensity.compact),
            child: const Text('Retry'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
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

// ─── Maintenance banner ───────────────────────────────────────────────────────

class _MaintenanceBanner extends ConsumerWidget {
  const _MaintenanceBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId =
        ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
    if (tenantId.isEmpty) return const SizedBox.shrink();

    final alertsAsync = ref.watch(maintenanceAlertsProvider(tenantId));

    return alertsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (devices) {
        if (devices.isEmpty) return const SizedBox.shrink();

        final overdueCount = devices
            .where((d) => d.maintenanceStatus == MaintenanceStatus.overdue)
            .length;
        final hasOverdue = overdueCount > 0;
        final color = hasOverdue ? Colors.red : Colors.orange;
        final label = hasOverdue
            ? '$overdueCount Gerät${overdueCount != 1 ? 'e' : ''} überfällig'
            : '${devices.length} Gerät${devices.length != 1 ? 'e' : ''} bald fällig';

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                  color.withValues(alpha: 0.1),
                  Theme.of(context).colorScheme.surface),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_outlined, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Wartung: $label',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                ),
                Icon(Icons.chevron_right, color: color, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Pending invoice badge button ─────────────────────────────────────────────

class _PendingInvoiceButton extends ConsumerWidget {
  const _PendingInvoiceButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId =
        ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
    if (tenantId.isEmpty) return const SizedBox.shrink();

    final pendingAsync = ref.watch(pendingInvoicesProvider(tenantId));
    final count = pendingAsync.valueOrNull?.length ?? 0;

    return IconButton(
      tooltip: count > 0
          ? '$count offene ${count == 1 ? 'Rechnung' : 'Rechnungen'} zur Prüfung'
          : 'Rechnungen',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.receipt_long_outlined),
      ),
      onPressed: onTap,
    );
  }
}

// ─── Navigation Drawer ────────────────────────────────────────────────────────

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer();

  void _go(BuildContext context, String route) {
    Navigator.pop(context); // Drawer schließen
    context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider).valueOrNull;

    return NavigationDrawer(
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tenant != null) ...[
                TenantLogoAvatar(
                  name: tenant.name,
                  primaryColor: tenant.primaryColor,
                  logoUrl: tenant.logoUrl,
                  radius: 20,
                ),
                const SizedBox(height: 10),
                Text(tenant.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ] else
                const Text('Verwaltung',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 8),

        // ── Auswertung ──────────────────────────────────────────────────
        const _DrawerSection('AUSWERTUNG'),
        _DrawerTile(Icons.bar_chart_outlined, 'Analytics',
            () => _go(context, AppRoutes.analytics)),
        _DrawerTile(Icons.calendar_month_outlined, 'Kalender',
            () => _go(context, AppRoutes.calendar)),
        _DrawerTile(Icons.bolt_outlined, 'Energieverbrauch',
            () => _go(context, AppRoutes.energy)),

        const SizedBox(height: 4),
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 4),

        // ── Objekte & Personen ──────────────────────────────────────────
        const _DrawerSection('OBJEKTE & PERSONEN'),
        _DrawerTile(Icons.location_city_outlined, 'Gebäude',
            () => _go(context, AppRoutes.buildings)),
        _DrawerTile(Icons.description_outlined, 'Mietverhältnisse',
            () => _go(context, AppRoutes.tenants)),
        _DrawerTile(Icons.mail_outlined, 'Einladungen',
            () => _go(context, '/manager/${AppRoutes.invitations}')),

        const SizedBox(height: 4),
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 4),

        // ── Finanzen & Daten ────────────────────────────────────────────
        const _DrawerSection('FINANZEN & DATEN'),
        _DrawerTile(Icons.receipt_long_outlined, 'Jahresabrechnungen',
            () => _go(context, AppRoutes.statements)),
        _DrawerTile(Icons.download_outlined, 'Export / DATEV',
            () => _go(context, AppRoutes.export)),
        _DrawerTile(Icons.upload_file_outlined, 'Bulk-Import',
            () => _go(context, AppRoutes.bulkImport)),

        const SizedBox(height: 4),
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 4),

        // ── Einstellungen ───────────────────────────────────────────────
        const _DrawerSection('EINSTELLUNGEN'),
        _DrawerTile(Icons.domain_outlined, 'Mandanten-Einstellungen',
            () => _go(context, AppRoutes.tenantSettings)),
        _DrawerTile(Icons.account_circle_outlined, 'Profil',
            () => _go(context, AppRoutes.profile)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minTileHeight: 48,
    );
  }
}
