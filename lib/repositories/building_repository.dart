import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/building.dart';
import '../models/unit.dart';
import '../user_provider.dart';

class BuildingRepository {
  BuildingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _buildings =>
      _firestore.collection('buildings');

  CollectionReference<Map<String, dynamic>> get _units =>
      _firestore.collection('units');

  Stream<List<Building>> watchBuildings(String tenantId) {
    return _buildings
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Building.fromDoc).toList());
  }

  Stream<List<Unit>> watchUnits(String buildingId) {
    return _units
        .where('buildingId', isEqualTo: buildingId)
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Unit.fromDoc).toList());
  }

  Future<String> createBuilding({
    required String name,
    required String address,
    required String tenantId,
  }) async {
    final ref = _buildings.doc();
    await ref.set({'name': name, 'address': address, 'tenantId': tenantId});
    return ref.id;
  }

  Future<Unit?> getUnit(String unitId) async {
    final doc = await _units.doc(unitId).get();
    if (!doc.exists) return null;
    return Unit.fromDoc(doc);
  }

  Future<String> createUnit({
    required String buildingId,
    required String name,
    required String tenantId,
    int? floor,
  }) async {
    final ref = _units.doc();
    await ref.set({
      'buildingId': buildingId,
      'name': name,
      'tenantId': tenantId,
      if (floor != null) 'floor': floor,
    });
    return ref.id;
  }
}

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
    StreamProvider.family<List<Unit>, String>((ref, buildingId) {
  if (buildingId.isEmpty) return const Stream.empty();
  return ref.read(buildingRepositoryProvider).watchUnits(buildingId);
});

/// Single unit by id (FutureProvider).
final unitByIdProvider =
    FutureProvider.family<Unit?, String>((ref, unitId) async {
  if (unitId.isEmpty) return null;
  return ref.read(buildingRepositoryProvider).getUnit(unitId);
});
