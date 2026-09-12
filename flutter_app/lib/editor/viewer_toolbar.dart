// The toolbar over the image.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split (2026-09-10) is for navigation, not
// decoupling. Imports live in editor_screen.dart.
part of '../editor_screen.dart';

class _ViewerToolbar extends StatelessWidget {
  const _ViewerToolbar({
    required this.zoomLabel,
    required this.beforeAfterMode,
    required this.beforeAfterEnabled,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomFit,
    required this.onToggleBeforeAfter,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.aiDenoiseActive,
    required this.onOpenAiDenoise,
    required this.colorizeActive,
    required this.onOpenColorize,
    required this.removeActive,
    required this.removeModeActive,
    required this.onToggleRemove,
    required this.cropOverlayActive,
    required this.onToggleCropOverlay,
    required this.onExport,
    required this.exporting,
    required this.onReset,
    required this.onOpenSettings,
    required this.onOpenAbout,
  });

  final String zoomLabel;
  final bool beforeAfterMode;
  final bool beforeAfterEnabled;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomFit;
  final VoidCallback? onToggleBeforeAfter;

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// True when a level is already applied to the current photo — shown as
  /// a filled/selected button, same convention as Before/After.
  final bool aiDenoiseActive;
  final VoidCallback? onOpenAiDenoise;

  /// True when colorize (item 37, DDColor) is already applied to the
  /// current photo — same selected/filled-button convention as
  /// [aiDenoiseActive].
  final bool colorizeActive;
  final VoidCallback? onOpenColorize;

  /// Object removal (2026-09-12): filled while the photo carries
  /// removals, and while the mode is open for painting the next one.
  final bool removeActive;
  final bool removeModeActive;
  final VoidCallback? onToggleRemove;

  final bool cropOverlayActive;
  final VoidCallback? onToggleCropOverlay;

  final VoidCallback? onExport;
  final bool exporting;
  final VoidCallback onReset;

  /// The app's own two windows. They sit in the slot the toolbar already
  /// reserved to line up with the sidebar, which is the only part of this
  /// bar that was not already carrying something.
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Crop takes over the whole editor — the panel to the right shows
    // nothing but its own controls — so the toolbar goes with it: while
    // the overlay is open every button here is inert except Crop itself,
    // which is how you get out. Note this only removes the *tap*: AI
    // Denoise and Colorize stay filled if they are applied to the photo,
    // because that fill says what the photo has on it, not what you can
    // press.
    final locked = cropOverlayActive;
    return Container(
      height: 64,
      color: DarkmoonColors.panel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Lines up under the folder/preset sidebar above — the preset
          // Amount slider used to live here; it now lives in the controls
          // panel just below the histogram (2026-09-01). The width is what
          // keeps the zoom controls aligned with the sidebar's own edge;
          // the slot stopped being empty when Settings and About moved out
          // of the retired menu bar and into the space it was already
          // holding open.
          SizedBox(
            width: _controlsPanelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _ToolbarPill(
                  height: _squareButtonSize,
                  showChrome: false,
                  children: [
                    _ToolbarSegment(
                      icon: CupertinoIcons.gear_alt,
                      iconSize: _squareButtonIconSize,
                      width: _squareButtonSize,
                      onTap: locked ? null : onOpenSettings,
                      tooltip: l10n.menuSettings,
                    ),
                    _ToolbarSegment(
                      icon: CupertinoIcons.info_circle,
                      iconSize: _squareButtonIconSize,
                      width: _squareButtonSize,
                      onTap: locked ? null : onOpenAbout,
                      tooltip: l10n.menuAbout,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Not Flexible: every segment inside is either an icon or
                  // the fixed-width zoom-percent readout, neither of which
                  // has any room to give — letting this pill shrink would
                  // only crush the percentage text unreadable, never
                  // actually save space.
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.minus,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: locked ? null : onZoomOut,
                      ),
                      _ToolbarSegment(
                        label: zoomLabel,
                        width: _squareButtonSize,
                        padded: false,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.add,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: locked ? null : onZoomIn,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_up_left_arrow_down_right,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: locked ? null : onZoomFit,
                        tooltip: l10n.fitToWindow,
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Centered in this Expanded region (a Spacer on both
                  // sides, not just before it) — the toolbar's most
                  // frequently-used controls, deliberately given the most
                  // visually prominent slot rather than sitting bunched
                  // against the right-aligned Crop/Denoise/Before-After
                  // group.
                  _ToolbarPill(
                    height: _squareButtonSize,
                    // Kept boxed (unlike its sibling pills) — explicit
                    // user request (2026-09-01) to restore the outline
                    // for this specific trio, and its fill matches the
                    // edit sections' own background instead of the usual
                    // toolbar button tone (2026-09-01, explicit user
                    // request).
                    backgroundColor: DarkmoonColors.sectionCardBackground,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_uturn_left,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: (canUndo && !locked) ? onUndo : null,
                        tooltip: l10n.undoButton,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_2_circlepath,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: locked ? null : onReset,
                        tooltip: l10n.resetTooltip,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_uturn_right,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: (canRedo && !locked) ? onRedo : null,
                        tooltip: l10n.redoButton,
                      ),
                    ],
                  ),
                  const Spacer(),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.crop,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        selected: cropOverlayActive,
                        onTap: onToggleCropOverlay,
                        tooltip: l10n.cropButton,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.sparkles,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        selected: aiDenoiseActive,
                        onTap: locked ? null : onOpenAiDenoise,
                        tooltip: l10n.aiDenoiseButton,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.paintbrush,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        selected: colorizeActive,
                        onTap: locked ? null : onOpenColorize,
                        tooltip: l10n.colorizeButton,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.bandage,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        selected: removeActive || removeModeActive,
                        onTap: locked ? null : onToggleRemove,
                        tooltip: l10n.removeButton,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.square_split_2x1,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        selected: beforeAfterMode,
                        onTap: locked ? null : onToggleBeforeAfter,
                        tooltip: l10n.beforeAfterButton,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Lines up under _ControlsPanel above — holds Export, so it
          // stays reachable regardless of how far the panel above has
          // been scrolled. Reset now lives between Undo/Redo instead.
          // Must match _controlsPanelWidth (not a separate literal): a
          // stale 280 here (_ControlsPanel is actually 300) shifted this
          // whole trailing slot 20px narrower than the real column above
          // it, which pushed the pill Row before it 20px too far right —
          // visibly spilling the rightmost pill (Before/After) into the
          // real right-column boundary.
          SizedBox(
            width: _controlsPanelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: _squareButtonSize,
                      child: ElevatedButton.icon(
                        onPressed: (exporting || locked) ? null : onExport,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          // A step up from the standard (very subtle)
                          // border token — Export is the toolbar's one
                          // primary action, so its outline gets a little
                          // more presence without going full accent/white.
                          // Darker than textMuted (tried first, read as
                          // too light).
                          side: const BorderSide(
                            color: Color(0xFF45474A),
                            width: 1.0,
                          ),
                        ),
                        icon: exporting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                // Arrow leaving the box. square_arrow_down
                                // is the same glyph pointing in, which
                                // reads as importing — the opposite of what
                                // this button does.
                                CupertinoIcons.square_arrow_up,
                                size: 16,
                              ),
                        label: Text(
                          exporting
                              ? l10n.exportingButton
                              : l10n.exportPanelButton,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A macOS-style segmented-control shell: a single rounded, bordered pill
/// containing [children] (usually [_ToolbarSegment]s) laid out edge to
/// edge with hairline dividers between them, rather than each control
/// being its own separately-chromed Material button.
class _ToolbarPill extends StatelessWidget {
  const _ToolbarPill({
    required this.children,
    this.height = 40,
    this.showChrome = true,
    this.backgroundColor = DarkmoonColors.surfaceRaised,
  });

  final List<Widget> children;

  /// Lets a pill of purely square icon buttons (see [_ToolbarSegment]'s
  /// `width` matching this) stand out a bit larger than the default —
  /// e.g. Crop/AI Denoise/Before-After/Undo/Reset/Redo/Fit-to-window,
  /// which are tapped far more often than the zoom +/- pair.
  final double height;

  /// Whether the pill draws its background fill/border/segment dividers
  /// at all — off for the viewer toolbar's experiment in bare, boxless
  /// buttons. The shape (radius/clip) stays wired either way, so
  /// flipping this back to true restores the old boxed look exactly.
  final bool showChrome;

  /// Fill behind the pill when [showChrome] is true — defaults to the
  /// toolbar's usual button tone, but the Undo/Reset/Redo pill overrides
  /// this to [DarkmoonColors.sectionCardBackground] (2026-09-01, explicit
  /// user request: match the edit sections' own background).
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: showChrome
          ? BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: DarkmoonColors.border),
            )
          : BoxDecoration(borderRadius: BorderRadius.circular(7)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && showChrome)
              Container(width: 1, color: DarkmoonColors.border),
            // Each segment decides for itself whether it can afford to
            // shrink (see _ToolbarSegment) — a blanket Flexible here would
            // give every segment equal shrink priority regardless of
            // whether it actually has room to give, which is exactly what
            // crushed the zoom percentage readout down to unreadable
            // before this while "Fit to window" barely budged.
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One segment of a [_ToolbarPill] — an icon or short label, flat-filled
/// with the accent color when [selected] rather than boxed in its own
/// bordered button. Plain [GestureDetector] rather than [InkWell]: the
/// selected fill is the only feedback state this needs, and skipping
/// Material's splash keeps it feeling like a native toggle instead of an
/// Android ripple.
class _ToolbarSegment extends StatelessWidget {
  const _ToolbarSegment({
    this.icon,
    this.label,
    this.selected = false,
    this.onTap,
    this.tooltip,
    this.width,
    this.padded = true,
    this.iconSize = 16,
  });

  final IconData? icon;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;
  final String? tooltip;
  final double? width;
  final double iconSize;
  // A fixed-[width] segment (e.g. the zoom-percent readout) already sizes
  // itself to fit its content exactly — adding the usual label padding on
  // top would eat into that same fixed width and leave too little room for
  // the text, so callers with a known-tight width opt out of it here.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? DarkmoonColors.background
        : (onTap == null
              ? DarkmoonColors.textMuted
              : DarkmoonColors.textSecondary);
    final content = Container(
      width: width,
      height: double.infinity,
      alignment: Alignment.center,
      padding: padded
          ? const EdgeInsets.symmetric(horizontal: 7)
          : EdgeInsets.zero,
      color: selected ? DarkmoonColors.accent : Colors.transparent,
      child: icon != null
          ? Icon(icon, size: iconSize, color: foreground)
          : Text(
              label!,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: 12.5, color: foreground),
            ),
    );
    final tappable = onTap == null
        ? content
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: content,
            ),
          );
    final result = tooltip == null
        ? tappable
        : Tooltip(message: tooltip!, child: tappable);
    // Only a plain (non-fixed-width) label can safely give up space —
    // icons and the zoom-percent readout have nothing left to trim
    // without becoming unreadable/clipped, so only *this* case opts into
    // shrinking (and ellipsizing) inside its [_ToolbarPill].
    return icon == null && width == null ? Flexible(child: result) : result;
  }
}
