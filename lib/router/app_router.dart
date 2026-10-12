import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/mvp_screens.dart';
import '../features/local/presentation/advanced_pages.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/local/presentation/budget_hub_page.dart';
import '../features/accounts/presentation/pages/asset_setup_page.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/ledgy_sidebar.dart';
import '../features/auth/presentation/profile_menu.dart';
import '../features/auth/presentation/profile_page.dart';

GoRouter createAppRouter({String? initialLocation}) => GoRouter(
  initialLocation: initialLocation ?? '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.toString(), child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
        GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
        GoRoute(
          path: '/transactions',
          builder: (_, state) => TransactionsPage(
            initialType: state.uri.queryParameters['type'],
            initialDate: DateTime.tryParse(
              state.uri.queryParameters['month'] ?? '',
            ),
          ),
        ),
        GoRoute(path: '/accounts', builder: (_, _) => const AccountsPage()),
        GoRoute(
          path: '/assets/:id',
          builder: (_, state) =>
              AssetDetailPage(assetId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/categories', builder: (_, _) => const CategoriesPage()),
        GoRoute(path: '/budgets', redirect: (_, _) => '/budget'),
        GoRoute(path: '/reports', redirect: (_, _) => '/'),
        GoRoute(path: '/analysis', redirect: (_, _) => '/'),
        GoRoute(
          path: '/budget',
          builder: (_, state) => BudgetHubPage(
            initialMonth: DateTime.tryParse(
              state.uri.queryParameters['month'] ?? '',
            ),
            initialSection: state.uri.queryParameters['section'] == 'recurring'
                ? 1
                : 0,
          ),
        ),
        GoRoute(path: '/budget-plans', redirect: (_, _) => '/budget'),
        GoRoute(
          path: '/recurring',
          redirect: (_, _) => '/budget?section=recurring',
        ),
        GoRoute(path: '/csv', builder: (_, _) => const CsvPage()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
        GoRoute(
          path: '/asset-setup',
          builder: (_, _) => const AssetSetupPage(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => AuthPage(
            registerInitially: state.uri.queryParameters['mode'] == 'register',
            next: state.uri.queryParameters['next'] == '/asset-setup'
                ? '/asset-setup'
                : '/settings',
          ),
        ),
      ],
    ),
  ],
);

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _sidebarPinned = false;

  static const _destinations = [
    ('/', 'Dashboard', Icons.space_dashboard_outlined),
    ('/transactions', 'Transaksi', Icons.receipt_long_outlined),
    ('/budget', 'Anggaran', Icons.calendar_month_outlined),
    ('/accounts', 'Aset', Icons.account_balance_wallet_outlined),
    ('/settings', 'Setting', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(widget.location);
    if (uri.path == '/onboarding' || uri.path == '/login') {
      return widget.child;
    }
    final selectedPath = switch (uri.path) {
      '/csv' => '/budget',
      '/asset-setup' => '/accounts',
      _ => uri.path,
    };
    final selected = _destinations
        .indexWhere((item) => item.$1 == selectedPath)
        .clamp(0, _destinations.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= AppTheme.sidebarBreakpoint;
    void navigate(int index) => context.go(_destinations[index].$1);
    if (wide) {
      return Scaffold(
        body: Stack(
          children: [
            Row(
              children: [
                SizedBox(
                  width: _sidebarPinned
                      ? AppTheme.sidebarExpandedWidth
                      : AppTheme.sidebarCompactWidth,
                ),
                const VerticalDivider(
                  width: AppTheme.sidebarDividerWidth,
                  color: AppTheme.sidebarBorder,
                ),
                Expanded(
                  child: RepaintBoundary(
                    key: const ValueKey('sidebar-page-content'),
                    child: widget.child,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: LedgySidebar(
                initiallyPinned: _sidebarPinned,
                profileBuilder: (labels) => ProfileMenu.sidebar(labels: labels),
                destinations: _destinations
                    .map(
                      (item) => SidebarDestination(
                        item.$1,
                        item.$2,
                        item.$3,
                        children: item.$1 == '/budget'
                            ? const [
                                SidebarSubdestination(
                                  '/budget',
                                  'Anggaran Bulanan',
                                  Icons.calendar_month_outlined,
                                ),
                                SidebarSubdestination(
                                  '/budget?section=recurring',
                                  'Transaksi Berulang',
                                  Icons.autorenew,
                                ),
                              ]
                            : const [],
                      ),
                    )
                    .toList(),
                selectedIndex: selected,
                onSelected: navigate,
                selectedSubpath: uri.path == '/budget'
                    ? (uri.queryParameters['section'] == 'recurring'
                          ? '/budget?section=recurring'
                          : '/budget')
                    : null,
                onSubSelected: (path) => context.go(path),
                onAddTransaction: () => showTransactionEditor(context),
                onPinnedChanged: (value) =>
                    setState(() => _sidebarPinned = value),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 5 ? selected : 0,
        onDestinationSelected: navigate,
        destinations: _destinations
            .take(5)
            .map(
              (item) =>
                  NavigationDestination(icon: Icon(item.$3), label: item.$2),
            )
            .toList(),
      ),
    );
  }
}
