class SaleMath {
  const SaleMath._();

  static int lineCents(num unitPrice, num quantity) =>
      (unitPrice * quantity * 100).round();

  static int subtotalCents(Iterable<(num, num)> lines) =>
      lines.fold<int>(0, (sum, line) => sum + lineCents(line.$1, line.$2));

  static int totalCents(int subtotal, num discount) =>
      (subtotal - (discount * 100).round()).clamp(0, 9007199254740991).toInt();
}
