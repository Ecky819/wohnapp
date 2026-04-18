import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
// MaintenanceStatus is part of device.dart

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
    String? tenantId,
    String? unitName,
    String? manufacturer,
    String? modelNumber,
    DateTime? installedAt,
    DateTime? lastServiceAt,
    DateTime? warrantyUntil,
    int? serviceIntervalMonths,
  }) async {
    final ref = _devices(unitId).doc();
    await ref.set({
      'unitId': unitId,
      'name': name,
      'category': category.name,
      if (tenantId != null) 'tenantId': tenantId,
      if (unitName != null) 'unitName': unitName,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (modelNumber != null) 'modelNumber': modelNumber,
      if (installedAt != null)
        'installedAt': Timestamp.fromDate(installedAt),
      if (lastServiceAt != null)
        'lastServiceAt': Timestamp.fromDate(lastServiceAt),
      if (warrantyUntil != null)
        'warrantyUntil': Timestamp.fromDate(warrantyUntil),
      if (serviceIntervalMonths != null)
        'serviceIntervalMonths': serviceIntervalMonths,
    });
    return ref.id;
  }

  /// All devices across every unit for [tenantId] that need attention.
  /// Uses a Firestore collection group query — requires the composite index
  /// (tenantId ASC, nextServiceDue ASC) but works even without it by
  /// post-filtering in-memory.
  Stream<List<Device>> watchMaintenanceAlerts(String tenantId) {
    return _firestore
        .collectionGroup('devices')
        .where('tenantId', isEqualTo: tenantId)
        .snapshots()
        .map((s) => s.docs
            .map(Device.fromDoc)
            .where((d) =>
                d.maintenanceStatus == MaintenanceStatus.overdue ||
                d.maintenanceStatus == MaintenanceStatus.dueSoon)
            .toList()
          ..sort((a, b) {
            final aDate = a.nextServiceDue ?? DateTime(9999);
            final bDate = b.nextServiceDue ?? DateTime(9999);
            return aDate.compareTo(bDate);
          }));
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

final maintenanceAlertsProvider =
    StreamProvider.family<List<Device>, String>((ref, tenantId) {
  if (tenantId.isEmpty) return const Stream.empty();
  return ref.read(deviceRepositoryProvider).watchMaintenanceAlerts(tenantId);
});
