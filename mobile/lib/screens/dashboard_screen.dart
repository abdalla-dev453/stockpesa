import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../features/dashboard/data/dashboard_repository.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<Map<String, dynamic>> data = _load();
  Future<Map<String, dynamic>> _load({bool force = false}) =>
      ref.read(dashboardRepositoryProvider).load(forceRefresh: force);
  Future<void> _refresh() async => setState(() => data = _load(force: true));
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: data,
    builder: (context, snap) {
      if (snap.hasError) return _error(apiError(snap.error!));
      if (!snap.hasData) {
        return const _DashboardSkeleton();
      }
      final d = snap.data!;
      return LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1000;
          final wide = constraints.maxWidth >= 640;
          final colors = Theme.of(context).colorScheme;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                desktop ? 32 : 18,
                desktop ? 26 : 10,
                desktop ? 32 : 18,
                100,
              ),
              children: [
                if (desktop)
                  Row(
                    children: [
                      Expanded(flex: 3, child: _salesSummary(d, compact: true)),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 2,
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            leading: Icon(
                              Icons.notifications_active_outlined,
                              color: colors.primary,
                            ),
                            title: const Text('Unread alerts'),
                            subtitle: const Text(
                              'Items that may need your attention',
                            ),
                            trailing: Text(
                              '${d['unreadAlerts'] ?? 0}',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  _salesSummary(d),
                const SizedBox(height: 18),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: desktop
                      ? 4
                      : wide
                      ? 4
                      : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: desktop
                      ? 1.75
                      : wide
                      ? 1.4
                      : 1.35,
                  children: [
                    _metric(
                      context,
                      'Products',
                      '${d['productCount'] ?? 0}',
                      Icons.inventory_2_outlined,
                      C.emerald,
                    ),
                    _metric(
                      context,
                      'This month',
                      kes(numberValue(d['salesMonth'])),
                      Icons.trending_up,
                      C.emerald,
                    ),
                    _metric(
                      context,
                      'Low stock',
                      '${d['lowStock'] ?? 0}',
                      Icons.warning_amber_rounded,
                      C.warn,
                    ),
                    _metric(
                      context,
                      'Out of stock',
                      '${d['outOfStock'] ?? 0}',
                      Icons.remove_shopping_cart_outlined,
                      C.danger,
                    ),
                  ],
                ),
                if (!desktop) ...[
                  const SizedBox(height: 20),
                  Text(
                    'At a glance',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.notifications_active_outlined,
                        color: colors.primary,
                      ),
                      title: const Text('Unread alerts'),
                      trailing: Text(
                        '${d['unreadAlerts'] ?? 0}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Pull down to refresh your business summary.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  Widget _salesSummary(Map<String, dynamic> d, {bool compact = false}) =>
      Container(
        padding: EdgeInsets.all(compact ? 26 : 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [C.forest, C.emerald]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: compact
            ? Row(
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: _salesText(d)),
                ],
              )
            : _salesText(d),
      );

  Widget _salesText(Map<String, dynamic> d) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Today at your shop', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 8),
      Text(
        kes(numberValue(d['salesToday'])),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '${d['saleCountToday'] ?? 0} completed sales',
        style: const TextStyle(color: Colors.white70),
      ),
    ],
  );
  Widget _metric(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _error(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: _refresh, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Container(
        height: 140,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      const SizedBox(height: 18),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
        children: List.generate(
          4,
          (_) => Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      const Center(child: CircularProgressIndicator()),
    ],
  );
}
