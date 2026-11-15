import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local carts only; sales are always submitted to the API while online.
class CartStore {
  static const _storage = FlutterSecureStorage();
  static const _activeKey = 'stockpesa.active_cart';
  static const _parkedKey = 'stockpesa.parked_carts';
  static const _productsKey = 'stockpesa.cached_products';

  Future<Map<String, dynamic>?> loadActive() async {
    final value = await _storage.read(key: _activeKey);
    if (value == null) return null;
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> saveActive(Map<String, dynamic> cart) =>
      _storage.write(key: _activeKey, value: jsonEncode(cart));

  Future<void> clearActive() => _storage.delete(key: _activeKey);

  Future<List<Map<String, dynamic>>> loadParked() async {
    final value = await _storage.read(key: _parkedKey);
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> saveParked(List<Map<String, dynamic>> carts) =>
      _storage.write(key: _parkedKey, value: jsonEncode(carts));

  Future<void> saveProducts(List<dynamic> products) =>
      _storage.write(key: _productsKey, value: jsonEncode(products));

  Future<List<Map<String, dynamic>>> loadProducts() async {
    final value = await _storage.read(key: _productsKey);
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> clearAll() async {
    await _storage.delete(key: _activeKey);
    await _storage.delete(key: _parkedKey);
    await _storage.delete(key: _productsKey);
  }
}
