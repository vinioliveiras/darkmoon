import 'package:flutter/material.dart';

/// Colors mirror the Python/PySide6 build's Photomator-inspired dark palette,
/// so the two versions stay visually consistent while this port is built out.
class DarkmoonColors {
  static const background = Color(0xFF1E1E20);
  static const panel = Color(0xFF1B1B1D);
  static const canvas = Color(0xFF141416);
  static const filmstrip = Color(0xFF19191B);
  static const surfaceRaised = Color(0xFF2C2C30);
  static const border = Color(0xFF38383D);
  static const divider = Color(0xFF303034);
  static const textPrimary = Color(0xFFE6E6E8);
  static const textSecondary = Color(0xFFC8C8CC);
  static const textMuted = Color(0xFF8A8A90);
  static const accent = Color(0xFF0A84FF);
  static const sliderTrack = Color(0xFFE8E8EA);
}

ThemeData buildDarkmoonTheme() {
  const scheme = ColorScheme.dark(
    surface: DarkmoonColors.background,
    primary: DarkmoonColors.accent,
    onSurface: DarkmoonColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: DarkmoonColors.background,
    canvasColor: DarkmoonColors.background,
    fontFamily: 'Segoe UI',
    sliderTheme: const SliderThemeData(
      trackHeight: 1,
      activeTrackColor: DarkmoonColors.sliderTrack,
      inactiveTrackColor: DarkmoonColors.border,
      thumbColor: Color(0xFFF2F2F2),
      overlayColor: Colors.transparent,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
    ),
    dividerTheme: const DividerThemeData(
      color: DarkmoonColors.divider,
      thickness: 1,
      space: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DarkmoonColors.surfaceRaised,
        foregroundColor: DarkmoonColors.textPrimary,
        side: const BorderSide(color: DarkmoonColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: DarkmoonColors.surfaceRaised,
        foregroundColor: DarkmoonColors.textPrimary,
        side: const BorderSide(color: DarkmoonColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: DarkmoonColors.textSecondary, fontSize: 12.5),
      labelSmall: TextStyle(
        color: DarkmoonColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    ),
  );
}
