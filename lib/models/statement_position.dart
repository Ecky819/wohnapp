enum DistributionKey { area, persons, consumption, equal, custom }

extension DistributionKeyX on DistributionKey {
  String get label {
    switch (this) {
      case DistributionKey.area:
        return 'nach Fläche';
      case DistributionKey.persons:
        return 'nach Personen';
      case DistributionKey.consumption:
        return 'nach Verbrauch';
      case DistributionKey.equal:
        return 'zu gleichen Teilen';
      case DistributionKey.custom:
        return 'individuell (%)';
    }
  }
}

/// Standard Betriebskosten-Kategorien (§ 2 BetrKV)
enum BetriebskostenCategory {
  grundsteuer,
  wasser,
  abwasser,
  aufzug,
  strassenreinigung,
  muell,
  gebaeudereinigung,
  gartenpflege,
  beleuchtung,
  schornstein,
  versicherung,
  hauswart,
  antenne,
  heizung,
  warmwasser,
  sonstiges,
}

extension BetriebskostenCategoryX on BetriebskostenCategory {
  String get label {
    switch (this) {
      case BetriebskostenCategory.grundsteuer:
        return 'Grundsteuer';
      case BetriebskostenCategory.wasser:
        return 'Wasserversorgung';
      case BetriebskostenCategory.abwasser:
        return 'Abwasserentsorgung';
      case BetriebskostenCategory.aufzug:
        return 'Fahrstuhl / Aufzug';
      case BetriebskostenCategory.strassenreinigung:
        return 'Straßenreinigung';
      case BetriebskostenCategory.muell:
        return 'Müllbeseitigung';
      case BetriebskostenCategory.gebaeudereinigung:
        return 'Gebäudereinigung';
      case BetriebskostenCategory.gartenpflege:
        return 'Gartenpflege';
      case BetriebskostenCategory.beleuchtung:
        return 'Beleuchtung';
      case BetriebskostenCategory.schornstein:
        return 'Schornsteinreinigung';
      case BetriebskostenCategory.versicherung:
        return 'Versicherungen';
      case BetriebskostenCategory.hauswart:
        return 'Hausmeister / Hauswart';
      case BetriebskostenCategory.antenne:
        return 'Gemeinschaftsantenne / Kabel';
      case BetriebskostenCategory.heizung:
        return 'Heizung';
      case BetriebskostenCategory.warmwasser:
        return 'Warmwasser';
      case BetriebskostenCategory.sonstiges:
        return 'Sonstige Betriebskosten';
    }
  }

  static BetriebskostenCategory fromString(String s) {
    return BetriebskostenCategory.values.firstWhere(
      (e) => e.name == s,
      orElse: () => BetriebskostenCategory.sonstiges,
    );
  }
}

class StatementPosition {
  const StatementPosition({
    required this.category,
    required this.label,
    required this.totalCost,
    required this.distributionKey,
    required this.tenantPercent,
    this.receiptImageUrls = const [],
  });

  final BetriebskostenCategory category;
  final String label;           // custom or category.label
  final double totalCost;
  final DistributionKey distributionKey;
  final double tenantPercent;   // 0–100
  final List<String> receiptImageUrls;

  double get tenantAmount => totalCost * tenantPercent / 100;

  Map<String, dynamic> toMap() => {
        'category': category.name,
        'label': label,
        'totalCost': totalCost,
        'distributionKey': distributionKey.name,
        'tenantPercent': tenantPercent,
        'receiptImageUrls': receiptImageUrls,
      };

  factory StatementPosition.fromMap(Map<String, dynamic> m) =>
      StatementPosition(
        category: BetriebskostenCategoryX.fromString(
            m['category'] as String? ?? 'sonstiges'),
        label: m['label'] as String? ?? '',
        totalCost: (m['totalCost'] as num?)?.toDouble() ?? 0.0,
        distributionKey: DistributionKey.values.firstWhere(
          (e) => e.name == (m['distributionKey'] as String?),
          orElse: () => DistributionKey.equal,
        ),
        tenantPercent: (m['tenantPercent'] as num?)?.toDouble() ?? 0.0,
        receiptImageUrls: (m['receiptImageUrls'] as List<dynamic>?)
                ?.cast<String>() ??
            [],
      );

  StatementPosition copyWith({List<String>? receiptImageUrls}) =>
      StatementPosition(
        category: category,
        label: label,
        totalCost: totalCost,
        distributionKey: distributionKey,
        tenantPercent: tenantPercent,
        receiptImageUrls: receiptImageUrls ?? this.receiptImageUrls,
      );
}
