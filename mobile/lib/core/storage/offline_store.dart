import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OfflineStore {
  static const _storage = FlutterSecureStorage();
  static const _cachePrefix = 'stockpesa.offline.cache.';
  static const _identityKey = 'stockpesa.offline.identity';
  static const _stockQueueKey = 'stockpesa.offline.stock_queue';
  static const _salesQueueKey = 'stockpesa.offline.sales_queue';
  static Future<void> _queueTail = Future<void>.value();

  Future<void> saveSnapshot(String name, Object data) async {
    await _storage.write(
      key: '$_cachePrefix$name',
      value: jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'data': data,
      }),
    );
  }

  Future<Map<String, dynamic>?> loadSnapshot(String name) async {
    final value = await _storage.read(key: '$_cachePrefix$name');
    if (value == null) return null;
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> saveIdentity(Map user) async {
    final nextUserId = user['id']?.toString();
    final nextBusinessId = user['businessId']?.toString();
    final current = await loadIdentity();
    if (current != null &&
        (current['id'] != nextUserId ||
            current['businessId'] != nextBusinessId ||
            current['role'] != user['role']?.toString())) {
      final values = await _storage.readAll();
      for (final key in values.keys.where(
        (key) => key.startsWith(_cachePrefix),
      )) {
        await _storage.delete(key: key);
      }
    }
    await _storage.write(
      key: _identityKey,
      value: jsonEncode({
        'id': nextUserId,
        'businessId': nextBusinessId,
        'role': user['role']?.toString(),
      }),
    );
  }

  Future<Map<String, dynamic>?> loadIdentity() async {
    final value = await _storage.read(key: _identityKey);
    if (value == null) return null;
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  String newOperationId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<void> clearSnapshotsAndIdentity() async {
    final values = await _storage.readAll();
    for (final key in values.keys.where((key) => key.startsWith(_cachePrefix))) {
      await _storage.delete(key: key);
    }
    await _storage.delete(key: _identityKey);
  }

  Future<List<Map<String, dynamic>>> loadStockQueue() async {
    final value = await _storage.read(key: _stockQueueKey);
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadStockQueueForCurrentUser() async {
    final identity = await loadIdentity();
    if (identity == null) return [];
    final userId = identity['id']?.toString();
    final businessId = identity['businessId']?.toString();
    if (userId == null || businessId == null) return [];
    return (await loadStockQueue())
        .where(
          (operation) =>
              operation['userId'] == userId &&
              operation['businessId'] == businessId,
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadSalesQueueForCurrentUser() async {
    final identity = await loadIdentity();
    if (identity == null) return [];
    final userId = identity['id']?.toString();
    final businessId = identity['businessId']?.toString();
    if (userId == null || businessId == null) return [];
    return (await _loadQueue(_salesQueueKey))
        .where(
          (operation) =>
              operation['userId'] == userId &&
              operation['businessId'] == businessId,
        )
        .toList();
  }

  Future<void> enqueueOfflineSale(Map<String, dynamic> operation) =>
      _updateQueueAt(_salesQueueKey, (operations) {
        if (operations.any((item) => item['id'] == operation['id'])) {
          return operations;
        }
        return [...operations, operation];
      });

  Future<void> updateOfflineSale(
    String id,
    Map<String, dynamic> updates,
  ) => _updateQueueAt(_salesQueueKey, (operations) {
    return [
      for (final operation in operations)
        if (operation['id'] == id)
          {...operation, ...updates}
        else
          operation,
    ];
  });

  Future<void> removeOfflineSale(String id) =>
      _updateQueueAt(
        _salesQueueKey,
        (operations) => operations.where((item) => item['id'] != id).toList(),
      );

  Future<void> enqueueStockOperation(Map<String, dynamic> operation) =>
      _updateQueue((operations) {
        if (operations.any((item) => item['id'] == operation['id'])) {
          return operations;
        }
        return [...operations, operation];
      });

  Future<void> updateStockOperation(
    String id,
    Map<String, dynamic> updates,
  ) => _updateQueue((operations) {
    return [
      for (final operation in operations)
        if (operation['id'] == id)
          {...operation, ...updates}
        else
          operation,
    ];
  });

  Future<void> removeStockOperation(String id) =>
      _updateQueue((operations) => operations.where((item) => item['id'] != id).toList());

  Future<void> _updateQueue(
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) update,
  ) => _updateQueueAt(_stockQueueKey, update);

  Future<void> _updateQueueAt(
    String key,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) update,
  ) => _serializeQueue(() async {
    final operations = await _loadQueue(key);
    await _storage.write(
      key: key,
      value: jsonEncode(update(operations)),
    );
  });

  Future<List<Map<String, dynamic>>> _loadQueue(String key) async {
    final value = await _storage.read(key: key);
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<T> _serializeQueue<T>(Future<T> Function() action) {
    final previous = _queueTail;
    final completed = Completer<void>();
    _queueTail = completed.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        completed.complete();
      }
    })();
  }
}
