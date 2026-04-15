import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/ticket.dart';
import '../../router.dart';
import '../../widgets/app_state_widgets.dart';

const _pageSize = 10;

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key});

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  final List<Ticket> _tickets = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;

    Query query = FirebaseFirestore.instance
        .collection('tickets')
        .where('createdBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    if (_lastDoc != null) {
      query = query.startAfterDocument(_lastDoc!);
    }

    final snap = await query.get();
    final newTickets = snap.docs.map(Ticket.fromDoc).toList();

    setState(() {
      _tickets.addAll(newTickets);
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
      _hasMore = snap.docs.length == _pageSize;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _tickets.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Tickets')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _tickets.isEmpty && !_isLoading
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Noch keine Tickets',
                subtitle: 'Melde einen Schaden über "Schaden melden".',
              )
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _tickets.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  // Letztes Item: Load-More-Trigger
                  if (index == _tickets.length) {
                    _loadMore();
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final ticket = _tickets[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () =>
                          context.push(AppRoutes.ticketDetailPath(ticket.id)),
                      leading: ticket.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                ticket.imageUrl!,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(Icons.report_problem),
                      title: Text(ticket.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ticket.description.isNotEmpty)
                            Text(
                              ticket.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'Status: ${ticket.statusLabel}',
                            style: TextStyle(
                              color: ticket.statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
