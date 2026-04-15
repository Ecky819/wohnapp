import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/activity_entry.dart';
import '../../models/comment.dart';
import '../../models/ticket.dart';
import '../../repositories/activity_repository.dart';
import '../../repositories/comment_repository.dart';
import '../../repositories/ticket_repository.dart';
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

          // Status-Buttons für Handwerker und Manager
          if (_canChangeStatus(ref)) ...[
            const SizedBox(height: 24),
            const Text('Status aktualisieren',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 10),
            _StatusButtons(ticket: ticket, onUpdate: _updateStatus),
          ],

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
          child: Image.network(
            urls.first,
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
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
            child: Image.network(
              urls[i],
              width: 280,
              fit: BoxFit.cover,
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
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
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
