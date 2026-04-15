import 'package:cloud_firestore/cloud_firestore.dart';

enum ActivityType { created, statusChanged, assigned, updated }

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.ticketId,
    required this.actorId,
    required this.actorName,
    required this.type,
    required this.detail,
    this.createdAt,
  });

  final String id;
  final String ticketId;
  final String actorId;
  final String actorName;
  final ActivityType type;
  final String detail; // e.g. "open → in_progress", "zugewiesen an Max"
  final DateTime? createdAt;

  factory ActivityEntry.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return ActivityEntry(
      id: doc.id,
      ticketId: m['ticketId'] as String? ?? '',
      actorId: m['actorId'] as String? ?? '',
      actorName: m['actorName'] as String? ?? '',
      type: _typeFromString(m['type'] as String? ?? ''),
      detail: m['detail'] as String? ?? '',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  static ActivityType _typeFromString(String s) {
    switch (s) {
      case 'statusChanged':
        return ActivityType.statusChanged;
      case 'assigned':
        return ActivityType.assigned;
      case 'updated':
        return ActivityType.updated;
      default:
        return ActivityType.created;
    }
  }

  String get typeString {
    switch (type) {
      case ActivityType.created:
        return 'created';
      case ActivityType.statusChanged:
        return 'statusChanged';
      case ActivityType.assigned:
        return 'assigned';
      case ActivityType.updated:
        return 'updated';
    }
  }
}
