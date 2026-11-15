import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';

class CustomersRepository {
  CustomersRepository(this.client);
  final Dio client;
  Future<List<dynamic>> list({String? search}) async =>
      (await client.get('/customers', queryParameters: {'search': search})).data
          as List;
  Future<Map<String, dynamic>> get(String id) async =>
      Map<String, dynamic>.from(
        (await client.get('/customers/$id')).data as Map,
      );
  Future<Map<String, dynamic>> recordPayment(
    String id,
    Map<String, dynamic> payment,
  ) async => Map<String, dynamic>.from(
    (await client.post('/customers/$id/payments', data: payment)).data as Map,
  );
}

final customersRepositoryProvider = Provider((ref) => CustomersRepository(dio));
