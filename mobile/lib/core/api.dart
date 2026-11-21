import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'storage/cart_store.dart';

const _configuredApi = String.fromEnvironment('API');
String get apiBase {
  if (_configuredApi.isNotEmpty) return _configuredApi;
  if (kIsWeb) return 'http://localhost:3000';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'http://10.0.2.2:3000', // Android emulator -> host
    _ => 'http://localhost:3000', // iOS simulator and desktop
  };
}
final _store = const FlutterSecureStorage();
Future<void>? _refreshFuture;
final _sessionExpired = StreamController<void>.broadcast();
Stream<void> get sessionExpiredStream => _sessionExpired.stream;
final Dio dio = _createDio();

Dio _createDio() => Dio(BaseOptions(
      baseUrl: apiBase,
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          final t = await _store.read(key: 'access');
          if (t != null) o.headers['Authorization'] = 'Bearer $t';
          h.next(o);
        },
        onError: (e, h) async {
          // Retrying a mutation after an expired access token can duplicate a
          // sale or stock operation. Only replay safe reads after refreshing.
          if (e.response?.statusCode == 401 &&
              e.requestOptions.path != '/auth/refresh' &&
              e.requestOptions.path != '/auth/logout' &&
              e.requestOptions.extra['sessionRetried'] != true) {
            try {
              _refreshFuture ??= _refreshAccessToken();
              await _refreshFuture;
              final access = await _store.read(key: 'access');
              if (access == null) {
                throw StateError('Session refresh returned no access token');
              }
              if (e.requestOptions.method.toUpperCase() == 'GET') {
                e.requestOptions.extra['sessionRetried'] = true;
                e.requestOptions.headers['Authorization'] = 'Bearer $access';
                return h.resolve(await dio.fetch(e.requestOptions));
              }
            } catch (_) {
              await _store.delete(key: 'access');
              await _store.delete(key: 'refresh');
              _sessionExpired.add(null);
            } finally {
              _refreshFuture = null;
            }
          }
          h.next(e);
        },
      ),
    );

Future<void> _refreshAccessToken() async {
  final refresh = await _store.read(key: 'refresh');
  if (refresh == null) throw StateError('No refresh token');
  final response = await Dio(
    BaseOptions(
      baseUrl: apiBase,
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  ).post('/auth/refresh', data: {'refreshToken': refresh});
  await saveTokens(Map<String, dynamic>.from(response.data as Map));
}

Future<void> saveTokens(Map d) async {
  await _store.write(key: 'access', value: d['accessToken']);
  await _store.write(key: 'refresh', value: d['refreshToken']);
}

Future<bool> hasSavedSession() async =>
    (await _store.read(key: 'access')) != null;

Future<Map<String, dynamic>> currentUser() async {
  final response = await dio.get('/auth/me');
  return Map<String, dynamic>.from(response.data as Map);
}

String apiError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null && status >= 500) {
      return 'We couldn’t complete that request. Please try again.';
    }
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      final message = data['message'];
      final text = message is List
          ? message.join('\n').trim()
          : message.toString().trim();
      if (_isTechnicalError(text)) {
        return 'We couldn’t complete that request. Please try again.';
      }
      return text;
    }
    if (error.response == null) {
      return 'You’re offline or the server can’t be reached. Check your connection and try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

bool _isTechnicalError(String message) =>
    RegExp(
      r'<!doctype|<html\b|<body\b|<pre\b|<script\b|<stacktrace\b',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(message) ||
    RegExp(r'^\s*(?:at\s+\S|#\d+\s)', multiLine: true).hasMatch(message) ||
    RegExp(
      r'^\s*Cannot\s+(?:GET|POST|PUT|PATCH|DELETE)\s',
      caseSensitive: false,
    ).hasMatch(message) ||
    RegExp(
      r'^\s*(?:Exception|Error|TypeError|RangeError|FormatException):',
      caseSensitive: false,
    ).hasMatch(message);

Future<bool> login(String id, String pw) async {
  final r = await dio.post(
    '/auth/login',
    data: {'identifier': id, 'password': pw},
  );
  await saveTokens(r.data);
  return true;
}

Future<void> logout() async {
  try {
    await dio.post('/auth/logout');
  } catch (_) {}
  await _store.delete(key: 'access');
  await _store.delete(key: 'refresh');
  await CartStore().clearAll();
}

Future<bool> hasCompletedOnboarding() async =>
    (await _store.read(key: 'onboarding')) == 'true';

Future<void> completeOnboarding() =>
    _store.write(key: 'onboarding', value: 'true');

Future<String?> readLocalPreference(String key) => _store.read(key: 'pref_$key');

Future<void> writeLocalPreference(String key, String value) =>
    _store.write(key: 'pref_$key', value: value);
