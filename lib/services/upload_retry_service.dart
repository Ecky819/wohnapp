import 'dart:math';

/// Thrown when all retry attempts for an upload have been exhausted.
class UploadException implements Exception {
  const UploadException({required this.cause, required this.attempts});
  final Object cause;
  final int attempts;

  @override
  String toString() =>
      'Upload fehlgeschlagen nach $attempts Versuchen: $cause';
}

/// Retries [operation] up to [maxAttempts] times with exponential back-off.
/// Throws [UploadException] if all attempts fail.
Future<T> withRetry<T>(
  Future<T> Function() operation, {
  int maxAttempts = 3,
  Duration baseDelay = const Duration(seconds: 2),
}) async {
  int attempt = 0;
  Object? lastError;
  while (attempt < maxAttempts) {
    try {
      return await operation();
    } catch (e) {
      lastError = e;
      attempt++;
      if (attempt >= maxAttempts) break;
      final delay = baseDelay * pow(2, attempt - 1).toInt();
      await Future<void>.delayed(delay);
    }
  }
  throw UploadException(cause: lastError ?? 'Unbekannter Fehler', attempts: maxAttempts);
}
