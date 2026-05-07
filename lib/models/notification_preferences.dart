/// Speichert pro User welche Push-Typen er empfangen möchte.
/// Wird als `notificationPreferences`-Map im User-Dokument gespeichert.
/// Fehlende Felder → Default true (opt-out statt opt-in).
class NotificationPreferences {
  const NotificationPreferences({
    this.ticketStatusChanged = true,
    this.ticketAssigned = true,
    this.newComment = true,
    this.newTicket = true,
    this.invoiceSubmitted = true,
    this.maintenanceAlert = true,
    this.statementCreated = true,
  });

  /// Mein Ticket hat den Status gewechselt (Mieter + Handwerker).
  final bool ticketStatusChanged;

  /// Mir wurde ein Ticket zugewiesen (Handwerker).
  final bool ticketAssigned;

  /// Neuer Kommentar auf einem meiner Tickets (alle Rollen).
  final bool newComment;

  /// Neues Ticket eingegangen (Manager).
  final bool newTicket;

  /// Handwerker hat eine Rechnung eingereicht (Manager).
  final bool invoiceSubmitted;

  /// Gerät überfällig / Wartungsalert (Manager).
  final bool maintenanceAlert;

  /// Neue Jahresabrechnung verfügbar (Mieter).
  final bool statementCreated;

  factory NotificationPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NotificationPreferences();
    bool get(String key) => (map[key] as bool?) ?? true;
    return NotificationPreferences(
      ticketStatusChanged: get('ticketStatusChanged'),
      ticketAssigned:      get('ticketAssigned'),
      newComment:          get('newComment'),
      newTicket:           get('newTicket'),
      invoiceSubmitted:    get('invoiceSubmitted'),
      maintenanceAlert:    get('maintenanceAlert'),
      statementCreated:    get('statementCreated'),
    );
  }

  Map<String, dynamic> toMap() => {
        'ticketStatusChanged': ticketStatusChanged,
        'ticketAssigned':      ticketAssigned,
        'newComment':          newComment,
        'newTicket':           newTicket,
        'invoiceSubmitted':    invoiceSubmitted,
        'maintenanceAlert':    maintenanceAlert,
        'statementCreated':    statementCreated,
      };

  NotificationPreferences copyWith({
    bool? ticketStatusChanged,
    bool? ticketAssigned,
    bool? newComment,
    bool? newTicket,
    bool? invoiceSubmitted,
    bool? maintenanceAlert,
    bool? statementCreated,
  }) =>
      NotificationPreferences(
        ticketStatusChanged: ticketStatusChanged ?? this.ticketStatusChanged,
        ticketAssigned:      ticketAssigned      ?? this.ticketAssigned,
        newComment:          newComment          ?? this.newComment,
        newTicket:           newTicket           ?? this.newTicket,
        invoiceSubmitted:    invoiceSubmitted    ?? this.invoiceSubmitted,
        maintenanceAlert:    maintenanceAlert    ?? this.maintenanceAlert,
        statementCreated:    statementCreated    ?? this.statementCreated,
      );
}
