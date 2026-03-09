import 'package:flutter/material.dart';

class CssTheme {
  // 🎨 Base colors (matcher mobil appen)
  static const bg = Color(0xFF7B7B7B); // bakgrunn bak sidene (mobil: 0xFF7B7B7B)
  static const surface = Color(0xFFE7E7E7); // cards
  static const surface2 = Color(0xFFDDDDDD); // felt / highlight

  static const header = Color(0xFF000000); // svart header
  static const outline = Color(0x33000000); // light border

  static const text = Color(0xFF111111);
  static const textMuted = Color(0xFF444444);

  // Accent
  static const primary = Color(0xFF00C853); // grønn (status)
  static const primary2 = Color(0xFF0F0F0F); // nesten svart

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: primary2,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary2,
      onPrimary: Colors.white,
      onSurface: text,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      colorScheme: scheme,

      // ✅ Cards (containers)
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      // ✅ Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary2, width: 2),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),

      // ✅ Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary2,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary2,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      // ✅ ListTile style (Dashboard)
      listTileTheme: const ListTileThemeData(
        iconColor: text,
        textColor: text,
      ),

      // ✅ Text style
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(fontWeight: FontWeight.w900, color: text),
        titleLarge: const TextStyle(fontWeight: FontWeight.w900, color: text),
        titleMedium: const TextStyle(fontWeight: FontWeight.w900, color: text),
        titleSmall: const TextStyle(fontWeight: FontWeight.w900, color: text),
      ),
    );
  }
}