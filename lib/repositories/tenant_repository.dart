import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tenant.dart';
import '../user_provider.dart';

class TenantRepository {
  TenantRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tenants =>
      _firestore.collection('tenants');

  Stream<Tenant?> watchTenant(String tenantId) {
    if (tenantId.isEmpty) return Stream.value(null);
    return _tenants.doc(tenantId).snapshots().map(
          (snap) => snap.exists ? Tenant.fromDoc(snap) : null,
        );
  }

  Future<void> upsertTenant(Tenant tenant) async {
    await _tenants.doc(tenant.id).set(tenant.toMap(), SetOptions(merge: true));
  }
}

final tenantRepositoryProvider = Provider<TenantRepository>(
  (ref) => TenantRepository(FirebaseFirestore.instance),
);

/// Stream of the currently logged-in user's tenant branding.
final tenantProvider = StreamProvider<Tenant?>((ref) {
  final tenantId = ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
  if (tenantId.isEmpty) return Stream.value(null);
  return ref.read(tenantRepositoryProvider).watchTenant(tenantId);
});
