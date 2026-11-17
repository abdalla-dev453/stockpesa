import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme_provider.dart';
import 'core/notifications/push_notifications.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StockPesaPushNotifications.instance.initialize();
  runApp(const ProviderScope(child: StockPesaApp()));
}

class StockPesaApp extends ConsumerStatefulWidget {
  const StockPesaApp({super.key});

  @override
  ConsumerState<StockPesaApp> createState() => _StockPesaAppState();
}

class _StockPesaAppState extends ConsumerState<StockPesaApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = ref.read(routerProvider);
      StockPesaPushNotifications.instance.setOpenHandler(router.go);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'StockPesa',
    theme: stockPesaTheme(),
    darkTheme: stockPesaTheme(dark: true),
    themeMode: ref.watch(themeModeProvider),
    debugShowCheckedModeBanner: false,
    routerConfig: ref.watch(routerProvider),
  );
}
