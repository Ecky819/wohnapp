import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/invitation.dart';

class UserRepository {
  UserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// Fetches existing user or creates one from an invitation.
  /// [invitation] must be provided on first registration.
  /// Falls back to tenant_1 only for legacy/dev users without invitation.
  Future<AppUser> getOrCreate(
    User firebaseUser, {
    Invitation? invitation,
  }) async {
    final ref = _users.doc(firebaseUser.uid);
    final doc = await ref.get();

    if (doc.exists) {
      return AppUser.fromMap(firebaseUser.uid, doc.data()!);
    }

    // New user — use invitation data if available
    final data = {
      'email': firebaseUser.email ?? '',
      'name': firebaseUser.email?.split('@')[0] ?? '',
      'role': invitation?.roleString ?? 'tenant_user',
      'tenantId': invitation?.tenantId ?? 'tenant_1',
      'createdAt': FieldValue.serverTimestamp(),
    };

    await ref.set(data);
    final created = await ref.get();
    return AppUser.fromMap(firebaseUser.uid, created.data()!);
  }

  Future<List<AppUser>> getContractors() async {
    final snap = await _users.where('role', isEqualTo: 'contractor').get();
    return snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList();
  }

  Future<void> updateSpecializations(
      String uid, List<String> specializations) {
    return _users.doc(uid).update({'specializations': specializations});
  }

  Future<void> assignUnit(String uid, String? unitId) {
    return _users.doc(uid).update({'unitId': unitId});
  }

  Stream<List<AppUser>> watchTenants(String tenantId) {
    return _users
        .where('tenantId', isEqualTo: tenantId)
        .where('role', isEqualTo: 'tenant_user')
        .snapshots()
        .map((s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());
  }
}

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(FirebaseFirestore.instance),
);
