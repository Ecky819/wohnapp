import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rental_agreement.dart';
import '../services/upload_retry_service.dart';
import '../user_provider.dart';

class RentalAgreementRepository {
  RentalAgreementRepository(this._firestore, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('rental_agreements');

  Stream<List<RentalAgreement>> watchAll(String tenantId) {
    return _col.where('tenantId', isEqualTo: tenantId).snapshots().map((s) {
      final list = s.docs.map(RentalAgreement.fromDoc).toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));
      return list;
    });
  }

  Stream<RentalAgreement?> watchOne(String id) {
    return _col
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? RentalAgreement.fromDoc(doc) : null);
  }

  Stream<List<RentalAgreement>> watchForUnit(String unitId) {
    return _col.where('unitId', isEqualTo: unitId).snapshots().map((s) {
      final list = s.docs.map(RentalAgreement.fromDoc).toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));
      return list;
    });
  }

  Future<String> create(RentalAgreement agreement) async {
    final ref = _col.doc();
    await ref.set(agreement.toMap());
    return ref.id;
  }

  Future<void> updateStatus(String id, String status) =>
      _col.doc(id).update({'status': status});

  Future<String> uploadContract(
    String agreementId,
    Uint8List bytes,
    String fileName,
  ) async {
    final ref = _storage.ref('rental_contracts/$agreementId/$fileName');
    final url = await withRetry(() async {
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      return ref.getDownloadURL();
    });
    await _col.doc(agreementId).update({
      'contractUrl': url,
      'contractFileName': fileName,
    });
    return url;
  }

  static const _chunkSize = 400;

  Future<int> batchCreate(
    List<RentalAgreement> agreements, {
    void Function(int done, int total)? onProgress,
  }) async {
    int done = 0;
    for (var i = 0; i < agreements.length; i += _chunkSize) {
      final chunk =
          agreements.sublist(i, min(i + _chunkSize, agreements.length));
      final batch = _firestore.batch();
      for (final a in chunk) {
        batch.set(_col.doc(), a.toMap());
      }
      await batch.commit();
      done += chunk.length;
      onProgress?.call(done, agreements.length);
    }
    return agreements.length;
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}

// ─── Providers ────────────────────────────────────────────────────────────────

final rentalAgreementRepositoryProvider = Provider<RentalAgreementRepository>(
  (ref) => RentalAgreementRepository(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
  ),
);

final rentalAgreementsProvider = StreamProvider<List<RentalAgreement>>((ref) {
  final tenantId =
      ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
  if (tenantId.isEmpty) return const Stream.empty();
  return ref.read(rentalAgreementRepositoryProvider).watchAll(tenantId);
});

final rentalAgreementByIdProvider =
    StreamProvider.family<RentalAgreement?, String>((ref, id) {
  if (id.isEmpty) return const Stream.empty();
  return ref.read(rentalAgreementRepositoryProvider).watchOne(id);
});
