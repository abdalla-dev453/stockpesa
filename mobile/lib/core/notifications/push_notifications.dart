import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = _firebaseOptions;
  if (options == null) return;
  await Firebase.initializeApp(options: options);
}

const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

FirebaseOptions? get _firebaseOptions {
  if (_projectId.isEmpty || _senderId.isEmpty || _apiKey.isEmpty) return null;
  final appId = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => _iosAppId,
    TargetPlatform.android => _androidAppId,
    _ => '',
  };
  if (appId.isEmpty) return null;
  return FirebaseOptions(
    apiKey: _apiKey,
    appId: appId,
    messagingSenderId: _senderId,
    projectId: _projectId,
    storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
    iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
        ? _iosBundleId
        : null,
  );
}

class StockPesaPushNotifications {
  StockPesaPushNotifications._();
  static final instance = StockPesaPushNotifications._();

  final _foreground = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get foregroundMessages => _foreground.stream;

  void Function(String path)? _openHandler;
  String? _pendingPath;
  String? _registeredId;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    final options = _firebaseOptions;
    if (options == null) return;
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_foreground.add);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
      FirebaseMessaging.instance.onRegistered.listen((id) {
        _registeredId = id;
        unawaited(_register(id));
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleOpen(initial);
      _initialized = true;
    } catch (_) {
      // Firebase setup must not prevent the inventory app from starting.
      _initialized = false;
    }
  }

  void setOpenHandler(void Function(String path) handler) {
    _openHandler = handler;
    final pending = _pendingPath;
    _pendingPath = null;
    if (pending != null) handler(pending);
  }

  Future<bool> requestPermissionAndRegister() async {
    if (!_initialized) await initialize();
    if (!_initialized) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
      final id = await _registerWithFirebase();
      return id != null && await _register(id);
    } catch (_) {
      return false;
    }
  }

  Future<void> registerIfAlreadyAllowed() async {
    if (!_initialized) await initialize();
    if (!_initialized) return;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _registerWithFirebase();
      }
    } catch (_) {}
  }

  Future<bool> hasPermission() async {
    if (!_initialized) await initialize();
    if (!_initialized) return false;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  Future<void> unregisterCurrentDevice() async {
    if (!_initialized) return;
    try {
      final id = _registeredId;
      if (id == null || id.isEmpty) return;
      await _remove(id);
      await FirebaseMessaging.instance.unregister();
      _registeredId = null;
    } catch (_) {
      // A failed network revocation is harmless; tokens are scoped to the account.
    }
  }

  Future<String?> _registerWithFirebase() async {
    final registered = FirebaseMessaging.instance.onRegistered.first;
    await FirebaseMessaging.instance.register();
    final id = await registered.timeout(const Duration(seconds: 10));
    _registeredId = id;
    return id;
  }

  Future<void> _remove(String id) async {
    try {
      await dio.delete('/notifications/devices', data: {'token': id});
    } catch (_) {}
  }

  Future<bool> _register(String token) async {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      _ => 'android',
    };
    try {
      await dio.post(
        '/notifications/devices',
        data: {'token': token, 'platform': platform},
      );
      return true;
    } catch (_) {
      // Token refresh runs without UI; the next sign-in can retry registration.
      return false;
    }
  }

  void _handleOpen(RemoteMessage message) {
    final path = _safePath(message.data['path']?.toString());
    if (path == null) return;
    final handler = _openHandler;
    if (handler == null) {
      _pendingPath = path;
    } else {
      handler(path);
    }
  }

  String? _safePath(String? path) {
    if (path == '/alerts' ||
        path == '/reports' ||
        path == '/staff' ||
        path == '/market-insights') {
      return path;
    }
    if (path != null &&
        RegExp(r'^/products/[0-9a-fA-F-]{36}$').hasMatch(path)) {
      return path;
    }
    if (path != null &&
        RegExp(r'^/customers/[0-9a-fA-F-]{36}$').hasMatch(path)) {
      return path;
    }
    return null;
  }
}

final foregroundPushMessagesProvider = StreamProvider<RemoteMessage>((ref) {
  return StockPesaPushNotifications.instance.foregroundMessages;
});
