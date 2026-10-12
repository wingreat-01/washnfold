import 'package:flutter/material.dart';

/// Semantic colors that differ between light and dark mode.
///
/// Screens used to hardcode light-only values (navy text, white cards, pale
/// tints...). They now read these from the active theme instead:
///
///     final p = context.palette;
///     Text('Hello', style: TextStyle(color: p.strong));
///
/// The light values below are exactly the colors the app used before dark
/// mode existed, so light mode looks unchanged.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// Page background.
  final Color canvas;

  /// Cards, sheets, nav bars.
  final Color surface;

  /// Slightly different from [surface]: inputs, inset panels.
  final Color surfaceAlt;

  /// Hairline borders and dividers.
  final Color border;

  /// Borders on inputs and unselected chips.
  final Color borderStrong;

  /// Headings and the most important text (was navy).
  final Color strong;

  /// Regular body text on a card.
  final Color body;

  /// Secondary text and inactive icons.
  final Color muted;

  /// Tertiary text, hints, placeholder icons.
  final Color subtle;

  /// Brand blue, tuned for contrast on the current background.
  final Color accent;

  /// Brand teal, tuned for contrast on the current background.
  final Color teal;

  /// Soft backgrounds behind metric icons.
  final Color tintGreen;
  final Color tintBlue;
  final Color tintPurple;
  final Color tintAmber;

  /// Error banner.
  final Color errorBg;
  final Color errorIcon;
  final Color errorTitle;
  final Color errorText;

  const AppPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.strong,
    required this.body,
    required this.muted,
    required this.subtle,
    required this.accent,
    required this.teal,
    required this.tintGreen,
    required this.tintBlue,
    required this.tintPurple,
    required this.tintAmber,
    required this.errorBg,
    required this.errorIcon,
    required this.errorTitle,
    required this.errorText,
  });

  static const light = AppPalette(
    canvas: Color(0xFFF5F7FA),
    surface: Colors.white,
    surfaceAlt: Color(0xFFF8FAFC),
    border: Color(0xFFE5EBF2),
    borderStrong: Color(0xFFD8E2EC),
    strong: Color(0xFF123047),
    body: Color(0xFF25364A),
    muted: Color(0xFF718096),
    subtle: Color(0xFF8795A7),
    accent: Color(0xFF2677C9),
    teal: Color(0xFF16A6A1),
    tintGreen: Color(0xFFE5F4EC),
    tintBlue: Color(0xFFE8F1FC),
    tintPurple: Color(0xFFF1EAFE),
    tintAmber: Color(0xFFFFF1DA),
    errorBg: Color(0xFFFFF3F0),
    errorIcon: Color(0xFFB42318),
    errorTitle: Color(0xFF912018),
    errorText: Color(0xFF7A271A),
  );

  static const dark = AppPalette(
    canvas: Color(0xFF0E1621),
    surface: Color(0xFF16212E),
    surfaceAlt: Color(0xFF1B2838),
    border: Color(0xFF263647),
    borderStrong: Color(0xFF32465A),
    strong: Color(0xFFE8EEF5),
    body: Color(0xFFC9D4E0),
    muted: Color(0xFF9AA9BA),
    subtle: Color(0xFF7F8EA1),
    accent: Color(0xFF5AA2E8),
    teal: Color(0xFF2EC4BE),
    tintGreen: Color(0xFF15372A),
    tintBlue: Color(0xFF15304A),
    tintPurple: Color(0xFF2A2142),
    tintAmber: Color(0xFF3A2C12),
    errorBg: Color(0xFF3A1D19),
    errorIcon: Color(0xFFFDA29B),
    errorTitle: Color(0xFFFECDCA),
    errorText: Color(0xFFF4A9A0),
  );

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? borderStrong,
    Color? strong,
    Color? body,
    Color? muted,
    Color? subtle,
    Color? accent,
    Color? teal,
    Color? tintGreen,
    Color? tintBlue,
    Color? tintPurple,
    Color? tintAmber,
    Color? errorBg,
    Color? errorIcon,
    Color? errorTitle,
    Color? errorText,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      strong: strong ?? this.strong,
      body: body ?? this.body,
      muted: muted ?? this.muted,
      subtle: subtle ?? this.subtle,
      accent: accent ?? this.accent,
      teal: teal ?? this.teal,
      tintGreen: tintGreen ?? this.tintGreen,
      tintBlue: tintBlue ?? this.tintBlue,
      tintPurple: tintPurple ?? this.tintPurple,
      tintAmber: tintAmber ?? this.tintAmber,
      errorBg: errorBg ?? this.errorBg,
      errorIcon: errorIcon ?? this.errorIcon,
      errorTitle: errorTitle ?? this.errorTitle,
      errorText: errorText ?? this.errorText,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      strong: l(strong, other.strong),
      body: l(body, other.body),
      muted: l(muted, other.muted),
      subtle: l(subtle, other.subtle),
      accent: l(accent, other.accent),
      teal: l(teal, other.teal),
      tintGreen: l(tintGreen, other.tintGreen),
      tintBlue: l(tintBlue, other.tintBlue),
      tintPurple: l(tintPurple, other.tintPurple),
      tintAmber: l(tintAmber, other.tintAmber),
      errorBg: l(errorBg, other.errorBg),
      errorIcon: l(errorIcon, other.errorIcon),
      errorTitle: l(errorTitle, other.errorTitle),
      errorText: l(errorText, other.errorText),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The palette for the current light/dark theme.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  static const navy = Color(0xFF123047);
  static const blue = Color(0xFF2677C9);
  static const teal = Color(0xFF16A6A1);
  static const canvas = Color(0xFFF5F7FA);
  static const border = Color(0xFFE5EBF2);
  static const mutedText = Color(0xFF68788C);

  static ThemeData get light => _build(Brightness.light, AppPalette.light);
  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: brightness,
      primary: p.accent,
      // Text/icons on the brand blue: white on the deep light-mode blue,
      // deep navy on the lighter dark-mode blue (white would be too faint).
      onPrimary: brightness == Brightness.dark ? const Color(0xFF06223D) : Colors.white,
      secondary: p.teal,
      surface: p.surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.canvas,
      extensions: <ThemeExtension<dynamic>>[p],
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.strong,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: p.strong, letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: p.surface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.borderStrong)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.borderStrong)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.accent, width: 1.6)),
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
        backgroundColor: p.surface,
        indicatorColor: p.accent.withOpacity(.10),
        labelTextStyle: MaterialStateProperty.resolveWith((states) => TextStyle(fontSize: 11, fontWeight: states.contains(MaterialState.selected) ? FontWeight.w800 : FontWeight.w500)),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
      textTheme: TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.25, color: p.strong),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, color: p.strong),
        bodyMedium: const TextStyle(height: 1.35),
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

/// Same status colors, lightened in dark mode so text and icons stay readable
/// on dark cards. Light mode returns exactly what [statusColor] does.
Color statusColorFor(BuildContext context, String statusAsString) {
  if (Theme.of(context).brightness != Brightness.dark) {
    return statusColor(statusAsString);
  }
  switch (statusAsString) {
    case 'received': return const Color(0xFF94A3B8);
    case 'washing': return const Color(0xFF5AA2E8);
    case 'drying': return const Color(0xFFF59E0B);
    case 'folding_pressing': return const Color(0xFFB794F4);
    case 'ready': return const Color(0xFF34D399);
    case 'picked_up': return const Color(0xFF94A3B8);
    default: return const Color(0xFF94A3B8);
  }
}
