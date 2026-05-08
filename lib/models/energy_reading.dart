import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ─── Zählertyp ────────────────────────────────────────────────────────────────

enum EnergyType { electricity, gas, water, heating }

extension EnergyTypeX on EnergyType {
  String get label {
    switch (this) {
      case EnergyType.electricity: return 'Strom';
      case EnergyType.gas:         return 'Gas';
      case EnergyType.water:       return 'Wasser';
      case EnergyType.heating:     return 'Wärme';
    }
  }

  String get unit {
    switch (this) {
      case EnergyType.electricity: return 'kWh';
      case EnergyType.gas:         return 'm³';
      case EnergyType.water:       return 'm³';
      case EnergyType.heating:     return 'kWh';
    }
  }

  IconData get icon {
    switch (this) {
      case EnergyType.electricity: return Icons.bolt_outlined;
      case EnergyType.gas:         return Icons.local_fire_department_outlined;
      case EnergyType.water:       return Icons.water_drop_outlined;
      case EnergyType.heating:     return Icons.thermostat_outlined;
    }
  }

  Color get color {
    switch (this) {
      case EnergyType.electricity: return Colors.amber;
      case EnergyType.gas:         return Colors.orange;
      case EnergyType.water:       return Colors.blue;
      case EnergyType.heating:     return Colors.red;
    }
  }

  String get firestoreValue {
    switch (this) {
      case EnergyType.electricity: return 'electricity';
      case EnergyType.gas:         return 'gas';
      case EnergyType.water:       return 'water';
      case EnergyType.heating:     return 'heating';
    }
  }

  static EnergyType fromString(String? s) {
    switch (s) {
      case 'gas':      return EnergyType.gas;
      case 'water':    return EnergyType.water;
      case 'heating':  return EnergyType.heating;
      default:         return EnergyType.electricity;
    }
  }

  /// CSV-Import-Alias (deutsche Bezeichnungen akzeptieren)
  static EnergyType fromCsvLabel(String s) {
    final l = s.trim().toLowerCase();
    if (l == 'gas')                     return EnergyType.gas;
    if (l == 'wasser')                  return EnergyType.water;
    if (l == 'wärme' || l == 'warme' || l == 'heating') return EnergyType.heating;
    return EnergyType.electricity;
  }
}

// ─── Modell ───────────────────────────────────────────────────────────────────

class EnergyReading {
  const EnergyReading({
    required this.id,
    required this.tenantId,
    required this.unitId,
    required this.unitName,
    required this.type,
    required this.value,
    required this.readingDate,
    this.meterNumber,
    this.note,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String tenantId;
  final String unitId;
  final String unitName;
  final EnergyType type;
  final double value;          // Zählerstand (absolut)
  final DateTime readingDate;
  final String? meterNumber;
  final String? note;
  final String? createdBy;
  final DateTime? createdAt;

  factory EnergyReading.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return EnergyReading(
      id: doc.id,
      tenantId: d['tenantId'] as String? ?? '',
      unitId: d['unitId'] as String? ?? '',
      unitName: d['unitName'] as String? ?? '',
      type: EnergyTypeX.fromString(d['type'] as String?),
      value: (d['value'] as num?)?.toDouble() ?? 0,
      readingDate: (d['readingDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      meterNumber: d['meterNumber'] as String?,
      note: d['note'] as String?,
      createdBy: d['createdBy'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'tenantId': tenantId,
        'unitId': unitId,
        'unitName': unitName,
        'type': type.firestoreValue,
        'value': value,
        'readingDate': Timestamp.fromDate(readingDate),
        if (meterNumber != null) 'meterNumber': meterNumber,
        if (note != null) 'note': note,
        if (createdBy != null) 'createdBy': createdBy,
      };
}
