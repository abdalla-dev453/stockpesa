import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets/product_image.dart';
import '../features/dashboard/data/dashboard_repository.dart';

const _tileNames = <String, String>{
  'attention': 'Needs attention',
  'quick_actions': 'Quick actions',
  'fast_movers': 'Fast movers',
  'sales_summary': 'Today at a glance',
  'stock_health': 'Stock health',
  'debt': 'Customer debt',
};
const _actions = <String, (String, IconData, String)>{
  'new_sale': ('New sale', Icons.point_of_sale_rounded, '/sell'),
  'add_product': ('Add product', Icons.add_box_outlined, '/products/add'),
  'receive_stock': (
    'Receive stock',
    Icons.move_to_inbox_outlined,
    '/stock/intake',
  ),
  'scan_barcode': (
    'Scan barcode',
    Icons.qr_code_scanner_rounded,
    '/sell?scan=true',
  ),
  'view_debt': (
    'View debt',
    Icons.account_balance_wallet_outlined,
    '/customers',
  ),
  'view_reports': ('View reports', Icons.bar_chart_rounded, '/reports'),
  'stock_count': ('Stock count', Icons.fact_check_outlined, '/stock/count'),
};

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<List<dynamic>> _data = _load();
  Future<List<dynamic>> _load() async {
    final repository = ref.read(dashboardRepositoryProvider);
    final board = await repository.loadBoard();
    final role = board['user']?['role']?.toString();
    final stats = role == 'STOREKEEPER'
        ? Map<String, dynamic>.from(board['summary'] as Map? ?? const {})
        : await repository.load(period: 'today');
    return [board, stats];
  }

  Future<void> _refresh() async => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(apiError(snapshot.error!), textAlign: TextAlign.center),
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) return const _BoardLoading();
      final board = Map<String, dynamic>.from(snapshot.data![0] as Map);
      final stats = Map<String, dynamic>.from(snapshot.data![1] as Map);
      final layout =
          ((board['layout'] as List?)?.cast<String>() ??
                  (board['defaultLayout'] as List).cast<String>())
              .where(_tileNames.containsKey)
              .toList();
      final favorites = (board['favorites'] as List? ?? []).cast<String>();
      final products = (board['fastMovers'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final pinnedProducts = (board['favoriteProducts'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final availableProducts = [...products, ...pinnedProducts]
          .fold<Map<String, Map<String, dynamic>>>({}, (map, product) {
            map[product['id'].toString()] = product;
            return map;
          })
          .values
          .toList();
      final role = board['user']?['role']?.toString() ?? 'OWNER';
      final roleActions = switch (role) {
        'CASHIER' => ['new_sale', 'scan_barcode', 'view_debt'],
        'STOREKEEPER' => ['receive_stock', 'stock_count'],
        _ => [
          'new_sale',
          'add_product',
          'receive_stock',
          'scan_barcode',
          'view_debt',
          'view_reports',
          'stock_count',
        ],
      };
      final quickActions = favorites
          .where(
            (id) =>
                _actions.containsKey(id) ||
                availableProducts.any((p) => p['id'] == id),
          )
          .toList();
      final shownActions = board['preferencesSaved'] == true
          ? quickActions
          : roleActions;
      final now = DateTime.now();
      final greeting = now.hour < 12
          ? 'Good morning'
          : now.hour < 17
          ? 'Good afternoon'
          : 'Good evening';
      final name = (board['user']?['name']?.toString().split(' ').first ?? '')
          .trim();
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting${name.isEmpty ? '' : ', $name'}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: mutedOn(context),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        board['businessName']?.toString() ?? 'Your shop',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                              color: inkOn(context),
                            ),
                      ),
                      Text(
                        _dateLabel(now),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: mutedOn(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => context.go('/alerts'),
                  tooltip: 'Alerts',
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
                IconButton(
                  onPressed: () => _editBoard(
                    context,
                    layout,
                    favorites,
                    availableProducts,
                    roleActions,
                  ),
                  tooltip: 'Edit board',
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final tile in layout) ...[
              if (tile == 'attention') ...[
                _attention(stats),
                const SizedBox(height: 16),
              ],
              if (tile == 'quick_actions') ...[
                _quickActions(shownActions, availableProducts, role),
                const SizedBox(height: 18),
              ],
              if (tile == 'fast_movers') ...[
                _fastMovers(products, role),
                const SizedBox(height: 18),
              ],
              if (tile == 'sales_summary') ...[
                _sales(stats),
                const SizedBox(height: 18),
              ],
              if (tile == 'stock_health') ...[
                _stockHealth(stats),
                const SizedBox(height: 18),
              ],
              if (tile == 'debt' &&
                  stats['outstandingCustomerDebt'] != null) ...[
                _debt(stats),
                const SizedBox(height: 18),
              ],
            ],
          ],
        ),
      );
    },
  );

  String _dateLabel(DateTime d) =>
      '${_weekday(d.weekday)}, ${d.day} ${_month(d.month)} ${d.year}';
  String _weekday(int d) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];
  String _month(int d) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][d - 1];

  Widget _section(String title, {Widget? action}) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      ?action,
    ],
  );

  Widget _attention(Map<String, dynamic> d) {
    final low = numberValue(d['lowStock']).toInt();
    final out = numberValue(d['outOfStock']).toInt();
    final debt = numberValue(d['outstandingCustomerDebt']);
    final debtors = numberValue(d['indebtedCustomers']).toInt();
    final alerts = numberValue(d['unreadAlerts']).toInt();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D1B2A41),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('Needs attention'),
            const SizedBox(height: 10),
            if (low + out == 0 && debt == 0 && alerts == 0)
              const Text(
                'You’re all caught up. Check back here for anything that needs your attention.',
                style: TextStyle(color: C.muted),
              )
            else ...[
              if (low + out > 0)
                _attentionRow(
                  Icons.inventory_2_outlined,
                  '$low products need restocking${out > 0 ? ' · $out out of stock' : ''}',
                  '/stock',
                ),
              if (debt > 0)
                _attentionRow(
                  Icons.account_balance_wallet_outlined,
                  '${kes(debt)} owed by $debtors customers',
                  '/customers',
                ),
              if (alerts > 0)
                _attentionRow(
                  Icons.notifications_active_outlined,
                  '$alerts unread alerts',
                  '/alerts',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _attentionRow(IconData icon, String label, String route) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(icon, color: C.amber),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.go(route),
  );

  Widget _quickActions(
    List<String> ids,
    List<Map<String, dynamic>> products,
    String role,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section('Quick actions'),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          final actionIds = [
            for (final id in ids)
              if (_actions.containsKey(id)) id,
          ];
          final columns = constraints.maxWidth >= 700
              ? 4
              : constraints.maxWidth >= 420
              ? 3
              : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 82,
            ),
            itemCount: actionIds.length,
            itemBuilder: (context, index) {
              final action = _actions[actionIds[index]]!;
              return Material(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.go(action.$3),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: C.emerald.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(action.$2, color: C.emerald, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            action.$1,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      if (ids.any((id) => products.any((p) => p['id'] == id))) ...[
        const SizedBox(height: 8),
        for (final id in ids)
          for (final p in products.where((p) => p['id'] == id))
            SizedBox(
              width: 220,
              child: Card(
                child: ListTile(
                  leading: ProductImage(
                    imageUrl: p['imageUrl']?.toString(),
                    width: 44,
                    height: 44,
                  ),
                  title: Text(
                    p['name']?.toString() ?? 'Product',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(kes(numberValue(p['sellingPrice']))),
                  onTap: () => context.go(
                    role == 'STOREKEEPER'
                        ? '/products/${p['id']}'
                        : '/sell?productId=${p['id']}',
                  ),
                ),
              ),
            ),
      ],
    ],
  );

  Widget _fastMovers(
    List<Map<String, dynamic>> products,
    String role,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section(
        'Fast movers',
        action: Text(
          '${products.length} products',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: C.muted),
        ),
      ),
      const SizedBox(height: 10),
      if (products.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Your best sellers will show here after you record a few sales.',
            ),
          ),
        )
      else
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final p = products[index];
              final quantity = numberValue(p['quantity']);
              final min = numberValue(p['minStock']);
              final stock = quantity <= 0
                  ? 'Out of stock'
                  : min > 0 && quantity <= min
                  ? '$quantity left · low'
                  : '$quantity ${p['unit'] ?? ''} left';
              return SizedBox(
                width: 152,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: quantity <= 0
                        ? null
                        : () => context.go(
                            role == 'STOREKEEPER'
                                ? '/products/${p['id']}'
                                : '/sell?productId=${p['id']}',
                          ),
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Center(
                              child: ProductImage(
                                imageUrl: p['imageUrl']?.toString(),
                                width: 62,
                                height: 62,
                              ),
                            ),
                          ),
                          Text(
                            p['name']?.toString() ?? 'Product',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            kes(numberValue(p['sellingPrice'])),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            stock,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: quantity <= min ? C.warn : C.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );

  Widget _sales(Map<String, dynamic> d) {
    final change = d['changePercent'] == null
        ? null
        : numberValue(d['changePercent']).toDouble();
    final saleCount = d['saleCount'] ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF174B82), Color(0xFF2F73B9), Color(0xFF568ED0)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33286EB2),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today at a glance',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 5),
          Text(
            kes(numberValue(d['sales'])),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$saleCount sales',
                style: const TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              if (change != null)
                Text(
                  '${change >= 0 ? '↑' : '↓'} ${change.abs()}% vs previous period',
                  style: const TextStyle(color: Colors.white),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stockHealth(Map<String, dynamic> d) => Card(
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined, color: C.emerald),
          title: const Text('Active products'),
          trailing: Text(
            '${d['productCount'] ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        ListTile(
          leading: const Icon(Icons.warning_amber_rounded, color: C.amber),
          title: const Text('Low / out of stock'),
          trailing: Text(
            '${numberValue(d['lowStock']).toInt()} / ${numberValue(d['outOfStock']).toInt()}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          onTap: () => context.go('/stock'),
        ),
      ],
    ),
  );
  Widget _debt(Map<String, dynamic> d) => Card(
    child: ListTile(
      leading: const Icon(
        Icons.account_balance_wallet_outlined,
        color: C.coral,
      ),
      title: const Text('Customer debt'),
      subtitle: Text('${d['indebtedCustomers'] ?? 0} customers with a balance'),
      trailing: Text(
        kes(numberValue(d['outstandingCustomerDebt'])),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      onTap: () => context.go('/customers'),
    ),
  );

  Future<void> _editBoard(
    BuildContext context,
    List<String> currentLayout,
    List<String> currentFavorites,
    List<Map<String, dynamic>> products,
    List<String> availableActions,
  ) async {
    var layout = List<String>.from(currentLayout);
    var favorites = List<String>.from(currentFavorites);
    final result = await showModalBottomSheet<(List<String>, List<String>)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Customize your board',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setSheet(() {
                          layout = [
                            'quick_actions',
                            'fast_movers',
                            'sales_summary',
                          ];
                        }),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Tiles · drag to reorder, remove to hide'),
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
                    children: [
                      for (final id in layout)
                        ListTile(
                          key: ValueKey(id),
                          title: Text(_tileNames[id]!),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () =>
                                    setSheet(() => layout.remove(id)),
                                icon: const Icon(Icons.close),
                              ),
                              const Icon(Icons.drag_handle),
                            ],
                          ),
                        ),
                    ],
                    onReorder: (oldIndex, newIndex) => setSheet(() {
                      if (newIndex > oldIndex) newIndex--;
                      final id = layout.removeAt(oldIndex);
                      layout.insert(newIndex, id);
                    }),
                  ),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Add a tile'),
                  ),
                ),
                Wrap(
                  children: [
                    for (final id in _tileNames.keys)
                      if (!layout.contains(id))
                        ActionChip(
                          label: Text(_tileNames[id]!),
                          onPressed: () => setSheet(() => layout.add(id)),
                        ),
                  ],
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Pinned shortcuts'),
                  ),
                ),
                SizedBox(
                  height: 145,
                  child: ListView(
                    children: [
                      for (final id in availableActions)
                        CheckboxListTile(
                          dense: true,
                          value: favorites.contains(id),
                          title: Text(_actions[id]!.$1),
                          secondary: Icon(_actions[id]!.$2),
                          onChanged: (on) => setSheet(() {
                            on == true
                                ? favorites.add(id)
                                : favorites.remove(id);
                          }),
                        ),
                      for (final p in products)
                        CheckboxListTile(
                          dense: true,
                          value: favorites.contains(p['id']),
                          title: Text(p['name']?.toString() ?? 'Product'),
                          secondary: const Icon(Icons.inventory_2_outlined),
                          onChanged: (on) => setSheet(() {
                            on == true
                                ? favorites.add(p['id'].toString())
                                : favorites.remove(p['id']);
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, (layout, favorites)),
                    child: const Text('Save board'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(dashboardRepositoryProvider)
          .saveBoard(layout: result.$1, favorites: result.$2);
      if (context.mounted) {
        setState(() => _data = _load());
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Your board is saved')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    }
  }
}

class _BoardLoading extends StatelessWidget {
  const _BoardLoading();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Container(
        height: 95,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        height: 130,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      const SizedBox(height: 16),
      const Center(child: CircularProgressIndicator()),
    ],
  );
}
