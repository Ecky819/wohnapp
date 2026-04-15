import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';

class DeviceRepository {
  DeviceRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _devices(String unitId) =>
      _firestore.collection('units').doc(unitId).collection('devices');

  Stream<List<Device>> watchDevices(String unitId) {
    return _devices(unitId)
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Device.fromDoc).toList());
  }

  Future<String> createDevice({
    required String unitId,
    required String name,
    required DeviceCategory category,
    String? manufacturer,
    String? modelNumber,
    DateTime? installedAt,
    DateTime? lastServiceAt,
    DateTime? warrantyUntil,
  }) async {
    final ref = _devices(unitId).doc();
    await ref.set({
      'unitId': unitId,
      'name': name,
      'category': category.name,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (modelNumber != null) 'modelNumber': modelNumber,
      if (installedAt != null)
        'installedAt': Timestamp.fromDate(installedAt),
      if (lastServiceAt != null)
        'lastServiceAt': Timestamp.fromDate(lastServiceAt),
      if (warrantyUntil != null)
        'warrantyUntil': Timestamp.fromDate(warrantyUntil),
    });
    return ref.id;
  }

  Future<void> updateLastService(
      String unitId, String deviceId, DateTime date) {
    return _devices(unitId).doc(deviceId).update({
      'lastServiceAt': Timestamp.fromDate(date),
    });
  }

  Future<void> deleteDevice(String unitId, String deviceId) {
    return _devices(unitId).doc(deviceId).delete();
  }
}

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => DeviceRepository(FirebaseFirestore.instance),
);

final devicesProvider =
    StreamProvider.family<List<Device>, String>((ref, unitId) {
  if (unitId.isEmpty) return const Stream.empty();
  return ref.read(deviceRepositoryProvider).watchDevices(unitId);
});
