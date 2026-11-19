import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';

class DashboardRepository {
  DashboardRepository(this.client);
  final Dio client;
  Map<String, dynamic>? _cache;
  DateTime? _cachedAt;
  String? _cachedPeriod;
  String? _cachedRange;

  Future<Map<String, dynamic>> load({bool forceRefresh = false, String period = 'today', DateTime? startDate, DateTime? endDate}) async {
    if (!forceRefresh &&
        _cache != null &&
        _cachedPeriod == period && _cachedRange == '${startDate?.toIso8601String()}|${endDate?.toIso8601String()}' &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(seconds: 30)) {
      return Map<String, dynamic>.from(_cache!);
    }
    final result = Map<String, dynamic>.from(
      (await client.get('/reports/dashboard', queryParameters: {
        'period': period,
        if (startDate != null) 'start_date': startDate.toIso8601String(),
        if (endDate != null) 'end_date': endDate.toIso8601String(),
      })).data as Map,
    );
    _cache = result;
    _cachedAt = DateTime.now();
    _cachedPeriod = period;
    _cachedRange = '${startDate?.toIso8601String()}|${endDate?.toIso8601String()}';
    return Map<String, dynamic>.from(result);
  }

  void clearCache() {
    _cache = null;
    _cachedAt = null;
    _cachedPeriod = null;
    _cachedRange = null;
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
