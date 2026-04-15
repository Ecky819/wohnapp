import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invitation.dart';

class InvitationRepository {
  InvitationRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _invitations =>
      _firestore.collection('invitations');

  /// Validates a code. Returns the invitation or throws a descriptive error.
  Future<Invitation> validate(String code) async {
    final doc = await _invitations.doc(code.toUpperCase()).get();

    if (!doc.exists) throw InvitationException('Ungültiger Einladungscode.');

    final inv = Invitation.fromDoc(doc);

    if (inv.used) throw InvitationException('Dieser Code wurde bereits verwendet.');
    if (inv.isExpired) throw InvitationException('Dieser Einladungscode ist abgelaufen.');

    return inv;
  }

  /// Marks an invitation as used. Call after successful registration.
  Future<void> markUsed(String code) {
    return _invitations.doc(code.toUpperCase()).update({
      'used': true,
      'usedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Creates a new invitation. Only managers should call this.
  Future<String> create({
    required String tenantId,
    required InvitationRole role,
    Duration validFor = const Duration(days: 7),
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final code = _generateCode();

    await _invitations.doc(code).set({
      'tenantId': tenantId,
      'role': role == InvitationRole.contractor ? 'contractor' : 'tenant_user',
      'used': false,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(validFor)),
    });

    return code;
  }

  /// Returns all invitations created by the current manager.
  Stream<List<Invitation>> watchAll() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return _invitations
        .where('createdBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Invitation.fromDoc).toList());
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/0/1 confusion
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

class InvitationException implements Exception {
  InvitationException(this.message);
  final String message;
  @override
  String toString() => message;
}

final invitationRepositoryProvider = Provider<InvitationRepository>(
  (ref) => InvitationRepository(FirebaseFirestore.instance),
);
