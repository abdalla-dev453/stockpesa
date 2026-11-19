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
import '../features/sales/domain/sale_math.dart';
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
  final Map<String, Map<String, dynamic>> _cart = {};
  List<Map<String, dynamic>> _products = [], _customers = [], _categories = [];
  List<Map<String, dynamic>> _parked = [];
  bool _loading = true, _saving = false, _hasCachedProducts = false;
  String? _loadError, _selectedCategory, _customerId, _overrideReason;
  String _method = 'CASH';
  bool _manualMpesa = false;
  String? _checkoutKey, _checkoutFingerprint;
  String _role = '';
  bool _initialProductHandled = false;

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
  double get _discountValue => double.tryParse(_discount.text) ?? 0;
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
  double get _change => max(0, _cashValue - _total).toDouble();
  bool get _canOverride => _role == 'OWNER' || _role == 'MANAGER';

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
    _restore();
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
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final active = await _store.loadActive();
      _parked = await _store.loadParked();
      if (active != null) {
        for (final raw in active['items'] as List? ?? []) {
          final item = Map<String, dynamic>.from(raw as Map);
          final id = item['id']?.toString();
          if (id != null) _cart[id] = item;
        }
        _method = active['method']?.toString() ?? 'CASH';
        _customerId = active['customerId']?.toString() ?? _customerId;
        _discount.text = active['discount']?.toString() ?? '';
        _cashReceived.text = active['cashReceived']?.toString() ?? '';
        _manualMpesa = active['manualMpesa'] == true;
        _mpesaAmount.text = active['mpesaAmount']?.toString() ?? '';
        _mpesaReceipt.text = active['mpesaReceipt']?.toString() ?? '';
        _checkoutKey = active['checkoutKey']?.toString();
        _checkoutFingerprint = active['checkoutFingerprint']?.toString();
        _overrideReason = active['overrideReason']?.toString();
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
      'cashReceived': _cashReceived.text,
      'manualMpesa': _manualMpesa,
      'mpesaAmount': _mpesaAmount.text,
      'mpesaReceipt': _mpesaReceipt.text,
      'checkoutKey': _checkoutKey,
      'checkoutFingerprint': _checkoutFingerprint,
      'overrideReason': _overrideReason,
    };
    await _store.saveActive(state);
  }

  Future<void> _loadCatalog({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
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
      _role = (responses[3].data as Map)['role']?.toString() ?? '';
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
        }
      } catch (_) {}
    }
    if (_cashReceived.text.isEmpty && _method == 'CASH' && _cart.isNotEmpty) {
      _cashReceived.text = _total.toStringAsFixed(2);
    }
    if (mounted) setState(() => _loading = false);
    if (!_initialProductHandled &&
        (widget.initialProductId != null || widget.initialScan) &&
        _loadError == null) {
      _initialProductHandled = true;
      if (widget.initialScan) {
        await _scanBarcode();
      } else {
        try {
          final product = Map<String, dynamic>.from(
            (await dio.get('/products/${widget.initialProductId}')).data as Map,
          );
          if (mounted) await _add(product);
        } catch (error) {
          if (mounted) _message(apiError(error));
        }
      }
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

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
      try {
        final variants = ((await dio.get('/products/${product['id']}/variants')).data as List)
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
    if (product['variantId'] == null) {
      try {
        final baseUnit = product['unit'].toString();
        final rows = (await dio.get('/unit-conversions', queryParameters: {'productId': product['id']})).data as List;
        final choices = <Map<String, dynamic>>[
          {'unit': baseUnit, 'factor': 1.0},
        ];
        for (final value in rows) {
          final row = value as Map;
          if (row['productId'] != null && row['productId']?.toString() != product['id'].toString()) continue;
          final multiplier = numberValue(row['multiplier']).toDouble();
          if (row['toUnit'] == baseUnit) choices.add({'unit': row['fromUnit'].toString(), 'factor': multiplier});
          if (row['fromUnit'] == baseUnit && multiplier != 0) choices.add({'unit': row['toUnit'].toString(), 'factor': 1 / multiplier});
        }
        if (choices.length > 1 && mounted) {
          final choice = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Choose selling unit')),
              for (final option in choices)
                ListTile(
                  title: Text(option['unit'].toString()),
                  subtitle: Text('${kes(numberValue(product['sellingPrice']) * (option['factor'] as double))} each'),
                  onTap: () => Navigator.pop(context, option),
                ),
            ])),
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
      _cashReceived.clear();
      _mpesaAmount.clear();
      _mpesaReceipt.clear();
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
      'cashReceived': _cashReceived.text,
      'manualMpesa': _manualMpesa,
      'mpesaAmount': _mpesaAmount.text,
      'mpesaReceipt': _mpesaReceipt.text,
      'overrideReason': _overrideReason,
    });
    await _store.saveParked(parked);
    setState(() {
      _parked = parked;
      _cart.clear();
      _method = 'CASH';
      _customerId = null;
      _discount.clear();
      _cashReceived.clear();
      _mpesaAmount.clear();
      _mpesaReceipt.clear();
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
        'cashReceived': _cashReceived.text,
        'manualMpesa': _manualMpesa,
        'mpesaAmount': _mpesaAmount.text,
        'mpesaReceipt': _mpesaReceipt.text,
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
      _cashReceived.text = selected['cashReceived']?.toString() ?? '';
      _manualMpesa = selected['manualMpesa'] == true;
      _mpesaAmount.text = selected['mpesaAmount']?.toString() ?? '';
      _mpesaReceipt.text = selected['mpesaReceipt']?.toString() ?? '';
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
      if (error is DioException && error.response?.statusCode == 404) {
        _message('Barcode not found. Add a product with this barcode.');
        if (mounted) {
          context.go('/products/add?barcode=${Uri.encodeComponent(code)}');
        }
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
    if (_discountValue < 0 || _discountValue > _subtotal) {
      _message('Discount must be between zero and the subtotal.');
      return;
    }
    _persist();
    context.go('/sell/payment');
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
              decoration: const InputDecoration(
                labelText: 'Credit limit (optional)',
              ),
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

  Future<void> _checkout() async {
    if (!_connected) {
      _message(
        'You are offline. The cart is saved locally; reconnect and retry to record the sale.',
      );
      return;
    }
    if (_cart.isEmpty) {
      _message('The cart is empty.');
      return;
    }
    if (_discountValue < 0 || _discountValue > _subtotal) {
      _message('Discount must be between zero and the subtotal.');
      return;
    }
    if (_method == 'CREDIT' && _customerId == null) {
      _message('Select or add a customer for a credit sale.');
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
      _ => _total,
    };
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
      'method': _method,
      'amountPaid': paid,
      if (_method == 'MPESA' && _manualMpesa)
        'mpesaReceiptNumber': _mpesaReceipt.text.trim().toUpperCase(),
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
      _message(apiError(error));
      // The request key and cart stay saved so a manual retry cannot duplicate a sale.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref
        .watch(connectivityProvider)
        .maybeWhen(
          data: (results) =>
              results.any((value) => value != ConnectivityResult.none),
          orElse: () => true,
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
                          '${kes(numberValue(product['sellingPrice']))}  ·  $quantity ${product['unit'] ?? 'units'} available',
                        ),
                        trailing: IconButton(
                          tooltip: 'Add to cart',
                          onPressed: () => _add(product),
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
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue to payment'),
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
                  '${_cart.length} products · ${kes(_total)}',
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
                  visualDensity: VisualDensity.compact,
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
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Add one',
                  onPressed: () =>
                      _setQuantity(entry.value, _qty(entry.value) + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          Row(
            children: [
              const Expanded(child: Text('Discount')),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _discount,
                  textAlign: TextAlign.end,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    prefixText: 'KES ',
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

  Widget _buildPaymentStep(bool connected) {
    final customer = _customers
        .where((row) => row['id'] == _customerId)
        .firstOrNull;
    final balance = customer == null ? 0 : numberValue(customer['balance']);
    final limit = customer?['creditLimit'] == null
        ? null
        : numberValue(customer!['creditLimit']);
    final shortBy = max(0, _total - _cashValue).toDouble();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => context.go('/sell'),
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
                  ]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value.$1,
                      child: Text(value.$2),
                    ),
                  )
                  .toList(),
          onChanged: (value) {
            setState(() {
              _method = value ?? 'CASH';
              if (_method == 'CASH' && _cashReceived.text.isEmpty) {
                _cashReceived.text = _total.toStringAsFixed(2);
              }
              if (_method == 'MPESA' && _mpesaAmount.text.isEmpty) {
                _mpesaAmount.text = _total.toStringAsFixed(2);
              }
            });
            _persist();
          },
        ),
        const SizedBox(height: 12),
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
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Reference not stored'),
              subtitle: Text(
                'The current sale API records the payment method but has no bank/card reference field.',
              ),
            ),
          ),
        if (_method == 'CREDIT' || shortBy > 0 || _method == 'MPESA') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _customerId,
            decoration: const InputDecoration(labelText: 'Customer account'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Select customer'),
              ),
              for (final row in _customers)
                DropdownMenuItem<String?>(
                  value: row['id']?.toString(),
                  child: Text(
                    '${row['name']} · due ${kes(numberValue(row['balance']))}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              setState(() => _customerId = value);
              _persist();
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _createCustomer,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add customer'),
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
          const Card(
            color: Color(0xFFFFF0CC),
            child: ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline: sale cannot be submitted'),
              subtitle: Text(
                'Your cart is saved here. Reconnect and retry; no sale has been queued.',
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
          onPressed: _saving || !connected ? null : _checkout,
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
            _saving ? 'Recording sale…' : 'Complete sale · ${kes(_total)}',
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
