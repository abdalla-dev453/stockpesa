import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';

class ProductsRepository {
  ProductsRepository(this.client);
  final Dio client;
  Future<List<dynamic>> categories() async =>
      (await client.get('/categories')).data as List;
  Future<Map<String, dynamic>> list({
    int page = 1,
    int limit = 100,
    String? search,
    String? categoryId,
    String? stockStatus,
  }) async => Map<String, dynamic>.from(
    (await client.get(
          '/products',
          queryParameters: {
            'page': page,
            'limit': limit,
            if (search?.isNotEmpty == true) 'search': search,
            if (categoryId != null) 'categoryId': categoryId,
            if (stockStatus != null) 'stockStatus': stockStatus,
          },
        )).data
        as Map,
  );
  Future<Map<String, dynamic>> get(String id) async =>
      Map<String, dynamic>.from(
        (await client.get('/products/$id')).data as Map,
      );
  Future<Map<String, dynamic>> lookup({String? barcode, String? sku}) async =>
      Map<String, dynamic>.from(
        (await client.get(
              '/products/lookup',
              queryParameters: {'barcode': barcode, 'sku': sku},
            )).data
            as Map,
      );
  Future<Map<String, dynamic>> create(Map<String, dynamic> product) async =>
      Map<String, dynamic>.from(
        (await client.post('/products', data: product)).data as Map,
      );
  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> changes,
  ) async => Map<String, dynamic>.from(
    (await client.patch('/products/$id', data: changes)).data as Map,
  );
  Future<void> archive(String id) async => client.delete('/products/$id');
}

final productsRepositoryProvider = Provider((ref) => ProductsRepository(dio));
