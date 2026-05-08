import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/energy_reading.dart';

class EnergyReadingRepository {
  EnergyReadingRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('energy_readings');

  /// Alle Ablesungen einer Wohnung, absteigend nach Datum.
  Stream<List<EnergyReading>> watchByUnit(String unitId) {
    return _col
        .where('unitId', isEqualTo: unitId)
        .orderBy('readingDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(EnergyReading.fromDoc).toList());
  }

  /// Alle Ablesungen eines Mandanten (für Übersichts-Screen).
  Stream<List<EnergyReading>> watchByTenant(String tenantId) {
    return _col
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('readingDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map(EnergyReading.fromDoc).toList());
  }

  Future<void> addReading(EnergyReading reading) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _col.add({
      ...reading.toMap(),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mehrere Ablesungen auf einmal (CSV-Import).
  Future<void> addBatch(List<EnergyReading> readings) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final batch = _db.batch();
    for (final r in readings) {
      final ref = _col.doc();
      batch.set(ref, {
        ...r.toMap(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> deleteReading(String id) async {
    await _col.doc(id).delete();
  }

  /// Einmaliger Fetch aller Ablesungen eines Mandanten (für CSV-Export).
  Future<List<EnergyReading>> fetchByTenant(String tenantId) async {
    final snap = await _col
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('readingDate', descending: false)
        .get();
    return snap.docs.map(EnergyReading.fromDoc).toList();
  }
}

final energyReadingRepositoryProvider = Provider<EnergyReadingRepository>(
  (ref) => EnergyReadingRepository(FirebaseFirestore.instance),
);

final energyReadingsByTenantProvider =
    StreamProvider.family<List<EnergyReading>, String>((ref, tenantId) {
  return ref.read(energyReadingRepositoryProvider).watchByTenant(tenantId);
});
