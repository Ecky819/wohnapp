import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/activity_entry.dart';
import '../../models/comment.dart';
import '../../models/invoice.dart';
import '../../models/ticket.dart';
import '../../repositories/activity_repository.dart';
import '../../repositories/comment_repository.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/ticket_repository.dart';
import '../../router.dart';
import '../../services/notification_service.dart';
import '../../ticket_provider.dart';
import '../../user_provider.dart';
import '../../widgets/app_state_widgets.dart';
import 'edit_ticket_screen.dart';

class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});
  final String ticketId;

  Future<void> _confirmArchive(
      BuildContext context, WidgetRef ref, Ticket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ticket archivieren?'),
        content: Text(
            '„${ticket.title}" wird archiviert und erscheint nicht mehr in den Listen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archivieren'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(ticketRepositoryProvider).archiveTicket(
          ticket.id,
          activityRepo: ref.read(activityRepositoryProvider),
        );
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketAsync = ref.watch(ticketDetailProvider(ticketId));
    final user = ref.watch(currentUserProvider).valueOrNull;
    final canEdit = user?.role == 'manager' ||
        (ticketAsync.valueOrNull?.createdBy == user?.uid &&
            ticketAsync.valueOrNull?.status == 'open');

    final isManager = user?.role == 'manager';
    final ticket = ticketAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket-Details'),
        actions: [
          if (canEdit && ticket != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Bearbeiten',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditTicketScreen(ticket: ticket),
                ),
              ),
            ),
          if (isManager && ticket != null && !ticket.archived)
            IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Archivieren',
              onPressed: () => _confirmArchive(context, ref, ticket),
            ),
        ],
      ),
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (t) => _TicketDetailBody(ticket: t),
      ),
    );
  }
}

class _TicketDetailBody extends ConsumerWidget {
  const _TicketDetailBody({required this.ticket});
  final Ticket ticket;

  bool get _isContractor =>
      FirebaseAuth.instance.currentUser?.uid == ticket.assignedTo;

  bool _canChangeStatus(WidgetRef ref) {
    final user = ref.read(currentUserProvider).valueOrNull;
    return _isContractor || user?.role == 'manager';
  }

  Future<void> _updateStatus(String status) async {
    final repo = TicketRepository(
      FirebaseFirestore.instance,
      FirebaseStorage.instance,
    );
    final activityRepo = ActivityRepository(FirebaseFirestore.instance);

    await repo.updateStatus(
      ticket.id,
      status,
      oldStatus: ticket.status,
      activityRepo: activityRepo,
    );

    await NotificationService.notifyStatusChange(
      ticketId: ticket.id,
      newStatus: status,
      createdBy: ticket.createdBy,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('dd.MM.yyyy – HH:mm');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status-Timeline ────────────────────────────────────────────
          _StatusTimeline(ticket: ticket),

          const SizedBox(height: 16),

          // ── Termin-Banner ──────────────────────────────────────────────
          if (ticket.scheduledAt != null)
            _AppointmentBanner(scheduledAt: ticket.scheduledAt!),

          // ── Handwerker-Card (für Mieter) ───────────────────────────────
          if (ticket.assignedTo != null)
            _ContractorInfoCard(ticket: ticket),

          const SizedBox(height: 8),

          // Fotos (mehrere, antippbar)
          if (ticket.imageUrls.isNotEmpty) ...[
            _ImageGallery(urls: ticket.imageUrls),
          ] else if (ticket.imageUrl != null) ...[
            _ImageGallery(urls: [ticket.imageUrl!]),
          ],

          const SizedBox(height: 20),

          // Titel + Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  ticket.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              _StatusBadge(ticket: ticket),
            ],
          ),

          const SizedBox(height: 12),

          // Beschreibung
          if (ticket.description.isNotEmpty) ...[
            Text(ticket.description,
                style: const TextStyle(fontSize: 15, color: Colors.black87)),
            const SizedBox(height: 16),
          ],

          const Divider(),

          // Metadaten
          _InfoRow(
            icon: ticket.categoryIcon,
            label: 'Typ',
            value: ticket.categoryLabel,
          ),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Erstellt',
            value: ticket.createdAt != null
                ? dateFormat.format(ticket.createdAt!)
                : '–',
          ),
          if (ticket.unitName != null)
            _InfoRow(
              icon: Icons.apartment_outlined,
              label: 'Wohnung',
              value: ticket.unitName!,
            ),
          if (ticket.scheduledAt != null)
            _InfoRow(
              icon: Icons.event_outlined,
              label: 'Geplant am',
              value: dateFormat.format(ticket.scheduledAt!),
            ),
          _InfoRow(
            icon: Icons.handyman_outlined,
            label: 'Handwerker',
            value: ticket.assignedToName ?? 'Noch nicht zugewiesen',
          ),
          _InfoRow(
            icon: Icons.flag_outlined,
            label: 'Priorität',
            value: ticket.priority == 'high' ? 'Hoch' : 'Normal',
          ),

          // Dokumente
          if (ticket.documents.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text('Anhänge',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            ...ticket.documents.map((doc) => _DocumentTile(doc: doc)),
          ],

          // Handwerker-Aktionskarte (Annehmen / Ablehnen / Termin)
          if (_isContractor) ...[
            const SizedBox(height: 24),
            const Divider(),
            _ContractorActionCard(ticket: ticket),
          ],

          // Status-Buttons für Handwerker und Manager
          if (_canChangeStatus(ref)) ...[
            const SizedBox(height: 24),
            const Text('Status aktualisieren',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 10),
            _StatusButtons(ticket: ticket, onUpdate: _updateStatus),
          ],

          // Rechnungen (Handwerker hochladen / Manager prüfen)
          const SizedBox(height: 24),
          const Divider(),
          _InvoiceSection(ticket: ticket),

          // Aktivitäts-Log
          const SizedBox(height: 24),
          const Divider(),
          _ActivityLog(ticketId: ticket.id),

          // Kommentar-Thread
          const SizedBox(height: 24),
          const Divider(),
          _CommentThread(ticket: ticket),
        ],
      ),
    );
  }
}

// ─── Status timeline ─────────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.ticket});
  final Ticket ticket;

  static const _steps = [
    ('open', 'Gemeldet', Icons.flag_outlined),
    ('assigned', 'Zugewiesen', Icons.person_outline),
    ('in_progress', 'In Bearbeitung', Icons.build_outlined),
    ('done', 'Erledigt', Icons.check_circle_outline),
  ];

  int get _currentStep {
    if (ticket.status == 'done') return 3;
    if (ticket.status == 'in_progress') return 2;
    if (ticket.assignedTo != null) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = _currentStep;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(_steps.length, (i) {
          final (_, label, icon) = _steps[i];
          final isDone = i < current;
          final isActive = i == current;
          final color = isDone || isActive ? cs.primary : cs.outlineVariant;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone || isActive
                              ? Color.alphaBlend(
                                  cs.primary.withValues(alpha: 0.15), cs.surface)
                              : Colors.transparent,
                          border: Border.all(color: color, width: 2),
                        ),
                        child: Icon(
                          isDone ? Icons.check : icon,
                          size: 16,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDone || isActive ? cs.primary : cs.outline,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // Connector line (not after last step)
                if (i < _steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 20),
                      color: i < current ? cs.primary : cs.outlineVariant,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── Appointment banner ───────────────────────────────────────────────────────

class _AppointmentBanner extends StatelessWidget {
  const _AppointmentBanner({required this.scheduledAt});
  final DateTime scheduledAt;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEEE, dd. MMMM yyyy', 'de');
    final isUpcoming = scheduledAt.isAfter(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.blue.withValues(alpha: 0.1),
          Theme.of(context).colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, color: Colors.blue, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUpcoming ? 'Ihr Termin' : 'Geplanter Termin',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600),
                ),
                Text(
                  fmt.format(scheduledAt),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Contractor info card ─────────────────────────────────────────────────────

class _ContractorInfoCard extends StatelessWidget {
  const _ContractorInfoCard({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = ticket.assignedToName ?? 'Handwerker';
    final isDone = ticket.status == 'done';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.green.withValues(alpha: 0.08),
          cs.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor:
                Color.alphaBlend(Colors.green.withValues(alpha: 0.15), cs.surface),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDone ? 'Erledigt von' : 'Zuständiger Handwerker',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                ),
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Icon(Icons.handyman_outlined, color: Colors.green, size: 20),
        ],
      ),
    );
  }
}

// ─── Image gallery ────────────────────────────────────────────────────────────

class _ImageGallery extends StatelessWidget {
  const _ImageGallery({required this.urls});
  final List<String> urls;

  void _openViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenImageViewer(
          urls: urls,
          initialIndex: initialIndex,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => _openViewer(context, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: urls.first,
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
            placeholder: (_, __) => const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (_, __, ___) => const SizedBox(
              height: 220,
              child: Center(child: Icon(Icons.broken_image_outlined, size: 48)),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _openViewer(context, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: urls[i],
              width: 280,
              fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox(
                width: 280,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, __, ___) => const SizedBox(
                width: 280,
                child: Center(
                    child: Icon(Icons.broken_image_outlined, size: 48)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullscreenImageViewer extends StatefulWidget {
  const _FullscreenImageViewer(
      {required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: widget.urls.length > 1
            ? Text('${_currentIndex + 1} / ${widget.urls.length}')
            : null,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      size: 64, color: Colors.white54)),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusButtons extends StatelessWidget {
  const _StatusButtons({required this.ticket, required this.onUpdate});
  final Ticket ticket;
  final Future<void> Function(String) onUpdate;

  @override
  Widget build(BuildContext context) {
    final statuses = [
      ('open', 'Offen', Colors.orange),
      ('in_progress', 'In Bearbeitung', Colors.blue),
      ('done', 'Erledigt', Colors.green),
    ];

    return Wrap(
      spacing: 8,
      children: statuses.map((s) {
        final (value, label, color) = s;
        final isActive = ticket.status == value;
        return ActionChip(
          label: Text(label),
          backgroundColor: isActive
              ? Color.alphaBlend(
                  color.withValues(alpha: 0.2),
                  Theme.of(context).colorScheme.surface)
              : null,
          side: isActive ? BorderSide(color: color) : null,
          labelStyle: isActive ? TextStyle(color: color) : null,
          onPressed: isActive ? null : () => onUpdate(value),
        );
      }).toList(),
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

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.doc});
  final Map<String, String> doc;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insert_drive_file_outlined, color: Colors.blue),
      title: Text(doc['name'] ?? '–', style: const TextStyle(fontSize: 13)),
      trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
      onTap: () async {
        final url = doc['url'];
        if (url == null) return;
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) launchUrl(uri);
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Activity log ────────────────────────────────────────────────────────────

class _ActivityLog extends ConsumerWidget {
  const _ActivityLog({required this.ticketId});
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(activityProvider(ticketId));
    final dateFormat = DateFormat('dd.MM. HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Aktivität',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        activityAsync.when(
          loading: () => const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) =>
              Text('Fehler: $e', style: const TextStyle(color: Colors.red)),
          data: (entries) {
            if (entries.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Keine Aktivitäten.',
                    style: TextStyle(color: Colors.grey)),
              );
            }
            return Column(
              children: entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_activityIcon(e.type),
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black87),
                            children: [
                              TextSpan(
                                  text: '${e.actorName}: ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              TextSpan(text: e.detail),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        e.createdAt != null
                            ? dateFormat.format(e.createdAt!)
                            : '',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  IconData _activityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.created:
        return Icons.add_circle_outline;
      case ActivityType.statusChanged:
        return Icons.swap_horiz;
      case ActivityType.assigned:
        return Icons.person_outline;
      case ActivityType.updated:
        return Icons.edit_outlined;
    }
  }
}

// ─── Comment thread ───────────────────────────────────────────────────────────

class _CommentThread extends ConsumerStatefulWidget {
  const _CommentThread({required this.ticket});
  final Ticket ticket;

  @override
  ConsumerState<_CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends ConsumerState<_CommentThread> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _sending = true);
    final authorName = user.name.isNotEmpty ? user.name : user.email;
    await ref.read(commentRepositoryProvider).addComment(
          ticketId: widget.ticket.id,
          authorId: user.uid,
          authorName: authorName,
          text: text,
        );
    // notify ticket creator + assigned contractor (except the sender)
    await NotificationService.notifyNewComment(
      ticketId: widget.ticket.id,
      ticketTitle: widget.ticket.title,
      authorName: authorName,
      createdBy: widget.ticket.createdBy,
      assignedTo: widget.ticket.assignedTo,
    );
    _controller.clear();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.ticket.id));
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Kommentare',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 12),
        commentsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Fehler: $e',
              style: const TextStyle(color: Colors.red)),
          data: (comments) {
            if (comments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Noch keine Kommentare.',
                    style: TextStyle(color: Colors.grey)),
              );
            }
            return Column(
              children: comments
                  .map((c) => _CommentBubble(
                        comment: c,
                        isOwn: c.authorId == currentUid,
                        onDelete: c.authorId == currentUid
                            ? () => ref
                                .read(commentRepositoryProvider)
                                .deleteComment(widget.ticket.id, c.id)
                            : null,
                      ))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Kommentar schreiben …',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Invoice section ─────────────────────────────────────────────────────────

class _InvoiceSection extends ConsumerStatefulWidget {
  const _InvoiceSection({required this.ticket});
  final Ticket ticket;

  @override
  ConsumerState<_InvoiceSection> createState() => _InvoiceSectionState();
}

class _InvoiceSectionState extends ConsumerState<_InvoiceSection> {
  bool _uploading = false;

  bool get _isContractor =>
      FirebaseAuth.instance.currentUser?.uid == widget.ticket.assignedTo;

  bool get _isManager =>
      ref.read(currentUserProvider).valueOrNull?.role == 'manager';

  Future<void> _submitInvoice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _uploading = true);
    try {
      // 1. Create invoice document first to get the ID
      final invoiceRepo = ref.read(invoiceRepositoryProvider);
      final invoice = Invoice(
        id: '',
        ticketId: widget.ticket.id,
        ticketTitle: widget.ticket.title,
        contractorId: user.uid,
        contractorName: user.name.isNotEmpty ? user.name : user.email,
        tenantId: user.tenantId,
        amount: 0.0,
        status: InvoiceStatus.pending,
        positions: const [],
      );
      final invoiceId = await invoiceRepo.createInvoice(invoice);

      // 2. Upload PDF
      final ref2 = FirebaseStorage.instance
          .ref('invoices/${user.uid}/$invoiceId.pdf');
      await ref2.putData(
        file.bytes!,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final pdfUrl = await ref2.getDownloadURL();

      // 3. Update invoice with PDF URL
      await invoiceRepo.updatePdfUrl(invoiceId, pdfUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rechnung eingereicht')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync =
        ref.watch(invoicesForTicketProvider(widget.ticket.id));
    final canSubmit =
        _isContractor && widget.ticket.status == 'done';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Rechnungen',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const Spacer(),
            if (canSubmit)
              FilledButton.icon(
                icon: _uploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Rechnung einreichen'),
                onPressed: _uploading ? null : _submitInvoice,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        invoicesAsync.when(
          loading: () => const SizedBox(
            height: 32,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) =>
              Text('Fehler: $e', style: const TextStyle(color: Colors.red)),
          data: (invoices) {
            if (invoices.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Noch keine Rechnungen.',
                    style: TextStyle(color: Colors.grey)),
              );
            }
            return Column(
              children: invoices
                  .map((inv) => _InvoiceTile(
                        invoice: inv,
                        isManager: _isManager,
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.isManager});
  final Invoice invoice;
  final bool isManager;

  Color _statusColor(InvoiceStatus s) {
    switch (s) {
      case InvoiceStatus.approved:
        return Colors.green;
      case InvoiceStatus.rejected:
        return Colors.red;
      case InvoiceStatus.exported:
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yy');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading:
            const Icon(Icons.receipt_long_outlined, color: Colors.blueGrey),
        title: Text(
          invoice.contractorName,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        subtitle: Text(
          invoice.createdAt != null ? fmt.format(invoice.createdAt!) : '–',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppStatusBadge(
              label: invoice.status.label,
              color: _statusColor(invoice.status),
            ),
            if (isManager) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ],
        ),
        onTap: isManager
            ? () => context.push(AppRoutes.invoiceDetailPath(invoice.id))
            : invoice.pdfUrl != null
                ? () async {
                    final uri = Uri.parse(invoice.pdfUrl!);
                    if (await canLaunchUrl(uri)) launchUrl(uri);
                  }
                : null,
      ),
    );
  }
}

// ─── Contractor action card (Phase D) ────────────────────────────────────────

class _ContractorActionCard extends ConsumerStatefulWidget {
  const _ContractorActionCard({required this.ticket});
  final Ticket ticket;

  @override
  ConsumerState<_ContractorActionCard> createState() =>
      _ContractorActionCardState();
}

class _ContractorActionCardState extends ConsumerState<_ContractorActionCard> {
  bool _loading = false;

  TicketRepository get _ticketRepo => ref.read(ticketRepositoryProvider);
  ActivityRepository get _activityRepo => ref.read(activityRepositoryProvider);

  Future<void> _accept() async {
    setState(() => _loading = true);
    try {
      await _ticketRepo.acceptAssignment(
        widget.ticket.id,
        activityRepo: _activityRepo,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auftrag angenommen')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Auftrag ablehnen?'),
        content: const Text(
            'Die Zuweisung wird aufgehoben. Der Verwalter muss erneut einen Handwerker zuweisen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ablehnen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _ticketRepo.declineAssignment(
        widget.ticket.id,
        activityRepo: _activityRepo,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auftrag abgelehnt')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAppointment() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: widget.ticket.scheduledAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('de'),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          widget.ticket.scheduledAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;

    final scheduledAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);

    setState(() => _loading = true);
    try {
      await _ticketRepo.setAppointment(
        widget.ticket.id,
        scheduledAt,
        activityRepo: _activityRepo,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Termin gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.ticket.status;
    final isOpen = status == 'open';
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(cs.primary.withValues(alpha: 0.05), cs.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.work_outline, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Mein Auftrag',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (isOpen) ...[
            // Not yet accepted: show accept / decline
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Annehmen'),
                    onPressed: _accept,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Ablehnen'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                    onPressed: _decline,
                  ),
                ),
              ],
            ),
          ] else ...[
            // Accepted (in_progress or done): show appointment button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(widget.ticket.scheduledAt != null
                    ? 'Termin ändern'
                    : 'Termin festlegen'),
                onPressed: _pickAppointment,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Comment bubble ───────────────────────────────────────────────────────────

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.comment,
    required this.isOwn,
    this.onDelete,
  });
  final Comment comment;
  final bool isOwn;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM. HH:mm');
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isOwn
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, onDelete != null ? 32 : 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isOwn)
                    Text(comment.authorName,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey)),
                  Text(comment.text, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    comment.createdAt != null
                        ? dateFormat.format(comment.createdAt!)
                        : '',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 14, color: Colors.grey),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
