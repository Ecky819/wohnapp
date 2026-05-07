import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_entry.dart';
import '../models/insurance_claim.dart';
import '../models/ticket.dart';
import '../services/notification_service.dart';
import '../services/upload_retry_service.dart';
import 'activity_repository.dart';

class TicketRepository {
  TicketRepository(this._firestore, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _firestore.collection('tickets');

  // ─── Streams ───────────────────────────────────────────────────────────────

  /// Used for full-text search in the manager board. Capped at 500 to avoid
  /// unbounded reads — the paginated [fetchManagerPage] is used for the main list.
  Stream<List<Ticket>> watchAll({required String tenantId, int limit = 500}) {
    if (tenantId.isEmpty) return const Stream.empty();
    return _tickets
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(Ticket.fromDoc).toList());
  }

  /// Cursor-based page fetch for the manager board (avoids loading all tickets).
  Future<({List<Ticket> tickets, DocumentSnapshot? lastDoc, bool hasMore})>
      fetchManagerPage({
    required String tenantId,
    String? statusFilter,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> q = _tickets
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('createdAt', descending: true)
        .limit(limit + 1); // fetch one extra to detect hasMore

    if (statusFilter != null) {
      q = q.where('status', isEqualTo: statusFilter);
    }
    if (startAfter != null) q = q.startAfterDocument(startAfter);

    final snap = await q.get();
    final hasMore = snap.docs.length > limit;
    final docs = hasMore ? snap.docs.sublist(0, limit) : snap.docs;
    return (
      tickets: docs.map(Ticket.fromDoc).toList(),
      lastDoc: docs.isNotEmpty ? docs.last : null,
      hasMore: hasMore,
    );
  }

  Stream<List<Ticket>> watchForContractor(String uid, {int limit = 50}) {
    return _tickets
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map(Ticket.fromDoc)
            .where((t) => !t.archived)
            .toList());
  }

  Future<({List<Ticket> tickets, DocumentSnapshot? lastDoc, bool hasMore})>
      fetchContractorPage({
    required String uid,
    String? statusFilter,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> q = _tickets
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit + 1);

    if (statusFilter != null) {
      q = q.where('status', isEqualTo: statusFilter);
    }
    if (startAfter != null) q = q.startAfterDocument(startAfter);

    final snap = await q.get();
    final hasMore = snap.docs.length > limit;
    final docs = hasMore ? snap.docs.sublist(0, limit) : snap.docs;
    final tickets = docs
        .map(Ticket.fromDoc)
        .where((t) => !t.archived)
        .toList();
    return (
      tickets: tickets,
      lastDoc: docs.isNotEmpty ? docs.last : null,
      hasMore: hasMore,
    );
  }

  Stream<List<Ticket>> watchByUser(String uid) {
    return _tickets
        .where('createdBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Ticket.fromDoc).toList());
  }

  Stream<Ticket> watchOne(String ticketId) {
    return _tickets.doc(ticketId).snapshots().map(Ticket.fromDoc);
  }

  // ─── Pagination ────────────────────────────────────────────────────────────

  Future<List<Ticket>> fetchPage({
    required String uid,
    required int limit,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _tickets
        .where('createdBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) query = query.startAfterDocument(startAfter);

    final snap = await query.get();
    return snap.docs.map(Ticket.fromDoc).toList();
  }

  /// Returns the raw [QueryDocumentSnapshot] list for cursor-based pagination.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchPageRaw({
    required String uid,
    required int limit,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _tickets
        .where('createdBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) query = query.startAfterDocument(startAfter);

    return query.get();
  }

  // ─── Mutations ────────────────────────────────────────────────────────────

  Future<String> createTicket({
    required String title,
    required String description,
    required String tenantId,
    String category = 'damage',
    String priority = 'normal',
    String? unitId,
    String? unitName,
    DateTime? scheduledAt,
    File? image,
    List<File> images = const [],
    List<PlatformFile> documents = const [],
    ActivityRepository? activityRepo,
    InsuranceClaim? insuranceClaim,
    /// Override the creator UID — used for anonymous guest reports.
    String? guestUid,
  }) async {
    final uid = guestUid ?? FirebaseAuth.instance.currentUser!.uid;
    final ref = _tickets.doc();

    await ref.set({
      'title': title,
      'description': description,
      'status': 'open',
      'priority': priority,
      'category': category,
      'tenantId': tenantId,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      if (unitId != null) 'unitId': unitId,
      if (unitName != null) 'unitName': unitName,
      if (scheduledAt != null) 'scheduledAt': Timestamp.fromDate(scheduledAt),
      if (insuranceClaim != null) 'insuranceClaim': insuranceClaim.toMap(),
    });

    // Upload all images (merges legacy single `image` param with `images` list)
    final allImages = [if (image != null) image, ...images];
    if (allImages.isNotEmpty) {
      final urls = await _uploadImages(uid, ref.id, allImages);
      await ref.update({'imageUrls': urls, 'imageUrl': urls.first});
    }

    if (documents.isNotEmpty) {
      final docs = await _uploadDocuments(uid, ref.id, documents);
      await ref.update({'documents': docs});
    }

    if (activityRepo != null) {
      await activityRepo.log(
        ticketId: ref.id,
        type: ActivityType.created,
        detail: 'Ticket erstellt',
      );
    }

    return ref.id;
  }

  Future<void> updateTicket(
    String ticketId, {
    required String title,
    required String description,
    required String priority,
    required String category,
    DateTime? scheduledAt,
    ActivityRepository? activityRepo,
  }) async {
    await _tickets.doc(ticketId).update({
      'title': title,
      'description': description,
      'priority': priority,
      'category': category,
      'scheduledAt': scheduledAt != null
          ? Timestamp.fromDate(scheduledAt)
          : FieldValue.delete(),
    });
    if (activityRepo != null) {
      await activityRepo.log(
        ticketId: ticketId,
        type: ActivityType.updated,
        detail: 'Ticket bearbeitet',
      );
    }
  }

  Future<void> updateStatus(
    String ticketId,
    String status, {
    String? oldStatus,
    ActivityRepository? activityRepo,
  }) async {
    await _tickets.doc(ticketId).update({
      'status': status,
      if (status == 'done') 'closedAt': FieldValue.serverTimestamp(),
    });
    if (activityRepo != null) {
      final label = _statusLabel(status);
      final oldLabel = oldStatus != null ? _statusLabel(oldStatus) : null;
      await activityRepo.log(
        ticketId: ticketId,
        type: ActivityType.statusChanged,
        detail: oldLabel != null ? '$oldLabel → $label' : label,
      );
    }
  }

  static String _statusLabel(String s) {
    switch (s) {
      case 'open':
        return 'Offen';
      case 'in_progress':
        return 'In Bearbeitung';
      case 'done':
        return 'Erledigt';
      default:
        return s;
    }
  }

  Future<void> updateInsuranceClaim(
    String ticketId,
    InsuranceClaim claim, {
    ActivityRepository? activityRepo,
  }) async {
    await _tickets
        .doc(ticketId)
        .update({'insuranceClaim': claim.toMap()});
    if (activityRepo != null) {
      await activityRepo.log(
        ticketId: ticketId,
        type: ActivityType.updated,
        detail: 'Versicherungsfall: ${claim.status.label}',
      );
    }
  }

  Future<void> archiveTicket(
    String ticketId, {
    ActivityRepository? activityRepo,
  }) async {
    await _tickets.doc(ticketId).update({'archived': true});
    if (activityRepo != null) {
      await activityRepo.log(
        ticketId: ticketId,
        type: ActivityType.updated,
        detail: 'Archiviert',
      );
    }
  }

  /// All tickets for a specific unit (used by Digital Twin).
  Stream<List<Ticket>> watchByUnit(String unitId) {
    return _tickets
        .where('unitId', isEqualTo: unitId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Ticket.fromDoc).toList());
  }

  Future<void> assignContractor(
    String ticketId, {
    required String contractorId,
    required String contractorName,
    String? ticketTitle,
    String? createdBy,
    ActivityRepository? activityRepo,
  }) async {
    await _tickets.doc(ticketId).update({
      'assignedTo': contractorId,
      'assignedToName': contractorName,
    });

    // Push notification to contractor
    await NotificationService.notifyAssignment(
      ticketId: ticketId,
      ticketTitle: ticketTitle ?? '',
      contractorId: contractorId,
    );

    // Activity log
    if (activityRepo != null) {
      await activityRepo.log(
        ticketId: ticketId,
        type: ActivityType.assigned,
        detail: 'Zugewiesen an $contractorName',
      );
    }
  }

  /// Contractor accepts their assignment: status → in_progress.
  Future<void> acceptAssignment(
    String ticketId, {
    ActivityRepository? activityRepo,
  }) async {
    await _tickets.doc(ticketId).update({'status': 'in_progress'});
    if (activityRepo != null) {
      await activityRepo.log(
        ticketId: ticketId,
        type: ActivityType.statusChanged,
        detail: 'Offen → In Bearbeitung (Auftrag angenommen)',
      );
    }
  }

  /// Contractor declines their assignment: clears assignedTo/Name, status stays open.
  Future<void> declineAssignment(
    String ticketId, {
    ActivityRepository? activityRepo,
  }) async {
    await _tickets.doc(ticketId).update({
      'assignedTo': FieldValue.delete(),
      'assignedToName': FieldValue.delete(),
    });
    if (activityRepo != null) {
      await activityRepo.log(
        ticketId: ticketId,
        type: ActivityType.assigned,
        detail: 'Zuweisung abgelehnt',
      );
    }
  }

  /// Contractor sets or updates the appointment date.
  Future<void> setAppointment(
    String ticketId,
    DateTime scheduledAt, {
    ActivityRepository? activityRepo,
  }) async {
    await _tickets.doc(ticketId).update({
      'scheduledAt': Timestamp.fromDate(scheduledAt),
    });
    if (activityRepo != null) {
      final label =
          '${scheduledAt.day.toString().padLeft(2, '0')}.'
          '${scheduledAt.month.toString().padLeft(2, '0')}.'
          '${scheduledAt.year}';
      await activityRepo.log(
        ticketId: ticketId,
        type: ActivityType.updated,
        detail: 'Termin festgelegt: $label',
      );
    }
  }

  // ─── Storage helpers ──────────────────────────────────────────────────────

  Future<List<String>> _uploadImages(
      String uid, String ticketId, List<File> files) async {
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final url = await withRetry(() async {
        final ref =
            _storage.ref().child('tickets/$uid/$ticketId/img_$i.jpg');
        await ref.putFile(files[i]);
        return ref.getDownloadURL();
      });
      urls.add(url);
    }
    return urls;
  }

  Future<List<Map<String, String>>> _uploadDocuments(
    String uid,
    String ticketId,
    List<PlatformFile> files,
  ) async {
    final results = <Map<String, String>>[];
    for (final f in files) {
      if (f.path == null) continue;
      final url = await withRetry(() async {
        final ref =
            _storage.ref().child('tickets/$uid/$ticketId/docs/${f.name}');
        await ref.putFile(File(f.path!));
        return ref.getDownloadURL();
      });
      results.add({'name': f.name, 'url': url});
    }
    return results;
  }
}

final ticketRepositoryProvider = Provider<TicketRepository>(
  (ref) => TicketRepository(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
  ),
);
