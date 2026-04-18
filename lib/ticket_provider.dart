import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_user.dart';
import 'models/ticket.dart';
import 'repositories/ticket_repository.dart';
import 'user_provider.dart';

export 'repositories/ticket_repository.dart' show ticketRepositoryProvider;

// ─── Manager ────────────────────────────────────────────────────────────────

final allTicketsProvider = StreamProvider<List<Ticket>>((ref) {
  final tenantId = ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
  return ref.watch(ticketRepositoryProvider).watchAll(tenantId: tenantId).map(
        (list) => list.where((t) => !t.archived).toList(),
      );
});

final ticketStatusFilterProvider = StateProvider<String?>((ref) => null);

final filteredTicketsProvider = Provider<AsyncValue<List<Ticket>>>((ref) {
  final filter = ref.watch(ticketStatusFilterProvider);
  return ref.watch(allTicketsProvider).whenData(
        (tickets) => filter == null
            ? tickets
            : tickets.where((t) => t.status == filter).toList(),
      );
});

// ─── Tenant ──────────────────────────────────────────────────────────────────

/// All tickets created by the current tenant user, newest first.
final tenantTicketsProvider = StreamProvider<List<Ticket>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(ticketRepositoryProvider).watchByUser(uid).map(
        (list) => list.where((t) => !t.archived).toList(),
      );
});

// ─── Contractor ─────────────────────────────────────────────────────────────

final contractorTicketsProvider = StreamProvider<List<Ticket>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(ticketRepositoryProvider).watchForContractor(uid);
});

final contractorStatusFilterProvider = StateProvider<String?>((ref) => null);

final filteredContractorTicketsProvider = Provider<AsyncValue<List<Ticket>>>((ref) {
  final filter = ref.watch(contractorStatusFilterProvider);
  return ref.watch(contractorTicketsProvider).whenData(
        (tickets) => filter == null
            ? tickets
            : tickets.where((t) => t.status == filter).toList(),
      );
});

// ─── Detail ──────────────────────────────────────────────────────────────────

final ticketDetailProvider =
    StreamProvider.family<Ticket, String>((ref, ticketId) {
  return ref.watch(ticketRepositoryProvider).watchOne(ticketId);
});

// ─── Contractors list (for assign sheet) ────────────────────────────────────

final contractorsProvider = FutureProvider<List<AppUser>>((ref) {
  return ref.read(userRepositoryProvider).getContractors();
});
