import 'package:cloud_firestore/cloud_firestore.dart';

class Unit {
  const Unit({
    required this.id,
    required this.buildingId,
    required this.name,
    required this.tenantId,
    this.floor,
    this.area,
    this.buildYear,
  });

  final String id;
  final String buildingId;
  final String name;
  final String tenantId;
  final int? floor;
  final double? area; // m²
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
      buildYear: data['buildYear'] as int?,
    );
  }

  String get displayName => floor != null ? '$name ($floor. OG)' : name;
}
