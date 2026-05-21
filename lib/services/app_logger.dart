import 'package:flutter/foundation.dart';

/// Zentraler Logger. In Debug-Mode: farbige Konsolenausgabe.
/// In Release-Mode: hier können Sentry / Firebase Crashlytics angebunden werden.
class AppLogger {
  AppLogger._();

  static void info(String message, {String? tag}) =>
      _log('INFO', message, tag: tag);

  static void warning(String message, {String? tag}) =>
      _log('WARN', message, tag: tag);

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    _log('ERROR', message, tag: tag);
    if (error != null) _log('ERROR', error.toString(), tag: tag);
    if (kDebugMode && stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
    // Hier Crashlytics/Sentry-Aufruf ergänzen, sobald konfiguriert:
    // FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }

  static void _log(String level, String message, {String? tag}) {
    if (!kDebugMode) return;
    final prefix = tag != null ? '[$tag]' : '';
    debugPrint('[$level]$prefix $message');
  }
}
