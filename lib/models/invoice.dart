import 'package:cloud_firestore/cloud_firestore.dart';

enum InvoiceStatus { pending, approved, rejected, exported }

extension InvoiceStatusX on InvoiceStatus {
  String get label {
    switch (this) {
      case InvoiceStatus.pending:
        return 'Ausstehend';
      case InvoiceStatus.approved:
        return 'Freigegeben';
      case InvoiceStatus.rejected:
        return 'Abgelehnt';
      case InvoiceStatus.exported:
        return 'Exportiert';
    }
  }
}

class InvoicePosition {
  const InvoicePosition({
    required this.description,
    required this.amount,
  });

  final String description;
  final double amount;

  Map<String, dynamic> toMap() => {
        'description': description,
        'amount': amount,
      };

  factory InvoicePosition.fromMap(Map<String, dynamic> m) => InvoicePosition(
        description: m['description'] as String? ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
      );
}

class Invoice {
  const Invoice({
    required this.id,
    required this.ticketId,
    required this.ticketTitle,
    required this.contractorId,
    required this.contractorName,
    required this.tenantId,
    required this.amount,
    required this.status,
    required this.positions,
    this.pdfUrl,
    this.rejectionReason,
    this.createdAt,
    this.approvedAt,
  });

  final String id;
  final String ticketId;
  final String ticketTitle;
  final String contractorId;
  final String contractorName;
  final String tenantId;
  final double amount;
  final InvoiceStatus status;
  final List<InvoicePosition> positions;
  final String? pdfUrl;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? approvedAt;

  static InvoiceStatus _parseStatus(String? s) {
    switch (s) {
      case 'approved':
        return InvoiceStatus.approved;
      case 'rejected':
        return InvoiceStatus.rejected;
      case 'exported':
        return InvoiceStatus.exported;
      default:
        return InvoiceStatus.pending;
    }
  }

  factory Invoice.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Invoice(
      id: doc.id,
      ticketId: data['ticketId'] as String? ?? '',
      ticketTitle: data['ticketTitle'] as String? ?? '',
      contractorId: data['contractorId'] as String? ?? '',
      contractorName: data['contractorName'] as String? ?? '',
      tenantId: data['tenantId'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      status: _parseStatus(data['status'] as String?),
      positions: (data['positions'] as List<dynamic>? ?? [])
          .map((p) => InvoicePosition.fromMap(p as Map<String, dynamic>))
          .toList(),
      pdfUrl: data['pdfUrl'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'ticketId': ticketId,
        'ticketTitle': ticketTitle,
        'contractorId': contractorId,
        'contractorName': contractorName,
        'tenantId': tenantId,
        'amount': amount,
        'status': status.name,
        'positions': positions.map((p) => p.toMap()).toList(),
        if (pdfUrl != null) 'pdfUrl': pdfUrl,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
      };
}
