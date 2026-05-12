import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/invitation.dart';
import '../models/notification_preferences.dart';

class UserRepository {
  UserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// Fetches existing user or creates one from an invitation.
  /// After loading, ensures Firebase Auth custom claims (role + tenantId)
  /// are in sync so Storage/Firestore Rules can use request.auth.token.
  Future<AppUser> getOrCreate(
    User firebaseUser, {
    Invitation? invitation,
  }) async {
    final ref = _users.doc(firebaseUser.uid);
    final doc = await ref.get();

    late AppUser appUser;

    if (doc.exists) {
      appUser = AppUser.fromMap(firebaseUser.uid, doc.data()!);
    } else {
      // New user — use invitation data if available
      final data = <String, dynamic>{
        'email': firebaseUser.email ?? '',
        'name': firebaseUser.email?.split('@')[0] ?? '',
        'role': invitation?.roleString ?? 'tenant_user',
        'tenantId': invitation?.tenantId ?? 'tenant_1',
        'createdAt': FieldValue.serverTimestamp(),
        if (invitation?.unitId != null) 'unitId': invitation!.unitId,
      };

      await ref.set(data);
      final created = await ref.get();
      appUser = AppUser.fromMap(firebaseUser.uid, created.data()!);
    }

    await _ensureCustomClaims(firebaseUser, appUser);

    return appUser;
  }

  /// Ensures custom claims { role, tenantId } are set in the Firebase Auth JWT.
  /// If missing or stale, calls refreshMyUserClaims Cloud Function and
  /// force-refreshes the token so rules have the latest claims immediately.
  Future<void> _ensureCustomClaims(User firebaseUser, AppUser appUser) async {
    try {
      final result = await firebaseUser.getIdTokenResult();
      final claims = result.claims ?? {};

      if (claims['role'] == appUser.role &&
          claims['tenantId'] == appUser.tenantId) {
        return; // Claims already up to date
      }

      // Claims missing or stale — ask server to set them
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('refreshMyUserClaims')
          .call();

      // Force token refresh so new claims are included immediately
      await firebaseUser.getIdToken(true);
    } catch (_) {
      // Non-fatal: syncUserClaims Firestore trigger will set claims async.
      // The next login will pick them up via token refresh.
    }
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

  Future<void> updateNotificationPreferences(
    String uid,
    NotificationPreferences prefs,
  ) {
    return _users.doc(uid).update({
      'notificationPreferences': prefs.toMap(),
    });
  }

  Future<NotificationPreferences> getPreferences(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return const NotificationPreferences();
    return NotificationPreferences.fromMap(
      doc.data()?['notificationPreferences'] as Map<String, dynamic>?,
    );
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
