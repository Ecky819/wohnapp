import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Wird geworfen wenn ein User zu viele Aktionen in kurzer Zeit durchführt.
class RateLimitException extends AppException {
  const RateLimitException()
      : super('Bitte kurz warten – zu viele Aktionen in kurzer Zeit.');
}

/// Wird geworfen wenn zwei User gleichzeitig dasselbe Dokument bearbeiten.
class ConflictException extends AppException {
  const ConflictException()
      : super(
            'Dieses Dokument wurde von jemand anderem geändert. '
            'Bitte Seite aktualisieren und erneut versuchen.');
}

/// Anwendungsweite Exception mit deutschsprachiger Nutzermeldung.
class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;

  /// Wandelt eine [FirebaseException] in eine [AppException] um.
  factory AppException.fromFirestore(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return const AppException(
            'Keine Berechtigung. Bitte erneut anmelden.');
      case 'unavailable':
        return const AppException(
            'Server nicht erreichbar. Bitte Verbindung prüfen.');
      case 'not-found':
        return const AppException('Dokument nicht gefunden.');
      case 'already-exists':
        return const AppException('Eintrag existiert bereits.');
      case 'resource-exhausted':
        return const AppException(
            'Zu viele Anfragen. Bitte kurz warten.');
      case 'unauthenticated':
        return const AppException('Sitzung abgelaufen. Bitte neu anmelden.');
      default:
        return AppException('Fehler beim Speichern (${e.code}).');
    }
  }

  /// Wandelt eine [FirebaseException] aus Storage um.
  factory AppException.fromStorage(FirebaseException e) {
    switch (e.code) {
      case 'object-not-found':
        return const AppException('Datei nicht gefunden.');
      case 'unauthorized':
        return const AppException(
            'Kein Zugriff auf diese Datei.');
      case 'canceled':
        return const AppException('Upload abgebrochen.');
      default:
        return AppException('Upload fehlgeschlagen (${e.code}).');
    }
  }
}
