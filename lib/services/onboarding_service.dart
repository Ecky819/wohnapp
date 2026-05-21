import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which first-time hints the user has already seen.
/// Backed by SharedPreferences so state survives app restarts.
class OnboardingService {
  OnboardingService._();
  static final instance = OnboardingService._();

  static const _prefix = 'onboarding_seen_';

  Future<bool> hasSeen(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$key') ?? false;
  }

  Future<void> markSeen(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key', true);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(k);
    }
  }
}

/// Hint key constants — prevents typos at usage sites.
abstract final class OnboardingKeys {
  static const managerCreateTicketFab = 'manager_create_ticket_fab';
  static const tenantsCreateFab       = 'tenants_create_fab';
  static const managerDrawer          = 'manager_drawer';
}
