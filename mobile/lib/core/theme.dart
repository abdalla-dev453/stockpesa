import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class C {
  static const emerald = Color(0xFF2868B2),
      forest = Color(0xFF174B82),
      amber = Color(0xFFF5A524),
      coral = Color(0xFFFF7043),
      bg = Color(0xFFF4F7FB),
      ink = Color(0xFF172033),
      muted = Color(0xFF69758A),
      border = Color(0xFFE1E7F0),
      ok = Color(0xFF16A34A),
      warn = Color(0xFFF59E0B),
      danger = Color(0xFFDC2626);
}

String kes(num v) => 'KES ${NumberFormat('#,##0.00').format(v)}';

/// Theme-aware text colours: C.ink is near-black and invisible on dark
/// surfaces, C.muted is too dim for dark backgrounds. Use these helpers in
/// place of the raw constants so labels stay visible in both modes.
Color inkOn(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFE7EFEA)
    : C.ink;
Color mutedOn(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF9FB0A8)
    : C.muted;
String businessDate(DateTime value) =>
    DateFormat('d MMM yyyy, HH:mm').format(value.toLocal());
String formatBusinessDate(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null ? 'Date unavailable' : businessDate(parsed);
}

num numberValue(Object? value) =>
    value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;
ThemeData stockPesaTheme({bool dark = false}) => ThemeData(
  useMaterial3: true,
  brightness: dark ? Brightness.dark : Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: C.emerald,
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: C.emerald,
    secondary: C.amber,
    tertiary: C.coral,
    surface: dark ? const Color(0xFF14211B) : Colors.white,
  ),
  scaffoldBackgroundColor: dark ? const Color(0xFF0D1712) : C.bg,
  textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
      .textTheme
      .apply(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        bodyColor: dark ? const Color(0xFFE7EFEA) : C.ink,
        displayColor: dark ? const Color(0xFFE7EFEA) : C.ink,
      ),
  inputDecorationTheme: InputDecorationTheme(
    labelStyle: TextStyle(color: dark ? const Color(0xFFB9C6BF) : C.muted),
    hintStyle: TextStyle(color: dark ? const Color(0xFF8FA098) : C.muted),
    floatingLabelStyle: TextStyle(
      color: dark ? const Color(0xFFB9C6BF) : C.muted,
    ),
    filled: true,
    fillColor: dark ? const Color(0xFF1B2A23) : Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: C.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: C.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: C.emerald, width: 1.6),
    ),
  ),
  dropdownMenuTheme: DropdownMenuThemeData(
    textStyle: TextStyle(color: dark ? const Color(0xFFE7EFEA) : C.ink),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: dark ? const Color(0xFF14211B) : Colors.white,
    titleTextStyle: TextStyle(
      color: dark ? const Color(0xFFE7EFEA) : C.ink,
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
    contentTextStyle: TextStyle(
      color: dark ? const Color(0xFFE7EFEA) : C.ink,
      fontSize: 14,
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(backgroundColor: null),
  cardTheme: CardThemeData(
    color: dark ? const Color(0xFF14211B) : Colors.white,
    elevation: 0,
    shadowColor: Colors.black12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: dark ? const Color(0xFF26382F) : C.border),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: C.coral,
    foregroundColor: Colors.white,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: dark ? const Color(0xFF1B2A23) : C.ink,
    contentTextStyle: const TextStyle(color: Colors.white),
    behavior: SnackBarBehavior.floating,
    showCloseIcon: true,
    closeIconColor: Colors.white70,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    elevation: 8,
  ),
  appBarTheme: AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    backgroundColor: dark ? const Color(0xFF0D1712) : Colors.white,
    foregroundColor: dark ? const Color(0xFFE7EFEA) : C.ink,
    surfaceTintColor: Colors.transparent,
    shape: Border(
      bottom: BorderSide(color: dark ? const Color(0xFF26382F) : C.border),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    height: 72,
    elevation: 0,
    backgroundColor: dark ? const Color(0xFF14211B) : Colors.white,
    indicatorColor: dark ? const Color(0xFF2B4E72) : const Color(0xFFE8F0FA),
    surfaceTintColor: Colors.transparent,
  ),
);
