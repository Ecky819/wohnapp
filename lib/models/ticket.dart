import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color, IconData, Icons;

import 'app_enums.dart';
import 'insurance_claim.dart';

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
  /// Geplantes Datum für Wartungstickets (Kalenderansicht).
  final DateTime? scheduledAt;
  /// Letzter Schreibzeitpunkt — für Conflict-Detection genutzt.
  final DateTime? updatedAt;
  final List<Map<String, String>> documents;
  final bool archived;
  final InsuranceClaim? insuranceClaim;

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
    this.updatedAt,
    this.documents = const [],
    this.archived = false,
    this.insuranceClaim,
  });

  final String category; // 'damage' | 'maintenance' | 'insurance_claim'

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
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      documents: (data['documents'] as List<dynamic>? ?? [])
          .map((e) => Map<String, String>.from(e as Map))
          .toList(),
      archived: data['archived'] as bool? ?? false,
      insuranceClaim: data['insuranceClaim'] != null
          ? InsuranceClaim.fromMap(
              Map<String, dynamic>.from(data['insuranceClaim'] as Map))
          : null,
    );
  }

  // ── Typ-sichere Enum-Getter (Backing-Feld bleibt String für Firestore) ────

  TicketStatus get statusEnum => TicketStatus.fromString(status);
  TicketCategory get categoryEnum => TicketCategory.fromString(category);
  TicketPriority get priorityEnum => TicketPriority.fromString(priority);

  String get categoryLabel {
    switch (category) {
      case 'maintenance':    return 'Wartung';
      case 'insurance_claim': return 'Versicherungsfall';
      default:               return 'Schaden';
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case 'maintenance':    return Icons.build_circle_outlined;
      case 'insurance_claim': return Icons.security_outlined;
      default:               return Icons.report_problem_outlined;
    }
  }

  String get statusLabel => statusEnum.label;
  Color get statusColor => statusEnum.color;
}
