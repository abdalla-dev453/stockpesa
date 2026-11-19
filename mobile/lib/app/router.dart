import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../features/auth/presentation/auth_provider.dart';
import '../screens/auth_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/detail_screens.dart';
import '../screens/more_screen.dart' show AlertsScreen;
import '../screens/products_screen.dart';
import '../screens/receipt_screen.dart';
import '../screens/legal_screen.dart';
import '../screens/market_insights_screen.dart';
import '../screens/notification_preferences_screen.dart';
import '../screens/sell_screen.dart';
import '../screens/stock_screen.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(sessionProvider, (_, _) => refresh.ping());
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.matchedLocation;
      const authRoutes = {'/login', '/register', '/forgot-password'};
      if (session.status == SessionStatus.loading) {
        return path == '/splash' ? null : '/splash';
      }
      if (!session.onboardingComplete && path != '/onboarding') {
        return '/onboarding';
      }
      if (!session.onboardingComplete && path == '/onboarding') return null;
      if (session.status == SessionStatus.signedOut) {
        return authRoutes.contains(path) ? null : '/login';
      }
      if (path == '/onboarding' ||
          path == '/splash' ||
          path == '/login' ||
          path == '/register' ||
          path == '/forgot-password') {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      GoRoute(
        path: '/login',
        builder: (context, _) => AuthScreen(
          onAuthenticated: () => ref.read(sessionProvider.notifier).signedIn(),
          onForgotPassword: () => context.go('/forgot-password'),
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (_, _) => AuthScreen(
          startInRegistration: true,
          onAuthenticated: () => ref.read(sessionProvider.notifier).signedIn(),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            StockPesaShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/products',
            builder: (_, _) => const ProductsScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (_, state) => ProductsScreen(
                  initialAction: 'add',
                  initialBarcode: state.uri.queryParameters['barcode'],
                ),
              ),
              GoRoute(
                path: 'import',
                builder: (_, _) =>
                    const ProductsScreen(initialAction: 'import'),
              ),
              GoRoute(
                path: ':productId',
                builder: (_, state) => ProductDetailScreen(
                  productId: state.pathParameters['productId']!,
                ),
              ),
              GoRoute(
                path: ':productId/edit',
                builder: (_, state) => ProductEditorScreen(
                  productId: state.pathParameters['productId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/sell',
            builder: (_, state) => SellScreen(
              initialCustomerId: state.uri.queryParameters['customerId'],
            ),
            routes: [
              GoRoute(path: 'cart', builder: (_, _) => const SellScreen()),
              GoRoute(
                path: 'payment',
                builder: (_, _) => const SellScreen(paymentStep: true),
              ),
              GoRoute(
                path: 'success/:saleId',
                builder: (context, state) => SaleSuccessPage(
                  saleId: state.pathParameters['saleId']!,
                  checkout: state.extra is Map
                      ? Map<String, dynamic>.from(state.extra as Map)
                      : null,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/stock',
            builder: (_, _) => const StockScreen(),
            routes: [
              GoRoute(
                path: 'intake',
                builder: (_, _) => const StockScreen(initialAction: 'intake'),
              ),
              GoRoute(
                path: 'adjust',
                builder: (_, _) => const StockScreen(initialAction: 'adjust'),
              ),
              GoRoute(
                path: 'count',
                builder: (_, _) => const StockCountsScreen(),
              ),
              GoRoute(
                path: 'movements',
                builder: (_, _) =>
                    const StockScreen(initialAction: 'movements'),
              ),
            ],
          ),
          GoRoute(
            path: '/customers',
            builder: (_, _) => const CustomersScreen(),
            routes: [
              GoRoute(
                path: ':customerId',
                builder: (_, state) => CustomerDetailScreen(
                  customerId: state.pathParameters['customerId']!,
                ),
              ),
            ],
          ),
          GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
          GoRoute(
            path: '/sales',
            builder: (_, _) => const SalesHistoryScreen(),
          ),
          GoRoute(
            path: '/sales/:saleId/receipt',
            builder: (_, state) =>
                ReceiptPreviewScreen(saleId: state.pathParameters['saleId']!),
          ),
          GoRoute(
            path: '/categories',
            builder: (_, _) => const CategoriesScreen(),
          ),
          GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
          GoRoute(
            path: '/market-insights',
            builder: (_, _) => const MarketInsightsScreen(),
          ),
          GoRoute(
            path: '/notification-settings',
            builder: (_, _) => const NotificationPreferencesScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const BusinessSettingsScreen(),
          ),
          GoRoute(
            path: '/privacy',
            builder: (_, _) => const LegalScreen(privacy: true),
          ),
          GoRoute(
            path: '/terms',
            builder: (_, _) => const LegalScreen(privacy: false),
          ),
          GoRoute(path: '/staff', builder: (_, _) => const StaffScreen()),
          GoRoute(path: '/more', builder: (_, _) => const MoreHubScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image(
            image: AssetImage('assets/branding/logo-wordmark-1440.png'),
            width: 240,
            height: 55,
            fit: BoxFit.contain,
            semanticLabel: 'StockPesa',
          ),
          SizedBox(height: 24),
          CircularProgressIndicator(),
        ],
      ),
    ),
  );
}

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final controller = PageController();
  int page = 0;
  static const slides = [
    (
      Icons.inventory_2_outlined,
      'Know your stock',
      'See what is on hand and catch low stock before it slows your shop.',
    ),
    (
      Icons.point_of_sale_outlined,
      'Sell with confidence',
      'Record cash, M-Pesa, bank, card, and credit sales in one place.',
    ),
    (
      Icons.insights_outlined,
      'Grow with clear numbers',
      'Use live business reports to make better day-to-day decisions.',
    ),
  ];
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    await ref.read(sessionProvider.notifier).finishOnboarding();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: finish, child: const Text('Skip')),
              ),
              Expanded(
                child: PageView.builder(
                  controller: controller,
                  itemCount: slides.length,
                  onPageChanged: (v) => setState(() => page = v),
                  itemBuilder: (_, i) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (i == 0)
                        Image.asset(
                          'assets/branding/onboarding-stock.png',
                          width: 240,
                          height: 180,
                          fit: BoxFit.contain,
                          semanticLabel: 'Retail shelves and inventory box',
                        )
                      else
                        Icon(
                          slides[i].$1,
                          size: 94,
                          color: const Color(0xFF0B7A4B),
                        ),
                      const SizedBox(height: 32),
                      Text(
                        slides[i].$2,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        slides[i].$3,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Container(
                    margin: const EdgeInsets.all(4),
                    width: i == page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == page
                          ? const Color(0xFF0B7A4B)
                          : Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: page == 2
                    ? finish
                    : () => controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                child: Text(page == 2 ? 'Get started' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Password help')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_reset_outlined, size: 48),
          const SizedBox(height: 16),
          Text(
            'Password reset is not available yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'The current StockPesa API does not provide a password reset endpoint. Please contact your business administrator to reset access.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    ),
  );
}

class SaleSuccessPage extends StatefulWidget {
  const SaleSuccessPage({super.key, required this.saleId, this.checkout});
  final String saleId;
  final Map<String, dynamic>? checkout;
  @override
  State<SaleSuccessPage> createState() => _SaleSuccessPageState();
}

class _SaleSuccessPageState extends State<SaleSuccessPage> {
  late Future<Map<String, dynamic>> sale = _load();
  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(
    (await dio.get('/sales/${widget.saleId}')).data as Map,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sale complete')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: sale,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(apiError(snapshot.error!)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final payments = data['payments'] as List? ?? [];
        final method =
            widget.checkout?['method']?.toString() ??
            payments.firstOrNull?['method']?.toString() ??
            'CREDIT';
        final awaitingPayment = payments.any(
          (payment) => payment['status'] == 'PENDING',
        );
        final change = method == 'CASH'
            ? math.max(
                0,
                numberValue(widget.checkout?['cashReceived']) -
                    numberValue(data['amountPaid']),
              )
            : 0;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF0B7A4B),
                    size: 72,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    awaitingPayment ? 'Sale recorded' : 'Sale complete',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Receipt ${data['saleNumber'] ?? widget.saleId}'),
                  Text('Total ${kes(numberValue(data['total']))}'),
                  Text('Payment method: $method'),
                  if (method == 'CASH' && change > 0)
                    Text('Change due: ${kes(change)}'),
                  if (numberValue(data['balanceDue']) > 0)
                    Text(
                      'Balance due: ${kes(numberValue(data['balanceDue']))}',
                    ),
                  Text(
                    awaitingPayment
                        ? 'M-Pesa payment is awaiting confirmation'
                        : 'Payment status: ${data['status'] ?? 'completed'}',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () =>
                        context.go('/sales/${widget.saleId}/receipt'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('View receipt'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.go('/sales/${widget.saleId}/receipt'),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share receipt'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/sell'),
                    child: const Text('New sale'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/dashboard'),
                    child: const Text('Back to dashboard'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
