import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/building.dart';
import '../models/unit.dart';
import '../user_provider.dart';
import '../utils/app_exception.dart';

// ─── Import data classes ──────────────────────────────────────────────────────

class ImportUnit {
  const ImportUnit({
    required this.name,
    this.floor,
    this.area,
    this.rooms,
    this.buildYear,
  });
  final String name;
  final int? floor;
  final double? area;
  final int? rooms;
  final int? buildYear;
}

class ImportBuilding {
  const ImportBuilding({
    required this.key,
    required this.name,
    required this.address,
    required this.units,
  });
  /// Deduplication key (typically the building name).
  final String key;
  final String name;
  final String address;
  final List<ImportUnit> units;
}

// ─── Repository ───────────────────────────────────────────────────────────────

class BuildingRepository {
  BuildingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const _chunkSize = 400; // stay well below Firestore's 500-op limit

  CollectionReference<Map<String, dynamic>> get _buildings =>
      _firestore.collection('buildings');

  CollectionReference<Map<String, dynamic>> get _units =>
      _firestore.collection('units');

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<List<Building>> watchBuildings(String tenantId) {
    return _buildings
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Building.fromDoc).toList());
  }

  Stream<List<Unit>> watchUnits(String buildingId, String tenantId) {
    return _units
        .where('buildingId', isEqualTo: buildingId)
        .where('tenantId', isEqualTo: tenantId)
        .snapshots()
        .map((s) {
          // Sort in Dart — avoids a 3-field composite index (buildingId+tenantId+name)
          final units = s.docs.map(Unit.fromDoc).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          return units;
        });
  }

  // ── Single-item writes (manual entry) ─────────────────────────────────────

  Future<String> createBuilding({
    required String name,
    required String address,
    required String tenantId,
  }) async {
    try {
      final ref = _buildings.doc();
      await ref.set({'name': name, 'address': address, 'tenantId': tenantId});
      return ref.id;
    } on FirebaseException catch (e) {
      throw AppException.fromFirestore(e);
    }
  }

  Future<String> createUnit({
    required String buildingId,
    required String name,
    required String tenantId,
    int? floor,
    double? area,
    int? rooms,
    int? buildYear,
  }) async {
    try {
      final ref = _units.doc();
      await ref.set({
        'buildingId': buildingId,
        'name': name,
        'tenantId': tenantId,
        if (floor != null) 'floor': floor,
        if (area != null) 'area': area,
        if (rooms != null) 'rooms': rooms,
        if (buildYear != null) 'buildYear': buildYear,
      });
      return ref.id;
    } on FirebaseException catch (e) {
      throw AppException.fromFirestore(e);
    }
  }

  // ── Batch import ───────────────────────────────────────────────────────────

  /// Imports [buildings] (with nested units) via chunked Firestore batch
  /// writes. Pre-generates document IDs so buildings and units can be written
  /// in separate phases without extra round-trips.
  ///
  /// [onProgress] is called after each batch commit with (writtenSoFar, total).
  /// Returns the total number of units written.
  Future<int> batchImport({
    required List<ImportBuilding> buildings,
    required String tenantId,
    void Function(int done, int total)? onProgress,
  }) async {
    final totalUnits = buildings.fold(0, (s, b) => s + b.units.length);
    final totalOps = buildings.length + totalUnits;
    int done = 0;

    // Phase 1 — buildings (pre-generate IDs so units can reference them)
    final buildingRefs = <String, DocumentReference<Map<String, dynamic>>>{
      for (final b in buildings) b.key: _buildings.doc(),
    };

    final buildingPayloads = buildings
        .map((b) => MapEntry(buildingRefs[b.key]!, {
              'name': b.name,
              'address': b.address,
              'tenantId': tenantId,
            }))
        .toList();

    try {
      for (var i = 0; i < buildingPayloads.length; i += _chunkSize) {
        final chunk = buildingPayloads.sublist(
            i, min(i + _chunkSize, buildingPayloads.length));
        final batch = _firestore.batch();
        for (final entry in chunk) {
          batch.set(entry.key, entry.value);
        }
        await batch.commit();
        done += chunk.length;
        onProgress?.call(done, totalOps);
      }

      // Phase 2 — units (reference the pre-generated building IDs)
      final unitPayloads = <Map<String, dynamic>>[
        for (final b in buildings)
          for (final u in b.units)
            {
              'buildingId': buildingRefs[b.key]!.id,
              'name': u.name,
              'tenantId': tenantId,
              if (u.floor != null) 'floor': u.floor,
              if (u.area != null) 'area': u.area,
              if (u.rooms != null) 'rooms': u.rooms,
              if (u.buildYear != null) 'buildYear': u.buildYear,
            },
      ];

      for (var i = 0; i < unitPayloads.length; i += _chunkSize) {
        final chunk =
            unitPayloads.sublist(i, min(i + _chunkSize, unitPayloads.length));
        final batch = _firestore.batch();
        for (final data in chunk) {
          batch.set(_units.doc(), data);
        }
        await batch.commit();
        done += chunk.length;
        onProgress?.call(done, totalOps);
      }
    } on FirebaseException catch (e) {
      throw AppException.fromFirestore(e);
    }

    return totalUnits;
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  Future<Unit?> getUnit(String unitId) async {
    final doc = await _units.doc(unitId).get();
    if (!doc.exists) return null;
    return Unit.fromDoc(doc);
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final buildingRepositoryProvider = Provider<BuildingRepository>(
  (ref) => BuildingRepository(FirebaseFirestore.instance),
);

/// All buildings for the current user's tenant.
final buildingsProvider = StreamProvider<List<Building>>((ref) {
  final tenantId = ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
  if (tenantId.isEmpty) return const Stream.empty();
  return ref.read(buildingRepositoryProvider).watchBuildings(tenantId);
});

/// Units for a given buildingId. Pass an empty string to get an empty stream.
final unitsProvider =
    StreamProvider.autoDispose.family<List<Unit>, String>((ref, buildingId) {
  if (buildingId.isEmpty) return const Stream.empty();
  final tenantId =
      ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';
  if (tenantId.isEmpty) return const Stream.empty();
  return ref.read(buildingRepositoryProvider).watchUnits(buildingId, tenantId);
});

/// Single unit by id (FutureProvider).
final unitByIdProvider =
    FutureProvider.autoDispose.family<Unit?, String>((ref, unitId) async {
  if (unitId.isEmpty) return null;
  return ref.read(buildingRepositoryProvider).getUnit(unitId);
});
