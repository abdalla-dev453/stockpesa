import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';

class SalesRepository {
  SalesRepository(this.client);
  final Dio client;
  Future<List<dynamic>> list() async =>
      (await client.get('/sales')).data as List;
  Future<Map<String, dynamic>> get(String id) async =>
      Map<String, dynamic>.from((await client.get('/sales/$id')).data as Map);
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> request, {
    required String idempotencyKey,
  }) async => Map<String, dynamic>.from(
    (await client.post(
          '/sales',
          data: request,
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        )).data
        as Map,
  );
  Future<Map<String, dynamic>> returnItems(
    String id,
    Map<String, dynamic> request,
  ) async => Map<String, dynamic>.from(
    (await client.post('/sales/$id/returns', data: request)).data as Map,
  );
}

final salesRepositoryProvider = Provider((ref) => SalesRepository(dio));
