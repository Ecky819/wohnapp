import '../models/app_user.dart';
import '../models/ticket.dart';

/// Maps routing category keys to German display labels and icons.
const routingCategories = <String, String>{
  'plumbing': 'Sanitär',
  'electrical': 'Elektro',
  'heating': 'Heizung',
  'general': 'Allgemein',
};

class RoutingService {
  /// German keywords per trade category.
  static const _keywords = <String, List<String>>{
    'plumbing': [
      'wasser', 'rohr', 'sanitär', 'dusche', 'toilette', 'wc', 'klo',
      'waschbecken', 'leck', 'tropft', 'tropfen', 'abfluss', 'verstopft',
      'spüle', 'wasserhahn', 'hahn', 'dichtung', 'undicht', 'feuchtigkeit',
    ],
    'electrical': [
      'strom', 'elektro', 'elektrisch', 'schalter', 'steckdose', 'sicherung',
      'lampe', 'licht', 'leuchte', 'kabel', 'kurzschluss', 'spannung',
      'zähler', 'sicherungskasten', 'verteiler', 'ausfall', 'flackert',
    ],
    'heating': [
      'heizung', 'heizkörper', 'heizkessel', 'wärme', 'temperatur',
      'kalt', 'heizt nicht', 'thermostat', 'ventil', 'pumpe', 'boiler',
      'warmwasser', 'fernwärme', 'gas', 'ölheizung',
    ],
    'general': [
      'tür', 'türe', 'fenster', 'schloss', 'schlüssel', 'wand', 'boden',
      'decke', 'farbe', 'schimmel', 'riss', 'putz', 'fliese', 'treppe',
      'aufzug', 'fahrstuhl', 'briefkasten', 'keller', 'dach',
    ],
  };

  /// Returns the best-matching routing category key for a given ticket.
  /// Falls back to 'general' if nothing matches.
  static String detectCategory(String title, String description) {
    final text = '${title.toLowerCase()} ${description.toLowerCase()}';
    final scores = <String, int>{};

    for (final entry in _keywords.entries) {
      scores[entry.key] =
          entry.value.where((kw) => text.contains(kw)).length;
    }

    final best =
        scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value > 0 ? best.key : 'general';
  }

  /// Ranks contractors for the given [category], ordered by:
  /// 1. Has matching specialization (or no specializations = all-rounder)
  /// 2. Lowest active ticket count (workload balancing)
  static List<RankedContractor> rankContractors({
    required String category,
    required List<AppUser> contractors,
    required List<Ticket> allTickets,
  }) {
    // Build workload map: active (non-done) tickets per contractor
    final workload = <String, int>{};
    for (final t in allTickets) {
      if (t.assignedTo != null && t.status != 'done') {
        workload[t.assignedTo!] = (workload[t.assignedTo!] ?? 0) + 1;
      }
    }

    final ranked = contractors.map((c) {
      final isSpecialist = c.specializations.isEmpty ||
          c.specializations.contains(category);
      final active = workload[c.uid] ?? 0;
      return RankedContractor(
        user: c,
        isSpecialist: isSpecialist,
        activeTickets: active,
      );
    }).toList();

    ranked.sort((a, b) {
      // Specialists first
      if (a.isSpecialist != b.isSpecialist) {
        return a.isSpecialist ? -1 : 1;
      }
      // Then by workload ascending
      return a.activeTickets.compareTo(b.activeTickets);
    });

    return ranked;
  }
}

class RankedContractor {
  const RankedContractor({
    required this.user,
    required this.isSpecialist,
    required this.activeTickets,
  });

  final AppUser user;
  final bool isSpecialist;
  final int activeTickets;
}
