import 'package:cloud_firestore/cloud_firestore.dart';

import 'statement_position.dart';

enum StatementStatus { draft, sent, acknowledged }

extension StatementStatusX on StatementStatus {
  String get label {
    switch (this) {
      case StatementStatus.draft:
        return 'Entwurf';
      case StatementStatus.sent:
        return 'Zugestellt';
      case StatementStatus.acknowledged:
        return 'Bestätigt';
    }
  }
}

class AnnualStatement {
  const AnnualStatement({
    required this.id,
    required this.tenantId,
    required this.unitId,
    required this.unitName,
    required this.recipientId,
    required this.recipientName,
    required this.year,
    required this.periodStart,
    required this.periodEnd,
    required this.pdfUrl,
    required this.status,
    required this.createdBy,
    required this.positions,
    required this.advancePayments,
    this.note,
    this.createdAt,
    this.sentAt,
    this.acknowledgedAt,
    this.acknowledgedBy,
  });

  final String id;
  final String tenantId;
  final String unitId;
  final String unitName;
  final String recipientId;
  final String recipientName;
  final int year;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String pdfUrl;
  final StatementStatus status;
  final String createdBy;
  final List<StatementPosition> positions;
  final double advancePayments;   // Vorauszahlungen des Mieters
  final String? note;
  final DateTime? createdAt;
  final DateTime? sentAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;

  /// Summe aller Mieteranteile
  double get totalTenantCosts =>
      positions.fold(0.0, (acc, p) => acc + p.tenantAmount);

  /// Positiv = Nachzahlung, negativ = Rückerstattung
  double get balance => totalTenantCosts - advancePayments;

  static StatementStatus _parseStatus(String? s) {
    switch (s) {
      case 'acknowledged':
        return StatementStatus.acknowledged;
      case 'sent':
        return StatementStatus.sent;
      default:
        return StatementStatus.draft;
    }
  }

  factory AnnualStatement.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AnnualStatement(
      id: doc.id,
      tenantId: d['tenantId'] as String? ?? '',
      unitId: d['unitId'] as String? ?? '',
      unitName: d['unitName'] as String? ?? '',
      recipientId: d['recipientId'] as String? ?? '',
      recipientName: d['recipientName'] as String? ?? '',
      year: (d['year'] as int?) ?? DateTime.now().year - 1,
      periodStart: (d['periodStart'] as Timestamp?)?.toDate() ??
          DateTime(DateTime.now().year - 1, 1, 1),
      periodEnd: (d['periodEnd'] as Timestamp?)?.toDate() ??
          DateTime(DateTime.now().year - 1, 12, 31),
      pdfUrl: d['pdfUrl'] as String? ?? '',
      status: _parseStatus(d['status'] as String?),
      createdBy: d['createdBy'] as String? ?? '',
      positions: (d['positions'] as List<dynamic>? ?? [])
          .map((p) =>
              StatementPosition.fromMap(p as Map<String, dynamic>))
          .toList(),
      advancePayments:
          (d['advancePayments'] as num?)?.toDouble() ?? 0.0,
      note: d['note'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      sentAt: (d['sentAt'] as Timestamp?)?.toDate(),
      acknowledgedAt: (d['acknowledgedAt'] as Timestamp?)?.toDate(),
      acknowledgedBy: d['acknowledgedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'tenantId': tenantId,
        'unitId': unitId,
        'unitName': unitName,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'year': year,
        'periodStart': Timestamp.fromDate(periodStart),
        'periodEnd': Timestamp.fromDate(periodEnd),
        'pdfUrl': pdfUrl,
        'status': status.name,
        'createdBy': createdBy,
        'positions': positions.map((p) => p.toMap()).toList(),
        'advancePayments': advancePayments,
        if (note != null) 'note': note,
        if (sentAt != null) 'sentAt': Timestamp.fromDate(sentAt!),
        if (acknowledgedAt != null)
          'acknowledgedAt': Timestamp.fromDate(acknowledgedAt!),
        if (acknowledgedBy != null) 'acknowledgedBy': acknowledgedBy,
      };
}
