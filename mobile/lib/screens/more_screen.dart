import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../features/insights/data/insights_repository.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.onLogout});
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(6, 8, 6, 14),
        child: Text(
          'Manage your business',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
        ),
      ),
      _item(
        context,
        'Customers & credit',
        'Customer accounts and payments',
        Icons.people_outline,
        '/customers',
      ),
      _item(
        context,
        'Categories',
        'Organize your product catalogue',
        Icons.category_outlined,
        '/categories',
      ),
      _item(
        context,
        'Staff',
        'Manage your team and roles',
        Icons.badge_outlined,
        '/staff',
      ),
      _item(
        context,
        'Sales history',
        'Review transactions and receipts',
        Icons.receipt_long_outlined,
        '/sales',
      ),
      _item(
        context,
        'Stock counts',
        'Count and reconcile inventory',
        Icons.fact_check_outlined,
        '/stock/count',
      ),
      _item(
        context,
        'Reports',
        'Sales and inventory performance',
        Icons.analytics_outlined,
        '/reports',
      ),
      _item(
        context,
        'Market insights',
        'Sales and stock patterns from your business data',
        Icons.insights_outlined,
        '/market-insights',
      ),
      _item(
        context,
        'Alerts',
        'Stock, customer and account notifications',
        Icons.notifications_active_outlined,
        '/alerts',
      ),
      _item(
        context,
        'Business settings',
        'Profile and receipt details',
        Icons.settings_outlined,
        '/settings',
      ),
      const SizedBox(height: 10),
      Card(
        child: ListTile(
          leading: const Icon(Icons.logout, color: C.danger),
          title: const Text('Sign out'),
          onTap: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text(
                  'You will need your password to sign back in.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            );
            if (yes == true) await onLogout();
          },
        ),
      ),
    ],
  );
  Widget _item(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    String route,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: C.emerald.withValues(alpha: .1),
        child: Icon(icon, color: C.emerald),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(route),
    ),
  );
}

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});
  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  List alerts = [];
  bool loading = true;
  int unread = 0;
  String filter = 'ALL';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await dio.get('/alerts', queryParameters: {'limit': 100});
      alerts = r.data['data'] as List;
      unread = r.data['unreadCount'] as int? ?? 0;
      ref.invalidate(unreadAlertsProvider);
    } catch (e) {
      _msg(apiError(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void _msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  Future<void> readAll() async {
    try {
      await dio.patch('/alerts/read-all');
      await load();
    } catch (e) {
      _msg(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Alerts'),
      actions: [
        TextButton(
          onPressed: unread == 0 ? null : readAll,
          child: const Text('Read all'),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final option in const [
                        'ALL',
                        'LOW',
                        'OUT',
                        'UNREAD',
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(switch (option) {
                              'ALL' => 'All',
                              'LOW' => 'Low stock',
                              'OUT' => 'Out of stock',
                              _ => 'Unread',
                            }),
                            selected: filter == option,
                            onSelected: (_) => setState(() => filter = option),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: () {
                    final visible = alerts.where((item) {
                      final kind = item['kind']?.toString();
                      return switch (filter) {
                        'LOW' => kind == 'low_stock',
                        'OUT' => kind == 'out_of_stock',
                        'UNREAD' => item['read'] != true,
                        _ => true,
                      };
                    }).toList();
                    if (visible.isEmpty) {
                      return ListView(
                        children: [
                          const SizedBox(height: 100),
                          Center(
                            child: Text(
                              filter == 'ALL'
                                  ? 'No business alerts yet.'
                                  : 'No alerts match this filter.',
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final a = visible[i] as Map, p = a['product'] as Map?;
                        final isRead = a['read'] == true;
                        return ListTile(
                          leading: Icon(
                            a['kind'] == 'out_of_stock'
                                ? Icons.remove_shopping_cart_outlined
                                : a['critical'] == true
                                ? Icons.security_outlined
                                : a['kind'] == 'low_stock'
                                ? Icons.warning_amber_rounded
                                : Icons.notifications_active_outlined,
                            color: isRead ? C.muted : C.warn,
                          ),
                          title: Text(
                            a['title'] ?? p?['name'] ?? a['kind'] ?? 'Business alert',
                            style: TextStyle(
                              fontWeight: isRead
                                  ? FontWeight.normal
                                  : FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [a['body']?.toString(), a['createdAt']?.toString()]
                                .whereType<String>()
                                .where((text) => text.isNotEmpty)
                                .join('  •  '),
                          ),
                          trailing: isRead
                              ? null
                              : const Icon(
                                  Icons.circle,
                                  size: 9,
                                  color: C.emerald,
                                ),
                          onTap: () async {
                            try {
                              if (!isRead) {
                                await dio.patch('/alerts/${a['id']}/read');
                                await load();
                              }
                              if (!context.mounted) return;
                              final data = a['data'];
                              final route = data is Map ? data['path']?.toString() : null;
                              if (route != null && (route.startsWith('/products/') || route.startsWith('/customers/') || route == '/reports' || route == '/staff' || route == '/market-insights')) {
                                context.go(route);
                              } else if (p?['id'] != null) {
                                context.go('/products/${p!['id']}');
                              } else {
                                context.go('/stock');
                              }
                            } catch (e) {
                              _msg(apiError(e));
                            }
                          },
                        );
                      },
                    );
                  }(),
                ),
              ],
            ),
          ),
  );
}
