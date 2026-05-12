import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'repositories/tenant_repository.dart';
import 'router.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('de_DE');

  // Enable Firestore offline persistence (disk cache, unlimited size)
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firestore settings error (non-fatal): $e');
  }

  // Init notifications in the background — requestPermission can hang on
  // simulators where APNS is unavailable; the app must not block on it.
  NotificationService.instance.init().catchError(
    (e) => debugPrint('NotificationService init error (non-fatal): $e'),
  );

  runApp(const ProviderScope(child: MyApp()));
}

// ─── Connectivity provider ────────────────────────────────────────────────────

final _connectivityProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

// ─── App ──────────────────────────────────────────────────────────────────────

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  StreamSubscription<String>? _navSub;

  @override
  void initState() {
    super.initState();
    _navSub = NotificationService.onNavigateTo.listen((path) {
      ref.read(routerProvider).go(path);
    });
  }

  @override
  void dispose() {
    _navSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final tenant = ref.watch(tenantProvider).valueOrNull;
    final primary = tenant?.primaryColor ?? Colors.indigo;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: _buildTheme(primary, Brightness.light),
      darkTheme: _buildTheme(primary, Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => _OfflineBannerWrapper(child: child!),
    );
  }

  /// Builds a Material 3 theme that uses the tenant's exact primary color
  /// for filled buttons, FABs and AppBar.
  /// For outlined/text buttons the color is auto-darkened to WCAG 4.5:1
  /// contrast so light brand colors remain readable on light surfaces.
  static ThemeData _buildTheme(Color primary, Brightness brightness) {
    final seedScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    );

    final scheme = seedScheme.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      secondaryContainer: primary,
      onSecondaryContainer: _onColor(primary),
    );

    // Outlined / text buttons show the primary as text color.
    // Darken it until it passes WCAG AA contrast against the surface.
    final textFg = _wcagReadable(primary, seedScheme.surface);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: textFg),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: textFg),
      ),
    );
  }

  /// Returns white for dark backgrounds, black for light (WCAG contrast).
  static Color _onColor(Color bg) =>
      bg.computeLuminance() < 0.35 ? Colors.white : Colors.black;

  /// Darkens [color] in steps until it achieves ≥4.5:1 contrast against
  /// [surface]. Falls back to [surface]'s on-color if no adjustment works.
  static Color _wcagReadable(Color color, Color surface) {
    final surfLum = surface.computeLuminance();
    Color c = color;
    for (var i = 0; i < 25; i++) {
      final fgLum = c.computeLuminance();
      final contrast = surfLum > fgLum
          ? (surfLum + 0.05) / (fgLum + 0.05)
          : (fgLum + 0.05) / (surfLum + 0.05);
      if (contrast >= 4.5) return c;
      // Darken by 8% per step
      c = Color.fromARGB(
        (c.a * 255.0).round().clamp(0, 255),
        (c.r * 255.0 * 0.92).round().clamp(0, 255),
        (c.g * 255.0 * 0.92).round().clamp(0, 255),
        (c.b * 255.0 * 0.92).round().clamp(0, 255),
      );
    }
    // Fallback: use black or white depending on surface brightness
    return _onColor(surface);
  }
}

// ─── Offline banner ───────────────────────────────────────────────────────────

class _OfflineBannerWrapper extends ConsumerWidget {
  const _OfflineBannerWrapper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(_connectivityProvider).valueOrNull;
    final isOffline = connectivity != null &&
        !connectivity.contains(ConnectivityResult.wifi) &&
        !connectivity.contains(ConnectivityResult.mobile) &&
        !connectivity.contains(ConnectivityResult.ethernet);

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: isOffline ? 32 : 0,
          color: Colors.orange.shade800,
          child: isOffline
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Keine Internetverbindung – Offline-Modus',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        Expanded(child: child),
      ],
    );
  }
}
