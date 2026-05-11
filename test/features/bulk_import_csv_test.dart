import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── Mirrors the parsing logic in BulkImportScreen ───────────────────────────

int? _parseFloor(String s) {
  final t = s.trim().toUpperCase();
  if (t == 'EG' || t == '0' || t == 'G') return 0;
  if (t == 'KG' || t == 'UG' || t == '-1') return -1;
  return int.tryParse(t);
}

double? _parseDouble(String s) {
  if (s.trim().isEmpty) return null;
  return double.tryParse(s.trim().replaceAll(',', '.'));
}

List<Map<String, dynamic>> parseUnitsCsv(String content) {
  final rows = const CsvToListConverter(
    fieldDelimiter: ';',
    eol: '\n',
  ).convert(content);
  return rows
      .skip(1)
      .where((r) => r.length >= 3)
      .map((r) => {
            'buildingName': r[0].toString().trim(),
            'buildingAddress': r.length > 1 ? r[1].toString().trim() : '',
            'unitName': r[2].toString().trim(),
            'floor': r.length > 3 ? _parseFloor(r[3].toString()) : null,
            'area': r.length > 4 ? _parseDouble(r[4].toString()) : null,
            'rooms': r.length > 5
                ? int.tryParse(r[5].toString().trim())
                : null,
            'buildYear': r.length > 6
                ? int.tryParse(r[6].toString().trim())
                : null,
          })
      .where((row) =>
          (row['buildingName'] as String).isNotEmpty &&
          (row['unitName'] as String).isNotEmpty)
      .toList();
}

List<Map<String, String>> parseInvitesCsv(String content) {
  final rows = const CsvToListConverter(
    fieldDelimiter: ';',
    eol: '\n',
  ).convert(content);
  return rows
      .skip(1)
      .where((r) => r.isNotEmpty)
      .map((r) {
        final roleStr =
            r.length > 2 ? r[2].toString().trim().toLowerCase() : '';
        return {
          'name': r[0].toString().trim(),
          'email': r.length > 1 ? r[1].toString().trim() : '',
          'role': (roleStr == 'handwerker' || roleStr == 'contractor')
              ? 'contractor'
              : 'tenant_user',
        };
      })
      .where((row) => row['name']!.isNotEmpty)
      .toList();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('parseUnitsCsv — basic', () {
    test('parses header + 2 rows (old 4-column format)', () {
      const csv = 'Gebäude;Adresse;Wohnungsname;Etage\n'
          'Haus A;Hauptstr. 1;Wohnung 1;1\n'
          'Haus A;Hauptstr. 1;Wohnung 2;2';
      final rows = parseUnitsCsv(csv);
      expect(rows.length, 2);
      expect(rows[0]['buildingName'], 'Haus A');
      expect(rows[0]['unitName'], 'Wohnung 1');
      expect(rows[0]['floor'], 1);
      expect(rows[1]['floor'], 2);
    });

    test('skips rows with empty building or unit name', () {
      const csv = 'Gebäude;Adresse;Wohnungsname\n'
          ';Adresse;Wohnung 1\n' // empty building → skip
          'Haus B;Adresse;\n' // empty unit → skip
          'Haus C;Adresse;Wohnung 3';
      final rows = parseUnitsCsv(csv);
      expect(rows.length, 1);
      expect(rows[0]['buildingName'], 'Haus C');
    });

    test('empty CSV → empty list', () {
      expect(parseUnitsCsv('Gebäude;Adresse;Wohnungsname\n'), isEmpty);
    });

    test('trims whitespace from all fields', () {
      const csv = 'Gebäude;Adresse;Wohnungsname\n'
          '  Haus A  ; Adresse ;  Wohnung 1  ';
      final rows = parseUnitsCsv(csv);
      expect(rows[0]['buildingName'], 'Haus A');
      expect(rows[0]['unitName'], 'Wohnung 1');
    });
  });

  group('parseUnitsCsv — extended columns', () {
    test('parses all 7 columns correctly', () {
      const csv =
          'Gebäude;Adresse;Wohnungsname;Etage;Fläche (m²);Zimmer;Baujahr\n'
          'Block A;Hauptstr. 1;App. 01;2;72.5;3;1985';
      final rows = parseUnitsCsv(csv);
      expect(rows.length, 1);
      expect(rows[0]['floor'], 2);
      expect(rows[0]['area'], 72.5);
      expect(rows[0]['rooms'], 3);
      expect(rows[0]['buildYear'], 1985);
    });

    test('accepts German decimal comma for area', () {
      const csv = 'Gebäude;Adresse;Wohnungsname;Etage;Fläche (m²)\n'
          'Haus X;Str. 1;WE 1;1;68,5';
      final rows = parseUnitsCsv(csv);
      expect(rows[0]['area'], 68.5);
    });

    test('EG floor string → 0', () {
      const csv = 'Gebäude;Adresse;Wohnungsname;Etage\n'
          'Haus X;Str. 1;WE EG;EG';
      final rows = parseUnitsCsv(csv);
      expect(rows[0]['floor'], 0);
    });

    test('KG/UG floor string → -1', () {
      const csv = 'Gebäude;Adresse;Wohnungsname;Etage\n'
          'Haus X;Str. 1;Keller;KG';
      final rows = parseUnitsCsv(csv);
      expect(rows[0]['floor'], -1);
    });

    test('empty optional columns → null', () {
      const csv =
          'Gebäude;Adresse;Wohnungsname;Etage;Fläche (m²);Zimmer;Baujahr\n'
          'Haus A;Str. 1;WE 1;;;; ';
      final rows = parseUnitsCsv(csv);
      expect(rows[0]['floor'], null);
      expect(rows[0]['area'], null);
      expect(rows[0]['rooms'], null);
      expect(rows[0]['buildYear'], null);
    });

    test('multiple buildings are all parsed', () {
      const csv = 'Gebäude;Adresse;Wohnungsname\n'
          'Haus A;Str. 1;WE 1\n'
          'Haus A;Str. 1;WE 2\n'
          'Haus B;Str. 2;WE 1\n'
          'Haus B;Str. 2;WE 2\n'
          'Haus B;Str. 2;WE 3';
      final rows = parseUnitsCsv(csv);
      expect(rows.length, 5);
      final buildings = rows.map((r) => r['buildingName']).toSet();
      expect(buildings, {'Haus A', 'Haus B'});
    });

    test('100-row CSV parses without error', () {
      final sb = StringBuffer('Gebäude;Adresse;Wohnungsname;Etage;Fläche\n');
      for (var i = 1; i <= 100; i++) {
        sb.writeln('Block ${(i / 10).ceil()};Str. 1;WE $i;${i % 5};${50 + i}');
      }
      final rows = parseUnitsCsv(sb.toString());
      expect(rows.length, 100);
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

    test('contractor role is case-insensitive', () {
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
