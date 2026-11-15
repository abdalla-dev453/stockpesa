import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class C {
  static const emerald = Color(0xFF0B7A4B),
      forest = Color(0xFF065F3A),
      amber = Color(0xFFF5A524),
      coral = Color(0xFFFF6B35),
      bg = Color(0xFFF7F8F7),
      ink = Color(0xFF10221A),
      muted = Color(0xFF5F6B65),
      border = Color(0xFFE3E7E4),
      ok = Color(0xFF16A34A),
      warn = Color(0xFFF59E0B),
      danger = Color(0xFFDC2626);
}

String kes(num v) => 'KES ${NumberFormat('#,##0.00').format(v)}';
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
  cardTheme: CardThemeData(
    color: dark ? const Color(0xFF14211B) : Colors.white,
    elevation: 1,
    shadowColor: Colors.black12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
);
