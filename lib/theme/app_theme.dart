import 'package:flutter/material.dart';

class AppTheme {
  static const navy = Color(0xFF123047);
  static const blue = Color(0xFF2677C9);
  static const teal = Color(0xFF16A6A1);
  static const canvas = Color(0xFFF5F7FA);
  static const border = Color(0xFFE5EBF2);
  static const mutedText = Color(0xFF68788C);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
      primary: blue,
      secondary: teal,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: navy,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: navy, letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD8E2EC))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD8E2EC))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: blue, width: 1.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: blue.withOpacity(.10),
        labelTextStyle: MaterialStateProperty.resolveWith((states) => TextStyle(fontSize: 11, fontWeight: states.contains(MaterialState.selected) ? FontWeight.w800 : FontWeight.w500)),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.25, color: navy),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, color: navy),
        bodyMedium: TextStyle(height: 1.35),
      ),
    );
  }
}

Color statusColor(String statusAsString) {
  switch (statusAsString) {
    case 'received': return const Color(0xFF64748B);
    case 'washing': return const Color(0xFF2677C9);
    case 'drying': return const Color(0xFFD97706);
    case 'folding_pressing': return const Color(0xFF805AD5);
    case 'ready': return const Color(0xFF16845B);
    case 'picked_up': return const Color(0xFF475569);
    default: return const Color(0xFF64748B);
  }
}
