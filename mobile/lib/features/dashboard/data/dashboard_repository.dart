import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';

class DashboardRepository {
  DashboardRepository(this.client);
  final Dio client;
  Map<String, dynamic>? _cache;
  DateTime? _cachedAt;

  Future<Map<String, dynamic>> load({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cache != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(seconds: 30)) {
      return Map<String, dynamic>.from(_cache!);
    }
    final result = Map<String, dynamic>.from(
      (await client.get('/reports/dashboard')).data as Map,
    );
    _cache = result;
    _cachedAt = DateTime.now();
    return Map<String, dynamic>.from(result);
  }

  void clearCache() {
    _cache = null;
    _cachedAt = null;
  }

  Future<List<dynamic>> alerts() async =>
      ((await client.get('/alerts', queryParameters: {'limit': 100})).data
              as Map)['data']
          as List;
  Future<List<dynamic>> stock() async =>
      (await client.get('/stock')).data as List;
  Future<List<dynamic>> sales() async =>
      (await client.get('/sales')).data as List;
}

final dashboardRepositoryProvider = Provider((ref) => DashboardRepository(dio));
