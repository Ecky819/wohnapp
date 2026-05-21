import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/models/app_enums.dart';
import 'package:wohnapp/models/rental_agreement.dart';

RentalAgreement _make({
  String status = 'active',
  double? monthlyRent,
  double? monthlyHeatingAdvance,
  List<NebenkostenPosition> nebenkostenPositionen = const [],
  String? contractUrl,
  String? contractFileName,
}) =>
    RentalAgreement(
      id: 'ag-1',
      tenantId: 'tenant_1',
      tenantName: 'Max Muster',
      unitId: 'unit-1',
      unitName: 'Whg 1',
      buildingId: 'bld-1',
      buildingName: 'Hauptstraße 1',
      startDate: DateTime(2024, 1, 1),
      status: status,
      createdAt: DateTime(2024, 1, 1),
      monthlyRent: monthlyRent,
      monthlyHeatingAdvance: monthlyHeatingAdvance,
      nebenkostenPositionen: nebenkostenPositionen,
      contractUrl: contractUrl,
      contractFileName: contractFileName,
    );

void main() {
  // ─── Warmmiete ─────────────────────────────────────────────────────────────

  group('RentalAgreement.monthlyWarmRent', () {
    test('zero when all fields absent', () {
      expect(_make().monthlyWarmRent, 0.0);
    });

    test('equals rent alone when no extras', () {
      expect(_make(monthlyRent: 800).monthlyWarmRent, 800.0);
    });

    test('sums rent + utilities + heating', () {
      final ag = _make(
        monthlyRent: 800,
        monthlyHeatingAdvance: 50,
        nebenkostenPositionen: [
          const NebenkostenPosition(bezeichnung: 'Wasser', monatlicheVorauszahlung: 30),
          const NebenkostenPosition(bezeichnung: 'Müll', monatlicheVorauszahlung: 20),
        ],
      );
      expect(ag.monthlyWarmRent, 900.0);
    });

    test('handles heating-only extras', () {
      expect(_make(monthlyRent: 600, monthlyHeatingAdvance: 80).monthlyWarmRent, 680.0);
    });
  });

  // ─── monthlyUtilityTotal ───────────────────────────────────────────────────

  group('RentalAgreement.monthlyUtilityTotal', () {
    test('zero with no positions', () {
      expect(_make().monthlyUtilityTotal, 0.0);
    });

    test('sums all positions', () {
      final ag = _make(nebenkostenPositionen: [
        const NebenkostenPosition(bezeichnung: 'A', monatlicheVorauszahlung: 25),
        const NebenkostenPosition(bezeichnung: 'B', monatlicheVorauszahlung: 15),
        const NebenkostenPosition(bezeichnung: 'C', monatlicheVorauszahlung: 10),
      ]);
      expect(ag.monthlyUtilityTotal, 50.0);
    });
  });

  // ─── hasContract ──────────────────────────────────────────────────────────

  group('RentalAgreement.hasContract', () {
    test('false when contractUrl is null', () {
      expect(_make().hasContract, isFalse);
    });

    test('false when contractUrl is empty string', () {
      expect(_make(contractUrl: '').hasContract, isFalse);
    });

    test('true when contractUrl is set', () {
      expect(_make(contractUrl: 'https://example.com/doc.pdf').hasContract, isTrue);
    });
  });

  // ─── hasUtilityCosts ──────────────────────────────────────────────────────

  group('RentalAgreement.hasUtilityCosts', () {
    test('false with no positions and no heating', () {
      expect(_make().hasUtilityCosts, isFalse);
    });

    test('true when heating advance is set', () {
      expect(_make(monthlyHeatingAdvance: 50).hasUtilityCosts, isTrue);
    });

    test('true when positions are present', () {
      final ag = _make(nebenkostenPositionen: [
        const NebenkostenPosition(bezeichnung: 'Wasser', monatlicheVorauszahlung: 20),
      ]);
      expect(ag.hasUtilityCosts, isTrue);
    });
  });

  // ─── isActive ─────────────────────────────────────────────────────────────

  group('RentalAgreement.isActive', () {
    test('true for active status', () {
      expect(_make(status: 'active').isActive, isTrue);
    });

    test('false for notice_given', () {
      expect(_make(status: 'notice_given').isActive, isFalse);
    });

    test('false for ended', () {
      expect(_make(status: 'ended').isActive, isFalse);
    });
  });

  // ─── statusEnum ───────────────────────────────────────────────────────────

  group('RentalAgreement.statusEnum', () {
    test('active → AgreementStatus.active', () {
      expect(_make(status: 'active').statusEnum, AgreementStatus.active);
    });

    test('notice_given → AgreementStatus.noticeGiven', () {
      expect(_make(status: 'notice_given').statusEnum, AgreementStatus.noticeGiven);
    });

    test('ended → AgreementStatus.ended', () {
      expect(_make(status: 'ended').statusEnum, AgreementStatus.ended);
    });

    test('statusColor active is green', () {
      expect(
        _make(status: 'active').statusColor.toARGB32(),
        Colors.green.toARGB32(),
      );
    });
  });

  // ─── NebenkostenPosition helpers ──────────────────────────────────────────

  group('NebenkostenPosition', () {
    test('toMap / fromMap round-trip', () {
      const pos = NebenkostenPosition(
        bezeichnung: 'Grundsteuer',
        monatlicheVorauszahlung: 45.5,
        umlageschluessel: 'einheit',
      );
      final map = pos.toMap();
      final restored = NebenkostenPosition.fromMap(map);
      expect(restored.bezeichnung, 'Grundsteuer');
      expect(restored.monatlicheVorauszahlung, 45.5);
      expect(restored.umlageschluessel, 'einheit');
    });

    test('umlageschluesselLabel wohnflaeche', () {
      const pos = NebenkostenPosition(
        bezeichnung: 'X',
        monatlicheVorauszahlung: 0,
        umlageschluessel: 'wohnflaeche',
      );
      expect(pos.umlageschluesselLabel, 'Wohnfläche');
    });

    test('standardPositionen has 13 entries', () {
      expect(NebenkostenPosition.standardPositionen.length, 13);
    });
  });
}
