import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';

class InsightsRepository {
  InsightsRepository(this.client);
  final Dio client;

  Future<Map<String, dynamic>> dashboard() async => Map<String, dynamic>.from(
    (await client.get('/reports/dashboard')).data as Map,
  );
  Future<Map<String, dynamic>> salesReport({String? from, String? to}) async =>
      Map<String, dynamic>.from(
        (await client.get(
              '/reports/sales',
              queryParameters: {'from': from, 'to': to},
            )).data
            as Map,
      );
  Future<List<dynamic>> customerDebt() async =>
      (await client.get('/reports/customer-debt')).data as List;
  Future<List<dynamic>> productsReport() async =>
      (await client.get('/reports/products')).data as List;
  Future<Map<String, dynamic>> stockSummary() async =>
      Map<String, dynamic>.from(
        (await client.get('/reports/stock-summary')).data as Map,
      );
  Future<List<dynamic>> alerts({int page = 1, int limit = 100}) async =>
      ((await client.get(
                '/alerts',
                queryParameters: {'page': page, 'limit': limit},
              )).data
              as Map)['data']
          as List;
  Future<int> unreadCount() async =>
      ((await client.get('/alerts', queryParameters: {'limit': 1})).data
              as Map)['unreadCount']
          as int? ??
      0;
  Future<void> markAlertRead(String id) async =>
      client.patch('/alerts/$id/read');
  Future<void> markAllAlertsRead() async => client.patch('/alerts/read-all');
}

final insightsRepositoryProvider = Provider((ref) => InsightsRepository(dio));
final unreadAlertsProvider = FutureProvider<int>(
  (ref) => ref.watch(insightsRepositoryProvider).unreadCount(),
);
