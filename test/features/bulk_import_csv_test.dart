import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

// Pure CSV parsing logic extracted for testing (mirrors BulkImportScreen parsing)
List<Map<String, String>> parseUnitsCsv(String content) {
  final rows = const CsvToListConverter(
    fieldDelimiter: ';',
    eol: '\n',
  ).convert(content);
  return rows.skip(1).where((r) => r.length >= 3).map((r) {
    return {
      'buildingName': r[0].toString().trim(),
      'buildingAddress': r.length > 1 ? r[1].toString().trim() : '',
      'unitName': r[2].toString().trim(),
      'floor': r.length > 3 ? r[3].toString().trim() : '',
    };
  }).where((row) => row['buildingName']!.isNotEmpty && row['unitName']!.isNotEmpty).toList();
}

List<Map<String, String>> parseInvitesCsv(String content) {
  final rows = const CsvToListConverter(
    fieldDelimiter: ';',
    eol: '\n',
  ).convert(content);
  return rows.skip(1).where((r) => r.isNotEmpty).map((r) {
    final roleStr = r.length > 2 ? r[2].toString().trim().toLowerCase() : '';
    return {
      'name': r[0].toString().trim(),
      'email': r.length > 1 ? r[1].toString().trim() : '',
      'role': (roleStr == 'handwerker' || roleStr == 'contractor')
          ? 'contractor'
          : 'tenant_user',
    };
  }).where((row) => row['name']!.isNotEmpty).toList();
}

void main() {
  group('parseUnitsCsv', () {
    test('parses header + 2 data rows', () {
      const csv = 'Gebäude;Adresse;Wohnungsname;Etage\n'
          'Haus A;Hauptstr. 1;Wohnung 1;1\n'
          'Haus A;Hauptstr. 1;Wohnung 2;2';
      final rows = parseUnitsCsv(csv);
      expect(rows.length, 2);
      expect(rows[0]['buildingName'], 'Haus A');
      expect(rows[0]['unitName'], 'Wohnung 1');
      expect(rows[0]['floor'], '1');
      expect(rows[1]['unitName'], 'Wohnung 2');
    });

    test('skips rows with empty building or unit name', () {
      const csv = 'Gebäude;Adresse;Wohnungsname\n'
          ';Adresse;Wohnung 1\n'       // empty building → skip
          'Haus B;Adresse;\n'          // empty unit → skip
          'Haus C;Adresse;Wohnung 3';
      final rows = parseUnitsCsv(csv);
      expect(rows.length, 1);
      expect(rows[0]['buildingName'], 'Haus C');
    });

    test('empty CSV → empty list', () {
      expect(parseUnitsCsv('Gebäude;Adresse;Wohnungsname\n'), isEmpty);
    });

    test('trims whitespace from fields', () {
      const csv = 'Gebäude;Adresse;Wohnungsname\n'
          '  Haus A  ; Adresse ;  Wohnung 1  ';
      final rows = parseUnitsCsv(csv);
      expect(rows[0]['buildingName'], 'Haus A');
      expect(rows[0]['unitName'], 'Wohnung 1');
    });
  });

  group('parseInvitesCsv', () {
    test('parses Mieter and Handwerker roles', () {
      const csv = 'Name;E-Mail;Rolle\n'
          'Max Mustermann;max@example.com;Mieter\n'
          'Hans Handwerker;hans@example.com;Handwerker';
      final rows = parseInvitesCsv(csv);
      expect(rows.length, 2);
      expect(rows[0]['role'], 'tenant_user');
      expect(rows[1]['role'], 'contractor');
    });

    test('defaults to tenant_user for unknown role', () {
      const csv = 'Name;E-Mail;Rolle\nJohn;j@example.com;Sonstige';
      final rows = parseInvitesCsv(csv);
      expect(rows[0]['role'], 'tenant_user');
    });

    test('contractor role case-insensitive', () {
      const csv = 'Name;E-Mail;Rolle\nFred;f@e.com;CONTRACTOR';
      final rows = parseInvitesCsv(csv);
      expect(rows[0]['role'], 'contractor');
    });

    test('skips rows with empty name', () {
      const csv = 'Name;E-Mail;Rolle\n;x@x.com;Mieter\nBerta;b@b.com;Mieter';
      final rows = parseInvitesCsv(csv);
      expect(rows.length, 1);
      expect(rows[0]['name'], 'Berta');
    });
  });
}
