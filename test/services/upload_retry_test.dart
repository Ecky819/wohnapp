import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/services/upload_retry_service.dart';

void main() {
  group('withRetry', () {
    test('returns value immediately on first success', () async {
      final result = await withRetry(() async => 42);
      expect(result, 42);
    });

    test('retries on failure and eventually succeeds', () async {
      int attempts = 0;
      final result = await withRetry(
        () async {
          attempts++;
          if (attempts < 3) throw Exception('transient error');
          return 'ok';
        },
        maxAttempts: 3,
        baseDelay: Duration.zero,
      );
      expect(result, 'ok');
      expect(attempts, 3);
    });

    test('throws after maxAttempts exhausted', () async {
      int attempts = 0;
      expect(
        () => withRetry(
          () async {
            attempts++;
            throw Exception('permanent error');
          },
          maxAttempts: 2,
          baseDelay: Duration.zero,
        ),
        throwsException,
      );
      // Give the future time to complete
      await Future<void>.delayed(Duration.zero);
      expect(attempts, greaterThanOrEqualTo(1));
    });

    test('respects maxAttempts = 1 (no retry)', () async {
      int attempts = 0;
      try {
        await withRetry(
          () async {
            attempts++;
            throw Exception('fail');
          },
          maxAttempts: 1,
          baseDelay: Duration.zero,
        );
      } catch (_) {}
      expect(attempts, 1);
    });
  });
}
