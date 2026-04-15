import 'package:cloud_firestore/cloud_firestore.dart';

class Building {
  const Building({
    required this.id,
    required this.name,
    required this.address,
    required this.tenantId,
  });

  final String id;
  final String name;
  final String address;
  final String tenantId;

  factory Building.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Building(
      id: doc.id,
      name: data['name'] as String? ?? '',
      address: data['address'] as String? ?? '',
      tenantId: data['tenantId'] as String? ?? '',
    );
  }
}
