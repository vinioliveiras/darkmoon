import 'package:flutter/material.dart';

/// Colors mirror the Python/PySide6 build's Photomator-inspired dark palette,
/// so the two versions stay visually consistent while this port is built out.
// Every gray below is a deliberately blue-leaning neutral (R < G < B, not
// R=G=B) rather than a true gray — a cool cast reads as more "premium
// dark UI" than a flat neutral gray and matches Photomator's own palette.
// Kept very subtle (R/B a couple points off G, not more) — a first pass
// with a much wider spread read as "too blue". Keep new tokens on this
// same restrained recipe instead of introducing pure neutrals.
class DarkmoonColors {
  static const background = Color(0xFF212224);
  static const panel = Color(0xFF121315);
  static const canvas = Color(0xFF191A1C);
  static const surfaceRaised = Color(0xFF303133);

  /// Standardized background for every modal window (Settings, About,
  /// Export, AI Denoise, the various confirm dialogs, …) — a very dark,
  /// near-black gray, deliberately darker than [surfaceRaised] so buttons/
  /// controls sitting on top of a dialog (still [surfaceRaised]) read as
  /// visibly raised above it instead of blending in. Same hex as [canvas]
  /// (the RAW viewport's own near-black ground) — kept as its own named
  /// token rather than reusing `canvas` directly so "dialogs" and "the
  /// image viewport" stay independently adjustable even though they
  /// happen to match today.
  static const dialogBackground = Color(0xFF191A1C);

  /// Fill for dropdown buttons/menus — darker than [surfaceRaised] but
  /// not as recessed as [dialogBackground] (that read as too dark once
  /// tried), sitting roughly between [panel] and [surfaceRaised].
  static const dropdownBackground = Color(0xFF242527);

  /// Outline color for windows/dialogs and every boxed component
  /// (dropdowns, cards, tooltips, …) — darker/softer than earlier so the
  /// contrast against the near-black backgrounds it usually sits on
  /// reads as a gentle edge rather than a hard line, while staying
  /// visibly lighter than [panel]/[dialogBackground] so it's still an
  /// outline, not invisible.
  static const border = Color(0xFF222325);

  /// Fill for a [_SectionCard]-style grouped card — darker still than
  /// the first pass (which read as too light a gray), only a hair
  /// lighter than [panel] so the card reads as faintly raised rather
  /// than flush with the panel background.
  static const sectionCardBackground = Color(0xFF1A1B1D);
  static const divider = Color(0xFF343537);

  /// A much darker divider variant — for a seam that should barely
  /// register (e.g. under the top File/Settings bar) rather than read
  /// as a visible rule the way [divider] does elsewhere.
  static const dividerDark = Color(0xFF131416);
  static const textPrimary = Color(0xFFE5E6E8);
  static const textSecondary = Color(0xFFC7C8CA);
  static const textMuted = Color(0xFF898A8C);
  static const accent = Color(0xFFFFFFFF);
  static const sliderTrack = Color(0xFFE6E7E9);

  /// A slider's *unfilled* rail — deliberately its own token rather than
  /// reusing [border] (that's what it did originally; several rounds of
  /// darkening [border] for window/component outlines quietly made every
  /// slider's empty track nearly invisible against the panel background
  /// as a side effect). Kept clearly lighter than the background tones a
  /// slider actually sits on, independent of how dark [border] gets.
  static const sliderInactiveTrack = Color(0xFF3C3E43);
}

/// The selected tab drawn the way a browser draws one: a box open at the
/// bottom, so the tab and the panel under it read as one surface.
///
/// Two things make that work, and both are why this is a hand-rolled
/// [Decoration] rather than a [BoxDecoration].
///
/// The outline is drawn on three sides only — left, top, right, with the
/// top corners rounded and the bottom ones square. A [Border] cannot skip a
/// side *and* round the corners next to it (`BorderRadius` with a partial
/// `Border` throws), so the path is built by hand.
///
/// And the rule Flutter paints under the whole tab bar has to stop at the
/// selected tab. That rule sits behind the bar (`_DividerPainter` is the
/// `painter` of a `CustomPaint` whose child is the bar), and the indicator
/// paints over it, so covering its last pixel row with [background] is
/// enough. Hence the colour: it is not a fill, it is the surface the tab
/// opens onto, and it has to match what is actually behind the bar or the
/// erasure shows up as a seam.
@immutable
class BrowserTabIndicator extends Decoration {
  const BrowserTabIndicator({
    this.background = DarkmoonColors.panel,
    this.outline = DarkmoonColors.divider,
    this.radius = 4.0,
  });

  /// The surface behind the tab bar — see the note above on why the
  /// indicator needs to know it.
  final Color background;

  final Color outline;

  /// Top corners only. Deliberately small: Photoshop's are square, and
  /// fully square looked wrong beside the app's own rounded controls.
  final double radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _BrowserTabPainter(this);

  @override
  bool operator ==(Object other) =>
      other is BrowserTabIndicator &&
      other.background == background &&
      other.outline == outline &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(background, outline, radius);
}

class _BrowserTabPainter extends BoxPainter {
  _BrowserTabPainter(this.decoration);

  final BrowserTabIndicator decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) {
      return;
    }
    final rect = offset & size;
    final r = decoration.radius;

    // Erase the bar's rule where this tab sits.
    //
    // The band is deliberately wider than the one-pixel rule it covers,
    // and that is not slack — it is the fix for a bug. A dialog whose
    // content changes height lands on a half-pixel offset half the time,
    // and there both the rule and an exactly-matching cover get
    // antialiased across the same two device rows at 50% each. Painting
    // 50% of the background over 50% of the rule leaves a quarter of it
    // showing: a faint line that appears out of nowhere the moment the
    // layout shifts, which is exactly how it was reported. Straddling the
    // rule instead covers both rows whole, at any offset.
    //
    // It costs a row above (inside the tab, already this colour) and a
    // row below the bar, where every use of this theme has either a gap
    // or a scroll view's own padding.
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.bottom - 2, rect.right, rect.bottom + 1),
      Paint()..color = decoration.background,
    );

    // Half-pixel inset so a 1px stroke lands on the pixel grid instead of
    // straddling two and coming out as a 2px smear.
    final left = rect.left + 0.5;
    final right = rect.right - 0.5;
    final top = rect.top + 0.5;
    final path = Path()
      ..moveTo(left, rect.bottom)
      ..lineTo(left, top + r)
      ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
      ..lineTo(right - r, top)
      ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
      ..lineTo(right, rect.bottom);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = decoration.outline,
    );
  }
}

/// Height of a tab across the app.
///
/// Well under Material's own 46: these sit above dense control panels and
/// dialogs where vertical space is the scarce thing, and a tab marked by
/// an outline does not need the height a filled one does to read. 34 was
/// still reading as tall (2026-09-07); this leaves a 12.5px label about
/// 7px of air either side, and the icon variant's 17px glyph about 5.
const double kTabHeight = 27.0;

/// Trailing space a vertical scroll view must leave for the scrollbar.
///
/// Flutter's desktop `Scrollbar` overlays the content it scrolls rather
/// than displacing it, so without this a slider's right end, a value
/// readout or a row's trailing icon sits underneath the thumb. There is no
/// theme setting that reserves the space — the scroll view has to.
///
/// Width of the thumb plus its cross-axis margin, plus a little air.
const double kScrollbarGutter = 14.0;

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
      inactiveTrackColor: DarkmoonColors.sliderInactiveTrack,
      thumbColor: Color(0xFFF2F2F2),
      overlayColor: Colors.transparent,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.5),
    ),
    dividerTheme: const DividerThemeData(
      color: DarkmoonColors.divider,
      thickness: 1,
      space: 1,
    ),
    // Flutter's desktop scroll behaviour wraps every scrollable in a
    // Scrollbar that draws *over* the content, so a slider's right end or
    // a list row's trailing icon ends up underneath the thumb. There is no
    // theme flag for "reserve space"; the fix is [kScrollbarGutter] as
    // trailing padding on the scroll view. This part makes the thumb quiet
    // and consistent — thin, inset, and only solid while it is being used.
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged) ||
            states.contains(WidgetState.hovered)) {
          return DarkmoonColors.textMuted;
        }
        return DarkmoonColors.divider;
      }),
    ),
    // Browser-style tabs, set once here so every TabBar in the app agrees.
    // The selected one is a box open at the bottom that swallows the rule
    // running under the bar; the unselected ones sit flat on the
    // background with that rule passing under them. See
    // [BrowserTabIndicator] — it defaults to the controls panel's own
    // background, so a TabBar on any other surface has to say so (the
    // dialogs do).
    tabBarTheme: const TabBarThemeData(
      indicator: BrowserTabIndicator(),
      // The indicator has to cover the whole tab, not just the label, or
      // it reads as a boxed word instead of a tab.
      indicatorSize: TabBarIndicatorSize.tab,
      // Material reserves 16 either side of a label. The editor's panel
      // is 300 wide and splits it four ways, which left each word 43px to
      // sit in and quietly faded the end off every one of them — in
      // English, and worse in German. The tabs stay equal-width and the
      // indicator still spans them whole; this only stops the padding
      // capping the word.
      labelPadding: EdgeInsets.symmetric(horizontal: 4),
      labelColor: DarkmoonColors.textPrimary,
      unselectedLabelColor: DarkmoonColors.textMuted,
      dividerColor: DarkmoonColors.divider,
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 12.5),
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
    // iOS/Apple-style switch (2026-09-01, explicit user request): a plain
    // capsule track (accent when on, a clearly-visible neutral gray when
    // off — the old off-track colour, `DarkmoonColors.border`, was tuned
    // for hairline dividers, not a control someone needs to read as "off"
    // at a glance, so it read as almost invisible against the panel
    // background) with a plain thumb and no Material halo/ripple. The
    // track is white (the app's accent) when on, so the thumb shifts to a
    // light gray when on — a white thumb on a white track was literally
    // invisible.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? const Color(0xFFBFBFC4)
            : Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? DarkmoonColors.accent
            : const Color(0xFF3A3B3E);
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
      // Same tone as the Settings dialog panel — covers both the File
      // menu (PopupMenuButton) and the image's right-click context menu
      // (showMenu), which share this one theme. The border below is on
      // `shape`, i.e. drawn once around the whole menu, not per item.
      color: DarkmoonColors.dialogBackground,
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
