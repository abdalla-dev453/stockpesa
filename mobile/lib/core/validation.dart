String? validateRequired(String? value, {String label = 'This field'}) =>
    value == null || value.trim().isEmpty ? '$label is required' : null;

String? validateEmail(String? value) =>
    value == null ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())
    ? 'Enter a valid email address'
    : null;

String? validateKenyanPhone(String? value) {
  if (value == null) return 'Enter a Kenyan phone number';
  final normalized = value.replaceAll(RegExp(r'[\s()-]'), '');
  if (!RegExp(r'^(?:\+?254|0)[17]\d{8}$').hasMatch(normalized)) {
    return 'Use a Kenyan mobile number, e.g. 0712345678';
  }
  return null;
}

String? validateNonNegativeMoney(String? value) {
  final amount = double.tryParse(value?.trim() ?? '');
  if (amount == null || !amount.isFinite || amount < 0) {
    return 'Enter a valid amount of zero or more';
  }
  if ((value!.split('.').elementAtOrNull(1)?.length ?? 0) > 2) {
    return 'Use no more than two decimal places';
  }
  return null;
}
