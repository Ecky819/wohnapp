import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/analytics/analytics_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/tenants/tenants_screen.dart';
import 'features/dashboard/contractor_home_screen.dart';
import 'features/dashboard/manager_home_screen.dart';
import 'features/dashboard/tenant_home_screen.dart';
import 'features/digital_twin/buildings_screen.dart';
import 'features/digital_twin/unit_detail_screen.dart';
import 'features/invitations/invitations_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/reporting/export_screen.dart';
import 'features/tickets/create_ticket_screen.dart';
import 'features/tickets/ticket_detail_screen.dart';
import 'features/tickets/ticket_list_screen.dart';
import 'login_screen.dart';
import 'models/app_user.dart';
import 'user_provider.dart';

// ─── Route names ─────────────────────────────────────────────────────────────

abstract class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const tenant = '/tenant';
  static const createTicket = 'create-ticket'; // sub-route
  static const myTickets = 'tickets';           // sub-route
  static const manager = '/manager';
  static const invitations = 'invitations';      // sub-route of /manager
  static const managerCreateTicket = 'create-ticket'; // sub-route of /manager
  static const analytics = '/analytics';
  static const buildings = '/buildings';
  static const unitDetail = '/unit/:id';
  static const contractor = '/contractor';
  static const profile = '/profile';
  static const ticketDetail = '/ticket/:id';
  static const calendar = '/calendar';
  static const export = '/export';
  static const tenants = '/tenants';

  static String ticketDetailPath(String id) => '/ticket/$id';
  static String unitDetailPath(String id) => '/unit/$id';
}

// ─── Router notifier (bridges Riverpod → GoRouter refreshListenable) ─────────

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    // Rebuild GoRouter whenever currentUserProvider changes
    _ref.listen<AsyncValue<AppUser?>>(
      currentUserProvider,
      (_, __) => notifyListeners(),
    );
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    final loc = state.matchedLocation;
    final onLogin = loc == AppRoutes.login;
    final onRegister = loc == AppRoutes.register;

    // Both login and register are public routes
    if (!isLoggedIn) return (onLogin || onRegister) ? null : AppRoutes.login;

    // Still loading — don't redirect yet
    final userAsync = _ref.read(currentUserProvider);
    return userAsync.whenOrNull(
      data: (user) {
        if (user == null) return null;
        if (onLogin || onRegister) return _homeForRole(user.role);
        return null;
      },
    );
  }

  static String _homeForRole(String role) {
    switch (role) {
      case 'manager':
        return AppRoutes.manager;
      case 'contractor':
        return AppRoutes.contractor;
      default:
        return AppRoutes.tenant;
    }
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    refreshListenable: notifier,
    initialLocation: AppRoutes.login,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, state) => RegisterScreen(
          prefillCode: state.uri.queryParameters['code'],
        ),
      ),
      GoRoute(
        path: AppRoutes.tenant,
        builder: (_, __) => const TenantHomeScreen(),
        routes: [
          GoRoute(
            path: AppRoutes.createTicket,
            builder: (_, __) => const CreateTicketScreen(),
          ),
          GoRoute(
            path: AppRoutes.myTickets,
            builder: (_, __) => const TicketListScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.manager,
        builder: (_, __) => const ManagerHomeScreen(),
        routes: [
          GoRoute(
            path: 'invitations',
            builder: (_, __) => const InvitationsScreen(),
          ),
          GoRoute(
            path: 'create-ticket',
            builder: (_, __) => const CreateTicketScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.analytics,
        builder: (_, __) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: AppRoutes.buildings,
        builder: (_, __) => const BuildingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.unitDetail,
        builder: (_, state) =>
            UnitDetailScreen(unitId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.contractor,
        builder: (_, __) => const ContractorHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.ticketDetail,
        builder: (_, state) => TicketDetailScreen(
          ticketId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (_, __) => const CalendarScreen(),
      ),
      GoRoute(
        path: AppRoutes.export,
        builder: (_, __) => const ExportScreen(),
      ),
      GoRoute(
        path: AppRoutes.tenants,
        builder: (_, __) => const TenantsScreen(),
      ),
    ],
  );
});
