import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) async* {
  try {
    final initial = await Connectivity().checkConnectivity();
    yield initial;
  } catch (_) {
    yield [ConnectivityResult.wifi];
  }
  yield* Connectivity().onConnectivityChanged;
});
