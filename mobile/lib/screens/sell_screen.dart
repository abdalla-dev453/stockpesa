import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/network/connectivity_provider.dart';
import '../core/storage/cart_store.dart';
import '../core/theme.dart';
import '../core/storage/offline_store.dart';
import '../features/sales/domain/sale_math.dart';
import '../features/sales/data/offline_sales_sync.dart';
import 'products_screen.dart' show BarcodeScanScreen;

class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({
    super.key,
    this.paymentStep = false,
    this.initialCustomerId,
    this.initialProductId,
    this.initialScan = false,
  });
  final bool paymentStep;
  final String? initialCustomerId;
  final String? initialProductId;
  final bool initialScan;

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  final _store = CartStore();
  final _search = TextEditingController();
  Timer? _searchDebounce;
  final _discount = TextEditingController();
  final _cashReceived = TextEditingController();
  final _mpesaAmount = TextEditingController();
  final _mpesaReceipt = TextEditingController();
  final _paymentReference = TextEditingController();
  final Map<String, Map<String, dynamic>> _cart = {};
  List<Map<String, dynamic>> _products = [], _customers = [], _categories = [];
  List<Map<String, dynamic>> _parked = [];
  bool _loading = true, _saving = false, _hasCachedProducts = false;
  bool _discountPercent = false;
  String? _loadError, _selectedCategory, _customerId, _overrideReason;
  String _method = 'CASH';
  List<Map<String, dynamic>> _splitTenders = [];
  bool _manualMpesa = false;
  String? _checkoutKey, _checkoutFingerprint;
  String _role = '';
  String _cashierName = '';
  List<Map<String, dynamic>> _offlineSales = [];
  bool _initialProductHandled = false;
  late final Future<void> _restoreFuture;

  bool get _connected => ref
      .read(connectivityProvider)
      .maybeWhen(
        data: (results) =>
            results.any((value) => value != ConnectivityResult.none),
        orElse: () => true,
      );

  double get _subtotal =>
      SaleMath.subtotalCents(
        _cart.values.map(
          (item) => (numberValue(item['sellingPrice']), _qty(item)),
        ),
      ) /
      100;
  double get _discountInput => double.tryParse(_discount.text) ?? 0;
  double get _discountValue => _discountPercent
      ? double.parse((_subtotal * _discountInput / 100).toStringAsFixed(2))
      : _discountInput;
  double get _total =>
      SaleMath.totalCents(
        SaleMath.subtotalCents(
          _cart.values.map(
            (item) => (numberValue(item['sellingPrice']), _qty(item)),
          ),
        ),
        _discountValue,
      ) /
      100;
  double get _cashValue => double.tryParse(_cashReceived.text) ?? 0;
  double get _splitPaid => _splitTenders.fold<double>(
    0,
    (sum, tender) =>
        sum + (double.tryParse(tender['amount']?.toString() ?? '') ?? 0),
  );
  double get _change => max(0, _cashValue - _total).toDouble();
  bool get _canOverride => _role == 'OWNER' || _role == 'MANAGER';

  Map<String, dynamic> _newTender(String method) => {
    'id': DateTime.now().microsecondsSinceEpoch.toString(),
    'method': method,
    'amount': '',
  };

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
    _restoreFuture = _restore();
    _loadCatalog();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchDebounce?.cancel();
    _discount.dispose();
    _cashReceived.dispose();
    _mpesaAmount.dispose();
    _mpesaReceipt.dispose();
    _paymentReference.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final active = await _store.loadActive();
      _parked = await _store.loadParked();
      _offlineSales = await OfflineStore().loadSalesQueueForCurrentUser();
      if (active != null) {
        final checkoutKey = active['checkoutKey']?.toString();
        if (_offlineSales.any((sale) => sale['id'] == checkoutKey)) {
          await _store.clearActive();
        } else {
          for (final raw in active['items'] as List? ?? []) {
            final item = Map<String, dynamic>.from(raw as Map);
            final id = item['id']?.toString();
            if (id != null) _cart[id] = item;
          }
          _method = active['method']?.toString() ?? 'CASH';
          _customerId = active['customerId']?.toString() ?? _customerId;
          _discount.text = active['discount']?.toString() ?? '';
          _discountPercent = active['discountPercent'] == true;
          _cashReceived.text = active['cashReceived']?.toString() ?? '';
          _manualMpesa = active['manualMpesa'] == true;
          _mpesaAmount.text = active['mpesaAmount']?.toString() ?? '';
          _mpesaReceipt.text = active['mpesaReceipt']?.toString() ?? '';
          _paymentReference.text = active['paymentReference']?.toString() ?? '';
          _splitTenders = (active['tenders'] as List? ?? [])
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
          _checkoutKey = active['checkoutKey']?.toString();
          _checkoutFingerprint = active['checkoutFingerprint']?.toString();
          _overrideReason = active['overrideReason']?.toString();
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        _message(
          'Could not restore the saved cart. Start a new sale or retry.',
        );
      }
    }
  }

  Future<void> _persist() async {
    final state = <String, dynamic>{
      'items': _cart.values.toList(),
      'method': _method,
      'customerId': _customerId,
      'discount': _discount.text,
      'discountPercent': _discountPercent,
      'cashReceived': _cashReceived.text,
      'manualMpesa': _manualMpesa,
      'mpesaAmount': _mpesaAmount.text,
      'mpesaReceipt': _mpesaReceipt.text,
      'paymentReference': _paymentReference.text,
      'tenders': _splitTenders,
      'checkoutKey': _checkoutKey,
      'checkoutFingerprint': _checkoutFingerprint,
      'overrideReason': _overrideReason,
    };
    await _store.saveActive(state);
  }

  Future<void> _loadCatalog({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      if (!_connected) {
        throw DioException(requestOptions: RequestOptions(path: '/products'));
      }
      final responses = await Future.wait([
        dio.get(
          '/products',
          queryParameters: {
            if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
            if (_selectedCategory != null && _selectedCategory!.isNotEmpty)
              'categoryId': _selectedCategory,
            'stockStatus': 'ALL',
            'page': 1,
            'limit': 30,
          },
        ),
        dio.get('/categories'),
        dio.get('/customers'),
        dio.get('/auth/me'),
      ]);
      _products = ((responses[0].data as Map)['data'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _categories = (responses[1].data as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _customers = (responses[2].data as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final user = responses[3].data as Map;
      _role = user['role']?.toString() ?? '';
      _cashierName = user['fullName']?.toString() ?? '';
      _loadError = null;
      _hasCachedProducts = false;
      await _store.saveProducts(_products);
      if (_customerId != null &&
          !_customers.any((c) => c['id'] == _customerId)) {
        _customerId = null;
      }
    } catch (error) {
      _loadError = apiError(error);
      try {
        final cached = await _store.loadProducts();
        if (cached.isNotEmpty) {
          _products = cached;
          _hasCachedProducts = true;
        } else {
          final catalog = await _store.loadCatalog();
          if (catalog != null) {
            _products = (catalog['products'] as List? ?? [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList();
            _categories = (catalog['categories'] as List? ?? [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList();
            _hasCachedProducts = _products.isNotEmpty;
          }
        }
      } catch (_) {
        _loadError =
            'The saved catalog could not be opened. Reconnect and try again.';
      }
      if (_search.text.trim().isNotEmpty) {
        final term = _search.text.trim().toLowerCase();
        _products = _products.where((product) {
          return [product['name'], product['sku'], product['barcode']].any(
            (value) => value?.toString().toLowerCase().contains(term) == true,
          );
        }).toList();
      }
    }
    if (_cashReceived.text.isEmpty && _method == 'CASH' && _cart.isNotEmpty) {
      _cashReceived.text = _total.toStringAsFixed(2);
    }
    if (mounted) setState(() => _loading = false);
    if (!_initialProductHandled &&
        (widget.initialProductId != null || widget.initialScan)) {
      _initialProductHandled = true;
      await _restoreFuture;
      if (!mounted) return;
      if (widget.initialScan) {
        await _scanBarcode();
      } else {
        final cached = _products
            .where(
              (product) => product['id']?.toString() == widget.initialProductId,
            )
            .firstOrNull;
        if (cached != null) {
          await _add(cached);
        } else if (_loadError == null) {
          try {
            final product = Map<String, dynamic>.from(
              (await dio.get('/products/${widget.initialProductId}')).data
                  as Map,
            );
            if (mounted) await _add(product);
          } catch (error) {
            if (mounted) _message(apiError(error));
          }
        } else if (mounted) {
          _message(
            'This product is not saved on this device. Reconnect to sell it.',
          );
        }
      }
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  Future<void> _refreshOfflineSales() async {
    final queued = await OfflineStore().loadSalesQueueForCurrentUser();
    if (mounted) setState(() => _offlineSales = queued);
  }

  double _qty(Map<String, dynamic> item) =>
      numberValue(item['_qty']).toDouble();
  double _available(Map<String, dynamic> item) =>
      numberValue(item['quantity']).toDouble();

  Future<bool> _confirmNegativeStock() async {
    if (!_canOverride) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow negative stock?'),
        content: const Text(
          'This sale will take the product below zero. StockPesa will record the NEGATIVE_STOCK_OVERRIDE reason in the audit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow this sale'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<void> _setQuantity(
    Map<String, dynamic> product,
    double quantity,
  ) async {
    final id = product['id'].toString();
    if (quantity <= 0) {
      setState(() => _cart.remove(id));
      await _persist();
      return;
    }
    if (quantity > _available(product)) {
      if (!_canOverride) {
        _message(
          _available(product) <= 0
              ? 'This product is out of stock.'
              : 'Only ${_available(product)} available.',
        );
        return;
      }
      final approved = await _confirmNegativeStock();
      if (!approved) return;
      _overrideReason = 'NEGATIVE_STOCK_OVERRIDE';
    }
    setState(() {
      _cart[id] = {...product, '_qty': quantity};
      if (_cart.values.every((item) => _qty(item) <= _available(item))) {
        _overrideReason = null;
      }
    });
    await _persist();
  }

  Future<void> _add(Map<String, dynamic> product) async {
    if (product['variantId'] == null) {
      final existing = _cart[product['id'].toString()];
      if (existing != null) {
        await _setQuantity(existing, _qty(existing) + 1);
        return;
      }
      if (_connected) {
        try {
          final variants =
              ((await dio.get('/products/${product['id']}/variants')).data
                      as List)
                  .where((value) => (value as Map)['active'] != false)
                  .toList();
          if (variants.isNotEmpty && mounted) {
            final selected = await showModalBottomSheet<Map<String, dynamic>>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(title: Text('Choose size or type')),
                    ...variants.map((value) {
                      final row = Map<String, dynamic>.from(value as Map);
                      return ListTile(
                        title: Text(row['name']?.toString() ?? 'Variant'),
                        subtitle: Text(
                          '${row['quantity'] ?? 0} available · ${kes(numberValue(row['sellingPrice']))}',
                        ),
                        onTap: () => Navigator.pop(context, {
                          ...row,
                          'id': row['id'],
                          'variantId': row['id'],
                          'parentProductId': product['id'],
                          'name': '${product['name']} · ${row['name']}',
                        }),
                      );
                    }),
                  ],
                ),
              ),
            );
            if (selected == null) return;
            product = selected;
          }
        } catch (error) {
          _message(apiError(error));
          return;
        }
      }
    }
    if (_connected && product['variantId'] == null) {
      try {
        final baseUnit = product['unit'].toString();
        final rows =
            (await dio.get(
                  '/unit-conversions',
                  queryParameters: {'productId': product['id']},
                )).data
                as List;
        final choices = <Map<String, dynamic>>[
          {'unit': baseUnit, 'factor': 1.0},
        ];
        for (final value in rows) {
          final row = value as Map;
          if (row['productId'] != null &&
              row['productId']?.toString() != product['id'].toString())
            continue;
          final multiplier = numberValue(row['multiplier']).toDouble();
          if (row['toUnit'] == baseUnit)
            choices.add({
              'unit': row['fromUnit'].toString(),
              'factor': multiplier,
            });
          if (row['fromUnit'] == baseUnit && multiplier != 0)
            choices.add({
              'unit': row['toUnit'].toString(),
              'factor': 1 / multiplier,
            });
        }
        if (choices.length > 1 && mounted) {
          final choice = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Choose selling unit')),
                  for (final option in choices)
                    ListTile(
                      title: Text(option['unit'].toString()),
                      subtitle: Text(
                        '${kes(numberValue(product['sellingPrice']) * (option['factor'] as double))} each',
                      ),
                      onTap: () => Navigator.pop(context, option),
                    ),
                ],
              ),
            ),
          );
          if (choice == null) return;
          final factor = choice['factor'] as double;
          product = {
            ...product,
            'unit': choice['unit'],
            '_saleUnit': choice['unit'],
            '_unitFactor': factor,
            'sellingPrice': numberValue(product['sellingPrice']) * factor,
            'quantity': numberValue(product['quantity']) / factor,
          };
        }
      } catch (error) {
        _message(apiError(error));
        return;
      }
    }
    final id = product['id'].toString();
    await _setQuantity(product, (_cart[id] == null ? 0 : _qty(_cart[id]!)) + 1);
  }

  Future<void> _editQuantity(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: _qty(item).toString());
    final quantity = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quantity · ${item['name']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity (${item['unit'] ?? 'units'})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (quantity != null) {
      if (quantity * 1000 != (quantity * 1000).roundToDouble()) {
        _message('Quantity supports up to three decimal places.');
        return;
      }
      await _setQuantity(item, quantity);
    }
  }

  Future<void> _clearCart() async {
    if (_cart.isEmpty) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this cart?'),
        content: const Text(
          'All current items and this sale’s discount will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep cart'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear cart'),
          ),
        ],
      ),
    );
    if (clear != true) return;
    setState(() {
      _cart.clear();
      _discount.clear();
      _discountPercent = false;
      _cashReceived.clear();
      _mpesaAmount.clear();
      _mpesaReceipt.clear();
      _paymentReference.clear();
      _splitTenders.clear();
      _manualMpesa = false;
      _checkoutKey = null;
      _checkoutFingerprint = null;
      _overrideReason = null;
    });
    await _persist();
  }

  Future<void> _parkCart() async {
    if (_cart.isEmpty) {
      _message('Add items before parking this sale.');
      return;
    }
    final parked = await _store.loadParked();
    parked.insert(0, {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'label': 'Sale · ${DateTime.now().toLocal()}',
      'items': _cart.values.toList(),
      'method': _method,
      'customerId': _customerId,
      'discount': _discount.text,
      'discountPercent': _discountPercent,
      'cashReceived': _cashReceived.text,
      'manualMpesa': _manualMpesa,
      'mpesaAmount': _mpesaAmount.text,
      'mpesaReceipt': _mpesaReceipt.text,
      'paymentReference': _paymentReference.text,
      'tenders': _splitTenders,
      'overrideReason': _overrideReason,
    });
    await _store.saveParked(parked);
    setState(() {
      _parked = parked;
      _cart.clear();
      _method = 'CASH';
      _customerId = null;
      _discount.clear();
      _discountPercent = false;
      _cashReceived.clear();
      _mpesaAmount.clear();
      _mpesaReceipt.clear();
      _paymentReference.clear();
      _splitTenders.clear();
      _manualMpesa = false;
      _overrideReason = null;
      _checkoutKey = null;
      _checkoutFingerprint = null;
    });
    await _persist();
    _message('Sale parked on this device. It has not been sent to StockPesa.');
  }

  Future<void> _openParked() async {
    final parked = await _store.loadParked();
    if (!mounted) return;
    if (parked.isEmpty) {
      _message('No parked sales on this device.');
      return;
    }
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Parked sales',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final row in parked)
              ListTile(
                leading: const Icon(Icons.pause_circle_outline),
                title: Text(row['label']?.toString() ?? 'Parked sale'),
                subtitle: Text(
                  '${(row['items'] as List? ?? []).length} products · KES ${_parkedTotal(row).toStringAsFixed(2)}',
                ),
                onTap: () => Navigator.pop(context, row),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final remaining = parked
        .where((row) => row['id'] != selected['id'])
        .toList();
    if (_cart.isNotEmpty) {
      remaining.insert(0, {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'label': 'Sale · ${DateTime.now().toLocal()}',
        'items': _cart.values.toList(),
        'method': _method,
        'customerId': _customerId,
        'discount': _discount.text,
        'discountPercent': _discountPercent,
        'cashReceived': _cashReceived.text,
        'manualMpesa': _manualMpesa,
        'mpesaAmount': _mpesaAmount.text,
        'mpesaReceipt': _mpesaReceipt.text,
        'paymentReference': _paymentReference.text,
        'tenders': _splitTenders,
        'overrideReason': _overrideReason,
      });
    }
    await _store.saveParked(remaining);
    setState(() {
      _cart
        ..clear()
        ..addEntries(
          (selected['items'] as List).map((row) {
            final item = Map<String, dynamic>.from(row as Map);
            return MapEntry(item['id'].toString(), item);
          }),
        );
      _method = selected['method']?.toString() ?? 'CASH';
      _customerId = selected['customerId']?.toString();
      _discount.text = selected['discount']?.toString() ?? '';
      _discountPercent = selected['discountPercent'] == true;
      _cashReceived.text = selected['cashReceived']?.toString() ?? '';
      _manualMpesa = selected['manualMpesa'] == true;
      _mpesaAmount.text = selected['mpesaAmount']?.toString() ?? '';
      _mpesaReceipt.text = selected['mpesaReceipt']?.toString() ?? '';
      _paymentReference.text = selected['paymentReference']?.toString() ?? '';
      _splitTenders = (selected['tenders'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _overrideReason = selected['overrideReason']?.toString();
      _parked = remaining;
      _checkoutKey = null;
      _checkoutFingerprint = null;
    });
    await _persist();
    if (widget.paymentStep && mounted) context.go('/sell');
  }

  double _parkedTotal(Map<String, dynamic> row) {
    final subtotal = (row['items'] as List? ?? []).fold<double>(0, (
      sum,
      value,
    ) {
      final item = value as Map;
      return sum +
          numberValue(item['sellingPrice']) * numberValue(item['_qty']);
    });
    return max(0, subtotal - numberValue(row['discount'])).toDouble();
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code == null || !mounted) return;
    try {
      final product = Map<String, dynamic>.from(
        (await dio.get(
              '/products/lookup',
              queryParameters: {'barcode': code},
            )).data
            as Map,
      );
      await _add(product);
    } catch (error) {
      final cached = _products
          .where((product) => product['barcode']?.toString() == code)
          .firstOrNull;
      if (cached != null) {
        _message(
          'Using the saved product record. Stock will be checked when online.',
        );
        await _add(cached);
      } else if (error is DioException && error.response?.statusCode == 404) {
        _message('Barcode not found. Add a product with this barcode.');
        if (mounted) {
          context.go('/products/add?barcode=${Uri.encodeComponent(code)}');
        }
      } else if (!_connected) {
        _message(
          'This barcode is not in the saved catalog. Reconnect to look it up.',
        );
      } else {
        _message(apiError(error));
      }
    }
  }

  void _continueToPayment() {
    if (_cart.isEmpty) {
      _message('Add products to the cart first.');
      return;
    }
    if (!_discountInput.isFinite ||
        _discountInput < 0 ||
        (_discountPercent
            ? _discountInput > 100
            : _discountInput > _subtotal)) {
      _message(
        _discountPercent
            ? 'Discount must be between 0 and 100%.'
            : 'Discount must be between zero and the subtotal.',
      );
      return;
    }
    _persist();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .94,
        child: _buildPaymentStep(_connected),
      ),
    );
  }

  Future<void> _createCustomer() async {
    final name = TextEditingController(),
        phone = TextEditingController(),
        limit = TextEditingController();
    final customer = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
            TextField(
              controller: limit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: 'Credit limit (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) {
                _message('Enter the customer name.');
                return;
              }
              final creditLimit = limit.text.trim().isEmpty
                  ? null
                  : double.tryParse(limit.text.trim());
              if (limit.text.trim().isNotEmpty &&
                  (creditLimit == null || creditLimit < 0)) {
                _message('Enter a valid non-negative credit limit.');
                return;
              }
              try {
                final response = await dio.post(
                  '/customers',
                  data: {
                    'name': name.text.trim(),
                    'phone': phone.text.trim().isEmpty
                        ? null
                        : phone.text.trim(),
                    'creditLimit': ?creditLimit,
                  },
                );
                if (context.mounted) {
                  Navigator.pop(
                    context,
                    Map<String, dynamic>.from(response.data as Map),
                  );
                }
              } catch (error) {
                if (context.mounted) _message(apiError(error));
              }
            },
            child: const Text('Save customer'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    limit.dispose();
    if (customer != null && mounted) {
      setState(() {
        _customers.add(customer);
        _customerId = customer['id']?.toString();
      });
      await _persist();
    }
  }

  Future<void> _selectCustomer() async {
    final search = TextEditingController();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final term = search.text.trim().toLowerCase();
          final customers = _customers.where((customer) {
            return term.isEmpty ||
                customer['name']?.toString().toLowerCase().contains(term) ==
                    true ||
                customer['phone']?.toString().toLowerCase().contains(term) ==
                    true;
          }).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: TextField(
                      controller: search,
                      autofocus: true,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search name or phone',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Walk-in customer'),
                    onTap: () => Navigator.pop(context, '__walkin__'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_add_alt_1),
                    title: const Text('Add customer'),
                    onTap: () => Navigator.pop(context, '__add__'),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: customers.length,
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        return ListTile(
                          title: Text(
                            customer['name']?.toString() ?? 'Customer',
                          ),
                          subtitle: Text(
                            '${customer['phone'] ?? 'No phone'} · Due ${kes(numberValue(customer['balance']))}',
                          ),
                          onTap: () => Navigator.pop(
                            context,
                            customer['id']?.toString(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    search.dispose();
    if (selected == null || !mounted) return;
    if (selected == '__add__') {
      await _createCustomer();
      return;
    }
    setState(() => _customerId = selected == '__walkin__' ? null : selected);
    await _persist();
  }

  Future<void> _checkout() async {
    final connected = _connected;
    if (_cart.isEmpty) {
      _message('The cart is empty.');
      return;
    }
    if (!_discountInput.isFinite ||
        _discountInput < 0 ||
        (_discountPercent
            ? _discountInput > 100
            : _discountInput > _subtotal)) {
      _message('Discount must be between zero and the subtotal.');
      return;
    }
    if (_method == 'CREDIT' && _customerId == null) {
      _message('Select or add a customer for a credit sale.');
      return;
    }
    if (!connected && _method != 'CASH') {
      _message(
        'Only cash sales can be saved offline. Reconnect for other payments.',
      );
      return;
    }
    final customer = _customers
        .where((row) => row['id'] == _customerId)
        .firstOrNull;
    final paid = switch (_method) {
      'CREDIT' => 0.0,
      'CASH' => min(_cashValue, _total).toDouble(),
      'MPESA' when _manualMpesa =>
        double.tryParse(_mpesaAmount.text.trim()) ?? 0.0,
      'SPLIT' => _splitPaid,
      _ => _total,
    };
    if (!paid.isFinite || paid < 0) {
      _message('Enter a valid payment amount.');
      return;
    }
    if (!connected && (_method != 'CASH' || paid < _total)) {
      _message('Offline sales must be paid in full with cash.');
      return;
    }
    if (_method == 'MPESA' && _manualMpesa) {
      final receipt = _mpesaReceipt.text.trim();
      if (!RegExp(r'^[A-Za-z0-9]{6,32}$').hasMatch(receipt)) {
        _message(
          'Enter a valid M-Pesa receipt number (6–32 letters or digits).',
        );
        return;
      }
      if (paid <= 0 || paid > _total) {
        _message(
          'Enter an M-Pesa amount greater than zero and no more than the sale total.',
        );
        return;
      }
    }
    if (_method == 'SPLIT') {
      final methods = _splitTenders
          .map((tender) => tender['method']?.toString())
          .toSet();
      if (_splitTenders.length < 2 || methods.length < 2) {
        _message('Choose at least two different payment methods.');
        return;
      }
      for (final tender in _splitTenders) {
        final method = tender['method']?.toString();
        final amount = double.tryParse(tender['amount']?.toString() ?? '');
        if (amount == null || !amount.isFinite || amount <= 0) {
          _message('Enter an amount above zero for every payment method.');
          return;
        }
        if (method == 'MPESA' &&
            !RegExp(
              r'^[A-Za-z0-9]{6,32}$',
            ).hasMatch(tender['mpesaReceiptNumber']?.toString() ?? '')) {
          _message('Enter a valid M-Pesa confirmation code for the payment.');
          return;
        }
        if ((method == 'BANK' || method == 'CARD') &&
            (tender['reference']?.toString().trim().isEmpty ?? true)) {
          _message(
            'Enter a reference for the ${method!.toLowerCase()} payment.',
          );
          return;
        }
      }
      if (_splitPaid > _total) {
        _message('Split payment amounts cannot exceed the sale total.');
        return;
      }
    }
    final balance = _total - paid;
    if (balance > 0 && _customerId == null) {
      _message('Select a customer to record the unpaid balance.');
      return;
    }
    if (customer != null &&
        customer['creditLimit'] != null &&
        numberValue(customer['balance']) + balance >
            numberValue(customer['creditLimit'])) {
      _message('This sale would exceed ${customer['name']}’s credit limit.');
      return;
    }
    if (_method == 'MPESA' && !_manualMpesa) {
      try {
        final config = (await dio.get('/payments/mpesa/config')).data as Map;
        if (config['mockEnabled'] != true) {
          _message(
            'M-Pesa is not configured by the API. No sale was recorded.',
          );
          return;
        }
      } catch (error) {
        _message(apiError(error));
        return;
      }
    }
    if ((_method == 'BANK' || _method == 'CARD') &&
        _paymentReference.text.trim().isEmpty) {
      _message(
        'Enter the ${_method == 'BANK' ? 'bank transfer' : 'card'} reference.',
      );
      return;
    }
    if (_cart.values.any((item) => _qty(item) > _available(item)) &&
        (!_canOverride || _overrideReason != 'NEGATIVE_STOCK_OVERRIDE')) {
      _message(
        _canOverride
            ? 'Confirm the negative stock override before checkout.'
            : 'A cashier cannot sell more than available stock.',
      );
      return;
    }

    final request = <String, dynamic>{
      'items': _cart.values
          .map(
            (item) => {
              if (item['variantId'] != null)
                'variantId': item['variantId']
              else
                'productId': item['id'],
              if (item['_saleUnit'] != null) 'unit': item['_saleUnit'],
              'quantity': _qty(item),
            },
          )
          .toList(),
      'method': _method == 'SPLIT' ? 'CASH' : _method,
      'amountPaid': paid,
      if (_method == 'SPLIT')
        'tenders': _splitTenders
            .map(
              (tender) => {
                'method': tender['method'],
                'amount': double.parse(tender['amount'].toString()),
                if (tender['method'] == 'MPESA')
                  'mpesaReceiptNumber': tender['mpesaReceiptNumber']
                      .toString()
                      .trim()
                      .toUpperCase(),
                if (tender['method'] == 'BANK' || tender['method'] == 'CARD')
                  'reference': tender['reference'].toString().trim(),
              },
            )
            .toList(),
      if (_method == 'MPESA' && _manualMpesa)
        'mpesaReceiptNumber': _mpesaReceipt.text.trim().toUpperCase(),
      if ((_method == 'BANK' || _method == 'CARD') &&
          _paymentReference.text.trim().isNotEmpty)
        'paymentReference': _paymentReference.text.trim(),
      if (_customerId != null) 'customerId': _customerId,
      if (_discountValue > 0)
        'discount': double.parse(_discountValue.toStringAsFixed(2)),
      if (_overrideReason != null) 'overrideReason': _overrideReason,
    };
    final fingerprint = jsonEncode(request);
    if (_checkoutKey == null || _checkoutFingerprint != fingerprint) {
      _checkoutKey = List.generate(
        32,
        (_) => Random.secure().nextInt(16).toRadixString(16),
      ).join();
      _checkoutFingerprint = fingerprint;
      await _persist();
    }
    setState(() => _saving = true);
    try {
      if (!connected) {
        await _saveOfflineCashSale(request);
        return;
      }
      final response = await dio.post(
        '/sales',
        data: request,
        options: Options(headers: {'Idempotency-Key': _checkoutKey}),
      );
      final sale = Map<String, dynamic>.from(response.data as Map);
      if (_method == 'MPESA' && !_manualMpesa) {
        final payment = (sale['payments'] as List? ?? []).firstOrNull;
        if (payment != null && payment['status'] == 'PENDING') {
          await dio.post('/payments/mpesa/mock/${payment['id']}/confirm');
        }
      }
      await HapticFeedback.mediumImpact();
      await _store.clearActive();
      if (!mounted) return;
      context.go(
        '/sell/success/${sale['id']}',
        extra: {'method': _method, 'cashReceived': _cashValue},
      );
    } catch (error) {
      if (error is DioException &&
          error.response == null &&
          _method == 'CASH' &&
          _cashValue >= _total) {
        try {
          await _saveOfflineCashSale(request);
        } catch (storageError) {
          _message('Sale was not saved offline: ${apiError(storageError)}');
        }
      } else {
        _message(apiError(error));
      }
      // The request key and cart stay saved so a manual retry cannot duplicate a sale.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOfflineCashSale(Map<String, dynamic> request) async {
    final cashReceived = _cashValue;
    final changeDue = _change;
    final saleTotal = _total;
    final identity = await OfflineStore().loadIdentity();
    if (identity == null ||
        identity['id'] == null ||
        identity['businessId'] == null) {
      throw StateError(
        'Reconnect once to prepare this device before recording offline sales.',
      );
    }
    final operationId = _checkoutKey;
    if (operationId == null) {
      throw StateError(
        'Sale reference is missing. Keep the cart and try again.',
      );
    }
    await OfflineStore().enqueueOfflineSale({
      'id': operationId,
      'request': request,
      'userId': identity['id'],
      'businessId': identity['businessId'],
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'total': saleTotal,
      'cashReceived': cashReceived,
      'change': changeDue,
      'items': _cart.values
          .map(
            (item) => {
              'name': item['name'],
              'quantity': _qty(item),
              'unit': item['_saleUnit'] ?? item['unit'],
              'unitPrice': item['sellingPrice'],
            },
          )
          .toList(),
    });
    try {
      await _applyOfflineStock();
    } catch (error) {
      if (mounted) {
        _message(
          'Sale saved; cached stock could not be updated: ${apiError(error)}',
        );
      }
    }
    try {
      await _store.clearActive();
    } catch (error) {
      if (mounted) {
        _message('Sale saved. The cart will be cleared when you reopen Sell.');
      }
    }
    if (mounted) {
      setState(() {
        _offlineSales = [
          ..._offlineSales,
          {
            'id': operationId,
            'status': 'pending',
            'total': _total,
            'createdAt': DateTime.now().toIso8601String(),
          },
        ];
        _cart.clear();
        _discount.clear();
        _discountPercent = false;
        _cashReceived.clear();
        _mpesaAmount.clear();
        _mpesaReceipt.clear();
        _paymentReference.clear();
        _manualMpesa = false;
        _splitTenders.clear();
        _customerId = null;
        _checkoutKey = null;
        _checkoutFingerprint = null;
        _overrideReason = null;
      });
    }
    await _persist();
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: C.warn),
            SizedBox(width: 10),
            Expanded(child: Text('Sale saved on this device')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local receipt · ${operationId.substring(0, 8).toUpperCase()}',
            ),
            const SizedBox(height: 8),
            Text('Total ${kes(saleTotal)}'),
            Text(
              'Cash received ${kes(cashReceived)} · Change ${kes(changeDue)}',
            ),
            const SizedBox(height: 8),
            const Text(
              'Not synced yet. Keep this screen open or reconnect; StockPesa will send the sale once the connection returns.',
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ready for next sale'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyOfflineStock() async {
    final updated = _products.map((product) {
      final item = _cart[product['id']?.toString()];
      if (item == null || item['variantId'] != null) return product;
      final factor = numberValue(item['_unitFactor']).toDouble();
      return {
        ...product,
        'quantity':
            numberValue(product['quantity']) -
            _qty(item) * (factor == 0 ? 1 : factor),
      };
    }).toList();
    _products = updated;
    await _store.saveProducts(updated);
    await _store.saveCatalog(updated, _categories);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectivityProvider, (_, next) {
      final connected = next.asData?.value.any(
        (value) => value != ConnectivityResult.none,
      );
      if (connected == true) {
        unawaited(() async {
          await ref.read(offlineSalesSyncProvider).syncPending();
          await _refreshOfflineSales();
        }());
      }
    });
    final connected = ref
        .watch(connectivityProvider)
        .maybeWhen(
          data: (results) =>
              results.any((value) => value != ConnectivityResult.none),
          orElse: () => false,
        );
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : widget.paymentStep
        ? _buildPaymentStep(connected)
        : _buildSaleStep(connected);
  }

  Widget _buildSaleStep(bool connected) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sell',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${_cashierName.isEmpty ? 'Attendant' : _cashierName} · ${businessDate(DateTime.now())} ${TimeOfDay.now().format(context)}',
                    style: TextStyle(color: mutedOn(context), fontSize: 12),
                  ),
                ],
              ),
            ),
            _connectionBadge(connected),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 250),
                    () => _loadCatalog(),
                  );
                },
                onSubmitted: (_) {
                  _searchDebounce?.cancel();
                  _loadCatalog();
                },
                decoration: InputDecoration(
                  labelText: 'Search name, SKU, or barcode',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () {
                      _searchDebounce?.cancel();
                      _loadCatalog();
                    },
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Scan barcode',
              onPressed: _scanBarcode,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton(
              tooltip: 'Parked sales',
              onPressed: _openParked,
              icon: Badge(
                isLabelVisible: _parked.isNotEmpty,
                label: Text('${_parked.length}'),
                child: const Icon(Icons.pause_circle_outline),
              ),
            ),
          ],
        ),
      ),
      if (_hasCachedProducts)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Showing products saved on this device. Their stock may have changed; StockPesa checks stock when you reconnect.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      if (_offlineSales.isNotEmpty) _offlineSalesBanner(connected),
      if (_categories.isNotEmpty)
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedCategory == null,
                  onSelected: (_) {
                    setState(() => _selectedCategory = null);
                    _loadCatalog();
                  },
                ),
              ),
              for (final category in _categories)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(category['name']?.toString() ?? 'Category'),
                    selected: _selectedCategory == category['id'],
                    onSelected: (_) {
                      setState(
                        () => _selectedCategory = category['id']?.toString(),
                      );
                      _loadCatalog();
                    },
                  ),
                ),
            ],
          ),
        ),
      Expanded(
        child: _loadError != null && _products.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _loadCatalog(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _products.isEmpty
            ? const Center(
                child: Text(
                  'No products found. Add a product or change your search.',
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _loadCatalog(showLoading: false),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                  itemCount: _products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    final quantity = _available(product);
                    final minimum = numberValue(product['minStock']);
                    final outOfStock = quantity <= 0;
                    final lowStock =
                        !outOfStock && minimum > 0 && quantity <= minimum;
                    final cartQty = _cart[product['id']] == null
                        ? 0
                        : _qty(_cart[product['id']]!);
                    return Card(
                      child: ListTile(
                        title: Text(
                          product['name']?.toString() ?? 'Product',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${kes(numberValue(product['sellingPrice']))}  ·  $quantity ${product['unit'] ?? 'units'}${outOfStock
                              ? ' · Out of stock'
                              : lowStock
                              ? ' · Low stock'
                              : ' available'}',
                          style: TextStyle(
                            color: outOfStock
                                ? C.danger
                                : lowStock
                                ? C.warn
                                : null,
                            fontWeight: outOfStock || lowStock
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Add to sale',
                          onPressed: outOfStock && !_canOverride
                              ? null
                              : () => _add(product),
                          icon: Icon(
                            cartQty > 0
                                ? Icons.add_circle
                                : Icons.add_circle_outline,
                            color: C.emerald,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
      if (_cart.isNotEmpty) _cartSummary(),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _cart.isEmpty ? null : _parkCart,
                icon: const Icon(Icons.pause),
                label: const Text('Park'),
              ),
              const SizedBox(width: 8),
              if (_cart.isNotEmpty)
                IconButton(
                  tooltip: 'Clear cart',
                  onPressed: _clearCart,
                  icon: const Icon(Icons.delete_outline),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _cart.isEmpty ? null : _continueToPayment,
                icon: const Icon(Icons.point_of_sale),
                label: Text(
                  'Complete Sale · ${kes(_total)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _cartSummary() => Card(
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_cart.length} ${_cart.length == 1 ? 'product' : 'products'} in sale · ${kes(_total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: _openParked,
                child: Text('Parked ${_parked.length}'),
              ),
            ],
          ),
          for (final entry in _cart.entries)
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.value['name']?.toString() ?? 'Product',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove one',
                  onPressed: () =>
                      _setQuantity(entry.value, _qty(entry.value) - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                InkWell(
                  onTap: () => _editQuantity(entry.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      _qty(entry.value).toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add one',
                  onPressed: () =>
                      _setQuantity(entry.value, _qty(entry.value) + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                SizedBox(
                  width: 82,
                  child: Text(
                    kes(
                      _qty(entry.value) *
                          numberValue(entry.value['sellingPrice']),
                    ),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove item',
                  onPressed: () => _setQuantity(entry.value, 0),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          Row(
            children: [
              const Expanded(child: Text('Discount')),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('KES')),
                  ButtonSegment(value: true, label: Text('%')),
                ],
                selected: {_discountPercent},
                onSelectionChanged: (value) {
                  setState(() {
                    _discountPercent = value.first;
                  });
                  _persist();
                },
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _discount,
                  textAlign: TextAlign.end,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    prefixText: _discountPercent ? null : 'KES ',
                    suffixText: _discountPercent ? '%' : null,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _persist();
                  },
                ),
              ),
            ],
          ),
          const Row(
            children: [
              Expanded(child: Text('Tax')),
              Text('Not configured'),
            ],
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                kes(_total),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _connectionBadge(bool connected) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: connected
          ? C.ok.withValues(alpha: .10)
          : C.warn.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          size: 16,
          color: connected ? C.ok : C.warn,
        ),
        const SizedBox(width: 5),
        Text(
          connected ? 'Online' : 'Offline',
          style: TextStyle(
            color: connected ? C.ok : C.warn,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _offlineSalesBanner(bool connected) {
    final failed = _offlineSales.where((sale) => sale['status'] == 'failed');
    final failedCount = failed.length;
    final firstFailure = failedCount == 0 ? null : failed.first;
    final status = failedCount > 0
        ? '$failedCount sale${failedCount == 1 ? '' : 's'} need review · ${firstFailure?['lastError'] ?? 'Check stock and retry'}'
        : '${_offlineSales.length} offline sale${_offlineSales.length == 1 ? '' : 's'} waiting to sync';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0CC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (connected)
            IconButton(
              tooltip: failedCount > 0 ? 'Retry failed sales' : 'Sync sales',
              onPressed: () async {
                if (failedCount > 0) {
                  await ref.read(offlineSalesSyncProvider).retryFailed();
                } else {
                  await ref.read(offlineSalesSyncProvider).syncPending();
                }
                await _refreshOfflineSales();
              },
              icon: const Icon(Icons.sync),
            ),
        ],
      ),
    );
  }

  Widget _splitTenderEditor(int index) {
    final tender = _splitTenders[index];
    final tenderId = tender['id']?.toString() ?? 'legacy-$index';
    final method = tender['method']?.toString() ?? 'CASH';
    const methods = [
      ('CASH', 'Cash'),
      ('MPESA', 'M-Pesa'),
      ('BANK', 'Bank transfer'),
      ('CARD', 'Card'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('split-$tenderId-$method'),
                  initialValue: method,
                  decoration: InputDecoration(
                    labelText: 'Payment ${index + 1}',
                  ),
                  items: [
                    for (final option in methods)
                      DropdownMenuItem(
                        value: option.$1,
                        child: Text(option.$2),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _splitTenders[index] = {
                        ...tender,
                        'id': tenderId,
                        'method': value,
                      };
                    });
                    _persist();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('split-$tenderId-amount'),
                  initialValue: tender['amount']?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount (KES)'),
                  onChanged: (value) {
                    _splitTenders[index]['amount'] = value;
                    setState(() {});
                    _persist();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remove payment',
                onPressed: () {
                  setState(() => _splitTenders.removeAt(index));
                  _persist();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (method == 'MPESA')
            TextFormField(
              key: ValueKey('split-$tenderId-mpesa'),
              initialValue: tender['mpesaReceiptNumber']?.toString() ?? '',
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              decoration: const InputDecoration(
                labelText: 'M-Pesa confirmation code',
              ),
              onChanged: (value) {
                _splitTenders[index]['mpesaReceiptNumber'] = value;
                _persist();
              },
            ),
          if (method == 'BANK' || method == 'CARD')
            TextFormField(
              key: ValueKey('split-$tenderId-reference'),
              initialValue: tender['reference']?.toString() ?? '',
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText:
                    '${method == 'BANK' ? 'Bank transfer' : 'Card'} reference',
              ),
              onChanged: (value) {
                _splitTenders[index]['reference'] = value;
                _persist();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentStep(bool connected) {
    final customer = _customers
        .where((row) => row['id'] == _customerId)
        .firstOrNull;
    final balance = customer == null ? 0 : numberValue(customer['balance']);
    final limit = customer?['creditLimit'] == null
        ? null
        : numberValue(customer!['creditLimit']);
    final shortBy = switch (_method) {
      'CASH' => max(0, _total - _cashValue).toDouble(),
      'CREDIT' => _total,
      'SPLIT' => max(0, _total - _splitPaid).toDouble(),
      'MPESA' when _manualMpesa => max(
        0,
        _total - (double.tryParse(_mpesaAmount.text) ?? 0),
      ).toDouble(),
      _ => 0.0,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Text(
              'Payment',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Icon(Icons.looks_two_outlined, color: C.emerald),
              const SizedBox(width: 8),
              Text(
                'Step 2 of 2 · Payment and confirmation',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final item in _cart.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['name']?.toString() ?? 'Product'),
                    subtitle: Text(
                      '${_qty(item)} × ${kes(numberValue(item['sellingPrice']))}',
                    ),
                    trailing: Text(
                      kes(_qty(item) * numberValue(item['sellingPrice'])),
                    ),
                  ),
                const Divider(),
                _moneyRow('Subtotal', _subtotal),
                _moneyRow('Discount', _discountValue),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Tax'),
                  trailing: Text('Not configured'),
                ),
                _moneyRow('Total', _total, bold: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'Payment method'),
          items:
              const [
                    ('CASH', 'Cash'),
                    ('MPESA', 'M-Pesa'),
                    ('BANK', 'Bank transfer'),
                    ('CARD', 'Card'),
                    ('CREDIT', 'Credit'),
                    ('SPLIT', 'Split payment'),
                  ]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value.$1,
                      child: Text(value.$2),
                    ),
                  )
                  .toList(),
          onChanged: (value) {
            if (!connected) return;
            setState(() {
              _method = value ?? 'CASH';
              if (_method == 'CASH' && _cashReceived.text.isEmpty) {
                _cashReceived.text = _total.toStringAsFixed(2);
              }
              if (_method == 'MPESA' && _mpesaAmount.text.isEmpty) {
                _mpesaAmount.text = _total.toStringAsFixed(2);
              }
              if (_method == 'SPLIT' && _splitTenders.isEmpty) {
                _splitTenders = [_newTender('CASH'), _newTender('MPESA')];
              }
            });
            _persist();
          },
        ),
        const SizedBox(height: 12),
        if (_method == 'SPLIT') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Split payment',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Text(
                    'Enter each confirmed payment. M-Pesa needs its confirmation code.',
                  ),
                  for (var index = 0; index < _splitTenders.length; index++)
                    _splitTenderEditor(index),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() => _splitTenders.add(_newTender('CASH')));
                        _persist();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add payment method'),
                    ),
                  ),
                  _moneyRow('Amount received', _splitPaid, bold: true),
                  _moneyRow(shortBy > 0 ? 'Balance due' : 'Remaining', shortBy),
                  if (_splitPaid > _total)
                    const Text(
                      'Payment amounts exceed the sale total.',
                      style: TextStyle(color: C.danger),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_method == 'CASH') ...[
          TextField(
            controller: _cashReceived,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount received (KES)',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            onChanged: (_) {
              setState(() {});
              _persist();
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final amount in [_total, 500.0, 1000.0])
                ActionChip(
                  label: Text(amount == _total ? 'Exact' : kes(amount)),
                  onPressed: () {
                    _cashReceived.text = amount.toStringAsFixed(2);
                    setState(() {});
                    _persist();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          _moneyRow(
            shortBy > 0 ? 'Balance due' : 'Change due',
            shortBy > 0 ? shortBy : _change,
            bold: true,
          ),
        ],
        if (_method == 'MPESA') ...[
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: false, label: Text('Mock payment')),
              ButtonSegment<bool>(value: true, label: Text('Manual receipt')),
            ],
            selected: {_manualMpesa},
            onSelectionChanged: (selection) {
              setState(() {
                _manualMpesa = selection.first;
                if (_manualMpesa && _mpesaAmount.text.isEmpty) {
                  _mpesaAmount.text = _total.toStringAsFixed(2);
                }
              });
              _persist();
            },
          ),
          const SizedBox(height: 8),
          if (_manualMpesa) ...[
            TextField(
              controller: _mpesaReceipt,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              decoration: const InputDecoration(
                labelText: 'M-Pesa receipt number',
                hintText: 'For example, QAB123XYZ',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              onChanged: (_) => _persist(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mpesaAmount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'M-Pesa amount received (KES)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onChanged: (_) {
                setState(() {});
                _persist();
              },
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline),
              title: Text('Record a payment already received'),
              subtitle: Text(
                'Enter the receipt from the customer’s confirmed M-Pesa transaction. This does not initiate STK Push.',
              ),
            ),
          ] else
            const Card(
              color: Color(0xFFE9F5ED),
              child: ListTile(
                leading: Icon(Icons.phone_android, color: C.emerald),
                title: Text('M-Pesa mock checkout'),
                subtitle: Text(
                  'Creates a pending mock payment and confirms it through the demo callback.',
                ),
              ),
            ),
        ],
        if (_method == 'BANK' || _method == 'CARD')
          TextField(
            controller: _paymentReference,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText:
                  '${_method == 'BANK' ? 'Bank transfer' : 'Card'} reference',
              prefixIcon: const Icon(Icons.receipt_long_outlined),
            ),
            onChanged: (_) => _persist(),
          ),
        if (_method == 'CREDIT' ||
            shortBy > 0 ||
            _method == 'MPESA' ||
            _method == 'SPLIT') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: connected ? _selectCustomer : null,
            icon: const Icon(Icons.person_search_outlined),
            label: Text(
              customer == null
                  ? 'Select customer for the balance'
                  : '${customer['name']} · due ${kes(balance)}',
            ),
          ),
          if (customer != null)
            Card(
              child: ListTile(
                title: Text(customer['name']?.toString() ?? 'Customer'),
                subtitle: Text(
                  'Outstanding ${kes(balance)} · Credit limit ${limit == null ? 'not set' : kes(limit)}',
                ),
              ),
            ),
        ],
        if (!connected)
          Card(
            color: Color(0xFFFFF0CC),
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Offline cash sale'),
              subtitle: const Text(
                'Cash paid in full can be saved on this device and synced when you reconnect. Other payment methods need a connection.',
              ),
              trailing: _method == 'CASH'
                  ? null
                  : TextButton(
                      onPressed: () {
                        setState(() {
                          _method = 'CASH';
                          _cashReceived.text = _total.toStringAsFixed(2);
                        });
                        _persist();
                      },
                      child: const Text('Use cash'),
                    ),
            ),
          ),
        if (_hasCachedProducts)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Cached product stock can be out of date. The API will validate availability when online.',
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving || (!connected && _method != 'CASH')
              ? null
              : _checkout,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(
            _saving
                ? 'Saving sale…'
                : connected
                ? 'Complete Sale · ${kes(_total)}'
                : 'Save cash sale offline · ${kes(_total)}',
          ),
        ),
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Catalog refresh failed: $_loadError',
              style: const TextStyle(color: C.danger),
            ),
          ),
      ],
    );
  }

  Widget _moneyRow(String title, double value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          kes(value),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            fontSize: bold ? 18 : 14,
          ),
        ),
      ],
    ),
  );
}
