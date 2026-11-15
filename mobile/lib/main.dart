import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'core/theme.dart';

void main() => runApp(const ProviderScope(child: StockPesaApp()));

class StockPesaApp extends ConsumerWidget {
  const StockPesaApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'StockPesa',
    theme: stockPesaTheme(),
    darkTheme: stockPesaTheme(dark: true),
    themeMode: ThemeMode.system,
    debugShowCheckedModeBanner: false,
    routerConfig: ref.watch(routerProvider),
  );
}
