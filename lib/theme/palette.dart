import 'package:flutter/material.dart';

/// Starloom's palette: a moonlit stop-motion set. Ink-purple night, pale
/// ghost blue, bone white, with candle and pumpkin glows.
class Clay {
  static const night = Color(0xFF0D0A14);
  static const dusk = Color(0xFF1A1428);
  static const bruise = Color(0xFF34284D);
  static const plum = Color(0xFF4A3466);
  static const ghost = Color(0xFF8FA9C4);
  static const moss = Color(0xFF55705A);
  static const bone = Color(0xFFEDE3D0);
  static const ash = Color(0xFF9B93A8);
  static const candle = Color(0xFFF2C14E);
  static const pumpkin = Color(0xFFE0782F);
  static const rose = Color(0xFFB0405F);

  /// Colors for little clay pebbles next to songs, picked by a hash.
  static const pebbles = [
    Color(0xFF6F5A8E), Color(0xFF557A8C), Color(0xFF8C5A6E), Color(0xFF5E7A5A),
    Color(0xFF9A6A3E), Color(0xFF4F5F8F), Color(0xFF7E4E5E), Color(0xFF6A7F98),
  ];

  static const display = 'MysteryQuest';
  static const storybook = 'IMFell';

  static ThemeData theme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: plum,
        brightness: Brightness.dark,
        primary: candle,
        secondary: ghost,
        surface: dusk,
      ),
      scaffoldBackgroundColor: night,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: bone, displayColor: bone),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: bruise,
        contentTextStyle: TextStyle(color: bone),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dusk,
        hintStyle: const TextStyle(color: ash),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: dusk, showDragHandle: true),
      dialogTheme: const DialogThemeData(backgroundColor: dusk),
    );
  }

  static TextStyle title(double size, {Color color = bone}) =>
      TextStyle(fontFamily: display, fontSize: size, color: color, height: 1.1);

  static TextStyle book(double size, {Color color = ash}) =>
      TextStyle(fontFamily: storybook, fontSize: size, color: color);
}
