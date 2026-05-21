import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color;

import 'app_enums.dart';

// ─── Betriebskostenposition (§2 BetrKV) ──────────────────────────────────────

class NebenkostenPosition {
  const NebenkostenPosition({
    required this.bezeichnung,
    required this.monatlicheVorauszahlung,
    this.umlageschluessel = 'wohnflaeche',
  });

  final String bezeichnung;
  final double monatlicheVorauszahlung;
  // Umlageschlüssel: 'wohnflaeche' | 'einheit' | 'direkt'
  final String umlageschluessel;

  factory NebenkostenPosition.fromMap(Map<String, dynamic> m) =>
      NebenkostenPosition(
        bezeichnung: m['bezeichnung'] as String? ?? '',
        monatlicheVorauszahlung:
            (m['vorauszahlung'] as num?)?.toDouble() ?? 0,
        umlageschluessel:
            m['umlageschluessel'] as String? ?? 'wohnflaeche',
      );

  Map<String, dynamic> toMap() => {
        'bezeichnung': bezeichnung,
        'vorauszahlung': monatlicheVorauszahlung,
        'umlageschluessel': umlageschluessel,
      };

  String get umlageschluesselLabel => switch (umlageschluessel) {
        'wohnflaeche' => 'Wohnfläche',
        'einheit' => 'Pro Einheit',
        'direkt' => 'Direkt',
        _ => umlageschluessel,
      };

  // Standard-Positionen nach §2 BetrKV
  static const standardPositionen = [
    'Grundsteuer',
    'Wasserversorgung',
    'Entwässerung / Abwasser',
    'Aufzug',
    'Straßenreinigung / Müllabfuhr',
    'Hausreinigung',
    'Gartenpflege',
    'Hausbeleuchtung',
    'Sach- und Haftpflichtversicherung',
    'Hauswart / Hausmeister',
    'Gemeinschaftsantenne / Kabelanschluss',
    'Warmwasser',
    'Sonstige Betriebskosten',
  ];
}

// ─── Mietverhältnis ───────────────────────────────────────────────────────────

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
    // Nebenkosten
    this.nebenkostenPositionen = const [],
    this.monthlyHeatingAdvance,
    // Vertrag
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
  // Betriebskosten-Positionen (§2 BetrKV)
  final List<NebenkostenPosition> nebenkostenPositionen;
  // Heizkosten-Vorauszahlung separat (Pflicht nach HeizkostenVO)
  final double? monthlyHeatingAdvance;
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
      nebenkostenPositionen:
          (d['nebenkostenPositionen'] as List<dynamic>? ?? [])
              .map((e) =>
                  NebenkostenPosition.fromMap(e as Map<String, dynamic>))
              .toList(),
      monthlyHeatingAdvance:
          (d['monthlyHeatingAdvance'] as num?)?.toDouble(),
      contractUrl: d['contractUrl'] as String?,
      contractFileName: d['contractFileName'] as String?,
      status: d['status'] as String? ?? 'active',
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
        if (nebenkostenPositionen.isNotEmpty)
          'nebenkostenPositionen':
              nebenkostenPositionen.map((p) => p.toMap()).toList(),
        if (monthlyHeatingAdvance != null)
          'monthlyHeatingAdvance': monthlyHeatingAdvance,
        if (contractUrl != null) 'contractUrl': contractUrl,
        if (contractFileName != null) 'contractFileName': contractFileName,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  // Gesamte monatliche Betriebskosten-Vorauszahlung (ohne Heizung)
  double get monthlyUtilityTotal =>
      nebenkostenPositionen.fold(0.0, (s, p) => s + p.monatlicheVorauszahlung);

  // Warmmiete = Kaltmiete + NK + HK
  double get monthlyWarmRent =>
      (monthlyRent ?? 0) +
      monthlyUtilityTotal +
      (monthlyHeatingAdvance ?? 0);

  bool get hasUtilityCosts =>
      nebenkostenPositionen.isNotEmpty || monthlyHeatingAdvance != null;

  AgreementStatus get statusEnum => AgreementStatus.fromString(status);
  String get statusLabel => statusEnum.label;
  Color get statusColor => statusEnum.color;

  bool get isActive => statusEnum == AgreementStatus.active;
  bool get hasContract => contractUrl != null && contractUrl!.isNotEmpty;
}
