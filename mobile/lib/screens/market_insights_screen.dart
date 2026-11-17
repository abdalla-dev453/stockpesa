import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';

class MarketInsightsScreen extends StatefulWidget {
  const MarketInsightsScreen({super.key});
  @override
  State<MarketInsightsScreen> createState() => _MarketInsightsScreenState();
}

class _MarketInsightsScreenState extends State<MarketInsightsScreen> {
  int days = 7;
  late Future<Map<String, dynamic>> data = _load();

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(
    (await dio.get(
          '/reports/market-insights',
          queryParameters: {'days': days},
        )).data
        as Map,
  );

  void _changeDays(int value) => setState(() {
    days = value;
    data = _load();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Market insights')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(apiError(snapshot.error!)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snapshot.data!;
        final trend = (d['trend'] as List? ?? []).cast<Map>();
        final best = (d['bestSellers'] as List? ?? []).cast<Map>();
        final slow = (d['slowMoving'] as List? ?? []).cast<Map>();
        final running = (d['runningOut'] as List? ?? []).cast<Map>();
        return RefreshIndicator(
          onRefresh: () async => setState(() => data = _load()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                d['source']?.toString() ?? 'Business data',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 days')),
                  ButtonSegment(value: 30, label: Text('30 days')),
                ],
                selected: {days},
                onSelectionChanged: (s) => _changeDays(s.first),
              ),
              const SizedBox(height: 16),
              _section(context, 'Sales trend', [
                if (trend.isEmpty)
                  const Text('No completed sales in this period.')
                else
                  for (final row in trend)
                    ListTile(
                      dense: true,
                      title: Text(
                        formatBusinessDate(row['date']).split(',').first,
                      ),
                      subtitle: LinearProgressIndicator(
                        value: _bar(
                          numberValue(row['sales']),
                          trend.map((r) => numberValue(r['sales'])),
                        ),
                      ),
                      trailing: Text(kes(numberValue(row['sales']))),
                    ),
              ]),
              _section(context, 'Stock health', [
                Text(
                  d['stockHealth'] == null
                      ? 'Add products to see stock health.'
                      : '${d['stockHealth']}% of active products are above their minimum stock level.',
                ),
              ]),
              _section(context, 'Best sellers', [
                if (best.isEmpty)
                  const Text('Not enough sales data yet.')
                else
                  for (final p in best)
                    _row(
                      '${p['name']}',
                      '${numberValue(p['quantitySold'])} sold',
                    ),
              ]),
              _section(context, 'Slow moving', [
                if (slow.isEmpty)
                  const Text('No product history yet.')
                else
                  for (final p in slow)
                    _row(
                      '${p['name']}',
                      '${numberValue(p['quantitySold'])} sold · ${numberValue(p['onHand'])} on hand',
                    ),
              ]),
              _section(context, 'May run out soon', [
                if (running.isEmpty)
                  const Text(
                    'No products are projected to run out within 14 days from this period’s sales velocity.',
                  )
                else
                  for (final p in running)
                    _row(
                      '${p['name']}',
                      '${numberValue(p['onHand'])} on hand · about ${p['estimatedDaysRemaining']} days at recent sales pace',
                    ),
              ]),
              const SizedBox(height: 8),
              Text(
                d['note']?.toString() ?? '',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: C.muted),
              ),
            ],
          ),
        );
      },
    ),
  );

  double _bar(num value, Iterable<num> values) {
    final max = values.fold<num>(0, (a, b) => a > b ? a : b);
    return max == 0 ? 0 : (value / max).clamp(0, 1).toDouble();
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Widget _row(String title, String detail) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(detail),
  );
}
