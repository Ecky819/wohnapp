import 'package:cloud_firestore/cloud_firestore.dart';

class Unit {
  const Unit({
    required this.id,
    required this.buildingId,
    required this.name,
    required this.tenantId,
    this.floor,
    this.area,
    this.rooms,
    this.buildYear,
  });

  final String id;
  final String buildingId;
  final String name;
  final String tenantId;
  final int? floor;
  final double? area; // m²
  final int? rooms;
  final int? buildYear;

  factory Unit.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Unit(
      id: doc.id,
      buildingId: data['buildingId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      tenantId: data['tenantId'] as String? ?? '',
      floor: data['floor'] as int?,
      area: (data['area'] as num?)?.toDouble(),
      rooms: data['rooms'] as int?,
      buildYear: data['buildYear'] as int?,
    );
  }

  String get displayName => floor != null ? '$name ($floor. OG)' : name;

  String get details {
    final parts = <String>[];
    if (rooms != null) parts.add('$rooms Zi.');
    if (area != null) parts.add('${area!.toStringAsFixed(1)} m²');
    if (buildYear != null) parts.add('Bj. $buildYear');
    return parts.join(' · ');
  }
}
