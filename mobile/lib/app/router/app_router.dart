import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/presentation/accounts_page.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/setup_password_page.dart';
import '../../features/bootstrap/presentation/bootstrap_page.dart';
import '../../features/categories/presentation/categories_page.dart';
import '../../features/data_management/presentation/data_management_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/legacy_webview/presentation/legacy_webview_page.dart';
import '../../features/main/presentation/main_shell_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/server_config/presentation/server_config_page.dart';
import '../../features/statistics/presentation/mobile_statistics_page.dart';
import '../../features/transactions/data/transaction_models.dart';
import '../../features/transactions/presentation/quick_transaction_page.dart';
import '../../features/transactions/presentation/transaction_details_page.dart';
import 'app_route_paths.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: AppRoutePaths.bootstrap,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      return switch (authState.stage) {
        AuthStage.checking =>
          location == AppRoutePaths.bootstrap ? null : AppRoutePaths.bootstrap,
        AuthStage.serverRequired =>
          location == AppRoutePaths.serverConfig
              ? null
              : AppRoutePaths.serverConfig,
        AuthStage.setupRequired =>
          location == AppRoutePaths.setupPassword
              ? null
              : AppRoutePaths.setupPassword,
        AuthStage.loginRequired =>
          location == AppRoutePaths.login ? null : AppRoutePaths.login,
        AuthStage.authenticated => _redirectAuthenticated(location),
      };
    },
    routes: [
      GoRoute(
        path: AppRoutePaths.bootstrap,
        builder: (context, state) => const BootstrapPage(),
      ),
      GoRoute(
        path: AppRoutePaths.serverConfig,
        builder: (context, state) => const ServerConfigPage(),
      ),
      GoRoute(
        path: AppRoutePaths.setupPassword,
        builder: (context, state) => const SetupPasswordPage(),
      ),
      GoRoute(
        path: AppRoutePaths.login,
        builder: (context, state) => const LoginPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShellPage(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.home,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.transactions,
                builder: (context, state) => const TransactionDetailsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.statistics,
                builder: (context, state) => const MobileStatisticsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.profile,
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutePaths.quickTransaction,
        builder: (context, state) => QuickTransactionPage(
          editingTransaction: state.extra is TransactionItem
              ? state.extra! as TransactionItem
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutePaths.accounts,
        builder: (context, state) => const AccountsPage(),
      ),
      GoRoute(
        path: AppRoutePaths.categories,
        builder: (context, state) => const CategoriesPage(),
      ),
      GoRoute(
        path: AppRoutePaths.dataManagement,
        builder: (context, state) => const DataManagementPage(),
      ),
      GoRoute(
        path: AppRoutePaths.legacyWebView,
        builder: (context, state) {
          final url = state.uri.queryParameters['url'];
          return LegacyWebViewPage(initialUrl: url);
        },
      ),
    ],
  );
});

String? _redirectAuthenticated(String location) {
  final authOnlyRoutes = {
    AppRoutePaths.bootstrap,
    AppRoutePaths.serverConfig,
    AppRoutePaths.setupPassword,
    AppRoutePaths.login,
  };
  return authOnlyRoutes.contains(location) ? AppRoutePaths.home : null;
}

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    _removeListener = ref.listen<AuthState>(authControllerProvider, (_, __) {
      notifyListeners();
    }).close;
  }

  late final void Function() _removeListener;

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }
}
