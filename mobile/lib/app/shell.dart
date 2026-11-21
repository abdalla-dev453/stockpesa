import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/network/connectivity_provider.dart';
import '../core/notifications/push_notifications.dart';
import '../core/theme.dart';
import '../features/auth/presentation/auth_provider.dart';
import '../features/insights/data/insights_repository.dart';
import '../screens/more_screen.dart' as legacy;

class StockPesaShell extends ConsumerStatefulWidget {
  const StockPesaShell({
    super.key,
    required this.child,
    required this.location,
  });
  final Widget child;
  final String location;

  @override
  ConsumerState<StockPesaShell> createState() => _StockPesaShellState();
}

class _StockPesaShellState extends ConsumerState<StockPesaShell> {
  Timer? _alertPoll;
  int? _lastUnread;

  @override
  void initState() {
    super.initState();
    _alertPoll = Timer.periodic(
      const Duration(seconds: 45),
      (_) => ref.invalidate(unreadAlertsProvider),
    );
  }

  @override
  void dispose() {
    _alertPoll?.cancel();
    super.dispose();
  }

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
    final location = widget.location;
    if (location.startsWith('/products')) return 1;
    if (location.startsWith('/sell')) return 2;
    if (location.startsWith('/stock')) return 3;
    if (location == '/dashboard') return 0;
    return 4;
  }

  void _showNotification(String title, String body) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: C.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.notifications_active_outlined, color: C.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: C.amber,
            onPressed: () => context.go('/alerts'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final location = widget.location;
    ref.listen(foregroundPushMessagesProvider, (_, state) {
      final message = state.asData?.value;
      if (message == null || !context.mounted) return;
      final title = message.notification?.title?.trim();
      final body = message.notification?.body?.trim();
      _showNotification(
        title?.isNotEmpty == true ? title! : 'New StockPesa alert',
        body?.isNotEmpty == true
            ? body!
            : 'Open your alerts to see the latest update.',
      );
      ref.invalidate(unreadAlertsProvider);
    });
    ref.listen(unreadAlertsProvider, (_, next) {
      final current = next.asData?.value;
      if (current == null) return;
      final before = _lastUnread;
      _lastUnread = current;
      if (before != null && current > before) {
        _showNotification(
          'New business alert',
          'You have $current unread alerts.',
        );
      }
    });
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 600;
    final desktop = width >= 1000;
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
        location == '/market-insights' ||
        location == '/notification-settings' ||
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
        : location == '/market-insights'
        ? 'Market insights'
        : location == '/notification-settings'
        ? 'Notifications'
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
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/stockpesa-icon-48.png',
                    width: 28,
                    height: 28,
                    semanticLabel: 'StockPesa',
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
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
                      'Offline · Saved products and your cart are available. Checkout needs internet; no sale is queued.',
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
    if (desktop) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1720),
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Row(
              children: [
                _DesktopSidebar(location: location, unread: unread),
                Expanded(
                  child: Column(
                    children: [
                      if (!childHasAppBar)
                        _DesktopTopBar(
                          title: title,
                          online: online,
                          unread: unread,
                        ),
                      if (!online) _OfflineBanner(),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
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

class _DesktopSidebar extends ConsumerWidget {
  const _DesktopSidebar({required this.location, required this.unread});
  final String location;
  final int unread;

  static const primary = [
    (Icons.space_dashboard_outlined, 'Overview', '/dashboard'),
    (Icons.inventory_2_outlined, 'Products', '/products'),
    (Icons.point_of_sale_outlined, 'New sale', '/sell'),
    (Icons.warehouse_outlined, 'Stock', '/stock'),
    (Icons.people_outline, 'Customers', '/customers'),
    (Icons.receipt_long_outlined, 'Sales history', '/sales'),
    (Icons.analytics_outlined, 'Reports', '/reports'),
    (Icons.insights_outlined, 'Market insights', '/market-insights'),
    (Icons.notifications_outlined, 'Alerts', '/alerts'),
  ];
  static const management = [
    (Icons.category_outlined, 'Categories', '/categories'),
    (Icons.badge_outlined, 'Staff', '/staff'),
    (Icons.settings_outlined, 'Settings', '/settings'),
    (Icons.menu, 'More', '/more'),
  ];

  bool _isSelected(String path) =>
      location == path ||
      (path != '/dashboard' && location.startsWith('$path/'));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 18, 20),
            child: Row(
              children: [
                Image.asset(
                  'assets/branding/stockpesa-icon-48.png',
                  width: 38,
                  height: 38,
                  semanticLabel: 'StockPesa',
                ),
                const SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'StockPesa',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
                    Text(
                      'Business workspace',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              children: [
                _sectionLabel(context, 'WORKSPACE'),
                for (final destination in primary)
                  _destination(
                    context,
                    destination.$1,
                    destination.$2,
                    destination.$3,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 22, 12, 8),
                  child: Divider(height: 1, color: colors.outlineVariant),
                ),
                _sectionLabel(context, 'MANAGE'),
                for (final destination in management)
                  _destination(
                    context,
                    destination.$1,
                    destination.$2,
                    destination.$3,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Text(
              'Know your stock. Grow your business.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.15,
      ),
    ),
  );

  Widget _destination(
    BuildContext context,
    IconData icon,
    String label,
    String path,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = _isSelected(path);
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: .10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => context.go(path),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 13),
                Icon(icon, size: 19, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? colors.primary : colors.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (path == '/alerts' && unread > 0)
                  Badge(
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends ConsumerWidget {
  const _DesktopTopBar({
    required this.title,
    required this.online,
    required this.unread,
  });
  final String title;
  final bool online;
  final int unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: online
                  ? colors.primary.withValues(alpha: .08)
                  : colors.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: online ? colors.primary : colors.error,
                ),
                const SizedBox(width: 7),
                Text(
                  online ? 'Online' : 'Offline',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: online ? colors.primary : colors.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Alerts${unread > 0 ? ', $unread unread' : ''}',
            onPressed: () => context.go('/alerts'),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Account menu',
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
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: colors.primary.withValues(alpha: .12),
                foregroundColor: colors.primary,
                child: const Icon(Icons.person_outline, size: 19),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: colors.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline · Saved products and your cart are available. Checkout needs internet; no sale is queued.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
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
