import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockpesa/screens/auth_screen.dart';
import 'package:stockpesa/core/theme.dart';

void main() {
  testWidgets('sign-in screen presents the account fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: stockPesaTheme(),
        home: AuthScreen(onAuthenticated: () {}),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email or phone'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('New to StockPesa? Create an account'), findsOneWidget);
  });

  testWidgets('registration mode displays business setup fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: stockPesaTheme(),
        home: AuthScreen(onAuthenticated: () {}),
      ),
    );
    await tester.tap(find.text('New to StockPesa? Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Set up your shop'), findsOneWidget);
    expect(find.text('Business name'), findsOneWidget);
    expect(find.text('Your full name'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });
}
