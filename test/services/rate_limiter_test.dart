import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/services/rate_limiter.dart';
import 'package:wohnapp/utils/app_exception.dart';

void main() {
  // Use a fresh instance per test group to avoid cross-test state leakage.
  late RateLimiter limiter;

  setUp(() => limiter = RateLimiter.instance..reset('test_key'));

  group('RateLimiter.isThrottled', () {
    test('returns false before first call', () {
      expect(limiter.isThrottled('new_key'), isFalse);
    });

    test('returns false after reset', () {
      limiter.checkOrThrow('test_key');
      limiter.reset('test_key');
      expect(limiter.isThrottled('test_key'), isFalse);
    });

    test('returns true immediately after checkOrThrow', () {
      limiter.checkOrThrow('test_key');
      expect(limiter.isThrottled('test_key'), isTrue);
    });

    test('different keys are independent', () {
      limiter.checkOrThrow('key_a');
      expect(limiter.isThrottled('key_b'), isFalse);
    });
  });

  group('RateLimiter.checkOrThrow', () {
    test('first call succeeds', () {
      expect(() => limiter.checkOrThrow('test_key'), returnsNormally);
    });

    test('second immediate call throws RateLimitException', () {
      limiter.checkOrThrow('test_key');
      expect(
        () => limiter.checkOrThrow('test_key'),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('zero-duration cooldown never throttles', () {
      limiter.checkOrThrow('test_key', cooldown: Duration.zero);
      expect(
        () => limiter.checkOrThrow('test_key', cooldown: Duration.zero),
        returnsNormally,
      );
    });
  });
}
