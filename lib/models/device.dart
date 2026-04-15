import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show IconData, Icons;

enum DeviceCategory { heating, plumbing, electrical, general }

extension DeviceCategoryX on DeviceCategory {
  String get label {
    switch (this) {
      case DeviceCategory.heating:
        return 'Heizung';
      case DeviceCategory.plumbing:
        return 'Sanitär';
      case DeviceCategory.electrical:
        return 'Elektro';
      case DeviceCategory.general:
        return 'Allgemein';
    }
  }

  IconData get icon {
    switch (this) {
      case DeviceCategory.heating:
        return Icons.local_fire_department_outlined;
      case DeviceCategory.plumbing:
        return Icons.plumbing_outlined;
      case DeviceCategory.electrical:
        return Icons.electrical_services_outlined;
      case DeviceCategory.general:
        return Icons.build_outlined;
    }
  }

  /// Maps to the routing-service category key.
  String get routingKey {
    switch (this) {
      case DeviceCategory.heating:
        return 'heating';
      case DeviceCategory.plumbing:
        return 'plumbing';
      case DeviceCategory.electrical:
        return 'electrical';
      case DeviceCategory.general:
        return 'general';
    }
  }

  static DeviceCategory fromString(String value) {
    return DeviceCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DeviceCategory.general,
    );
  }
}

class Device {
  const Device({
    required this.id,
    required this.unitId,
    required this.name,
    required this.category,
    this.manufacturer,
    this.modelNumber,
    this.installedAt,
    this.lastServiceAt,
    this.warrantyUntil,
  });

  final String id;
  final String unitId;
  final String name;
  final DeviceCategory category;
  final String? manufacturer;
  final String? modelNumber;
  final DateTime? installedAt;
  final DateTime? lastServiceAt;
  final DateTime? warrantyUntil;

  factory Device.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Device(
      id: doc.id,
      unitId: data['unitId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      category: DeviceCategoryX.fromString(
          data['category'] as String? ?? 'general'),
      manufacturer: data['manufacturer'] as String?,
      modelNumber: data['modelNumber'] as String?,
      installedAt: (data['installedAt'] as Timestamp?)?.toDate(),
      lastServiceAt: (data['lastServiceAt'] as Timestamp?)?.toDate(),
      warrantyUntil: (data['warrantyUntil'] as Timestamp?)?.toDate(),
    );
  }

  bool get warrantyActive =>
      warrantyUntil != null && DateTime.now().isBefore(warrantyUntil!);
}
