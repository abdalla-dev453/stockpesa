import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/storage/offline_store.dart';

class OfflineStockSync {
  OfflineStockSync(this.client, this.store);
  final Dio client;
  final OfflineStore store;
  bool _running = false;

  String _failureMessage(Object error) =>
      error is StateError ? error.message.toString() : apiError(error);

  Future<void> syncPending() async {
    if (_running) return;
    _running = true;
    try {
      final operations = await store.loadStockQueueForCurrentUser();
      for (final operation in operations) {
        if (operation['status'] == 'failed') return;
        try {
          await _syncOperationWithAuthRetry(operation);
          await store.removeStockOperation(operation['id'].toString());
        } on DioException catch (error) {
          if ((error.response?.statusCode ?? 500) >= 500) {
            await store.updateStockOperation(operation['id'].toString(), {
              'lastError': _failureMessage(error),
            });
          } else {
            await store.updateStockOperation(operation['id'].toString(), {
              'status': 'failed',
              'lastError': _failureMessage(error),
            });
          }
          return;
        } catch (error) {
          await store.updateStockOperation(operation['id'].toString(), {
            'status': 'failed',
            'lastError': _failureMessage(error),
          });
          return;
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> retryFailed() async {
    final operations = await store.loadStockQueueForCurrentUser();
    for (final operation
        in operations.where((item) => item['status'] == 'failed')) {
      await store.updateStockOperation(operation['id'].toString(), {
        'status': 'pending',
        'lastError': null,
      });
    }
    await syncPending();
  }

  Future<void> _syncOperation(Map<String, dynamic> operation) async {
    final payload = Map<String, dynamic>.from(operation['payload'] as Map);
    switch (operation['kind']) {
      case 'intake':
        await client.post(
          '/stock/intake',
          data: payload,
          options: Options(
            headers: {'Idempotency-Key': operation['id'].toString()},
          ),
        );
      case 'adjustment':
        await client.post(
          '/stock/adjustments',
          data: payload,
          options: Options(
            headers: {'Idempotency-Key': operation['id'].toString()},
          ),
        );
      case 'count':
        final countId = payload['countId'].toString();
        if (payload['create'] == true) {
          await client.post(
            '/stock-counts',
            data: {'clientId': countId, 'notes': payload['notes']},
          );
        } else {
          final current = Map<String, dynamic>.from(
            (await client.get('/stock-counts/$countId')).data as Map,
          );
          if (current['status'] != 'open') {
            throw StateError('This offline count is no longer open.');
          }
        }
        for (final item in payload['items'] as List? ?? const []) {
          final row = Map<String, dynamic>.from(item as Map);
          await client.post(
            '/stock-counts/$countId/items',
            data: {
              'productId': row['productId'],
              'countedQuantity': row['countedQuantity'],
            },
          );
        }
      default:
        throw StateError('Unsupported offline stock operation.');
    }
  }

  Future<void> _syncOperationWithAuthRetry(
    Map<String, dynamic> operation,
  ) async {
    try {
      await _syncOperation(operation);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      await _syncOperation(operation);
    }
  }
}

final offlineStockSyncProvider = Provider(
  (ref) => OfflineStockSync(dio, OfflineStore()),
);
