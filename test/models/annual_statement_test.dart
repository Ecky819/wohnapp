import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/models/annual_statement.dart';
import 'package:wohnapp/models/statement_position.dart';

StatementPosition _pos(double totalCost, double tenantPercent) =>
    StatementPosition(
      category: BetriebskostenCategory.wasser,
      label: 'Test',
      totalCost: totalCost,
      distributionKey: DistributionKey.area,
      tenantPercent: tenantPercent,
      receiptImageUrls: const [],
    );

AnnualStatement _make({
  List<StatementPosition> positions = const [],
  double advancePayments = 0,
}) =>
    AnnualStatement(
      id: 'stmt-1',
      tenantId: 'tenant_1',
      unitId: 'unit_1',
      unitName: 'Wohnung 1',
      recipientId: 'user_1',
      recipientName: 'Max Mustermann',
      year: 2024,
      periodStart: DateTime(2024, 1, 1),
      periodEnd: DateTime(2024, 12, 31),
      pdfUrl: '',
      status: StatementStatus.sent,
      createdBy: 'manager_1',
      positions: positions,
      advancePayments: advancePayments,
    );

void main() {
  group('AnnualStatement.totalTenantCosts', () {
    test('empty positions → 0', () {
      expect(_make().totalTenantCosts, 0.0);
    });

    test('single position 50% of 1000 = 500', () {
      expect(
        _make(positions: [_pos(1000, 50)]).totalTenantCosts,
        500.0,
      );
    });

    test('multiple positions summed correctly', () {
      final stmt = _make(positions: [
        _pos(1000, 50), // 500
        _pos(600, 25),  // 150
        _pos(200, 100), // 200
      ]);
      expect(stmt.totalTenantCosts, closeTo(850.0, 0.001));
    });
  });

  group('AnnualStatement.balance', () {
    test('costs > advance → positive (Nachzahlung)', () {
      final stmt = _make(
        positions: [_pos(1000, 100)],
        advancePayments: 800,
      );
      expect(stmt.balance, closeTo(200.0, 0.001));
    });

    test('costs < advance → negative (Rückerstattung)', () {
      final stmt = _make(
        positions: [_pos(600, 100)],
        advancePayments: 800,
      );
      expect(stmt.balance, closeTo(-200.0, 0.001));
    });

    test('costs == advance → zero', () {
      final stmt = _make(
        positions: [_pos(1000, 100)],
        advancePayments: 1000,
      );
      expect(stmt.balance, closeTo(0.0, 0.001));
    });

    test('no positions + zero advance → zero', () {
      expect(_make().balance, 0.0);
    });
  });

  group('StatementStatus', () {
    test('all statuses have labels', () {
      for (final s in StatementStatus.values) {
        expect(s.label, isNotEmpty, reason: 'StatementStatus.$s has no label');
      }
    });

    test('acknowledged label is non-empty', () {
      expect(StatementStatus.acknowledged.label, isNotEmpty);
    });
  });
}
