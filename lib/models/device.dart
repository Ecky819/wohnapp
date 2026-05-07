import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import 'sensor_reading.dart';

enum MaintenanceStatus { overdue, dueSoon, ok, unknown }

extension MaintenanceStatusX on MaintenanceStatus {
  String get label {
    switch (this) {
      case MaintenanceStatus.overdue:
        return 'Überfällig';
      case MaintenanceStatus.dueSoon:
        return 'Bald fällig';
      case MaintenanceStatus.ok:
        return 'OK';
      case MaintenanceStatus.unknown:
        return 'Unbekannt';
    }
  }
}

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

  /// Default service interval in months for this category.
  int get defaultIntervalMonths {
    switch (this) {
      case DeviceCategory.heating:
        return 12;
      case DeviceCategory.plumbing:
        return 24;
      case DeviceCategory.electrical:
        return 24;
      case DeviceCategory.general:
        return 12;
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
    this.tenantId,
    this.unitName,
    this.manufacturer,
    this.modelNumber,
    this.installedAt,
    this.lastServiceAt,
    this.warrantyUntil,
    this.serviceIntervalMonths,
    this.sensorThresholds = const {},
  });

  final String id;
  final String unitId;
  final String name;
  final DeviceCategory category;
  final String? tenantId;
  final String? unitName;
  final String? manufacturer;
  final String? modelNumber;
  final DateTime? installedAt;
  final DateTime? lastServiceAt;
  final DateTime? warrantyUntil;
  /// Configured maintenance interval in months. Null → use category default.
  final int? serviceIntervalMonths;
  /// Sensor-Schwellwerte: sensorType → { min, max }
  final Map<String, SensorThreshold> sensorThresholds;

  int get effectiveIntervalMonths =>
      serviceIntervalMonths ?? category.defaultIntervalMonths;

  /// Date from which the interval is counted: lastServiceAt, then installedAt.
  DateTime? get _baseDate => lastServiceAt ?? installedAt;

  DateTime? get nextServiceDue {
    final base = _baseDate;
    if (base == null) return null;
    return DateTime(
      base.year,
      base.month + effectiveIntervalMonths,
      base.day,
    );
  }

  MaintenanceStatus get maintenanceStatus {
    final due = nextServiceDue;
    if (due == null) return MaintenanceStatus.unknown;
    final now = DateTime.now();
    if (due.isBefore(now)) return MaintenanceStatus.overdue;
    if (due.isBefore(now.add(const Duration(days: 30)))) {
      return MaintenanceStatus.dueSoon;
    }
    return MaintenanceStatus.ok;
  }

  factory Device.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Device(
      id: doc.id,
      unitId: data['unitId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      category: DeviceCategoryX.fromString(
          data['category'] as String? ?? 'general'),
      tenantId: data['tenantId'] as String?,
      unitName: data['unitName'] as String?,
      manufacturer: data['manufacturer'] as String?,
      modelNumber: data['modelNumber'] as String?,
      installedAt: (data['installedAt'] as Timestamp?)?.toDate(),
      lastServiceAt: (data['lastServiceAt'] as Timestamp?)?.toDate(),
      warrantyUntil: (data['warrantyUntil'] as Timestamp?)?.toDate(),
      serviceIntervalMonths: data['serviceIntervalMonths'] as int?,
      sensorThresholds: _parseThresholds(
          data['sensorThresholds'] as Map<String, dynamic>?),
    );
  }

  static Map<String, SensorThreshold> _parseThresholds(
      Map<String, dynamic>? raw) {
    if (raw == null) return {};
    return raw.map((k, v) =>
        MapEntry(k, SensorThreshold.fromMap(Map<String, dynamic>.from(v as Map))));
  }

  bool get warrantyActive =>
      warrantyUntil != null && DateTime.now().isBefore(warrantyUntil!);
}
