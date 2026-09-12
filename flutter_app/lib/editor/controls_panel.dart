// The controls panel: every adjustment section and its tab strips.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split (2026-09-10) is for navigation, not
// decoupling. Imports live in editor_screen.dart.
part of '../editor_screen.dart';

class _ControlsPanel extends StatefulWidget {
  const _ControlsPanel({
    required this.values,
    required this.actions,
    required this.histogram,
    required this.metadata,
    required this.colorProfileMode,
    required this.colorProfileChoice,
    required this.userColorProfiles,
    required this.customProfileMissing,
    required this.levelBusy,
    required this.uprightBusy,
    required this.tabbedLayout,
    required this.tabIcons,
    required this.selectedProfileIsUsers,
    required this.onExport,
    required this.exporting,
    required this.enabled,
    required this.curves,
    required this.masks,
    required this.activeMaskId,
    required this.maskOverlayVisible,
    required this.maskOverlayOpacity,
    required this.brushRadius,
    required this.brushHardness,
    required this.brushErase,
    required this.aiMasksResolving,
    required this.aiMaskFailures,
    required this.brushFlow,
    required this.cropOverlayActive,
    required this.removeModeActive,
    required this.removeHasStrokes,
    required this.removalCount,
    required this.removalBusy,
    required this.cropTransform,
    required this.cropAspectRatio,
    required this.guidedModeActive,
    required this.lensCorrection,
    required this.lensProfiles,
    required this.resolvedLensProfile,
    required this.wbEyedropperActive,
  });

  final Map<String, double> values;

  /// Every callback the panel fires — one object the editor builds once,
  /// since they are all stable tear-offs of its own methods.
  final _ControlsPanelActions actions;
  final Histogram? histogram;
  final RawMetadata? metadata;
  final bool wbEyedropperActive;

  /// How strongly the *entire current edit* renders, 0..200% — see the
  /// top-level `_globalEditAmountKey`/`withGlobalEditAmountApplied`. Sits
  /// just below the histogram (2026-09-01) — previously lived in the
  /// viewer toolbar under the preset sidebar.

  /// COLOR PROFILE section's mode dropdown — see [ColorProfileMode]'s doc.
  final ColorProfileMode colorProfileMode;

  /// What the COLOR PROFILE dropdown is showing: a `ColorProfileMode`
  /// index for a built-in, or a `ColorProfile.id` for one of the user's.
  final int colorProfileChoice;
  final Map<int, ColorProfile> userColorProfiles;

  /// True when this photo refers to a user profile that is not installed —
  /// drives both the dropdown's placeholder entry and the warning below it.
  final bool customProfileMissing;

  /// Group the sections into tabs, or list them all in one scroll — see
  /// `AppSettings.tabbedControlsPanel`.
  final bool tabbedLayout;

  /// Whether [tabbedLayout]'s tabs carry a glyph instead of a word.
  final bool tabIcons;

  final bool levelBusy;

  final bool uprightBusy;

  /// Whether the selected profile is one the user owns. The built-ins are
  /// not editable, renameable or deletable, so their menu offers only
  /// import.
  final bool selectedProfileIsUsers;

  final VoidCallback? onExport;
  final bool exporting;

  /// False when no photo is loaded — every control (sliders, reset,
  /// export) is locked rather than acting on a placeholder value.
  final bool enabled;

  final PhotoCurves curves;

  final List<MaskLayer> masks;
  final String activeMaskId;
  final bool maskOverlayVisible;
  final Map<MaskType, double> maskOverlayOpacity;

  final double brushRadius;
  final double brushHardness;
  final bool brushErase;

  /// Flow mask's live per-pass deposit-rate tool setting — shares the
  /// brush-drawing controls/state above, this is its one extra slider.
  final double brushFlow;

  /// Which masks a model is currently thinking about, and which ones it
  /// failed on (with the reason) — the panel is the only place that can
  /// tell the user an AI mask is empty because it is still computing
  /// rather than because it selected nothing.
  final Set<String> aiMasksResolving;
  final Map<String, String> aiMaskFailures;

  final bool cropOverlayActive;

  /// Object removal mode takes the panel like crop does — see
  /// [_RemoveObjectsPanel].
  final bool removeModeActive;
  final bool removeHasStrokes;
  final int removalCount;
  final bool removalBusy;
  final CropTransformParams cropTransform;
  final double? cropAspectRatio;

  /// See [CropOverlay.guidedModeActive].
  final bool guidedModeActive;

  final LensCorrectionParams lensCorrection;
  final List<LensProfile> lensProfiles;

  /// The profile actually in effect for the selected photo right now --
  /// see `_resolvedLensProfileFor`'s doc comment.
  final LensProfile? resolvedLensProfile;

  @override
  State<_ControlsPanel> createState() => _ControlsPanelState();
}

/// Which tab a section lives under. Three for now; the panel used to be
/// one long scroll of all eleven, which meant Lens Correction was a dozen
/// section-heights below the Tone sliders people actually reach for.
/// Declaration order is the order the tabs appear in: the bar is built
/// from [_ControlsTab.values].
enum _ControlsTab { adjust, details, colour, effects }

/// Which tab each entry of [_sections] belongs to.
///
/// A key missing from here would have thrown on every build with a bang
/// operator, and hiding the section instead would be worse — it would
/// simply vanish from the panel with nothing to explain it. So the lookup
/// falls back to Adjust and an assert names the omission during
/// development, where it can still be fixed.
const _sectionTabs = <String, _ControlsTab>{
  // White Balance sits with the tonal work, not under Colour, even though
  // it is plainly a colour control. It is one of the first things touched
  // on almost every photo, and the existing editor test caught it
  // disappearing from the opening tab. Meridian puts it at the top of
  // Basic for the same reason.
  'WHITE BALANCE': _ControlsTab.adjust,
  'TONE': _ControlsTab.adjust,
  // Presence (Texture, Clarity, Dehaze and friends) and Detail
  // (sharpening, noise reduction) both act on local contrast and are both
  // judged at 100% zoom on a patch of texture, not while setting overall
  // exposure. They belong together, on their own tab.
  'PRESENCE': _ControlsTab.details,
  'DETAIL': _ControlsTab.details,
};

class _ControlsPanelState extends State<_ControlsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: _ControlsTab.values.length, vsync: this)
        ..addListener(() {
          // The tab bar animates on its own, but the section list below is
          // rebuilt from the index rather than living in a TabBarView, so it
          // needs to be told.
          if (mounted) {
            setState(() {});
          }
        });

  _ControlsTab get _tab => _ControlsTab.values[_tabController.index];

  /// Whether a section belongs to the tab currently showing. Always true
  /// with tabs off, which is what turns the three filtered lists back into
  /// the single flat one.
  bool _inTab(_ControlsTab tab) => !widget.tabbedLayout || _tab == tab;

  /// [_sections]'s tab, defaulting rather than throwing — see [_sectionTabs].
  _ControlsTab _tabOf(String section) {
    assert(
      _sectionTabs.containsKey(section),
      'section "$section" has no tab in _sectionTabs; it will appear under '
      'Adjust until one is assigned',
    );
    return _sectionTabs[section] ?? _ControlsTab.adjust;
  }

  String _tabLabel(AppLocalizations l10n, _ControlsTab tab) => switch (tab) {
    _ControlsTab.adjust => l10n.controlsTabAdjust,
    _ControlsTab.colour => l10n.controlsTabColour,
    _ControlsTab.details => l10n.controlsTabDetails,
    _ControlsTab.effects => l10n.controlsTabEffects,
  };

  IconData _tabIcon(_ControlsTab tab) => switch (tab) {
    _ControlsTab.adjust => CupertinoIcons.slider_horizontal_3,
    _ControlsTab.details => CupertinoIcons.circle_righthalf_fill,
    _ControlsTab.colour => CupertinoIcons.circle_grid_hex,
    _ControlsTab.effects => CupertinoIcons.fx,
  };

  Widget _buildRemovePanel() => _RemoveObjectsPanel(
    brushRadius: widget.brushRadius,
    brushHardness: widget.brushHardness,
    brushErase: widget.brushErase,
    hasStrokes: widget.removeHasStrokes,
    removalCount: widget.removalCount,
    busy: widget.removalBusy,
    actions: widget.actions,
  );

  Widget _buildCropPanel() => _CropTransformPanel(
    params: widget.cropTransform,
    onChanged: widget.actions.onCropTransformChanged,
    onChangeEnd: widget.actions.onCropTransformChangeEnd,
    aspectRatio: widget.cropAspectRatio,
    onAspectRatioChanged: widget.actions.onCropAspectRatioChanged,
    onDone: widget.actions.onToggleCropOverlay,
    onReset: widget.actions.onResetCropTransform,
    onStraighteningChanged: widget.actions.onStraighteningChanged,
    guidedModeActive: widget.guidedModeActive,
    onToggleGuidedMode: widget.actions.onToggleGuidedMode,
    onLevel: widget.actions.onLevel,
    levelBusy: widget.levelBusy,
    onUpright: widget.actions.onUpright,
    uprightBusy: widget.uprightBusy,
  );

  Widget _buildControlsTabBar(AppLocalizations l10n) => TabBar(
    controller: _tabController,
    // Every appearance choice lives in the app theme's tabBarTheme, so
    // this bar and the dialogs' all look alike without any of them saying
    // so individually.
    // Words by default, glyphs on request (Settings > Tab labels). A
    // word says which section it opens outright; a glyph is more compact
    // but has to be learned. Either way the name reaches the semantics
    // tree — an icon with no accessible name is unreadable to a screen
    // reader, and it costs nothing to give it one.
    tabs: [
      for (final tab in _ControlsTab.values)
        if (widget.tabIcons)
          Tab(
            height: kTabHeight,
            icon: Tooltip(
              message: _tabLabel(l10n, tab),
              child: Semantics(
                label: _tabLabel(l10n, tab),
                child: Icon(_tabIcon(tab), size: 17),
              ),
            ),
          )
        else
          Tab(height: kTabHeight, text: _tabLabel(l10n, tab)),
    ],
  );

  /// Section names the user has collapsed, Meridian-style — every section
  /// starts expanded, matching the panel's previous (always-open) layout.
  final Set<String> _collapsed = {};

  /// A category switch flips (and its own slide animation starts) the
  /// instant it's tapped — [onChanged] fires synchronously, same as any
  /// slider drag. What's deferred is [onChangeEnd]: the expensive settled
  /// render it triggers runs its GPU shader chain on the main isolate
  /// (see `render_gpu.dart`'s doc comment) and can stall the frame pump
  /// long enough to freeze the switch's own animation mid-slide if it
  /// starts immediately — a slider's thumb has no such animation to
  /// interrupt after release, which is why this was only ever visible on
  /// toggles (2026-09-02). Giving the animation a head start (skipped
  /// entirely when the user has animations off, via [AnimationsConfig])
  /// doesn't make the render itself any faster — it only changes *when*
  /// the resulting stall lands, not whether it happens.
  void _toggleCategoryEnabled(String key, bool value) {
    widget.actions.onChanged(key, value ? 1 : 0);
    final delay = AnimationsConfig.duration(
      context,
      const Duration(milliseconds: 200),
    );
    if (delay == Duration.zero) {
      widget.actions.onChangeEnd(key, value ? 1 : 0);
      return;
    }
    Future.delayed(delay, () {
      if (!mounted) return;
      widget.actions.onChangeEnd(key, value ? 1 : 0);
    });
  }

  // The crop panel used to be inside the scrolling section list, so
  // opening it scrolled the panel to the top to bring it into view. It
  // now sits in the fixed block above the tabs and is always visible, so
  // there is nothing left to scroll to.

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// The camera as-shot White Balance for the current photo — the neutral
  /// reference the Temperature/Tint sliders default to.
  ({double kelvin, double tint}) get _asShot => (
    kelvin: widget.metadata?.asShotKelvin ?? wbDefaultKelvin,
    tint: widget.metadata?.asShotTint ?? wbDefaultTint,
  );

  /// The neutral point for the Temperature/Tint sliders — where the value
  /// marker sits and what a double-click resets to. It follows the
  /// selected White Balance mode: a fixed lighting preset uses that
  /// preset's Kelvin/Tint, everything else (As Shot / Auto / Custom) uses
  /// the camera as-shot. Null for any non-WB slider.
  double? _wbSliderFallback(String name) {
    if (name != 'Temperature' && name != 'Tint') {
      return null;
    }
    final modeIndex = (widget.values['WhiteBalanceMode'] ?? 0).toInt().clamp(
      0,
      WbMode.values.length - 1,
    );
    final preset = wbModePreset(WbMode.values[modeIndex]);
    if (preset != null) {
      return name == 'Temperature' ? preset.kelvin : preset.tint;
    }
    return name == 'Temperature' ? _asShot.kelvin : _asShot.tint;
  }

  String _wbModeLabel(AppLocalizations l10n, WbMode mode) => switch (mode) {
    WbMode.asShot => l10n.wbModeAsShot,
    WbMode.auto => l10n.wbModeAuto,
    WbMode.daylight => l10n.wbModeDaylight,
    WbMode.cloudy => l10n.wbModeCloudy,
    WbMode.shade => l10n.wbModeShade,
    WbMode.tungsten => l10n.wbModeTungsten,
    WbMode.fluorescent => l10n.wbModeFluorescent,
    WbMode.flash => l10n.wbModeFlash,
    WbMode.custom => l10n.wbModeCustom,
  };

  String _colorProfileModeLabel(AppLocalizations l10n, ColorProfileMode mode) =>
      switch (mode) {
        ColorProfileMode.darkmoonDefault => l10n.colorProfileModeDefault,
        ColorProfileMode.vivid => l10n.colorProfileModeFlat,
        // Only reached when the profile this photo points at is gone; a
        // resolvable one is listed under its own name instead.
        ColorProfileMode.custom => l10n.colorProfileModeMissing,
      };

  Widget _buildWhiteBalanceModeRow(
    AppLocalizations l10n,
    Map<String, double> values,
  ) {
    final modeIndex = (values['WhiteBalanceMode'] ?? 0).toInt().clamp(0, 8);
    return Row(
      children: [
        Expanded(
          child: StyledDropdown<int>(
            value: modeIndex,
            // Short fixed list — show every mode without a scroll.
            maxMenuHeight: 460,
            items: [
              for (final mode in WbMode.values)
                StyledDropdownItem(
                  value: mode.index,
                  label: _wbModeLabel(l10n, mode),
                ),
            ],
            onChanged: (i) =>
                widget.actions.onWhiteBalanceMode(WbMode.values[i]),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 34,
          height: 34,
          child: IconButton(
            tooltip: l10n.wbEyedropperTooltip,
            isSelected: widget.wbEyedropperActive,
            onPressed: widget.actions.onToggleWbEyedropper,
            icon: const Icon(CupertinoIcons.eyedropper, size: 15),
          ),
        ),
      ],
    );
  }

  /// Which Color Curve channel is currently shown in the editor — only one
  /// at a time, switched via the R/G/B tabs, matching Meridian.
  String _activeColorChannel = 'red';

  /// Which Color Mixer band is currently shown — one of the 8 capitalized
  /// channel names used in the "Mixer" + channel + "Hue/Saturation/
  /// Luminance" slider keys (e.g. `'Red'`), switched via the dot picker.
  /// Only relevant in [_mixerViewMode] `'Mixer'` — `'HSL'` shows every
  /// channel at once instead.
  String _activeMixerChannel = 'Red';

  /// Color Mixer's own display mode, matching Meridian's Mixer/HSL toggle
  /// for the same underlying data: `'Mixer'` shows one selected channel's
  /// three sliders at a time (the dot picker above); `'HSL'` shows three
  /// stacked groups (Hue, Saturation, Luminance), each listing all 8
  /// channels together, for comparing/adjusting across channels within one
  /// attribute rather than across attributes within one channel.
  String _mixerViewMode = 'Mixer';

  /// Which Color Grading range's wheel is currently shown — one of
  /// 'Shadows', 'Midtones', 'Highlights' (the "Grade" + range +
  /// "Hue/Saturation/Luminance" slider key prefix), switched via tabs.
  String _activeGradeRange = 'Shadows';

  void _toggleSection(String section) {
    setState(() {
      if (!_collapsed.add(section)) {
        _collapsed.remove(section);
      }
    });
  }

  /// Builds one section: a [_SectionHeader] plus its collapsible body,
  /// wrapped together in a single [_SectionCard]. Returns a one-element
  /// list (not the widget directly) so call sites can keep spreading it
  /// into a `children:` list with `...`.
  List<Widget> _section(
    String key, {
    required String label,
    bool? enabled,
    ValueChanged<bool>? onEnabledChanged,
    required List<Widget> children,
  }) => [
    _SectionCard(
      label: label,
      collapsed: _collapsed.contains(key),
      onTap: () => _toggleSection(key),
      enabled: enabled,
      // Switching a section off collapses it, and switching it back on
      // opens it again. A section that is off does nothing, so leaving
      // its sliders on screen is noise; and a section that is on but
      // still collapsed reads as broken, since nothing you can see
      // changed when you enabled it.
      onEnabledChanged: onEnabledChanged == null
          ? null
          : (value) {
              setState(() {
                if (value) {
                  _collapsed.remove(key);
                } else {
                  _collapsed.add(key);
                }
              });
              onEnabledChanged(value);
            },
      body: _CollapsibleSection(
        collapsed: _collapsed.contains(key),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    final histogram = widget.histogram;
    final onChanged = widget.actions.onChanged;
    final onChangeEnd = widget.actions.onChangeEnd;
    final enabled = widget.enabled;
    final curves = widget.curves;
    final onToneCurveChanged = widget.actions.onToneCurveChanged;
    final onToneCurveChangeEnd = widget.actions.onToneCurveChangeEnd;
    final onColorCurveChanged = widget.actions.onColorCurveChanged;
    final onColorCurveChangeEnd = widget.actions.onColorCurveChangeEnd;
    final activeMask = widget.masks
        .where((m) => m.id == widget.activeMaskId)
        .firstOrNull;
    final isBrushActive =
        activeMask?.type == MaskType.brush || activeMask?.type == MaskType.flow;
    final isFlowActive = activeMask?.type == MaskType.flow;
    final isColorRangeActive = activeMask?.type == MaskType.colorRange;
    final isLuminanceActive = activeMask?.type == MaskType.luminance;
    final isAiMaskActive =
        activeMask != null && aiMaskTypes.contains(activeMask.type);
    final l10n = AppLocalizations.of(context)!;
    // Hoisted out of the tree because where it goes depends on the
    // layout: pinned above the tabs in the tabbed panel, and inside
    // the one scroll view with everything else in the flat list, which
    // is the behaviour turning the tabs off is meant to restore.
    final masksBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MaskLayerControls(
          masks: widget.masks,
          activeId: widget.activeMaskId,
          onToggleEnabled: widget.actions.onToggleMaskEnabled,
          onToggleInverted: widget.actions.onToggleMaskInverted,
          onClone: widget.actions.onCloneMask,
          onDelete: widget.actions.onDeleteMask,
          onOpacityChanged: widget.actions.onMaskOpacityChanged,
          onOpacityChangeEnd: widget.actions.onMaskOpacityChangeEnd,
          overlayVisible: widget.maskOverlayVisible,
          onToggleOverlayVisible: widget.actions.onToggleMaskOverlayVisible,
          overlayOpacity: widget.maskOverlayOpacity,
        ),
        if (isBrushActive) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SliderRow(
              name: l10n.maskBrushSizeLabel,
              min: 0.01,
              max: 0.4,
              value: widget.brushRadius,
              decimals: 2,
              onChanged: widget.actions.onBrushRadiusChanged,
              onChangeEnd: widget.actions.onBrushRadiusChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SliderRow(
              name: l10n.maskBrushHardnessLabel,
              min: 0,
              max: 1,
              value: widget.brushHardness,
              decimals: 2,
              onChanged: widget.actions.onBrushHardnessChanged,
              onChangeEnd: widget.actions.onBrushHardnessChanged,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.maskBrushEraseLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              // Same 34x21 SizedBox+FittedBox a section
              // header's switch uses, so the two read as
              // the same control. FittedBox rather than
              // Transform.scale for the reason documented
              // there: scale shrinks only the painting and
              // leaves a full-size box reserving space.
              SizedBox(
                width: 34,
                height: 21,
                child: FittedBox(
                  child: Switch(
                    value: widget.brushErase,
                    onChanged: (_) => widget.actions.onToggleBrushErase(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 32,
                width: 32,
                child: IconButton(
                  tooltip: l10n.maskUndoStrokeTooltip,
                  onPressed: widget.actions.onUndoStroke,
                  icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 15),
                ),
              ),
            ],
          ),
          if (isFlowActive)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SliderRow(
                name: l10n.flowAmountLabel,
                min: 1,
                max: 100,
                value: widget.brushFlow,
                decimals: 0,
                defaultValue: defaultFlowAmount,
                onChanged: widget.actions.onBrushFlowChanged,
                onChangeEnd: widget.actions.onBrushFlowChanged,
              ),
            ),
        ],
        if (isColorRangeActive) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    activeMask!.colorRange.r.round().clamp(0, 255),
                    activeMask.colorRange.g.round().clamp(0, 255),
                    activeMask.colorRange.b.round().clamp(0, 255),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: DarkmoonColors.border),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.colorRangeHint,
                  style: const TextStyle(
                    color: DarkmoonColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SliderRow(
              name: l10n.colorRangeToleranceLabel,
              min: 0,
              max: 100,
              value: activeMask.colorRange.tolerance,
              decimals: 0,
              onChanged: widget.actions.onColorRangeToleranceChanged,
              onChangeEnd: widget.actions.onColorRangeToleranceChangeEnd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SliderRow(
              name: l10n.colorRangeFeatherLabel,
              min: 0,
              max: 100,
              value: activeMask.colorRange.feather,
              decimals: 0,
              onChanged: widget.actions.onColorRangeFeatherChanged,
              onChangeEnd: widget.actions.onColorRangeFeatherChangeEnd,
            ),
          ),
        ],
        if (isLuminanceActive) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    activeMask!.luminance.targetLuma.round().clamp(0, 255),
                    activeMask.luminance.targetLuma.round().clamp(0, 255),
                    activeMask.luminance.targetLuma.round().clamp(0, 255),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: DarkmoonColors.border),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.luminanceHint,
                  style: const TextStyle(
                    color: DarkmoonColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SliderRow(
              name: l10n.luminanceToleranceLabel,
              min: 0,
              max: 100,
              value: activeMask.luminance.tolerance,
              decimals: 0,
              onChanged: widget.actions.onLuminanceToleranceChanged,
              onChangeEnd: widget.actions.onLuminanceToleranceChangeEnd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SliderRow(
              name: l10n.luminanceFeatherLabel,
              min: 0,
              max: 100,
              value: activeMask.luminance.feather,
              decimals: 0,
              onChanged: widget.actions.onLuminanceFeatherChanged,
              onChangeEnd: widget.actions.onLuminanceFeatherChangeEnd,
            ),
          ),
        ],
        if (isAiMaskActive) ...[
          const SizedBox(height: 8),
          // One line that says which of the three states this mask is in.
          // Without it an empty AI mask is unreadable: still thinking,
          // model missing, and "the model genuinely found no sky" all
          // look the same on the canvas.
          if (widget.aiMasksResolving.contains(activeMask.id))
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: DarkmoonColors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.aiMaskComputing,
                  style: const TextStyle(
                    color: DarkmoonColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            )
          else if (widget.aiMaskFailures.containsKey(activeMask.id))
            // No error color in the theme, and inventing one here would
            // be the only red in the app; the brighter of the two text
            // tones is enough to separate this from the hint it replaces.
            Text(
              l10n.aiMaskFailed,
              style: const TextStyle(
                color: DarkmoonColors.textPrimary,
                fontSize: 11,
              ),
            )
          else if (activeMask.type == MaskType.subject)
            Text(
              l10n.subjectMaskHint,
              style: const TextStyle(
                color: DarkmoonColors.textMuted,
                fontSize: 11,
              ),
            ),
          if (activeMask.type == MaskType.depth) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SliderRow(
                name: l10n.depthNearLabel,
                min: 0,
                max: 100,
                value: activeMask.depth.near * 100,
                decimals: 0,
                onChanged: (v) => widget.actions.onDepthGeometryChanged(
                  activeMask.depth.copyWith(near: v / 100),
                ),
                onChangeEnd: (v) => widget.actions.onDepthGeometryChangeEnd(
                  activeMask.depth.copyWith(near: v / 100),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SliderRow(
                name: l10n.depthFarLabel,
                min: 0,
                max: 100,
                value: activeMask.depth.far * 100,
                decimals: 0,
                onChanged: (v) => widget.actions.onDepthGeometryChanged(
                  activeMask.depth.copyWith(far: v / 100),
                ),
                onChangeEnd: (v) => widget.actions.onDepthGeometryChangeEnd(
                  activeMask.depth.copyWith(far: v / 100),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SliderRow(
                name: l10n.depthFeatherLabel,
                min: 0,
                max: 100,
                value: activeMask.depth.feather,
                decimals: 0,
                onChanged: (v) => widget.actions.onDepthGeometryChanged(
                  activeMask.depth.copyWith(feather: v),
                ),
                onChangeEnd: (v) => widget.actions.onDepthGeometryChangeEnd(
                  activeMask.depth.copyWith(feather: v),
                ),
              ),
            ),
          ],
        ],
        // The same pair the Crop panel ends with, and for the same
        // reason: both are a mode you are inside, and both need an
        // obvious way out. OK just leaves — a mask is committed as
        // it is edited, so there is nothing to apply. Cancel throws
        // the layer away, which is what makes it a cancel rather
        // than a second Done. Both land back on Full Image.
        if (widget.activeMaskId != imageMaskId) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: widget.actions.onDeleteMask,
                    child: Text(l10n.cancelButton),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: FilledButton(
                    onPressed: () => widget.actions.onSelectMask(imageMaskId),
                    child: Text(l10n.maskOkButton),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Container(
      width: _controlsPanelWidth,
      color: DarkmoonColors.panel,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          // The pinned mask block needs a ceiling measured against the
          // panel, not a constant and not a flex share. A constant
          // overflowed this column on a short window. A Flexible share
          // fixed the overflow but left dead space: a loose Flexible that
          // uses less than its allotment does not hand the remainder back,
          // so the sections stopped short and a blank rectangle sat above
          // the Export button.
          //
          // Capping against the real height keeps the block inflexible, so
          // the sections Expanded below absorbs everything left over and
          // there is nothing to leave behind.
          child: LayoutBuilder(
            builder: (context, panelBox) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Histogram + photo info are pinned at the very top of the
                // column so they stay put as the first item even while a
                // mask is being created/edited below — the mask UI and every
                // adjustment section scroll independently beneath them.
                // Hidden while cropping, like everything else in the
                // panel: the histogram describes colour, and cropping is
                // the one operation that changes none of it.
                if (!widget.cropOverlayActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _controlsPanelInset,
                      14,
                      _controlsPanelInset,
                      8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            l10n.histogramTitle,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        HistogramView(histogram: histogram),
                        PhotoMetadataView(metadata: widget.metadata),
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Divider(
                            color: DarkmoonColors.divider,
                            height: 1,
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                // The mask picker is pinned under the histogram in both
                // layouts (user's call, 2026-09-11): which mask the
                // sections apply to has to stay in view while they scroll.
                // The active mask's own controls follow the layout below.
                // Not while removing objects: the brush paints a removal
                // then, not a mask.
                if (!widget.cropOverlayActive && !widget.removeModeActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _controlsPanelInset,
                      10,
                      _controlsPanelInset,
                      8,
                    ),
                    child: MaskSelector(
                      masks: widget.masks,
                      activeId: widget.activeMaskId,
                      onSelect: widget.actions.onSelectMask,
                      onAdd: widget.actions.onAddMask,
                    ),
                  ),
                // Crop takes the whole panel, in both layouts. It is a
                // mode rather than another section — nothing else in here
                // acts on a photo while it is open, and leaving the masks
                // and the sections visible invites edits that the crop is
                // about to change the geometry underneath.
                if (widget.cropOverlayActive)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        _controlsPanelInset,
                        0,
                        _controlsPanelInset,
                        14,
                      ),
                      child: _buildCropPanel(),
                    ),
                  )
                else if (widget.removeModeActive)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        _controlsPanelInset,
                        0,
                        _controlsPanelInset,
                        14,
                      ),
                      child: _buildRemovePanel(),
                    ),
                  )
                else ...[
                  // Masks are fixed above the tabs, the way the histogram is:
                  // a mask is what every section below applies to, so
                  // scrolling it out of sight to reach a slider loses track
                  // of what is being edited.
                  //
                  // Capped and internally scrollable rather than free to grow:
                  // the block expands with the brush and colour-range
                  // controls, and without a ceiling a handful of masks would
                  // push the tabs off the bottom of the panel entirely.
                  // Flexible, not a fixed cap. A constant ceiling overflowed
                  // this column by 60px on a real window: the histogram plus
                  // the block plus the tab bar exceeded the panel, the Expanded
                  // below was left with nothing, and the difference spilled.
                  // Whatever the constant, some window is short enough to break
                  // it. Flexible makes the block yield instead — natural height
                  // when there is room, shrinking and scrolling inside when
                  // there is not — so the overflow is not expressible.
                  //
                  // flex 1 against the sections' 2 leaves it at most a third of
                  // the free space, which is the ceiling the constant was
                  // trying to express.
                  if (widget.tabbedLayout)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        // Half of whatever is left once the histogram and the tab
                        // bar have had their share, so the sections always keep
                        // the larger half. Collapses to nothing on a panel too
                        // short to hold all three rather than overflowing.
                        maxHeight: ((panelBox.maxHeight - 350) * 0.5).clamp(
                          0.0,
                          320.0,
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          _controlsPanelInset,
                          0,
                          _controlsPanelInset,
                          8,
                        ),
                        child: masksBlock,
                      ),
                    ),
                  if (widget.tabbedLayout) _buildControlsTabBar(l10n),
                  Expanded(
                    child: SingleChildScrollView(
                      // Keyed by tab so each keeps its own scroll position. A
                      // single controller shared by all four meant reading
                      // far down Colour and switching to Effects landed you
                      // at that same offset in a shorter list, which is not
                      // where anyone left off.
                      //
                      // PageStorage does the remembering; no controller is
                      // needed here now that opening Crop no longer scrolls
                      // this list, Crop being pinned above the tabs.
                      key: PageStorageKey<_ControlsTab>(_tab),
                      padding: const EdgeInsets.fromLTRB(
                        _controlsPanelInset,
                        10,
                        _controlsPanelInset,
                        14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Flat list: the masks scroll with everything
                          // else, which is what the old panel did and what
                          // turning the tabs off is for. Pinning them in
                          // both layouts made "single list" not quite the
                          // layout it replaced.
                          if (!widget.tabbedLayout) ...[
                            masksBlock,
                            const SizedBox(height: 8),
                          ],
                          for (final entry in _sections.entries.where(
                            (e) => _inTab(_tabOf(e.key)),
                          )) ...[
                            // `values`/`onChanged`/`onChangeEnd` already resolve to
                            // either the global layer or the active mask's own (see
                            // the comment below on Tone Curve/Color Mixer/etc.), so
                            // the toggle works identically for both — no separate
                            // mask-vs-global branch needed.
                            ..._section(
                              entry.key,
                              label: _sectionLabel(l10n, entry.key),
                              enabled:
                                  (values[_categoryEnabledKey(entry.key)] ??
                                      1) !=
                                  0,
                              onEnabledChanged: (v) => _toggleCategoryEnabled(
                                _categoryEnabledKey(entry.key),
                                v,
                              ),
                              children: [
                                // The colour profile is chosen once per photo and then
                                // left alone — the same shape as As Shot white
                                // balance, which is why it leads this section
                                // rather than standing as one of its own
                                // (2026-09-09, user's call). Its two sliders
                                // went to the profile editor, where a curve can
                                // actually be judged against them.
                                if (entry.key == 'WHITE BALANCE') ...[
                                  Padding(
                                    // Matches White Balance's mode row below
                                    // (top: 6, bottom: 14) — was missing the
                                    // top gap, reading as noticeably closer to
                                    // the section title than every other
                                    // dropdown/mode row (2026-09-02).
                                    padding: const EdgeInsets.only(
                                      top: 6,
                                      bottom: 14,
                                    ),
                                    // One int identifies every entry: a
                                    // ColorProfileMode index for the built-ins,
                                    // a ColorProfile.id for the user's own.
                                    // reservedColorProfileIds keeps those two
                                    // number spaces from ever overlapping.
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: StyledDropdown<int>(
                                            value: widget.colorProfileChoice,
                                            items: [
                                              for (final mode in [
                                                ColorProfileMode
                                                    .darkmoonDefault,
                                                ColorProfileMode.vivid,
                                              ])
                                                StyledDropdownItem(
                                                  value: mode.index,
                                                  label: _colorProfileModeLabel(
                                                    l10n,
                                                    mode,
                                                  ),
                                                ),
                                              for (final profile
                                                  in widget
                                                      .userColorProfiles
                                                      .values)
                                                StyledDropdownItem(
                                                  value: profile.id,
                                                  label: profile.name,
                                                ),
                                              // The dangling reference gets its own
                                              // entry rather than snapping the
                                              // dropdown back to Default: the photo
                                              // still points at that profile, and the
                                              // control should say so.
                                              if (widget.customProfileMissing)
                                                StyledDropdownItem(
                                                  value:
                                                      widget.colorProfileChoice,
                                                  label: l10n
                                                      .colorProfileModeMissing,
                                                ),
                                            ],
                                            onChanged: widget
                                                .actions
                                                .onColorProfileChoiceChanged,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Creating a profile is not an edit to
                                        // this photo, so it sits beside the
                                        // dropdown rather than inside it — a
                                        // "+" entry in the list would look like
                                        // one more profile to pick.
                                        Tooltip(
                                          message: l10n.colorProfileNewTooltip,
                                          child: SizedBox(
                                            width: 30,
                                            height: 30,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              iconSize: 17,
                                              splashRadius: 16,
                                              color:
                                                  DarkmoonColors.textSecondary,
                                              icon: const Icon(Icons.add),
                                              onPressed: widget
                                                  .actions
                                                  .onCreateColorProfile,
                                            ),
                                          ),
                                        ),
                                        // Bare icon, not an IconButton: the
                                        // app's IconButtonTheme draws a filled
                                        // rounded-square meant for standalone
                                        // toolbar buttons, which reads as a box
                                        // around a quiet menu trigger. Same
                                        // reasoning as preset_panel.dart's row
                                        // menu.
                                        Tooltip(
                                          message: l10n.colorProfileMenuTooltip,
                                          child: PopupMenuButton<VoidCallback>(
                                            padding: EdgeInsets.zero,
                                            onSelected: (action) => action(),
                                            itemBuilder: (context) => [
                                              // Import is always here; the rest
                                              // only mean something once a user
                                              // profile is the one selected.
                                              PopupMenuItem(
                                                value: widget
                                                    .actions
                                                    .onImportColorProfile,
                                                child: Text(
                                                  l10n.colorProfileImportLabel,
                                                ),
                                              ),
                                              if (widget
                                                  .selectedProfileIsUsers) ...[
                                                const PopupMenuDivider(),
                                                PopupMenuItem(
                                                  value: widget
                                                      .actions
                                                      .onEditColorProfile,
                                                  child: Text(
                                                    l10n.colorProfileEditLabel,
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: widget
                                                      .actions
                                                      .onDuplicateColorProfile,
                                                  child: Text(
                                                    l10n.colorProfileDuplicateLabel,
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: widget
                                                      .actions
                                                      .onRenameColorProfile,
                                                  child: Text(
                                                    l10n.presetRenameLabel,
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: widget
                                                      .actions
                                                      .onExportColorProfile,
                                                  child: Text(
                                                    l10n.presetExportLabel,
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: widget
                                                      .actions
                                                      .onDeleteColorProfile,
                                                  child: Text(
                                                    l10n.presetDeleteLabel,
                                                  ),
                                                ),
                                              ],
                                            ],
                                            child: const Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Icon(
                                                CupertinoIcons.ellipsis,
                                                size: 14,
                                                color: DarkmoonColors.textMuted,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.customProfileMissing)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(
                                              top: 1,
                                              right: 6,
                                            ),
                                            child: Icon(
                                              Icons.error_outline,
                                              size: 14,
                                              color: DarkmoonColors.textMuted,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              l10n.colorProfileMissingWarning,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: DarkmoonColors
                                                        .textMuted,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                                if (entry.key == 'WHITE BALANCE')
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 6,
                                      bottom: 14,
                                    ),
                                    child: _buildWhiteBalanceModeRow(
                                      l10n,
                                      values,
                                    ),
                                  ),
                                for (final spec in entry.value)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SliderRow(
                                      name: _sliderLabel(l10n, spec.name),
                                      min: spec.min,
                                      max: spec.max,
                                      value:
                                          values[spec.name] ??
                                          _wbSliderFallback(spec.name) ??
                                          spec.defaultValue,
                                      decimals: spec.decimals,
                                      defaultValue:
                                          _wbSliderFallback(spec.name) ??
                                          spec.defaultValue,
                                      trackColors: spec.gradientColors,
                                      valueSuffix: spec.valueSuffix,
                                      onChanged: (v) => onChanged(spec.name, v),
                                      onChangeEnd: (v) =>
                                          onChangeEnd(spec.name, v),
                                    ),
                                  ),
                                // (The old "preserve brightness on Tint" toggle
                                // was removed — the current WB model is
                                // luminance-normalised by construction, so it
                                // was a no-op. The param still exists, inert.)
                              ],
                            ),
                            // Tone Curve/Color Curve/Color Mixer/Color Grading/
                            // Effects are available for masks too — `curves`/
                            // `onChanged`/`onChangeEnd` above already resolve to
                            // either the global state or the active mask's own
                            // (see _activeCurves/_onActiveChanged), so no extra
                            // mask-vs-global branching is needed here. Placed after
                            // Detail rather than interleaved with the _sections
                            // loop, so Presence/Detail stay right after Tone, ahead
                            // of the advanced color tools.
                          ],
                          // Tone Curve, Color Curve, Color Mixer, Color
                          // Grading, Effects and Lens Correction are their own
                          // sections rather than entries of _sections, because
                          // they are not plain slider lists.
                          //
                          // They used to be emitted from inside the loop above,
                          // on its DETAIL iteration. That worked while the loop
                          // always ran every entry; once the tabs filtered it,
                          // DETAIL only came up under Adjust and these five
                          // vanished from the other tabs entirely — Effects had
                          // nothing in it at all. They are siblings of the loop
                          // now, so what the loop yields cannot decide whether
                          // they exist.
                          if (_inTab(_ControlsTab.adjust))
                            ..._section(
                              'TONE CURVE',
                              label: l10n.sectionToneCurve,
                              enabled:
                                  (values[_categoryEnabledKey('TONE CURVE')] ??
                                      1) !=
                                  0,
                              onEnabledChanged: (v) => _toggleCategoryEnabled(
                                _categoryEnabledKey('TONE CURVE'),
                                v,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ToneCurveEditor(
                                    points: curves.tone,
                                    onChanged: onToneCurveChanged,
                                    onChangeEnd: onToneCurveChangeEnd,
                                  ),
                                ),
                                // Directly under the graph, sharing its x
                                // axis, so each handle sits at the input
                                // luminance it splits.
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: ParametricSplitBar(
                                    shadowSplit:
                                        values['ParamCurveShadowSplit'] ?? 25,
                                    midtoneSplit:
                                        values['ParamCurveMidtoneSplit'] ?? 50,
                                    highlightSplit:
                                        values['ParamCurveHighlightSplit'] ??
                                        75,
                                    onChanged: onChanged,
                                    onChangeEnd: onChangeEnd,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    l10n.toneCurveParametricLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: DarkmoonColors.textMuted,
                                        ),
                                  ),
                                ),
                                for (final spec in _parametricCurveSliders)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SliderRow(
                                      name: _sliderLabel(l10n, spec.name),
                                      min: spec.min,
                                      max: spec.max,
                                      value:
                                          values[spec.name] ??
                                          spec.defaultValue,
                                      decimals: spec.decimals,
                                      defaultValue: spec.defaultValue,
                                      onChanged: (v) => onChanged(spec.name, v),
                                      onChangeEnd: (v) =>
                                          onChangeEnd(spec.name, v),
                                    ),
                                  ),
                              ],
                            ),
                          if (_inTab(_ControlsTab.colour))
                            ..._section(
                              'COLOR CURVE',
                              label: l10n.sectionColorCurve,
                              enabled:
                                  (values[_categoryEnabledKey('COLOR CURVE')] ??
                                      1) !=
                                  0,
                              onEnabledChanged: (v) => _toggleCategoryEnabled(
                                _categoryEnabledKey('COLOR CURVE'),
                                v,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    bottom: 8,
                                  ),
                                  child: _ColorChannelTabs(
                                    active: _activeColorChannel,
                                    onSelect: (channel) => setState(
                                      () => _activeColorChannel = channel,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ToneCurveEditor(
                                    key: ValueKey(_activeColorChannel),
                                    points: _channelPoints(
                                      curves,
                                      _activeColorChannel,
                                    ),
                                    lineColor: _channelColor(
                                      _activeColorChannel,
                                    ),
                                    onChanged: (points) => onColorCurveChanged(
                                      _activeColorChannel,
                                      points,
                                    ),
                                    onChangeEnd: (points) =>
                                        onColorCurveChangeEnd(
                                          _activeColorChannel,
                                          points,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          if (_inTab(_ControlsTab.colour))
                            ..._section(
                              'COLOR MIXER',
                              label: l10n.sectionColorMixer,
                              enabled:
                                  (values[_categoryEnabledKey('COLOR MIXER')] ??
                                      1) !=
                                  0,
                              onEnabledChanged: (v) => _toggleCategoryEnabled(
                                _categoryEnabledKey('COLOR MIXER'),
                                v,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    bottom: 10,
                                  ),
                                  child: _MixerModeTabs(
                                    active: _mixerViewMode,
                                    onSelect: (mode) =>
                                        setState(() => _mixerViewMode = mode),
                                  ),
                                ),
                                if (_mixerViewMode == 'Mixer') ...[
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _MixerChannelDots(
                                      active: _activeMixerChannel,
                                      onSelect: (channel) => setState(
                                        () => _activeMixerChannel = channel,
                                      ),
                                    ),
                                  ),
                                  // Luminance re-enabled: color_mixer.dart now
                                  // ports Solstice's apply_hsl_panel in full
                                  // (scene-linear HSV, per-band Gaussian
                                  // influence, saturation-gated), including its
                                  // luma-preserving-then-adjusting Luminance
                                  // term — a different code path from the one
                                  // previously disabled after reports of it
                                  // blowing out/pixelating pixels (that one
                                  // relied on HSL lightness directly, not luma
                                  // explicitly restored after the shift).
                                  for (final suffix in const [
                                    'Hue',
                                    'Saturation',
                                    'Luminance',
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: SliderRow(
                                        name: _mixerSliderLabel(l10n, suffix),
                                        min: -100,
                                        max: 100,
                                        value:
                                            values['Mixer$_activeMixerChannel$suffix'] ??
                                            0,
                                        decimals: 0,
                                        defaultValue: 0,
                                        trackColors: _mixerTrackColors(
                                          _activeMixerChannel,
                                          suffix,
                                        ),
                                        onChanged: (v) => onChanged(
                                          'Mixer$_activeMixerChannel$suffix',
                                          v,
                                        ),
                                        onChangeEnd: (v) => onChangeEnd(
                                          'Mixer$_activeMixerChannel$suffix',
                                          v,
                                        ),
                                      ),
                                    ),
                                ] else
                                  for (final suffix in const [
                                    'Hue',
                                    'Saturation',
                                    'Luminance',
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              _mixerSliderLabel(l10n, suffix),
                                              style: TextStyle(
                                                color: DarkmoonColors.textMuted,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                          ),
                                          for (final channel in _mixerChannels)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: SliderRow(
                                                name: _mixerChannelLabel(
                                                  l10n,
                                                  channel,
                                                ),
                                                min: -100,
                                                max: 100,
                                                value:
                                                    values['Mixer$channel$suffix'] ??
                                                    0,
                                                decimals: 0,
                                                defaultValue: 0,
                                                trackColors: _mixerTrackColors(
                                                  channel,
                                                  suffix,
                                                ),
                                                onChanged: (v) => onChanged(
                                                  'Mixer$channel$suffix',
                                                  v,
                                                ),
                                                onChangeEnd: (v) => onChangeEnd(
                                                  'Mixer$channel$suffix',
                                                  v,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                              ],
                            ),
                          if (_inTab(_ControlsTab.colour))
                            ..._section(
                              'COLOR GRADING',
                              label: l10n.sectionColorGrading,
                              enabled:
                                  (values[_categoryEnabledKey(
                                        'COLOR GRADING',
                                      )] ??
                                      1) !=
                                  0,
                              onEnabledChanged: (v) => _toggleCategoryEnabled(
                                _categoryEnabledKey('COLOR GRADING'),
                                v,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    bottom: 10,
                                  ),
                                  child: _GradeRangeTabs(
                                    active: _activeGradeRange,
                                    onSelect: (range) => setState(
                                      () => _activeGradeRange = range,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Center(
                                    child: SizedBox(
                                      width: 160,
                                      child: ColorWheel(
                                        key: ValueKey(_activeGradeRange),
                                        hue:
                                            values['Grade${_activeGradeRange}Hue'] ??
                                            0,
                                        saturation:
                                            values['Grade${_activeGradeRange}Saturation'] ??
                                            0,
                                        onChanged: (hue, sat) {
                                          onChanged(
                                            'Grade${_activeGradeRange}Hue',
                                            hue,
                                          );
                                          onChanged(
                                            'Grade${_activeGradeRange}Saturation',
                                            sat,
                                          );
                                        },
                                        onChangeEnd: (hue, sat) {
                                          onChangeEnd(
                                            'Grade${_activeGradeRange}Hue',
                                            hue,
                                          );
                                          onChangeEnd(
                                            'Grade${_activeGradeRange}Saturation',
                                            sat,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SliderRow(
                                    name: l10n.mixerHueLabel,
                                    min: 0,
                                    max: 360,
                                    value:
                                        values['Grade${_activeGradeRange}Hue'] ??
                                        0,
                                    decimals: 0,
                                    defaultValue: 0,
                                    onChanged: (v) => onChanged(
                                      'Grade${_activeGradeRange}Hue',
                                      v,
                                    ),
                                    onChangeEnd: (v) => onChangeEnd(
                                      'Grade${_activeGradeRange}Hue',
                                      v,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SliderRow(
                                    name: l10n.mixerSaturationLabel,
                                    min: 0,
                                    max: 100,
                                    value:
                                        values['Grade${_activeGradeRange}Saturation'] ??
                                        0,
                                    decimals: 0,
                                    defaultValue: 0,
                                    onChanged: (v) => onChanged(
                                      'Grade${_activeGradeRange}Saturation',
                                      v,
                                    ),
                                    onChangeEnd: (v) => onChangeEnd(
                                      'Grade${_activeGradeRange}Saturation',
                                      v,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SliderRow(
                                    name: l10n.mixerLuminanceLabel,
                                    min: -100,
                                    max: 100,
                                    value:
                                        values['Grade${_activeGradeRange}Luminance'] ??
                                        0,
                                    decimals: 0,
                                    defaultValue: 0,
                                    onChanged: (v) => onChanged(
                                      'Grade${_activeGradeRange}Luminance',
                                      v,
                                    ),
                                    onChangeEnd: (v) => onChangeEnd(
                                      'Grade${_activeGradeRange}Luminance',
                                      v,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_inTab(_ControlsTab.effects))
                            ..._section(
                              'EFFECTS',
                              label: l10n.sectionEffects,
                              // On by default, like every other section —
                              // see _withCategoriesApplied's disabled() doc.
                              enabled:
                                  (values[_categoryEnabledKey('EFFECTS')] ??
                                      1) !=
                                  0,
                              onEnabledChanged: (v) => _toggleCategoryEnabled(
                                _categoryEnabledKey('EFFECTS'),
                                v,
                              ),
                              children: [
                                for (final spec in [
                                  ..._vignetteSliders,
                                  ..._grainSliders,
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SliderRow(
                                      name: _sliderLabel(l10n, spec.name),
                                      min: spec.min,
                                      max: spec.max,
                                      value:
                                          values[spec.name] ??
                                          spec.defaultValue,
                                      decimals: spec.decimals,
                                      defaultValue: spec.defaultValue,
                                      onChanged: (v) => onChanged(spec.name, v),
                                      onChangeEnd: (v) =>
                                          onChangeEnd(spec.name, v),
                                    ),
                                  ),
                              ],
                            ),
                          if (_inTab(_ControlsTab.effects))
                            ..._section(
                              'LENS CORRECTION',
                              label: l10n.sectionLensCorrection,
                              enabled: widget.lensCorrection.enabled,
                              onEnabledChanged: (v) =>
                                  widget.actions.onLensCorrectionChangeEnd(
                                    widget.lensCorrection.copyWith(enabled: v),
                                  ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: LensCorrectionPanel(
                                    params: widget.lensCorrection,
                                    resolvedProfile: widget.resolvedLensProfile,
                                    allProfiles: widget.lensProfiles,
                                    cameraMake:
                                        widget.metadata?.cameraMake ?? '',
                                    onChanged:
                                        widget.actions.onLensCorrectionChanged,
                                    onChangeEnd: widget
                                        .actions
                                        .onLensCorrectionChangeEnd,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<CurvePoint> _channelPoints(PhotoCurves curves, String channel) {
  switch (channel) {
    case 'red':
      return curves.red;
    case 'green':
      return curves.green;
    case 'blue':
      return curves.blue;
  }
  throw ArgumentError.value(channel, 'channel');
}

Color _channelColor(String channel) {
  switch (channel) {
    case 'red':
      return const Color(0xFFE0483C);
    case 'green':
      return const Color(0xFF3DD16B);
    case 'blue':
      return const Color(0xFF4FA6FF);
  }
  throw ArgumentError.value(channel, 'channel');
}

/// The 8 Color Mixer bands, in hue order — matches
/// [ColorMixerValues]'s channel order.
const _mixerChannels = [
  'Red',
  'Orange',
  'Yellow',
  'Green',
  'Aqua',
  'Blue',
  'Purple',
  'Magenta',
];

/// The hue angle (degrees) each Color Mixer channel is centred on —
/// matches `color_mixer.dart` / the shader's `HSL_RANGES` centres.
double _mixerChannelHue(String channel) => switch (channel) {
  'Red' => 358.0,
  'Orange' => 25.0,
  'Yellow' => 60.0,
  'Green' => 115.0,
  'Aqua' => 180.0,
  'Blue' => 225.0,
  'Purple' => 280.0,
  'Magenta' => 330.0,
  _ => 0.0,
};

/// Track gradient for a Color Mixer slider — the Hue slider runs through
/// the channel's actual neighbouring hues (Meridian-style), Saturation
/// grey→colour, Luminance dark→light of the colour.
List<Color> _mixerTrackColors(String channel, String suffix) {
  final hue = _mixerChannelHue(channel);
  Color at(double h, double s, double v) =>
      HSVColor.fromAHSV(1, h % 360, s, v).toColor();
  switch (suffix) {
    case 'Hue':
      return [
        at(hue - 42, 0.85, 0.95),
        at(hue, 0.85, 0.95),
        at(hue + 42, 0.85, 0.95),
      ];
    case 'Luminance':
      return [at(hue, 0.7, 0.22), at(hue, 0.85, 0.92), at(hue, 0.2, 1.0)];
    default: // Saturation
      return [const Color(0xFF6C6C72), at(hue, 0.9, 0.95)];
  }
}

Color _mixerChannelColor(String channel) {
  switch (channel) {
    case 'Red':
      return const Color(0xFFE0483C);
    case 'Orange':
      return const Color(0xFFE8873C);
    case 'Yellow':
      return const Color(0xFFE0C93C);
    case 'Green':
      return const Color(0xFF3DD16B);
    case 'Aqua':
      return const Color(0xFF3CC9D1);
    case 'Blue':
      return const Color(0xFF4FA6FF);
    case 'Purple':
      return const Color(0xFF9B6FE0);
    case 'Magenta':
      return const Color(0xFFE362D8);
  }
  throw ArgumentError.value(channel, 'channel');
}

String _mixerChannelLabel(AppLocalizations l10n, String channel) {
  switch (channel) {
    case 'Red':
      return l10n.colorChannelRed;
    case 'Orange':
      return l10n.colorChannelOrange;
    case 'Yellow':
      return l10n.colorChannelYellow;
    case 'Green':
      return l10n.colorChannelGreen;
    case 'Aqua':
      return l10n.colorChannelAqua;
    case 'Blue':
      return l10n.colorChannelBlue;
    case 'Purple':
      return l10n.colorChannelPurple;
    case 'Magenta':
      return l10n.colorChannelMagenta;
  }
  throw ArgumentError.value(channel, 'channel');
}

String _mixerSliderLabel(AppLocalizations l10n, String suffix) {
  switch (suffix) {
    case 'Hue':
      return l10n.mixerHueLabel;
    case 'Saturation':
      return l10n.mixerSaturationLabel;
    case 'Luminance':
      return l10n.mixerLuminanceLabel;
  }
  throw ArgumentError.value(suffix, 'suffix');
}

/// Toggles the Color Mixer between its two display modes — matches
/// Meridian's own Mixer/HSL tabs, which control the exact same 24
/// underlying values ("Mixer" + channel + "Hue/Saturation/Luminance"),
/// just grouped differently: by channel (below, one at a time) or by
/// attribute (all 8 channels stacked per Hue/Saturation/Luminance group).
class _MixerModeTabs extends StatelessWidget {
  const _MixerModeTabs({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  static const _modes = ['Mixer', 'HSL'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _SegmentedTabs<String>(
      items: _modes,
      active: active,
      onSelect: onSelect,
      labelOf: (mode) =>
          mode == 'Mixer' ? l10n.mixerModeMixerLabel : l10n.mixerModeHslLabel,
    );
  }
}

/// The Color Mixer's 8-band channel picker — small colored dots (one per
/// hue band) rather than text tabs, since 8 text labels wouldn't fit the
/// panel's width. Matches Meridian's own dot-based channel selector.
class _MixerChannelDots extends StatelessWidget {
  const _MixerChannelDots({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final channel in _mixerChannels)
          Tooltip(
            message: _mixerChannelLabel(l10n, channel),
            child: GestureDetector(
              onTap: () => onSelect(channel),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _mixerChannelColor(channel),
                  border: Border.all(
                    color: channel == active
                        ? DarkmoonColors.textPrimary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _gradeRangeLabel(AppLocalizations l10n, String range) {
  switch (range) {
    case 'Shadows':
      return l10n.sliderShadows;
    case 'Midtones':
      return l10n.gradeRangeMidtones;
    case 'Highlights':
      return l10n.sliderHighlights;
    case 'Global':
      return l10n.gradeRangeGlobal;
  }
  throw ArgumentError.value(range, 'range');
}

/// Shadows/Midtones/Highlights tab strip for the Color Grading panel —
/// one range's wheel is edited at a time, matching Meridian.
class _GradeRangeTabs extends StatelessWidget {
  const _GradeRangeTabs({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  static const _ranges = ['Global', 'Shadows', 'Midtones', 'Highlights'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _SegmentedTabs<String>(
      items: _ranges,
      active: active,
      onSelect: onSelect,
      labelOf: (range) => _gradeRangeLabel(l10n, range),
    );
  }
}

/// A single rounded, bordered capsule holding equal-width segments, the
/// active one highlighted by a borderless flat-fill pill rather than
/// each segment carrying its own border — softer, Photomator-style
/// segmented control shared by [_GradeRangeTabs] and [_ColorChannelTabs].
class _SegmentedTabs<T> extends StatelessWidget {
  const _SegmentedTabs({
    required this.items,
    required this.active,
    required this.onSelect,
    required this.labelOf,
    this.colorOf,
  });

  final List<T> items;
  final T active;
  final ValueChanged<T> onSelect;
  final String Function(T item) labelOf;

  /// Per-segment highlight color when selected — defaults to the app's
  /// monochrome accent everywhere except [_ColorChannelTabs], which
  /// color-codes each channel to match the curve editor itself.
  final Color Function(T item)? colorOf;

  static const _duration = Duration(milliseconds: 200);
  static const _padding = 3.0;

  @override
  Widget build(BuildContext context) {
    final activeIndex = items.indexOf(active);
    return Container(
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: DarkmoonColors.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: DarkmoonColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Real bug (2026-09-01, user report — the highlight drifted
          // further off with each tab to the right, worst on the last
          // one): Container's own padding above already shrinks the
          // constraints this LayoutBuilder receives — constraints.maxWidth
          // here is already the inner (padded) width. Subtracting
          // _padding * 2 again double-counted it, making segmentWidth too
          // narrow and compounding a growing offset as activeIndex grew.
          final segmentWidth = constraints.maxWidth / items.length;
          return Stack(
            children: [
              // The sliding highlight — a single pill that animates its
              // *position* between segments (not a per-segment fade),
              // matching the standard segmented-control feel (iOS tab
              // bars, Photomator's own range picker).
              AnimatedPositioned(
                duration: AnimationsConfig.duration(context, _duration),
                curve: Curves.easeOut,
                left: segmentWidth * activeIndex,
                width: segmentWidth,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: (colorOf?.call(active) ?? DarkmoonColors.accent)
                        .withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: _SegmentedTab(
                        label: labelOf(item),
                        selected: item == active,
                        color: colorOf?.call(item) ?? DarkmoonColors.accent,
                        onTap: () => onSelect(item),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentedTab extends StatelessWidget {
  const _SegmentedTab({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        // The sliding highlight pill lives behind this in the parent
        // Stack — only the text color/weight animates here.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Align(
            child: AnimatedDefaultTextStyle(
              duration: AnimationsConfig.duration(context, _duration),
              curve: Curves.easeOut,
              style: TextStyle(
                color: selected ? color : DarkmoonColors.textSecondary,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// R/G/B tab strip for the Color Curve panel — one channel's curve is
/// edited at a time, matching Meridian's per-channel Point Curve tabs.
class _ColorChannelTabs extends StatelessWidget {
  const _ColorChannelTabs({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  static const _channels = ['red', 'green', 'blue'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _SegmentedTabs<String>(
      items: _channels,
      active: active,
      onSelect: onSelect,
      labelOf: (channel) => _colorChannelLabel(l10n, channel),
      colorOf: _channelColor,
    );
  }
}

String _colorChannelLabel(AppLocalizations l10n, String channel) {
  switch (channel) {
    case 'red':
      return l10n.colorChannelRed;
    case 'green':
      return l10n.colorChannelGreen;
    case 'blue':
      return l10n.colorChannelBlue;
  }
  throw ArgumentError.value(channel, 'channel');
}
