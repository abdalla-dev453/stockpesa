import 'package:flutter_test/flutter_test.dart';
import 'package:stockpesa/core/theme.dart';
import 'package:stockpesa/core/validation.dart';
import 'package:stockpesa/features/sales/domain/sale_math.dart';

void main() {
  group('KES and numeric formatting', () {
    test('formats KES amounts with grouped thousands and cents', () {
      expect(kes(1234567.5), 'KES 1,234,567.50');
    });

    test('accepts numeric and API decimal values', () {
      expect(numberValue(12.5), 12.5);
      expect(numberValue('12.50'), 12.5);
      expect(numberValue('invalid'), 0);
    });

    test('formats Kenyan business dates and handles invalid values', () {
      expect(
        formatBusinessDate('2025-01-02T00:00:00Z'),
        contains('2 Jan 2025'),
      );
      expect(formatBusinessDate('bad-date'), 'Date unavailable');
    });
  });

  group('checkout math', () {
    test('rounds each line and totals in cents', () {
      expect(SaleMath.subtotalCents([(10.10, 3), (2.25, 2)]), 3480);
    });

    test('discount cannot produce a negative total', () {
      final subtotal = SaleMath.subtotalCents([(25, 2)]);
      expect(SaleMath.totalCents(subtotal, 10), 4000);
      expect(SaleMath.totalCents(subtotal, 100), 0);
    });
  });

  group('form validation', () {
    test('validates Kenyan mobile numbers in common formats', () {
      expect(validateKenyanPhone('0712 345 678'), isNull);
      expect(validateKenyanPhone('+254 (712) 345-678'), isNull);
      expect(validateKenyanPhone('12345'), isNotNull);
    });

    test('validates email and nonnegative two-decimal money', () {
      expect(validateEmail('owner@example.co.ke'), isNull);
      expect(validateEmail('not-an-email'), isNotNull);
      expect(validateNonNegativeMoney('10.25'), isNull);
      expect(validateNonNegativeMoney('-1'), isNotNull);
      expect(validateNonNegativeMoney('1.001'), isNotNull);
    });
  });
}
