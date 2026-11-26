import 'package:flutter/material.dart';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../core/network/connectivity_provider.dart';
import '../core/theme.dart';
import '../core/widgets/app_states.dart';
import '../core/storage/offline_store.dart';
import '../features/stock/data/offline_stock_sync.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key, this.initialAction});
  final String? initialAction;
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 2, vsync: this);
  List products = [], movements = [];
  bool loading = true;
  String? loadError;
  bool showingCache = false;
  List<Map<String, dynamic>> queuedOperations = [];
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
      try {
        await currentUser();
      } catch (error) {
        if (mounted) _msg('Could not refresh account identity: ${apiError(error)}');
      }
      await _saveStockSnapshot();
      showingCache = false;
      loadError = null;
    } catch (e) {
      final cached = await OfflineStore().loadSnapshot('stock');
      if (cached == null) {
        loadError = apiError(e);
      } else {
        final snapshot = Map<String, dynamic>.from(cached['data'] as Map);
        products = snapshot['products'] as List? ?? [];
        movements = snapshot['movements'] as List? ?? [];
        showingCache = true;
        loadError = null;
      }
    }
    queuedOperations = await OfflineStore().loadStockQueueForCurrentUser();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _saveStockSnapshot() async {
    try {
      await OfflineStore().saveSnapshot('stock', {
        'products': products,
        'movements': movements,
      });
    } catch (error) {
      if (mounted) {
        _msg('Could not save stock for offline use: ${apiError(error)}');
      }
    }
  }

  Future<bool> _queueStockChange({
    required String id,
    required String kind,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> product,
    required double quantityChangeInStockUnit,
  }) async {
    try {
      final identity = await OfflineStore().loadIdentity();
      if (identity == null ||
          identity['id'] == null ||
          identity['businessId'] == null) {
        _msg(
          'Reconnect once to securely prepare this device for offline stock updates.',
        );
        return false;
      }
      await OfflineStore().enqueueStockOperation({
        'id': id,
        'kind': kind,
        'payload': payload,
        'userId': identity['id'],
        'businessId': identity['businessId'],
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });
      final index = products.indexWhere(
        (row) => row['id']?.toString() == product['id']?.toString(),
      );
      if (index >= 0) {
        final updated = Map<String, dynamic>.from(products[index] as Map);
        updated['quantity'] =
            numberValue(updated['quantity']) + quantityChangeInStockUnit;
        products[index] = updated;
        await _saveStockSnapshot();
      }
      if (mounted) {
        setState(() => queuedOperations = [...queuedOperations, {
          'id': id,
          'kind': kind,
          'payload': payload,
          'status': 'pending',
        }]);
        _msg('Saved on this device. It will sync when the connection returns.');
      }
      return true;
    } catch (error) {
      if (mounted) _msg('Could not save the stock update offline: ${apiError(error)}');
      return false;
    }
  }

  void _msg(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> _changeStock(
    Map<String, dynamic> p, {
    required bool intake,
  }) async {
    final baseUnit = (p['unit'] ?? 'piece').toString();
    final intakeUnits = <String>{baseUnit};
    final intakeFactors = <String, double>{baseUnit: 1};
    if (intake) {
      try {
        final response = await dio.get('/unit-conversions', queryParameters: {'productId': p['id']});
        for (final value in response.data as List) {
          final row = value as Map;
          if (row['productId'] == null || row['productId']?.toString() == p['id'].toString()) {
            final multiplier = numberValue(row['multiplier']).toDouble();
            if (row['toUnit'] == baseUnit && multiplier > 0) {
              final unit = row['fromUnit'].toString();
              intakeUnits.add(unit);
              intakeFactors[unit] = multiplier;
            }
            if (row['fromUnit'] == baseUnit && multiplier > 0) {
              final unit = row['toUnit'].toString();
              intakeUnits.add(unit);
              intakeFactors[unit] = 1 / multiplier;
            }
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    var selectedUnit = baseUnit;
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
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(intake ? 'Receive stock' : 'Adjust stock'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p['name'] ?? ''),
              if (intake && intakeUnits.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: selectedUnit,
                  decoration: const InputDecoration(labelText: 'Receiving unit'),
                  items: intakeUnits.map((unit) => DropdownMenuItem(value: unit, child: Text(unit))).toList(),
                  onChanged: (value) { if (value != null) setDialogState(() => selectedUnit = value); },
                ),
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
                  decoration: InputDecoration(labelText: 'Cost per $selectedUnit'),
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
                  (intake ? amount <= 0 : amount == 0) ||
                  amount * 1000 != (amount * 1000).roundToDouble() ||
                  (intake &&
                      (unitCost == null ||
                          unitCost < 0 ||
                          unitCost * 100 !=
                              (unitCost * 100).roundToDouble()))) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Enter a valid quantity (up to 3 decimals) and cost (up to 2 decimals).',
                    ),
                  ),
                );
                return;
              }
              try {
                if (intake) {
                  final payload = <String, dynamic>{
                    'productId': p['id'],
                    'quantity': amount,
                    'unitCost': unitCost,
                    'unit': selectedUnit,
                    'supplier': supplier.text.trim().isEmpty
                        ? null
                        : supplier.text.trim(),
                    'reference': reference.text.trim().isEmpty
                        ? null
                        : reference.text.trim(),
                    'notes': notes.text.trim().isEmpty
                        ? null
                        : notes.text.trim(),
                  };
                  await dio.post(
                    '/stock/intake',
                    data: payload,
                    options: Options(headers: {'Idempotency-Key': requestKey}),
                  );
                } else {
                  final payload = <String, dynamic>{
                    'productId': p['id'],
                    'quantityChange': amount,
                    'reason': reason.text.trim().isEmpty
                        ? 'OTHER'
                        : reason.text.trim(),
                    'notes': notes.text.trim().isEmpty
                        ? null
                        : notes.text.trim(),
                  };
                  await dio.post(
                    '/stock/adjustments',
                    data: payload,
                    options: Options(headers: {'Idempotency-Key': requestKey}),
                  );
                }
                if (context.mounted) Navigator.pop(context, true);
              } catch (e) {
                if (e is DioException && e.response == null) {
                  final queued = await _queueStockChange(
                    id: requestKey,
                    kind: intake ? 'intake' : 'adjustment',
                    payload: {
                      'productId': p['id'],
                      if (intake) ...{
                        'quantity': amount,
                        'unitCost': unitCost,
                        'unit': selectedUnit,
                        'supplier': supplier.text.trim().isEmpty
                            ? null
                            : supplier.text.trim(),
                        'reference': reference.text.trim().isEmpty
                            ? null
                            : reference.text.trim(),
                        'notes': notes.text.trim().isEmpty
                            ? null
                            : notes.text.trim(),
                      } else ...{
                        'quantityChange': amount,
                        'reason': reason.text.trim().isEmpty
                            ? 'OTHER'
                            : reason.text.trim(),
                        'notes': notes.text.trim().isEmpty
                            ? null
                            : notes.text.trim(),
                      },
                    },
                    product: p,
                    quantityChangeInStockUnit: intake
                        ? amount * (intakeFactors[selectedUnit] ?? 1)
                        : amount,
                  );
                  if (queued && context.mounted) {
                    Navigator.pop(context, true);
                  }
                  return;
                }
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
      )),
    );
    if (ok == true) {
      await load();
      if (mounted) _msg('Stock updated');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (showingCache || queuedOperations.isNotEmpty)
        _offlineNotice(context),
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
                      separatorBuilder: (_, _) => const SizedBox(height: 7),
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
                      separatorBuilder: (_, _) => const Divider(height: 1),
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

  Widget _offlineNotice(BuildContext context) {
    final failed = queuedOperations
        .where((item) => item['status'] == 'failed')
        .length;
    final pending = queuedOperations.length;
    final failedOperation = failed == 0
        ? null
        : queuedOperations.firstWhere((item) => item['status'] == 'failed');
    final status = showingCache
        ? 'Showing saved stock data; it may be out of date.'
        : [
            '$pending stock change${pending == 1 ? '' : 's'} waiting to sync',
            if (failed > 0)
              '· $failed need review: ${failedOperation?['lastError'] ?? 'retry required'}',
          ].join(' ');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0CC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (pending > 0)
            IconButton(
              tooltip: failed > 0 ? 'Retry failed changes' : 'Sync stock changes',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final connected = ref
                    .read(connectivityProvider)
                    .maybeWhen(
                      data: (results) => results.any(
                        (item) => item != ConnectivityResult.none,
                      ),
                      orElse: () => false,
                    );
                if (!connected) {
                  _msg('Reconnect before retrying stock changes.');
                  return;
                }
                if (failed > 0) {
                  await ref.read(offlineStockSyncProvider).retryFailed();
                } else {
                  await ref.read(offlineStockSyncProvider).syncPending();
                }
                await load();
              },
              icon: const Icon(Icons.sync_rounded, size: 19),
            ),
        ],
      ),
    );
  }
}
