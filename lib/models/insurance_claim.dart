import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ─── Status ───────────────────────────────────────────────────────────────────

enum ClaimStatus { reported, underReview, approved, rejected, settled }

extension ClaimStatusX on ClaimStatus {
  String get label {
    switch (this) {
      case ClaimStatus.reported:    return 'Gemeldet';
      case ClaimStatus.underReview: return 'In Prüfung';
      case ClaimStatus.approved:    return 'Genehmigt';
      case ClaimStatus.rejected:    return 'Abgelehnt';
      case ClaimStatus.settled:     return 'Reguliert';
    }
  }

  Color get color {
    switch (this) {
      case ClaimStatus.reported:    return Colors.orange;
      case ClaimStatus.underReview: return Colors.blue;
      case ClaimStatus.approved:    return Colors.green;
      case ClaimStatus.rejected:    return Colors.red;
      case ClaimStatus.settled:     return Colors.purple;
    }
  }

  IconData get icon {
    switch (this) {
      case ClaimStatus.reported:    return Icons.report_outlined;
      case ClaimStatus.underReview: return Icons.manage_search_outlined;
      case ClaimStatus.approved:    return Icons.check_circle_outline;
      case ClaimStatus.rejected:    return Icons.cancel_outlined;
      case ClaimStatus.settled:     return Icons.verified_outlined;
    }
  }

  String get firestoreValue {
    switch (this) {
      case ClaimStatus.reported:    return 'reported';
      case ClaimStatus.underReview: return 'under_review';
      case ClaimStatus.approved:    return 'approved';
      case ClaimStatus.rejected:    return 'rejected';
      case ClaimStatus.settled:     return 'settled';
    }
  }

  /// Which statuses the manager can move to from this state.
  List<ClaimStatus> get nextStatuses {
    switch (this) {
      case ClaimStatus.reported:    return [ClaimStatus.underReview];
      case ClaimStatus.underReview: return [ClaimStatus.approved, ClaimStatus.rejected];
      case ClaimStatus.approved:    return [ClaimStatus.settled];
      case ClaimStatus.rejected:    return [];
      case ClaimStatus.settled:     return [];
    }
  }

  bool get isTerminal =>
      this == ClaimStatus.rejected || this == ClaimStatus.settled;

  static ClaimStatus fromString(String? s) {
    switch (s) {
      case 'under_review': return ClaimStatus.underReview;
      case 'approved':     return ClaimStatus.approved;
      case 'rejected':     return ClaimStatus.rejected;
      case 'settled':      return ClaimStatus.settled;
      default:             return ClaimStatus.reported;
    }
  }
}

// ─── Model ────────────────────────────────────────────────────────────────────

class InsuranceClaim {
  const InsuranceClaim({
    required this.status,
    required this.insurerName,
    this.policyNumber,
    this.claimNumber,
    this.deductibleAmount,
    this.estimatedDamage,
    this.approvedAmount,
    this.reportedAt,
    this.settledAt,
    this.expertName,
    this.expertReportUrl,
    this.notes,
  });

  final ClaimStatus status;
  final String insurerName;         // Versicherungsgesellschaft
  final String? policyNumber;       // Policennummer
  final String? claimNumber;        // Schadennummer (vergeben durch Versicherung)
  final double? deductibleAmount;   // Selbstbeteiligung (€)
  final double? estimatedDamage;    // Geschätzter Schaden (€)
  final double? approvedAmount;     // Genehmigter Betrag (€)
  final DateTime? reportedAt;       // Datum der Schadensmeldung
  final DateTime? settledAt;        // Datum der Regulierung
  final String? expertName;         // Gutachter
  final String? expertReportUrl;    // Link / Download-URL des Gutachtens
  final String? notes;              // Interne Notizen

  factory InsuranceClaim.fromMap(Map<String, dynamic> map) => InsuranceClaim(
        status: ClaimStatusX.fromString(map['status'] as String?),
        insurerName: map['insurerName'] as String? ?? '',
        policyNumber: map['policyNumber'] as String?,
        claimNumber: map['claimNumber'] as String?,
        deductibleAmount: (map['deductibleAmount'] as num?)?.toDouble(),
        estimatedDamage: (map['estimatedDamage'] as num?)?.toDouble(),
        approvedAmount: (map['approvedAmount'] as num?)?.toDouble(),
        reportedAt: (map['reportedAt'] as Timestamp?)?.toDate(),
        settledAt: (map['settledAt'] as Timestamp?)?.toDate(),
        expertName: map['expertName'] as String?,
        expertReportUrl: map['expertReportUrl'] as String?,
        notes: map['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'status': status.firestoreValue,
        'insurerName': insurerName,
        if (policyNumber != null) 'policyNumber': policyNumber,
        if (claimNumber != null) 'claimNumber': claimNumber,
        if (deductibleAmount != null) 'deductibleAmount': deductibleAmount,
        if (estimatedDamage != null) 'estimatedDamage': estimatedDamage,
        if (approvedAmount != null) 'approvedAmount': approvedAmount,
        if (reportedAt != null)
          'reportedAt': Timestamp.fromDate(reportedAt!),
        if (settledAt != null)
          'settledAt': Timestamp.fromDate(settledAt!),
        if (expertName != null) 'expertName': expertName,
        if (expertReportUrl != null) 'expertReportUrl': expertReportUrl,
        if (notes != null) 'notes': notes,
      };

  InsuranceClaim copyWith({
    ClaimStatus? status,
    String? insurerName,
    String? policyNumber,
    String? claimNumber,
    double? deductibleAmount,
    double? estimatedDamage,
    double? approvedAmount,
    DateTime? reportedAt,
    DateTime? settledAt,
    String? expertName,
    String? expertReportUrl,
    String? notes,
  }) =>
      InsuranceClaim(
        status: status ?? this.status,
        insurerName: insurerName ?? this.insurerName,
        policyNumber: policyNumber ?? this.policyNumber,
        claimNumber: claimNumber ?? this.claimNumber,
        deductibleAmount: deductibleAmount ?? this.deductibleAmount,
        estimatedDamage: estimatedDamage ?? this.estimatedDamage,
        approvedAmount: approvedAmount ?? this.approvedAmount,
        reportedAt: reportedAt ?? this.reportedAt,
        settledAt: settledAt ?? this.settledAt,
        expertName: expertName ?? this.expertName,
        expertReportUrl: expertReportUrl ?? this.expertReportUrl,
        notes: notes ?? this.notes,
      );
}
