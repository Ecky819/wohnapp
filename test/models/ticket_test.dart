import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/models/ticket.dart';

Ticket _make({
  String status = 'open',
  String category = 'damage',
  String priority = 'normal',
  DateTime? createdAt,
  DateTime? closedAt,
}) => Ticket(
  id: 'test-id',
  title: 'Test',
  description: 'Desc',
  status: status,
  priority: priority,
  tenantId: 'tenant_1',
  createdBy: 'user_1',
  category: category,
  createdAt: createdAt,
  closedAt: closedAt,
);

void main() {
  group('Ticket.statusLabel', () {
    test('open → Offen', () {
      expect(_make(status: 'open').statusLabel, 'Offen');
    });
    test('in_progress → In Bearbeitung', () {
      expect(_make(status: 'in_progress').statusLabel, 'In Bearbeitung');
    });
    test('done → Erledigt', () {
      expect(_make(status: 'done').statusLabel, 'Erledigt');
    });
    test('unknown falls back to raw value', () {
      expect(_make(status: 'custom').statusLabel, 'custom');
    });
  });

  group('Ticket.categoryLabel', () {
    test('damage → Schaden', () {
      expect(_make(category: 'damage').categoryLabel, 'Schaden');
    });
    test('maintenance → Wartung', () {
      expect(_make(category: 'maintenance').categoryLabel, 'Wartung');
    });
  });

  group('Ticket.statusColor', () {
    test('open is orange', () {
      expect(_make(status: 'open').statusColor.toARGB32(),
          equals(Colors.orange.toARGB32()));
    });
    test('in_progress is blue', () {
      expect(_make(status: 'in_progress').statusColor.toARGB32(),
          equals(Colors.blue.toARGB32()));
    });
    test('done is green', () {
      expect(_make(status: 'done').statusColor.toARGB32(),
          equals(Colors.green.toARGB32()));
    });
    test('unknown falls back to grey', () {
      expect(_make(status: 'other').statusColor.toARGB32(),
          equals(Colors.grey.toARGB32()));
    });
  });
}
