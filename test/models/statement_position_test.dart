import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/models/statement_position.dart';

StatementPosition _make({
  double totalCost = 1000.0,
  double tenantPercent = 50.0,
  DistributionKey key = DistributionKey.area,
}) =>
    StatementPosition(
      category: BetriebskostenCategory.wasser,
      label: 'Wasser',
      totalCost: totalCost,
      distributionKey: key,
      tenantPercent: tenantPercent,
      receiptImageUrls: const [],
    );

void main() {
  group('StatementPosition.tenantAmount', () {
    test('50 % of 1000 = 500', () {
      expect(_make(totalCost: 1000, tenantPercent: 50).tenantAmount, 500.0);
    });

    test('100 % of 240 = 240', () {
      expect(_make(totalCost: 240, tenantPercent: 100).tenantAmount, 240.0);
    });

    test('0 % = 0', () {
      expect(_make(totalCost: 500, tenantPercent: 0).tenantAmount, 0.0);
    });

    test('33.33 % of 900 ≈ 300', () {
      final amount = _make(totalCost: 900, tenantPercent: 33.33).tenantAmount;
      expect(amount, closeTo(299.97, 0.01));
    });

    test('zero total cost → 0', () {
      expect(_make(totalCost: 0, tenantPercent: 50).tenantAmount, 0.0);
    });
  });

  group('StatementPosition.distributionKey label', () {
    test('area label is not empty', () {
      expect(DistributionKey.area.label, isNotEmpty);
    });
    test('persons label is not empty', () {
      expect(DistributionKey.persons.label, isNotEmpty);
    });
    test('all keys have labels', () {
      for (final key in DistributionKey.values) {
        expect(key.label, isNotEmpty,
            reason: 'DistributionKey.$key has no label');
      }
    });
  });

  group('BetriebskostenCategory', () {
    test('all categories have labels', () {
      for (final cat in BetriebskostenCategory.values) {
        expect(cat.label, isNotEmpty,
            reason: 'BetriebskostenCategory.$cat has no label');
      }
    });
  });
}
