import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/utils/app_exception.dart';

FirebaseException _fe(String code) =>
    FirebaseException(plugin: 'firestore', code: code);

void main() {
  // ─── AppException.fromFirestore ───────────────────────────────────────────

  group('AppException.fromFirestore', () {
    test('permission-denied', () {
      final ex = AppException.fromFirestore(_fe('permission-denied'));
      expect(ex.message, contains('Berechtigung'));
    });

    test('unavailable', () {
      final ex = AppException.fromFirestore(_fe('unavailable'));
      expect(ex.message, contains('Server nicht erreichbar'));
    });

    test('not-found', () {
      final ex = AppException.fromFirestore(_fe('not-found'));
      expect(ex.message, contains('nicht gefunden'));
    });

    test('already-exists', () {
      final ex = AppException.fromFirestore(_fe('already-exists'));
      expect(ex.message, contains('existiert bereits'));
    });

    test('resource-exhausted', () {
      final ex = AppException.fromFirestore(_fe('resource-exhausted'));
      expect(ex.message, contains('Zu viele'));
    });

    test('unauthenticated', () {
      final ex = AppException.fromFirestore(_fe('unauthenticated'));
      expect(ex.message, contains('Sitzung abgelaufen'));
    });

    test('unknown code includes code in message', () {
      final ex = AppException.fromFirestore(_fe('some-unknown-code'));
      expect(ex.message, contains('some-unknown-code'));
    });
  });

  // ─── AppException.fromStorage ─────────────────────────────────────────────

  group('AppException.fromStorage', () {
    FirebaseException stEx(String code) =>
        FirebaseException(plugin: 'firebase_storage', code: code);

    test('object-not-found', () {
      final ex = AppException.fromStorage(stEx('object-not-found'));
      expect(ex.message, contains('nicht gefunden'));
    });

    test('unauthorized', () {
      final ex = AppException.fromStorage(stEx('unauthorized'));
      expect(ex.message, contains('Zugriff'));
    });

    test('canceled', () {
      final ex = AppException.fromStorage(stEx('canceled'));
      expect(ex.message, contains('abgebrochen'));
    });

    test('unknown code includes code', () {
      final ex = AppException.fromStorage(stEx('quota-exceeded'));
      expect(ex.message, contains('quota-exceeded'));
    });
  });

  // ─── ConflictException ────────────────────────────────────────────────────

  group('ConflictException', () {
    test('is a subtype of AppException', () {
      expect(const ConflictException(), isA<AppException>());
    });

    test('message mentions änder', () {
      expect(
        const ConflictException().message,
        contains('geändert'),
      );
    });

    test('toString equals message', () {
      const ex = ConflictException();
      expect(ex.toString(), ex.message);
    });
  });

  // ─── RateLimitException ───────────────────────────────────────────────────

  group('RateLimitException', () {
    test('is a subtype of AppException', () {
      expect(const RateLimitException(), isA<AppException>());
    });

    test('message is non-empty', () {
      expect(const RateLimitException().message, isNotEmpty);
    });
  });
}
