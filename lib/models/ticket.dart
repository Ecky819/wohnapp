import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color, Colors, IconData, Icons;

class Ticket {
  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final String tenantId;
  final String createdBy;
  final String? imageUrl;        // legacy single image (kept for backwards compat)
  final List<String> imageUrls;  // multiple images
  final String? assignedTo;
  final String? assignedToName;
  final String? unitId;
  final String? unitName;
  final DateTime? createdAt;
  final DateTime? closedAt;
  /// Planned date for maintenance tickets. Used in the calendar view.
  final DateTime? scheduledAt;
  final List<Map<String, String>> documents;
  final bool archived;

  const Ticket({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.tenantId,
    required this.createdBy,
    required this.category,
    this.imageUrl,
    this.imageUrls = const [],
    this.assignedTo,
    this.assignedToName,
    this.unitId,
    this.unitName,
    this.createdAt,
    this.closedAt,
    this.scheduledAt,
    this.documents = const [],
    this.archived = false,
  });

  final String category; // 'damage' | 'maintenance'

  factory Ticket.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Ticket(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      status: data['status'] as String? ?? 'open',
      priority: data['priority'] as String? ?? 'normal',
      tenantId: data['tenantId'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      category: data['category'] as String? ?? 'damage',
      imageUrl: data['imageUrl'] as String?,
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      assignedTo: data['assignedTo'] as String?,
      assignedToName: data['assignedToName'] as String?,
      unitId: data['unitId'] as String?,
      unitName: data['unitName'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      scheduledAt: (data['scheduledAt'] as Timestamp?)?.toDate(),
      documents: (data['documents'] as List<dynamic>? ?? [])
          .map((e) => Map<String, String>.from(e as Map))
          .toList(),
      archived: data['archived'] as bool? ?? false,
    );
  }

  String get categoryLabel =>
      category == 'maintenance' ? 'Wartung' : 'Schaden';

  IconData get categoryIcon =>
      category == 'maintenance' ? Icons.build_circle_outlined : Icons.report_problem_outlined;

  String get statusLabel {
    switch (status) {
      case 'open':
        return 'Offen';
      case 'in_progress':
        return 'In Bearbeitung';
      case 'done':
        return 'Erledigt';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'done':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
