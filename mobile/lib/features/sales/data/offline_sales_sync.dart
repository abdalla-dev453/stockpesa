import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/storage/offline_store.dart';

class OfflineSalesSync {
  OfflineSalesSync(this.client, this.store);

  final Dio client;
  final OfflineStore store;
  bool _running = false;

  Future<void> syncPending() async {
    if (_running) return;
    _running = true;
    try {
      final operations = await store.loadSalesQueueForCurrentUser();
      for (final operation in operations) {
        if (operation['status'] == 'failed') return;
        try {
          await _submit(operation);
          await store.removeOfflineSale(operation['id'].toString());
        } on DioException catch (error) {
          final status = error.response?.statusCode;
          if (status == null || status >= 500) {
            await store.updateOfflineSale(operation['id'].toString(), {
              'lastError': apiError(error),
              'lastAttemptAt': DateTime.now().toIso8601String(),
            });
          } else {
            await store.updateOfflineSale(operation['id'].toString(), {
              'status': 'failed',
              'lastError': apiError(error),
            });
          }
          return;
        } catch (error) {
          await store.updateOfflineSale(operation['id'].toString(), {
            'status': 'failed',
            'lastError': error.toString(),
          });
          return;
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> retryFailed() async {
    final operations = await store.loadSalesQueueForCurrentUser();
    for (final operation
        in operations.where((item) => item['status'] == 'failed')) {
      await store.updateOfflineSale(operation['id'].toString(), {
        'status': 'pending',
        'lastError': null,
      });
    }
    await syncPending();
  }

  Future<void> _submit(Map<String, dynamic> operation) async {
    final request = Map<String, dynamic>.from(operation['request'] as Map);
    final headers = {'Idempotency-Key': operation['id'].toString()};
    try {
      await client.post('/sales', data: request, options: Options(headers: headers));
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      await client.post('/sales', data: request, options: Options(headers: headers));
    }
  }
}

final offlineSalesSyncProvider = Provider(
  (ref) => OfflineSalesSync(dio, OfflineStore()),
);
