import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';

class BusinessRepository {
  BusinessRepository(this.client);
  final Dio client;
  Future<Map<String, dynamic>> profile() async => Map<String, dynamic>.from(
    (await client.get('/business/profile')).data as Map,
  );
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> changes,
  ) async => Map<String, dynamic>.from(
    (await client.patch('/business/profile', data: changes)).data as Map,
  );
  Future<List<dynamic>> staff() async =>
      (await client.get('/users')).data as List;
  Future<Map<String, dynamic>> addStaff(Map<String, dynamic> staff) async =>
      Map<String, dynamic>.from(
        (await client.post('/users', data: staff)).data as Map,
      );
  Future<Map<String, dynamic>> updateStaff(
    String id,
    Map<String, dynamic> changes,
  ) async => Map<String, dynamic>.from(
    (await client.patch('/users/$id', data: changes)).data as Map,
  );
  Future<void> removeStaff(String id) async => client.delete('/users/$id');
}

final businessRepositoryProvider = Provider((ref) => BusinessRepository(dio));
