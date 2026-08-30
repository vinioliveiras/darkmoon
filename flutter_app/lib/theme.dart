import 'package:flutter/material.dart';

/// Colors mirror the Python/PySide6 build's Photomator-inspired dark palette,
/// so the two versions stay visually consistent while this port is built out.
class DarkmoonColors {
  static const background = Color(0xFF1E1E20);
  static const panel = Color(0xFF1B1B1D);
  static const canvas = Color(0xFF141416);
  static const filmstrip = Color(0xFF19191B);
  static const surfaceRaised = Color(0xFF2C2C30);

  /// Standardized background for every modal window (Settings, About,
  /// Export, AI Denoise, the various confirm dialogs, …) — a very dark,
  /// near-black gray, deliberately darker than [surfaceRaised] so buttons/
  /// controls sitting on top of a dialog (still [surfaceRaised]) read as
  /// visibly raised above it instead of blending in. Same hex as [canvas]
  /// (the RAW viewport's own near-black ground) — kept as its own named
  /// token rather than reusing `canvas` directly so "dialogs" and "the
  /// image viewport" stay independently adjustable even though they
  /// happen to match today.
  static const dialogBackground = Color(0xFF141416);

  /// Darker, more recessed fill for dropdown buttons/menus — same near-
  /// black tone as [dialogBackground] rather than the lighter
  /// [surfaceRaised] most other boxed controls use, matching Photomator's
  /// own darker chrome.
  static const dropdownBackground = Color(0xFF141416);
  static const border = Color(0xFF38383D);
  static const divider = Color(0xFF303034);
  static const textPrimary = Color(0xFFE6E6E8);
  static const textSecondary = Color(0xFFC8C8CC);
  static const textMuted = Color(0xFF8A8A90);
  static const accent = Color(0xFFFFFFFF);
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
    // The Material ripple is the single biggest thing that reads as
    // "Android" rather than "Mac" — macOS controls give a flat opacity/
    // highlight change on press, never an expanding ripple. Turning it
    // off globally (each button's own hover/pressed overlay below still
    // gives feedback) is what makes the rest of this theme actually look
    // native-ish instead of just Material-with-different-colors.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
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
      style:
          ElevatedButton.styleFrom(
            backgroundColor: DarkmoonColors.surfaceRaised,
            foregroundColor: DarkmoonColors.textPrimary,
            disabledBackgroundColor: DarkmoonColors.surfaceRaised.withValues(
              alpha: 0.5,
            ),
            side: const BorderSide(color: DarkmoonColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            elevation: 0,
            shadowColor: Colors.transparent,
            overlayColor: Colors.white.withValues(alpha: 0.06),
          ).copyWith(
            // A flat opacity dip on press instead of the ripple — the
            // closest cheap equivalent to how macOS buttons darken/lighten
            // slightly when clicked.
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.14);
              }
              if (states.contains(WidgetState.hovered)) {
                return Colors.white.withValues(alpha: 0.06);
              }
              return Colors.transparent;
            }),
          ),
    ),
    // Experiment (2026-08-30): plain icon buttons — no boxed background,
    // no border — matching Photomator's toolbar, where only primary
    // actions get a pill and everything else is a bare glyph. Hover/press
    // still give a flat opacity overlay for feedback (below). Being
    // tried in the editor's controls panel first.
    iconButtonTheme: IconButtonThemeData(
      style:
          IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: DarkmoonColors.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.14);
              }
              if (states.contains(WidgetState.hovered)) {
                return Colors.white.withValues(alpha: 0.06);
              }
              return Colors.transparent;
            }),
          ),
    ),
    // macOS-style switch: a plain rounded track (accent when on, subtle
    // gray when off) with a plain thumb — no Material halo/ripple around
    // it. The track is now white (the app's accent), so the thumb has to
    // shift to a light gray when on — a white thumb on a white track was
    // literally invisible.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? const Color(0xFFBFBFC4)
            : Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? DarkmoonColors.accent
            : DarkmoonColors.border;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DarkmoonColors.textPrimary,
        overlayColor: Colors.transparent,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: DarkmoonColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: DarkmoonColors.border),
      ),
      elevation: 8,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: DarkmoonColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DarkmoonColors.border),
      ),
      textStyle: const TextStyle(
        color: DarkmoonColors.textPrimary,
        fontSize: 11.5,
      ),
    ),
    // Without this, SnackBars fall back to Material's own light-surface
    // default (a near-white bar) regardless of `brightness: Brightness.
    // dark` above — ThemeData doesn't derive it from colorScheme.surface
    // the way most other widgets do, so it has to be set explicitly here
    // like every other themed surface in this file.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DarkmoonColors.surfaceRaised,
      contentTextStyle: const TextStyle(
        color: DarkmoonColors.textPrimary,
        fontSize: 12.5,
      ),
      actionTextColor: DarkmoonColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: DarkmoonColors.border),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        color: DarkmoonColors.textSecondary,
        fontSize: 12.5,
      ),
      labelSmall: TextStyle(
        color: DarkmoonColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    ),
  );
}
