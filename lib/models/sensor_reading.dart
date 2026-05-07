import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ─── Sensor-Typen ─────────────────────────────────────────────────────────────

enum SensorType {
  temperature,
  humidity,
  co2,
  waterLeak,
  smoke,
  energyKwh,
  custom,
}

extension SensorTypeX on SensorType {
  String get label {
    switch (this) {
      case SensorType.temperature: return 'Temperatur';
      case SensorType.humidity:    return 'Luftfeuchtigkeit';
      case SensorType.co2:         return 'CO₂';
      case SensorType.waterLeak:   return 'Wasserleck';
      case SensorType.smoke:       return 'Rauchmelder';
      case SensorType.energyKwh:   return 'Energieverbrauch';
      case SensorType.custom:      return 'Sensor';
    }
  }

  String get defaultUnit {
    switch (this) {
      case SensorType.temperature: return '°C';
      case SensorType.humidity:    return '%';
      case SensorType.co2:         return 'ppm';
      case SensorType.waterLeak:   return '';
      case SensorType.smoke:       return '';
      case SensorType.energyKwh:   return 'kWh';
      case SensorType.custom:      return '';
    }
  }

  IconData get icon {
    switch (this) {
      case SensorType.temperature: return Icons.thermostat_outlined;
      case SensorType.humidity:    return Icons.water_drop_outlined;
      case SensorType.co2:         return Icons.co2_outlined;
      case SensorType.waterLeak:   return Icons.water_damage_outlined;
      case SensorType.smoke:       return Icons.crisis_alert_outlined;
      case SensorType.energyKwh:   return Icons.bolt_outlined;
      case SensorType.custom:      return Icons.sensors_outlined;
    }
  }

  Color get color {
    switch (this) {
      case SensorType.temperature: return Colors.orange;
      case SensorType.humidity:    return Colors.blue;
      case SensorType.co2:         return Colors.green;
      case SensorType.waterLeak:   return Colors.red;
      case SensorType.smoke:       return Colors.red;
      case SensorType.energyKwh:   return Colors.purple;
      case SensorType.custom:      return Colors.grey;
    }
  }

  static SensorType fromString(String? s) {
    switch (s) {
      case 'temperature': return SensorType.temperature;
      case 'humidity':    return SensorType.humidity;
      case 'co2':         return SensorType.co2;
      case 'water_leak':  return SensorType.waterLeak;
      case 'smoke':       return SensorType.smoke;
      case 'energy_kwh':  return SensorType.energyKwh;
      default:            return SensorType.custom;
    }
  }

  String get firestoreValue {
    switch (this) {
      case SensorType.temperature: return 'temperature';
      case SensorType.humidity:    return 'humidity';
      case SensorType.co2:         return 'co2';
      case SensorType.waterLeak:   return 'water_leak';
      case SensorType.smoke:       return 'smoke';
      case SensorType.energyKwh:   return 'energy_kwh';
      case SensorType.custom:      return 'custom';
    }
  }
}

// ─── Modell ───────────────────────────────────────────────────────────────────

class SensorReading {
  const SensorReading({
    required this.id,
    required this.tenantId,
    required this.sensorType,
    required this.value,
    required this.unit,
    required this.timestamp,
    this.deviceId,
    this.unitId,
    this.label,
    this.source,
  });

  final String id;
  final String tenantId;
  final SensorType sensorType;
  final double value;
  final String unit;
  final DateTime timestamp;
  final String? deviceId;
  final String? unitId;
  final String? label;   // optionaler Anzeigename aus dem Webhook
  final String? source;  // homeassistant | mqtt | custom

  String get displayLabel => label ?? sensorType.label;

  factory SensorReading.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SensorReading(
      id: doc.id,
      tenantId: d['tenantId'] as String? ?? '',
      sensorType: SensorTypeX.fromString(d['sensorType'] as String?),
      value: (d['value'] as num?)?.toDouble() ?? 0,
      unit: d['unit'] as String? ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deviceId: d['deviceId'] as String?,
      unitId: d['unitId'] as String?,
      label: d['label'] as String?,
      source: d['source'] as String?,
    );
  }
}

// ─── Schwellwert ──────────────────────────────────────────────────────────────

class SensorThreshold {
  const SensorThreshold({this.min, this.max});

  final double? min;
  final double? max;

  factory SensorThreshold.fromMap(Map<String, dynamic> map) => SensorThreshold(
        min: (map['min'] as num?)?.toDouble(),
        max: (map['max'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };

  String get description {
    if (min != null && max != null) return '$min … $max';
    if (min != null) return 'min. $min';
    if (max != null) return 'max. $max';
    return '–';
  }
}
