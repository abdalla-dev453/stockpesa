import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart' show dio;

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  if (kIsWeb) {
    Future<List<ConnectivityResult>> checkApi() async {
      try {
        await dio.get('/health');
        return [ConnectivityResult.wifi];
      } on DioException {
        return [ConnectivityResult.none];
      }
    }

    yield await checkApi();
    await for (final _ in Stream.periodic(const Duration(seconds: 20))) {
      yield await checkApi();
    }
    return;
  }

  try {
    final initial = await Connectivity().checkConnectivity();
    yield initial;
  } catch (_) {
    yield [ConnectivityResult.none];
  }
  yield* Connectivity().onConnectivityChanged;
});
