import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/network/connectivity_provider.dart';
import '../features/auth/presentation/auth_provider.dart';
import '../features/insights/data/insights_repository.dart';
import '../screens/more_screen.dart' as legacy;

class StockPesaShell extends ConsumerWidget {
  const StockPesaShell({
    super.key,
    required this.child,
    required this.location,
  });
  final Widget child;
  final String location;

  static const destinations = [
    (
      Icons.space_dashboard_outlined,
      Icons.space_dashboard,
      'Home',
      '/dashboard',
    ),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Products', '/products'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Sell', '/sell'),
    (Icons.warehouse_outlined, Icons.warehouse, 'Stock', '/stock'),
    (Icons.menu, Icons.menu, 'More', '/more'),
  ];

  int get selected {
    if (location.startsWith('/products')) return 1;
    if (location.startsWith('/sell')) return 2;
    if (location.startsWith('/stock')) return 3;
    if (location == '/dashboard') return 0;
    return 4;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 600;
    final selectedIndex = selected;
    final online = ref
        .watch(connectivityProvider)
        .maybeWhen(
          data: (results) =>
              results.any((item) => item != ConnectivityResult.none),
          orElse: () => false,
        );
    final unread = ref.watch(unreadAlertsProvider).asData?.value ?? 0;
    final childHasAppBar =
        location == '/alerts' ||
        location == '/reports' ||
        location == '/settings' ||
        location == '/staff' ||
        location == '/sales' ||
        location == '/categories' ||
        location.startsWith('/customers') ||
        location == '/stock/count' ||
        location.startsWith('/sales') ||
        location.startsWith('/sell/success');
    final title = location.startsWith('/products')
        ? 'Products'
        : location.startsWith('/sell')
        ? 'New sale'
        : location.startsWith('/stock')
        ? 'Inventory'
        : location == '/alerts'
        ? 'Alerts'
        : location.startsWith('/reports')
        ? 'Reports'
        : location.startsWith('/customers')
        ? 'Customers'
        : location == '/settings'
        ? 'Business settings'
        : location == '/staff'
        ? 'Staff'
        : location == '/sales'
        ? 'Sales history'
        : location == '/categories'
        ? 'Categories'
        : location == '/more'
        ? 'More'
        : 'Overview';
    final scaffold = Scaffold(
      appBar: childHasAppBar
          ? null
          : AppBar(
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: [
                Semantics(
                  label: online ? 'Online' : 'Offline',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Icon(
                        Icons.circle,
                        size: 9,
                        color: online ? const Color(0xFF16A34A) : Colors.grey,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Alerts${unread > 0 ? ', $unread unread' : ''}',
                  onPressed: () => context.go('/alerts'),
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Business profile',
                  onSelected: (value) async {
                    if (value == 'settings') context.go('/settings');
                    if (value == 'logout') {
                      await ref.read(sessionProvider.notifier).signOut();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.store_outlined),
                        title: Text('Business profile'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.logout),
                        title: Text('Sign out'),
                      ),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4, right: 16),
                    child: CircleAvatar(
                      radius: 17,
                      child: Icon(Icons.person_outline, size: 19),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton:
          childHasAppBar || selectedIndex == 2 || location.startsWith('/sell')
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('/sell'),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('New sale'),
            ),
      body: Column(
        children: [
          if (!online)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF0CC),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline · Your cart is saved on this device. Sales need an internet connection; nothing is queued.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Row(
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (index) =>
                        context.go(destinations[index].$4),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: d.$3 == 'More'
                              ? Badge(
                                  isLabelVisible: unread > 0,
                                  label: Text(unread > 99 ? '99+' : '$unread'),
                                  child: Icon(d.$1),
                                )
                              : Icon(d.$1),
                          selectedIcon: d.$3 == 'More'
                              ? Badge(
                                  isLabelVisible: unread > 0,
                                  label: Text(unread > 99 ? '99+' : '$unread'),
                                  child: Icon(d.$2),
                                )
                              : Icon(d.$2),
                          label: Text(d.$3),
                        ),
                    ],
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) =>
                  context.go(destinations[index].$4),
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: d.$3 == 'More'
                        ? Badge(
                            isLabelVisible: unread > 0,
                            label: Text(unread > 99 ? '99+' : '$unread'),
                            child: Icon(d.$1),
                          )
                        : Icon(d.$1),
                    selectedIcon: d.$3 == 'More'
                        ? Badge(
                            isLabelVisible: unread > 0,
                            label: Text(unread > 99 ? '99+' : '$unread'),
                            child: Icon(d.$2),
                          )
                        : Icon(d.$2),
                    label: d.$3,
                  ),
              ],
            ),
    );
    if (width >= 1000) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: scaffold,
        ),
      );
    }
    return scaffold;
  }
}

class MoreHubScreen extends ConsumerWidget {
  const MoreHubScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MoreScreenContent(
    onLogout: () => ref.read(sessionProvider.notifier).signOut(),
  );
}

class MoreScreenContent extends StatelessWidget {
  const MoreScreenContent({super.key, required this.onLogout});
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) => legacy.MoreScreen(onLogout: onLogout);
}
