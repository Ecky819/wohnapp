import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_entry.dart';

class ActivityRepository {
  ActivityRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _activity(String ticketId) =>
      _firestore
          .collection('tickets')
          .doc(ticketId)
          .collection('activity');

  Stream<List<ActivityEntry>> watchActivity(String ticketId) {
    return _activity(ticketId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(ActivityEntry.fromDoc).toList());
  }

  Future<void> log({
    required String ticketId,
    required ActivityType type,
    required String detail,
    String? actorNameOverride,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    String actorName = actorNameOverride ?? '';

    if (actorName.isEmpty && uid.isNotEmpty) {
      // Try to resolve name from Firestore
      try {
        final doc =
            await _firestore.collection('users').doc(uid).get();
        actorName = doc.data()?['name'] as String? ?? '';
        if (actorName.isEmpty) {
          actorName = doc.data()?['email'] as String? ?? uid;
        }
      } catch (_) {
        actorName = uid;
      }
    }

    await _activity(ticketId).add({
      'ticketId': ticketId,
      'actorId': uid,
      'actorName': actorName,
      'type': ActivityEntry(
              id: '',
              ticketId: ticketId,
              actorId: uid,
              actorName: actorName,
              type: type,
              detail: detail)
          .typeString,
      'detail': detail,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(FirebaseFirestore.instance),
);

final activityProvider =
    StreamProvider.family<List<ActivityEntry>, String>((ref, ticketId) {
  return ref.watch(activityRepositoryProvider).watchActivity(ticketId);
});
