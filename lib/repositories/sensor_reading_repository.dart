import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sensor_reading.dart';

class SensorReadingRepository {
  SensorReadingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('sensor_readings');

  /// Neueste Messung pro Sensor-Typ für eine Wohnung.
  Stream<List<SensorReading>> watchLatestByUnit(String unitId) {
    return _col
        .where('unitId', isEqualTo: unitId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => _deduplicateByType(
            s.docs.map(SensorReading.fromDoc).toList()));
  }

  /// Alle Messungen eines Geräts für einen Sensor-Typ (Verlauf).
  Stream<List<SensorReading>> watchHistory(
      String deviceId, SensorType type) {
    return _col
        .where('deviceId', isEqualTo: deviceId)
        .where('sensorType', isEqualTo: type.firestoreValue)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(SensorReading.fromDoc).toList());
  }

  /// Neueste Messung pro Sensor-Typ für einen Mandanten (alle Wohnungen).
  Stream<List<SensorReading>> watchLatestByTenant(String tenantId) {
    return _col
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => _deduplicateByType(
            s.docs.map(SensorReading.fromDoc).toList()));
  }

  /// Gibt nur den neuesten Wert pro Sensor-Typ zurück.
  List<SensorReading> _deduplicateByType(List<SensorReading> readings) {
    final seen = <String>{};
    final result = <SensorReading>[];
    for (final r in readings) {
      final key = '${r.sensorType.firestoreValue}_${r.deviceId ?? r.unitId}';
      if (seen.add(key)) result.add(r);
    }
    return result;
  }
}

final sensorReadingRepositoryProvider = Provider<SensorReadingRepository>(
  (ref) => SensorReadingRepository(FirebaseFirestore.instance),
);
