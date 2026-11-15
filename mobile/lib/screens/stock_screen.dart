import 'package:flutter/material.dart';
import 'dart:math';
import 'package:dio/dio.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets/app_states.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key, this.initialAction});
  final String? initialAction;
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 2, vsync: this);
  List products = [], movements = [];
  bool loading = true;
  String? loadError;
  @override
  void initState() {
    super.initState();
    if (widget.initialAction == 'movements') tabs.index = 1;
    load().then((_) {
      if (mounted && widget.initialAction != null && loadError == null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openInitialAction(),
        );
      }
    });
  }

  Future<void> _openInitialAction() async {
    final product = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          widget.initialAction == 'intake' ? 'Receive stock' : 'Adjust stock',
        ),
        content: SizedBox(
          width: 420,
          child: products.isEmpty
              ? const Text('Add a product before recording stock.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final row in products)
                      ListTile(
                        title: Text(row['name']?.toString() ?? 'Product'),
                        subtitle: Text(
                          '${row['quantity'] ?? 0} ${row['unit'] ?? ''} on hand',
                        ),
                        onTap: () => Navigator.pop(
                          dialogContext,
                          Map<String, dynamic>.from(row as Map),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (product != null && mounted) {
      await _changeStock(product, intake: widget.initialAction == 'intake');
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await Future.wait([
        dio.get('/stock'),
        dio.get('/stock/movements'),
      ]);
      products = r[0].data as List;
      movements = r[1].data as List;
      loadError = null;
    } catch (e) {
      loadError = apiError(e);
    }
    if (mounted) setState(() => loading = false);
  }

  void _msg(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> _changeStock(
    Map<String, dynamic> p, {
    required bool intake,
  }) async {
    final qty = TextEditingController(),
        cost = TextEditingController(),
        supplier = TextEditingController(),
        reference = TextEditingController(),
        reason = TextEditingController(text: 'DAMAGE'),
        notes = TextEditingController();
    final requestKey = List.generate(
      32,
      (_) => Random.secure().nextInt(16).toRadixString(16),
    ).join();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(intake ? 'Receive stock' : 'Adjust stock'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p['name'] ?? ''),
              TextField(
                controller: qty,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: true,
                  signed: !intake,
                ),
                decoration: InputDecoration(
                  labelText: intake
                      ? 'Quantity received'
                      : 'Quantity change (use minus to remove)',
                ),
              ),
              if (intake)
                TextField(
                  controller: cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Unit cost'),
                ),
              if (intake) ...[
                TextField(
                  controller: supplier,
                  decoration: const InputDecoration(
                    labelText: 'Supplier (optional)',
                  ),
                ),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference (optional)',
                  ),
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
              ],
              if (!intake) ...[
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason (e.g. DAMAGE)',
                  ),
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(qty.text),
                  unitCost = double.tryParse(cost.text);
              if (amount == null ||
                  amount == 0 ||
                  (intake && (unitCost == null || unitCost < 0))) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid quantity and cost'),
                  ),
                );
                return;
              }
              try {
                if (intake) {
                  await dio.post(
                    '/stock/intake',
                    data: {
                      'productId': p['id'],
                      'quantity': amount,
                      'unitCost': unitCost,
                      'supplier': supplier.text.trim().isEmpty
                          ? null
                          : supplier.text.trim(),
                      'reference': reference.text.trim().isEmpty
                          ? null
                          : reference.text.trim(),
                      'notes': notes.text.trim().isEmpty
                          ? null
                          : notes.text.trim(),
                    },
                    options: Options(headers: {'Idempotency-Key': requestKey}),
                  );
                } else {
                  await dio.post(
                    '/stock/adjustments',
                    data: {
                      'productId': p['id'],
                      'quantityChange': amount,
                      'reason': reason.text.trim().isEmpty
                          ? 'OTHER'
                          : reason.text.trim(),
                      'notes': notes.text.trim().isEmpty
                          ? null
                          : notes.text.trim(),
                    },
                    options: Options(headers: {'Idempotency-Key': requestKey}),
                  );
                }
                if (context.mounted) Navigator.pop(context, true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              }
            },
            child: Text(intake ? 'Receive' : 'Adjust'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await load();
      if (mounted) _msg('Stock updated');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: Colors.white,
        child: TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: 'On hand'),
            Tab(text: 'Movements'),
          ],
        ),
      ),
      Expanded(
        child: loading
            ? const LoadingState(label: 'Loading stock…')
            : loadError != null
            ? ErrorState(message: loadError!, onRetry: load)
            : TabBarView(
                controller: tabs,
                children: [
                  RefreshIndicator(
                    onRefresh: load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 7),
                      itemBuilder: (context, i) {
                        final p = Map<String, dynamic>.from(products[i] as Map);
                        final quantity = numberValue(p['quantity']);
                        final state = p['status'] ?? '';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: ListTile(
                              title: Text(
                                p['name'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '$quantity ${p['unit'] ?? ''}  •  $state',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) =>
                                    _changeStock(p, intake: v == 'intake'),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'intake',
                                    child: Text('Receive stock'),
                                  ),
                                  PopupMenuItem(
                                    value: 'adjust',
                                    child: Text('Adjust stock'),
                                  ),
                                ],
                                child: const Icon(Icons.more_vert),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: movements.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = movements[i] as Map;
                        final product = m['product'] as Map?;
                        return ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              numberValue(m['quantityChange']) >= 0
                                  ? Icons.south_west
                                  : Icons.north_east,
                            ),
                          ),
                          title: Text(product?['name'] ?? 'Product'),
                          subtitle: Text(
                            '${m['type']}  •  ${m['createdAt'] ?? ''}',
                          ),
                          trailing: Text(
                            '${numberValue(m['quantityChange']) > 0 ? '+' : ''}${m['quantityChange']}',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    ],
  );
}
