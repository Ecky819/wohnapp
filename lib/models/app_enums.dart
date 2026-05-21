import 'package:flutter/material.dart' show Color, Colors;

// ─── Ticket-Status ────────────────────────────────────────────────────────────

enum TicketStatus {
  open('open', 'Offen'),
  inProgress('in_progress', 'In Bearbeitung'),
  done('done', 'Erledigt');

  const TicketStatus(this.value, this.label);

  /// Firestore-String-Wert (unveränderlich, DB-kompatibel).
  final String value;
  final String label;

  factory TicketStatus.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => open);

  Color get color => switch (this) {
        TicketStatus.open => Colors.orange,
        TicketStatus.inProgress => Colors.blue,
        TicketStatus.done => Colors.green,
      };
}

// ─── Nutzer-Rollen ────────────────────────────────────────────────────────────

enum UserRole {
  manager('manager', 'Verwaltung'),
  contractor('contractor', 'Handwerker'),
  tenantUser('tenant_user', 'Mieter');

  const UserRole(this.value, this.label);

  final String value;
  final String label;

  factory UserRole.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => tenantUser);
}

// ─── Mietverhältnis-Status ────────────────────────────────────────────────────

enum AgreementStatus {
  active('active', 'Aktiv'),
  noticeGiven('notice_given', 'Kündigung'),
  ended('ended', 'Beendet');

  const AgreementStatus(this.value, this.label);

  final String value;
  final String label;

  factory AgreementStatus.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => active);

  Color get color => switch (this) {
        AgreementStatus.active => Colors.green,
        AgreementStatus.noticeGiven => Colors.orange,
        AgreementStatus.ended => Colors.grey,
      };
}

// ─── Ticket-Kategorie ─────────────────────────────────────────────────────────

enum TicketCategory {
  damage('damage', 'Schaden'),
  maintenance('maintenance', 'Wartung'),
  insuranceClaim('insurance_claim', 'Versicherungsfall');

  const TicketCategory(this.value, this.label);

  final String value;
  final String label;

  factory TicketCategory.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => damage);
}

// ─── Ticket-Priorität ─────────────────────────────────────────────────────────

enum TicketPriority {
  low('low', 'Niedrig'),
  normal('normal', 'Normal'),
  high('high', 'Hoch'),
  urgent('urgent', 'Dringend');

  const TicketPriority(this.value, this.label);

  final String value;
  final String label;

  factory TicketPriority.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => normal);
}
