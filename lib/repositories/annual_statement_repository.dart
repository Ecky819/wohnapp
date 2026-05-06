import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/annual_statement.dart';
import '../models/app_user.dart';

class AnnualStatementRepository {
  AnnualStatementRepository(this._db, this._storage);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('statements');

  // ─── Streams ──────────────────────────────────────────────────────────────

  Stream<List<AnnualStatement>> watchForManager(String tenantId) {
    return _col
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(AnnualStatement.fromFirestore).toList());
  }

  Stream<List<AnnualStatement>> watchForRecipient(String recipientId) {
    return _col
        .where('recipientId', isEqualTo: recipientId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(AnnualStatement.fromFirestore).toList());
  }

  /// Mieter des Mandanten (für Empfänger-Auswahl im Formular)
  Stream<List<AppUser>> watchTenants(String tenantOrgId) {
    return _db
        .collection('users')
        .where('tenantId', isEqualTo: tenantOrgId)
        .where('role', isEqualTo: 'tenant_user')
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppUser.fromMap(d.id, d.data()))
            .toList());
  }

  // ─── Storage Uploads ──────────────────────────────────────────────────────

  Future<String> uploadReceiptImage(
    String tenantId,
    String fileName,
    Uint8List bytes,
  ) async {
    final ref =
        _storage.ref('statements/$tenantId/receipts/$fileName');
    await ref.putData(
        bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<String> uploadPdf(
    String tenantId,
    String fileName,
    Uint8List bytes,
  ) async {
    final ref = _storage.ref('statements/$tenantId/$fileName');
    await ref.putData(
        bytes, SettableMetadata(contentType: 'application/pdf'));
    return ref.getDownloadURL();
  }

  // ─── Mutations ────────────────────────────────────────────────────────────

  Future<String> create(AnnualStatement stmt) async {
    final ref = await _col.add({
      ...stmt.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'sentAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> acknowledge(String statementId, String userId) async {
    await _col.doc(statementId).update({
      'status': StatementStatus.acknowledged.name,
      'acknowledgedAt': FieldValue.serverTimestamp(),
      'acknowledgedBy': userId,
    });
  }
}

final annualStatementRepositoryProvider =
    Provider<AnnualStatementRepository>((ref) {
  return AnnualStatementRepository(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
  );
});

final managerStatementsProvider =
    StreamProvider.family<List<AnnualStatement>, String>((ref, tenantId) {
  return ref
      .read(annualStatementRepositoryProvider)
      .watchForManager(tenantId);
});

final tenantStatementsProvider =
    StreamProvider.family<List<AnnualStatement>, String>((ref, recipientId) {
  return ref
      .read(annualStatementRepositoryProvider)
      .watchForRecipient(recipientId);
});
