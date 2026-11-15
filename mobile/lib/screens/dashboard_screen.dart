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
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [C.forest, C.emerald]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Today at your shop',
                    style: TextStyle(color: Colors.white70),
                  ),
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
                  Colors.blue,
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
            const SizedBox(height: 20),
            Text(
              'At a glance',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.notifications_active_outlined,
                  color: C.coral,
                ),
                title: const Text('Unread alerts'),
                trailing: Text(
                  '${d['unreadAlerts'] ?? 0}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Pull down to refresh your business summary.',
              style: TextStyle(color: C.muted),
            ),
          ],
        ),
      );
    },
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
          Text(title, style: const TextStyle(color: C.muted)),
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
          const Icon(Icons.cloud_off_outlined, size: 40, color: C.muted),
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
