import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../features/dashboard/data/dashboard_repository.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String period = 'today';
  DateTime? customStart, customEnd;
  late Future<Map<String, dynamic>> data = _load();
  Future<Map<String, dynamic>> _load({bool force = false}) =>
      ref.read(dashboardRepositoryProvider).load(forceRefresh: force, period: period, startDate: customStart, endDate: customEnd);
  Future<void> _refresh() async => setState(() => data = _load(force: true));

  static const periods = <String, String>{
    'today': 'Today', 'yesterday': 'Yesterday', 'last_7_days': 'Last 7 days',
    'last_30_days': 'Last 30 days', 'this_month': 'This month', 'last_month': 'Last month', 'custom': 'Custom range',
  };

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: data,
    builder: (context, snap) {
      if (snap.hasError) return _error(apiError(snap.error!));
      if (!snap.hasData) return const _DashboardSkeleton();
      final d = snap.data!;
      final now = DateTime.now();
      final greeting = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
      final title = period == 'custom' && customStart != null ? '${customStart!.day}/${customStart!.month} – ${customEnd!.day}/${customEnd!.month}' : periods[period]!;
      final change = d['changePercent'];
      return RefreshIndicator(onRefresh: _refresh, child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
        children: [
          Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: C.muted)),
            Text('Business overview', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(DateTime.now().toLocal().toString().substring(0, 10), style: Theme.of(context).textTheme.bodySmall),
          ])), IconButton(onPressed: () => context.go('/alerts'), icon: const Icon(Icons.notifications_none_rounded))]),
          const SizedBox(height: 16),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: periods.entries.map((entry) => Padding(
            padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(entry.value), selected: period == entry.key,
              onSelected: (_) async {
                if (entry.key == 'custom') {
                  final range = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: customStart == null ? null : DateTimeRange(start: customStart!, end: customEnd!));
                  if (range == null || !context.mounted) return;
                  setState(() { period = 'custom'; customStart = DateTime(range.start.year, range.start.month, range.start.day); customEnd = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59); data = _load(); });
                } else if (period != entry.key) {
                  setState(() { period = entry.key; data = _load(); });
                }
              }),
          )).toList())),
          const SizedBox(height: 14),
          _salesHero(context, d, title, change),
          const SizedBox(height: 16),
          GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: MediaQuery.sizeOf(context).width > 650 ? 4 : 2,
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.6,
            children: [
              _metric(context, 'Transactions', '${d['saleCount'] ?? 0}', Icons.receipt_long_outlined, C.emerald),
              _metric(context, 'Items sold', numberValue(d['itemsSold']).toStringAsFixed(0), Icons.shopping_bag_outlined, C.forest),
              _metric(context, 'Low stock', '${d['lowStock'] ?? 0}', Icons.warning_amber_rounded, C.warn),
              _metric(context, 'Out of stock', '${d['outOfStock'] ?? 0}', Icons.remove_shopping_cart_outlined, C.danger),
            ]),
          const SizedBox(height: 22),
          _sectionHeading(context, 'Sales trend', periods[period]!),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 12), child: _TrendChart(points: (d['trend'] as List? ?? []).cast<Map>().map((p) => numberValue(p['sales']).toDouble()).toList()))),
          if ((d['paymentMethods'] as List? ?? []).isNotEmpty) ...[
            const SizedBox(height: 22), _sectionHeading(context, 'Payments received', title), const SizedBox(height: 8),
            Card(child: Column(children: (d['paymentMethods'] as List).map((p) => ListTile(dense: true,
              leading: CircleAvatar(backgroundColor: C.emerald.withValues(alpha: .1), child: const Icon(Icons.payments_outlined, color: C.emerald, size: 19)),
              title: Text((p['method'] ?? '').toString()), trailing: Text(kes(numberValue(p['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),)).toList())),
          ],
          const SizedBox(height: 22), _sectionHeading(context, 'Stock health', 'Inventory at a glance'), const SizedBox(height: 8),
          Card(child: Column(children: [
            ListTile(leading: const Icon(Icons.inventory_2_outlined, color: C.emerald), title: const Text('Active products'), trailing: Text('${d['productCount'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800))),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.notifications_active_outlined, color: C.warn), title: const Text('Unread alerts'), trailing: Text('${d['unreadAlerts'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)), onTap: () => context.go('/alerts')),
          ])),
          if (d['outstandingCustomerDebt'] != null) ...[
            const SizedBox(height: 22), _sectionHeading(context, 'Money owed', 'Customer balances'), const SizedBox(height: 8),
            Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined, color: C.coral), title: const Text('Outstanding receivables'), subtitle: Text('${d['indebtedCustomers']} customers with a balance'), trailing: Text(kes(numberValue(d['outstandingCustomerDebt'])), style: const TextStyle(fontWeight: FontWeight.w800)), onTap: () => context.go('/reports'))),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () => context.go('/sell'), icon: const Icon(Icons.add), label: const Text('New sale')),
          const SizedBox(height: 10), OutlinedButton.icon(onPressed: () => context.go('/reports'), icon: const Icon(Icons.bar_chart_rounded), label: const Text('View reports')),
        ],
      ));
    },
  );

  Widget _salesHero(BuildContext context, Map<String, dynamic> d, String title, dynamic change) {
    final pct = change == null ? null : numberValue(change).toDouble();
    final positive = pct == null || pct >= 0;
    return Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.forest, C.emerald]), borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title sales', style: const TextStyle(color: Colors.white70)), const SizedBox(height: 8),
        Text(kes(numberValue(d['sales'])), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 30)),
        const SizedBox(height: 8),
        Row(children: [const Icon(Icons.receipt_outlined, size: 17, color: Colors.white70), const SizedBox(width: 6), Text('${d['saleCount'] ?? 0} sales', style: const TextStyle(color: Colors.white70)),
          const Spacer(), if (pct != null) Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)), child: Row(children: [Icon(positive ? Icons.trending_up : Icons.trending_down, color: Colors.white, size: 16), const SizedBox(width: 4), Text('${pct.abs()}% vs previous period', style: const TextStyle(color: Colors.white, fontSize: 11))]))]),
      ]));
  }

  Widget _sectionHeading(BuildContext context, String heading, String detail) => Row(children: [Expanded(child: Text(heading, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))), Text(detail, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: C.muted))]);
  Widget _metric(BuildContext context, String title, String value, IconData icon, Color color) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: color), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: C.muted))])));
  Widget _error(String message) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_outlined, size: 40), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center), TextButton(onPressed: _refresh, child: const Text('Retry'))])));
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});
  final List<double> points;
  @override
  Widget build(BuildContext context) => SizedBox(height: 170, child: points.isEmpty
    ? Center(child: Text('Sales will appear here once recorded.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
    : CustomPaint(painter: _TrendPainter(points, Theme.of(context).colorScheme.primary), child: const SizedBox.expand()));
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points, this.color);
  final List<double> points; final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const inset = 12.0; final chart = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final grid = Paint()..color = color.withValues(alpha: .10)..strokeWidth = 1;
    for (var i = 0; i < 4; i++) { final y = chart.top + chart.height * i / 3; canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid); }
    if (points.isEmpty) return;
    final maxValue = points.reduce((a, b) => a > b ? a : b); final minValue = points.reduce((a, b) => a < b ? a : b);
    final range = maxValue == minValue ? (maxValue == 0 ? 1.0 : maxValue) : maxValue - minValue;
    final path = Path();
    for (var i = 0; i < points.length; i++) { final x = points.length == 1 ? chart.center.dx : chart.left + chart.width * i / (points.length - 1); final y = chart.bottom - ((points[i] - minValue) / range) * chart.height; i == 0 ? path.moveTo(x, y) : path.lineTo(x, y); }
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < points.length; i++) { final x = points.length == 1 ? chart.center.dx : chart.left + chart.width * i / (points.length - 1); final y = chart.bottom - ((points[i] - minValue) / range) * chart.height; canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color); }
  }
  @override bool shouldRepaint(covariant _TrendPainter old) => old.points != points || old.color != color;
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [Container(height: 150, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(24))), const SizedBox(height: 18), GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.35, children: List.generate(4, (_) => Card(color: Theme.of(context).colorScheme.surfaceContainerHighest))), const Center(child: CircularProgressIndicator())]);
}
