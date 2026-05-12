import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color, Colors;

class RentalAgreement {
  const RentalAgreement({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    this.tenantEmail = '',
    this.userId,
    required this.unitId,
    required this.unitName,
    required this.buildingId,
    required this.buildingName,
    required this.startDate,
    this.endDate,
    this.monthlyRent,
    this.deposit,
    this.contractUrl,
    this.contractFileName,
    required this.status,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String tenantId;
  final String tenantName;
  final String tenantEmail;
  final String? userId;
  final String unitId;
  final String unitName;
  final String buildingId;
  final String buildingName;
  final DateTime startDate;
  final DateTime? endDate;
  final double? monthlyRent;
  final double? deposit;
  final String? contractUrl;
  final String? contractFileName;
  final String status; // active | notice_given | ended
  final DateTime createdAt;
  final String? notes;

  factory RentalAgreement.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return RentalAgreement(
      id: doc.id,
      tenantId: d['tenantId'] as String? ?? '',
      tenantName: d['tenantName'] as String? ?? '',
      tenantEmail: d['tenantEmail'] as String? ?? '',
      userId: d['userId'] as String?,
      unitId: d['unitId'] as String? ?? '',
      unitName: d['unitName'] as String? ?? '',
      buildingId: d['buildingId'] as String? ?? '',
      buildingName: d['buildingName'] as String? ?? '',
      startDate: (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (d['endDate'] as Timestamp?)?.toDate(),
      monthlyRent: (d['monthlyRent'] as num?)?.toDouble(),
      deposit: (d['deposit'] as num?)?.toDouble(),
      contractUrl: d['contractUrl'] as String?,
      contractFileName: d['contractFileName'] as String?,
      status: d['status'] as String? ?? 'active',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: d['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'tenantId': tenantId,
        'tenantName': tenantName,
        'tenantEmail': tenantEmail,
        if (userId != null) 'userId': userId,
        'unitId': unitId,
        'unitName': unitName,
        'buildingId': buildingId,
        'buildingName': buildingName,
        'startDate': Timestamp.fromDate(startDate),
        if (endDate != null) 'endDate': Timestamp.fromDate(endDate!),
        if (monthlyRent != null) 'monthlyRent': monthlyRent,
        if (deposit != null) 'deposit': deposit,
        if (contractUrl != null) 'contractUrl': contractUrl,
        if (contractFileName != null) 'contractFileName': contractFileName,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  String get statusLabel => switch (status) {
        'active' => 'Aktiv',
        'ended' => 'Beendet',
        'notice_given' => 'Kündigung',
        _ => status,
      };

  Color get statusColor => switch (status) {
        'active' => Colors.green,
        'ended' => Colors.grey,
        'notice_given' => Colors.orange,
        _ => Colors.grey,
      };

  bool get isActive => status == 'active';
  bool get hasContract => contractUrl != null && contractUrl!.isNotEmpty;
}
