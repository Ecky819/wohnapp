import '../utils/app_exception.dart';

/// Client-side rate limiter using in-memory timestamps.
///
/// Resets on app restart, which is acceptable for an MVP.
/// For server-side enforcement use Cloud Functions with a token-bucket approach.
class RateLimiter {
  RateLimiter._();
  static final RateLimiter instance = RateLimiter._();

  final _lastCall = <String, DateTime>{};

  /// Returns true if the action for [key] is within [cooldown] of the last call.
  bool isThrottled(String key, {Duration cooldown = const Duration(seconds: 5)}) {
    final last = _lastCall[key];
    return last != null && DateTime.now().difference(last) < cooldown;
  }

  /// Records a call for [key] and throws [RateLimitException] if throttled.
  void checkOrThrow(String key, {Duration cooldown = const Duration(seconds: 5)}) {
    if (isThrottled(key, cooldown: cooldown)) throw const RateLimitException();
    _lastCall[key] = DateTime.now();
  }

  /// Resets the cooldown for [key] (call after a failed attempt so the user can retry immediately).
  void reset(String key) => _lastCall.remove(key);
}
