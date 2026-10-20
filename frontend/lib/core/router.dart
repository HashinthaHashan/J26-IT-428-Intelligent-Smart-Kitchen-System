import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/alerts/alerts_providers.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/child/child_screen.dart';
import '../features/home/dashboard_screen.dart';
import '../features/lpg/lpg_screen.dart';
import '../features/pantry/pantry_screen.dart';
import '../features/pest/pest_screen.dart';
import '../shared/widgets/clay.dart';
import '../shared/widgets/clay_nav_bar.dart';
import 'theme.dart';
import 'ws_client.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/lpg', builder: (_, _) => const LpgScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/pantry', builder: (_, _) => const PantryScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/pest', builder: (_, _) => const PestScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/child', builder: (_, _) => const ChildScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/alerts',
        builder: (_, _) => const AlertsScreen(),
      ),
    ],
  ),
);

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _titles = [
    'KitchenGuard',
    'LPG',
    'Pantry',
    'Pest',
    'Child safety',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadAlertsProvider);
    final connection = ref.watch(liveConnectionProvider).value;
    final reconnecting =
        connection == LiveConnectionState.reconnecting ||
        connection == LiveConnectionState.connecting;
    // Tabs already redesigned in the clay style draw their own header and
    // let content scroll under the floating nav (Home, LPG, Pantry, Pest).
    final isHome = const {0, 1, 2, 3}.contains(shell.currentIndex);
    return Scaffold(
      backgroundColor: isHome ? Clay.background : null,
      // Clay tabs draw their own header (label + bell); the rest keep the app bar.
      appBar: isHome ? null : AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_titles[shell.currentIndex]),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Alerts',
            onPressed: () => context.push('/alerts'),
            icon: Badge(
              backgroundColor: criticalRed,
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          const SizedBox(width: 12),
        ],
        bottom:
            reconnecting
                ? const PreferredSize(
                  preferredSize: Size.fromHeight(24),
                  child: ColoredBox(
                    color: Color(0xFFFFF5E5),
                    child: SizedBox(
                      height: 28,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Reconnecting...'),
                        ],
                      ),
                    ),
                  ),
                )
                : null,
      ),
      body: shell,
      // On Home the content scrolls underneath the floating pill (soft fade,
      // no backing strip). Other tabs keep their layout above the bar.
      extendBody: isHome,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isHome
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Clay.background.withValues(alpha: 0),
                    Clay.background.withValues(alpha: 0.92),
                  ],
                )
              : null,
          color: isHome ? null : Theme.of(context).scaffoldBackgroundColor,
        ),
        child: ClayNavBar(
          selectedIndex: shell.currentIndex,
          onSelected:
              (index) => shell.goBranch(
                index,
                initialLocation: index == shell.currentIndex,
              ),
          items: const [
            ClayNavItem('Home', Icons.home_outlined),
            ClayNavItem('LPG', Icons.local_fire_department_outlined),
            ClayNavItem('Pantry', Icons.inventory_2_outlined),
            ClayNavItem('Pest', Icons.track_changes_rounded),
            ClayNavItem('Child', Icons.sentiment_satisfied_outlined),
          ],
        ),
      ),
    );
  }
}
