import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/analytics/analytics_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/tenants/create_rental_agreement_screen.dart';
import 'features/tenants/rental_agreement_detail_screen.dart';
import 'features/tenants/tenants_screen.dart';
import 'features/dashboard/contractor_home_screen.dart';
import 'features/dashboard/manager_home_screen.dart';
import 'features/dashboard/tenant_home_screen.dart';
import 'features/digital_twin/buildings_screen.dart';
import 'features/digital_twin/unit_detail_screen.dart';
import 'features/invitations/invitations_screen.dart';
import 'features/invoices/invoice_detail_screen.dart';
import 'features/tickets/guest_report_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/settings/bulk_import_screen.dart';
import 'features/settings/tenant_settings_screen.dart';
import 'features/statements/manager_statements_screen.dart';
import 'features/statements/create_statement_screen.dart';
import 'features/statements/tenant_statements_screen.dart';
import 'features/energy/energy_screen.dart';
import 'features/reporting/export_screen.dart';
import 'features/tickets/create_ticket_screen.dart';
import 'features/tickets/insurance_claim_screen.dart';
import 'features/tickets/ticket_detail_screen.dart';
import 'features/tickets/ticket_list_screen.dart';
import 'login_screen.dart';
import 'models/app_user.dart';
import 'models/tenant.dart';
import 'repositories/tenant_repository.dart';
import 'user_provider.dart';

// ─── Route names ─────────────────────────────────────────────────────────────

abstract class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const onboarding = '/onboarding';
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
  static const insuranceClaim = '/ticket/:id/insurance-claim';
  static const calendar = '/calendar';
  static const export = '/export';
  static const tenants = '/tenants';
  static const invoiceDetail = '/invoice/:id';
  static const guestReport = '/guest-report';
  static const tenantSettings = '/tenant-settings';
  static const bulkImport = '/bulk-import';
  static const statements = '/statements';
  static const createStatement = '/statements/create';
  static const tenantStatements = '/my-statements';
  static const energy = '/energy';
  static const createRentalAgreement = '/rental-agreement/create';
  static const rentalAgreementDetail = '/rental-agreement/:id';

  static String ticketDetailPath(String id) => '/ticket/$id';
  static String unitDetailPath(String id) => '/unit/$id';
  static String invoiceDetailPath(String id) => '/invoice/$id';
  static String rentalAgreementDetailPath(String id) => '/rental-agreement/$id';
  static String guestReportPath({
    required String unitId,
    required String tenantId,
    required String unitName,
  }) =>
      '/guest-report?unitId=$unitId&tenantId=$tenantId'
      '&unitName=${Uri.encodeComponent(unitName)}';
}

// ─── Router notifier (bridges Riverpod → GoRouter refreshListenable) ─────────

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<AppUser?>>(currentUserProvider, (_, __) => notifyListeners());
    // Also rebuild when tenant data arrives so the onboarding redirect fires
    // as soon as we know whether a tenant doc exists — not just when auth changes.
    _ref.listen<AsyncValue<Tenant?>>(tenantProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;

  // Routes that require the 'manager' role.
  static const _managerOnlyPrefixes = [
    '/manager',
    '/analytics',
    '/buildings',
    '/unit/',
    '/tenants',
    '/export',
    '/tenant-settings',
    '/bulk-import',
    '/statements',
    '/calendar',
    '/energy',
    '/rental-agreement',
  ];

  // Routes that require the 'contractor' role (exact or prefix).
  static const _contractorOnlyPrefixes = ['/contractor'];

  // Routes only for tenant_user role.
  static const _tenantOnlyPrefixes = ['/tenant', '/my-statements'];

  static bool _matchesPrefixes(String loc, List<String> prefixes) =>
      prefixes.any((p) => loc == p || loc.startsWith('$p/'));

  String? redirect(BuildContext context, GoRouterState state) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    final loc = state.matchedLocation;
    final onLogin = loc == AppRoutes.login;
    final onRegister = loc == AppRoutes.register;
    final onGuestReport = loc.startsWith(AppRoutes.guestReport);

    // Unauthenticated users may only visit login, register, or guest-report.
    if (!isLoggedIn) {
      return (onLogin || onRegister || onGuestReport) ? null : AppRoutes.login;
    }

    final userAsync = _ref.read(currentUserProvider);
    final onOnboarding = loc == AppRoutes.onboarding;

    return userAsync.whenOrNull(
      data: (user) {
        if (user == null) return null;

        // Redirect from auth screens to role home.
        if (onLogin || onRegister) return _homeForRole(user.role);

        // Manager: check onboarding first, then enforce role boundaries.
        if (user.role == 'manager') {
          final tenantAsync = _ref.read(tenantProvider);
          final onboardingRedirect = tenantAsync.whenOrNull(
            data: (tenant) {
              if (tenant == null && !onOnboarding) return AppRoutes.onboarding;
              if (tenant != null && onOnboarding) return AppRoutes.manager;
              return null;
            },
          );
          if (onboardingRedirect != null) return onboardingRedirect;

          // Manager must not access contractor-only or tenant-only areas.
          if (_matchesPrefixes(loc, _contractorOnlyPrefixes) ||
              _matchesPrefixes(loc, _tenantOnlyPrefixes)) {
            return AppRoutes.manager;
          }
          return null;
        }

        // Contractor: block manager-only and tenant-only routes.
        if (user.role == 'contractor') {
          if (_matchesPrefixes(loc, _managerOnlyPrefixes) ||
              _matchesPrefixes(loc, _tenantOnlyPrefixes)) {
            return AppRoutes.contractor;
          }
          return null;
        }

        // Tenant user: block manager-only and contractor-only routes.
        if (_matchesPrefixes(loc, _managerOnlyPrefixes) ||
            _matchesPrefixes(loc, _contractorOnlyPrefixes)) {
          return AppRoutes.tenant;
        }
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
        path: AppRoutes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
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
        path: AppRoutes.insuranceClaim,
        builder: (_, state) => InsuranceClaimScreen(
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
      GoRoute(
        path: AppRoutes.invoiceDetail,
        builder: (_, state) => InvoiceDetailScreen(
          invoiceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.tenantSettings,
        builder: (_, __) => const TenantSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.bulkImport,
        builder: (_, __) => const BulkImportScreen(),
      ),
      GoRoute(
        path: AppRoutes.statements,
        builder: (_, __) => const ManagerStatementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.createStatement,
        builder: (_, __) => const CreateStatementScreen(),
      ),
      GoRoute(
        path: AppRoutes.tenantStatements,
        builder: (_, __) => const TenantStatementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.energy,
        builder: (_, __) => const EnergyScreen(),
      ),
      GoRoute(
        path: AppRoutes.guestReport,
        builder: (_, state) => GuestReportScreen(
          unitId: state.uri.queryParameters['unitId'] ?? '',
          tenantId: state.uri.queryParameters['tenantId'] ?? '',
          unitName: Uri.decodeComponent(
              state.uri.queryParameters['unitName'] ?? ''),
        ),
      ),
      GoRoute(
        path: AppRoutes.createRentalAgreement,
        builder: (_, __) => const CreateRentalAgreementScreen(),
      ),
      GoRoute(
        path: AppRoutes.rentalAgreementDetail,
        builder: (_, state) => RentalAgreementDetailScreen(
          agreementId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});
