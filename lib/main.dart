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
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await NotificationService.instance.init();
  runApp(const ProviderScope(child: MyApp()));
}

// ─── Connectivity provider ────────────────────────────────────────────────────

final _connectivityProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

// ─── App ──────────────────────────────────────────────────────────────────────

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final tenant = ref.watch(tenantProvider).valueOrNull;
    final seedColor = tenant?.primaryColor ?? Colors.indigo;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(colorSchemeSeed: seedColor, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seedColor,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      builder: (context, child) => _OfflineBannerWrapper(child: child!),
    );
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
