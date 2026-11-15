import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';

class StockRepository {
  StockRepository(this.client);
  final Dio client;
  Future<List<dynamic>> onHand() async =>
      (await client.get('/stock')).data as List;
  Future<List<dynamic>> movements() async =>
      (await client.get('/stock/movements')).data as List;
  Future<void> intake(Map<String, dynamic> request) async =>
      client.post('/stock/intake', data: request);
  Future<void> adjust(Map<String, dynamic> request) async =>
      client.post('/stock/adjustments', data: request);
  Future<List<dynamic>> counts() async =>
      (await client.get('/stock/counts')).data as List;
  Future<Map<String, dynamic>> createCount() async => Map<String, dynamic>.from(
    (await client.post('/stock/counts')).data as Map,
  );
}

final stockRepositoryProvider = Provider((ref) => StockRepository(dio));
