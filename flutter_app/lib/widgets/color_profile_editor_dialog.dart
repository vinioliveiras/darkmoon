import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/color_profile.dart';
import '../render/color_profile_reference.dart';
import '../render/hsl.dart';
import '../render/tone_curve.dart';
import '../theme.dart';
import 'color_profile_preview.dart';
import 'dialog_chrome.dart';
import 'slider_row.dart';
import 'tone_curve_editor.dart';

/// Why the editor closed.
///
/// Picking a colour needs the photo, and the photo is behind a modal
/// barrier that swallows clicks — so arming the eyedropper closes the
/// dialog carrying its work, and the editor reopens it once a pixel has
/// been sampled. The alternative, letting clicks fall through a dialog
/// that is still on screen, does not exist while the barrier is there.
class ColorProfileEditorResult {
  const ColorProfileEditorResult.saved(this.profile) : pickHue = false;
  const ColorProfileEditorResult.pickHue(this.profile) : pickHue = true;

  /// The profile as it stood when the dialog closed — the thing to save,
  /// or the thing to hand back when reopening after a pick.
  final ColorProfile profile;

  /// True when the user asked to sample a colour rather than to save.
  final bool pickHue;
}

/// Creates or edits a user-authored "darkmoon Color" profile.
///
/// Centred, animated and over a dimming barrier, like every other dialog
/// in the app — user's call, 2026-09-07.
///
/// Two columns: the previews on the left, the controls on the right, so
/// the change and the control driving it are on screen together.
///
/// The previews live inside the dialog ([ColorProfilePreview]) rather than
/// being the canvas behind it — what the centring and the dimming made
/// necessary, and better anyway: they run `applyColorProfile` and nothing
/// else, so the profile's effect is isolated from the photo's own
/// exposure, curves and masks.
///
/// There are two of them, the same profile on different subjects. The
/// generated chart (`buildReferenceChart`) carries every hue bin, the
/// memory colours and a neutral ramp, so no control here is left with
/// nothing to act on; the open photo below it is the one that actually
/// decides whether a profile is any good. Both at once rather than a
/// switch: a profile that flatters the chart and ruins skin is precisely
/// the mistake worth catching, and showing one at a time hides it.
///
/// [onDraftChanged] and [onDraftSettled] report the work in progress to
/// the editor, which records it so the photo behind is already correct the
/// moment the dialog closes. Neither drives a render any more: the canvas
/// sits behind a dimming barrier while this is open, and a GPU pass per
/// frame of a drag for something nobody can see is pure waste.
class ColorProfileEditorDialog extends StatefulWidget {
  const ColorProfileEditorDialog({
    super.key,
    required this.initial,
    required this.existingNames,
    required this.onDraftChanged,
    required this.onDraftSettled,
    this.highlightHue,
    this.photoPreview,
  });

  /// The open photo, downscaled to packed RGB (0..255, three floats per
  /// pixel) for the preview's "current photo" source. Null when no photo
  /// is open, which is the one case where only the reference chart is
  /// offered.
  final ({Float32List rgb, int width, int height})? photoPreview;

  /// A hue in degrees just sampled from the photo. The dialog opens on the
  /// Colour tab with the range (or bin) that owns it marked, which is the
  /// whole point of the eyedropper: naming which of the eight ranges a
  /// given patch of sky or skin actually falls in.
  final double? highlightHue;

  /// The profile to open with — a fresh identity one when creating, an
  /// installed one when editing.
  final ColorProfile initial;

  /// Names already taken, so the dialog can warn before saving rather than
  /// letting the store silently append " (2)".
  final Set<String> existingNames;

  final ValueChanged<ColorProfile> onDraftChanged;
  final ValueChanged<ColorProfile> onDraftSettled;

  @override
  State<ColorProfileEditorDialog> createState() =>
      _ColorProfileEditorDialogState();
}

/// The eight named hue ranges of the Basic tab, each covering three of the
/// 24 bins (24 / 8). Centres are the middle bin of each group.
///
/// Basic exists because 24 bins x 3 values is 72 controls, which is not an
/// interface. Advanced exposes the bins directly for anyone who wants
/// them; both write the same table, so a profile built in one is fully
/// editable in the other.
const _hueRanges = <({String key, int firstBin})>[
  (key: 'red', firstBin: 0),
  (key: 'orange', firstBin: 3),
  (key: 'yellow', firstBin: 6),
  (key: 'green', firstBin: 9),
  (key: 'aqua', firstBin: 12),
  (key: 'blue', firstBin: 15),
  (key: 'purple', firstBin: 18),
  (key: 'magenta', firstBin: 21),
];

const _binsPerRange = colorProfileBins ~/ 8;

class _ColorProfileEditorDialogState extends State<ColorProfileEditorDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
    // Straight to Colour when reopened after a sample: the user asked a
    // question about a colour and this is the answer.
    initialIndex: widget.highlightHue == null ? 0 : 1,
  );
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initial.name,
  );

  /// The tone curve as editable control points. Kept as points rather than
  /// as the 33 sampled values so the graph behaves like every other curve
  /// in the app — drag, add, right-click to remove — and the 33 are
  /// derived on the way out.
  late List<CurvePoint> _tonePoints = _pointsFromTone(widget.initial.tone);

  late List<double> _hueShift = List<double>.of(widget.initial.hueShift);
  late List<double> _satMul = List<double>.of(widget.initial.satMul);
  late List<double> _lumMul = List<double>.of(widget.initial.lumMul);

  bool _advanced = false;

  /// Built once. Regenerating it per frame would be wasted work — it never
  /// changes, only what is applied to it does.
  late final Float32List _referenceChart = buildReferenceChart();

  /// Which range or bin the last sampled colour landed in, or null.
  late final int? _highlightBin = widget.highlightHue == null
      ? null
      : (widget.highlightHue! / (360 / colorProfileBins)).floor() %
            colorProfileBins;

  /// Recovers editable control points from a stored 33-point curve.
  ///
  /// An identity ramp comes back as the two-point identity rather than 33
  /// collinear points, so opening a profile that has no tone curve gives a
  /// clean graph instead of a row of handles to delete.
  static List<CurvePoint> _pointsFromTone(List<double> tone) {
    var identity = true;
    for (var i = 0; i < tone.length; i++) {
      if ((tone[i] - i / (tone.length - 1)).abs() > 1e-4) {
        identity = false;
        break;
      }
    }
    if (identity) {
      return List<CurvePoint>.of(identityToneCurve);
    }
    // Nine points across the range: enough to follow a fitted curve
    // closely, few enough to still be draggable.
    const n = 9;
    return [
      for (var i = 0; i < n; i++)
        () {
          final x = i / (n - 1);
          final f = x * (tone.length - 1);
          final i0 = f.floor().clamp(0, tone.length - 1);
          final i1 = (i0 + 1).clamp(0, tone.length - 1);
          final v = tone[i0] + (tone[i1] - tone[i0]) * (f - i0);
          return CurvePoint(x, v.clamp(0.0, 1.0));
        }(),
    ];
  }

  ColorProfile get _draft => ColorProfile(
    tone: [
      for (var i = 0; i < colorProfileTonePoints; i++)
        evaluateToneCurveAt(
          _tonePoints,
          i / (colorProfileTonePoints - 1),
        ).clamp(0.0, 1.0),
    ],
    hueShift: _hueShift,
    satMul: _satMul,
    lumMul: _lumMul,
    name: _nameController.text.trim(),
    id: widget.initial.id,
  );

  void _changed() => widget.onDraftChanged(_draft);
  void _settled() => widget.onDraftSettled(_draft);

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ tone tab

  Widget _buildToneTab(AppLocalizations l10n) => ListView(
    padding: EdgeInsets.zero,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          l10n.colorProfileEditorToneHint,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textMuted),
        ),
      ),
      ToneCurveEditor(
        points: _tonePoints,
        onChanged: (points) {
          setState(() => _tonePoints = points);
          _changed();
        },
        onChangeEnd: (points) {
          setState(() => _tonePoints = points);
          _settled();
        },
      ),
    ],
  );

  // ----------------------------------------------------------- colour tab

  /// Writes [value] into [table] across one named range's bins, and only
  /// those.
  ///
  /// It writes nothing into the neighbouring bins, deliberately. Feathering
  /// the edges is tempting and wrong twice over: with 24 bins across 8
  /// ranges there are exactly three bins each and no spare ones between, so
  /// bin 3 *belongs to* Orange — Red's slider reaching into it would
  /// silently corrupt a range the user did not touch. And because
  /// `onChanged` fires continuously through a drag, a blend that reads the
  /// current value back would ratchet: 1.25, then 1.375, then 1.4375, for
  /// one uninterrupted gesture.
  ///
  /// No smoothing is needed anyway. The renderer already interpolates
  /// between bin centres — `applyColorProfile` lerps the two neighbouring
  /// bins on the CPU, and `color_profile.frag` sums a triangular weight per
  /// bin — so a change of value from one bin to the next is already a 15°
  /// ramp in the picture, not a step.
  void _setRange(List<double> table, int firstBin, double value) {
    for (var i = 0; i < _binsPerRange; i++) {
      table[(firstBin + i) % colorProfileBins] = value;
    }
  }

  /// The hue, in degrees, a bin sits at.
  static double _binHue(int bin) => bin * (360.0 / colorProfileBins);

  static Color _swatch(double hue, double sat, double value) {
    final (r, g, b) = hsvToRgb(hue % 360.0, sat, value);
    return Color.fromARGB(
      255,
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (b * 255).round().clamp(0, 255),
    );
  }

  /// Track gradients showing what each slider actually does at this hue,
  /// the way White Balance's own sliders show warm-to-cool. Without them
  /// three identically-grey tracks per range give no clue which is which,
  /// and the label is the only thing distinguishing them.
  ///
  /// Seven stops: enough that the ramp reads as continuous, few enough to
  /// stay cheap to rebuild on every frame of a drag.
  static const _stops = 7;

  static List<Color> _hueTrack(double hue) => [
    for (var i = 0; i < _stops; i++)
      // Matches the slider's own -30..+30 degree range, so the colour
      // under the handle is the colour the handle produces.
      _swatch(hue - 30 + 60 * i / (_stops - 1), 0.75, 0.85),
  ];

  static List<Color> _satTrack(double hue) => [
    for (var i = 0; i < _stops; i++) _swatch(hue, i / (_stops - 1), 0.85),
  ];

  static List<Color> _lumTrack(double hue) => [
    for (var i = 0; i < _stops; i++)
      _swatch(hue, 0.65, 0.25 + 0.7 * i / (_stops - 1)),
  ];

  double _rangeValue(List<double> table, int firstBin) =>
      table[(firstBin + _binsPerRange ~/ 2) % colorProfileBins];

  Widget _buildColorTab(AppLocalizations l10n) => ListView(
    padding: EdgeInsets.zero,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              _advanced
                  ? l10n.colorProfileEditorAdvancedHint
                  : l10n.colorProfileEditorBasicHint,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textMuted),
            ),
          ),
          Tooltip(
            message: l10n.colorProfileEyedropper,
            child: IconButton(
              iconSize: 16,
              splashRadius: 16,
              color: DarkmoonColors.textSecondary,
              icon: const Icon(Icons.colorize),
              // Closes the dialog carrying the work — see
              // ColorProfileEditorResult for why it cannot stay open.
              onPressed: () => Navigator.of(
                context,
              ).pop(ColorProfileEditorResult.pickHue(_draft)),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _advanced = !_advanced),
            child: Text(
              _advanced
                  ? l10n.colorProfileEditorModeBasic
                  : l10n.colorProfileEditorModeAdvanced,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      if (!_advanced)
        for (final range in _hueRanges) ..._basicRange(l10n, range)
      else
        for (var bin = 0; bin < colorProfileBins; bin++)
          ..._advancedBin(l10n, bin),
    ],
  );

  /// True when the last sampled colour falls inside this range.
  bool _rangeHolds(int firstBin) {
    final bin = _highlightBin;
    if (bin == null) {
      return false;
    }
    for (var i = 0; i < _binsPerRange; i++) {
      if ((firstBin + i) % colorProfileBins == bin) {
        return true;
      }
    }
    return false;
  }

  List<Widget> _basicRange(
    AppLocalizations l10n,
    ({String key, int firstBin}) range,
  ) => [
    Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        _hueRangeLabel(l10n, range.key),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _rangeHolds(range.firstBin)
              ? DarkmoonColors.accent
              : DarkmoonColors.textSecondary,
          fontWeight: _rangeHolds(range.firstBin) ? FontWeight.w700 : null,
        ),
      ),
    ),
    _slider(
      l10n.colorProfileEditorHue,
      _rangeValue(_hueShift, range.firstBin),
      -30,
      30,
      0,
      (v) => _setRange(_hueShift, range.firstBin, v),
      track: _hueTrack(_binHue(range.firstBin + _binsPerRange ~/ 2)),
    ),
    _slider(
      l10n.colorProfileEditorSaturation,
      (_rangeValue(_satMul, range.firstBin) - 1) * 100,
      -100,
      100,
      0,
      (v) => _setRange(_satMul, range.firstBin, 1 + v / 100),
      track: _satTrack(_binHue(range.firstBin + _binsPerRange ~/ 2)),
    ),
    _slider(
      l10n.colorProfileEditorLuminance,
      (_rangeValue(_lumMul, range.firstBin) - 1) * 100,
      -100,
      100,
      0,
      (v) => _setRange(_lumMul, range.firstBin, 1 + v / 100),
      track: _lumTrack(_binHue(range.firstBin + _binsPerRange ~/ 2)),
    ),
  ];

  List<Widget> _advancedBin(AppLocalizations l10n, int bin) => [
    Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        // The bin's own hue, in degrees — the only label that means
        // anything at this granularity.
        '${bin * (360 ~/ colorProfileBins)}°',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: bin == _highlightBin
              ? DarkmoonColors.accent
              : DarkmoonColors.textSecondary,
          fontWeight: bin == _highlightBin ? FontWeight.w700 : null,
        ),
      ),
    ),
    _slider(
      l10n.colorProfileEditorHue,
      _hueShift[bin],
      -30,
      30,
      0,
      (v) => _hueShift[bin] = v,
      track: _hueTrack(_binHue(bin)),
    ),
    _slider(
      l10n.colorProfileEditorSaturation,
      (_satMul[bin] - 1) * 100,
      -100,
      100,
      0,
      (v) => _satMul[bin] = 1 + v / 100,
      track: _satTrack(_binHue(bin)),
    ),
    _slider(
      l10n.colorProfileEditorLuminance,
      (_lumMul[bin] - 1) * 100,
      -100,
      100,
      0,
      (v) => _lumMul[bin] = 1 + v / 100,
      track: _lumTrack(_binHue(bin)),
    ),
  ];

  Widget _slider(
    String name,
    double value,
    double min,
    double max,
    double defaultValue,
    void Function(double) write, {
    List<Color>? track,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SliderRow(
      name: name,
      min: min,
      max: max,
      value: value.clamp(min, max),
      defaultValue: defaultValue,
      trackColors: track,
      onChanged: (v) {
        setState(() => write(v));
        _changed();
      },
      onChangeEnd: (v) {
        setState(() => write(v));
        _settled();
      },
    ),
  );

  String _hueRangeLabel(AppLocalizations l10n, String key) => switch (key) {
    'red' => l10n.hueRangeRed,
    'orange' => l10n.hueRangeOrange,
    'yellow' => l10n.hueRangeYellow,
    'green' => l10n.hueRangeGreen,
    'aqua' => l10n.hueRangeAqua,
    'blue' => l10n.hueRangeBlue,
    'purple' => l10n.hueRangePurple,
    _ => l10n.hueRangeMagenta,
  };

  // ------------------------------------------------------------ base tab

  Widget _buildBaseTab(AppLocalizations l10n) {
    final name = _nameController.text.trim();
    final duplicate =
        name.isNotEmpty &&
        name != widget.initial.name &&
        widget.existingNames.contains(name);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(
          l10n.colorProfileEditorNameLabel,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameController,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
            fontSize: 13,
            color: DarkmoonColors.textPrimary,
          ),
          decoration: const InputDecoration(isDense: true),
        ),
        if (duplicate)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.colorProfileEditorNameTaken,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textMuted),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          l10n.colorProfileEditorResetHint,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textMuted),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              setState(() {
                _tonePoints = List<CurvePoint>.of(identityToneCurve);
                _hueShift = List<double>.of(identityColorProfile.hueShift);
                _satMul = List<double>.of(identityColorProfile.satMul);
                _lumMul = List<double>.of(identityColorProfile.lumMul);
              });
              _settled();
            },
            child: Text(l10n.colorProfileEditorReset),
          ),
        ),
      ],
    );
  }

  /// The left column: the profile applied to two different subjects at
  /// once.
  ///
  /// The chart on top answers "what does this profile do" — it carries
  /// every hue bin, the memory colours and a neutral ramp, so no control
  /// in this dialog is left with nothing to act on. The open photo below
  /// answers "what does it do to mine", which is the question that
  /// actually decides whether a profile is any good.
  ///
  /// Both, not one or the other behind a switch: a profile that flatters
  /// the chart and ruins skin is exactly the mistake worth catching, and
  /// a switch hides it by only ever showing one of the two.
  Widget _buildPreview(AppLocalizations l10n) {
    final photo = widget.photoPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorProfilePreview(
          source: _referenceChart,
          sourceWidth: referenceChartWidth,
          sourceHeight: referenceChartHeight,
          profile: _draft,
        ),
        if (photo != null) ...[
          const SizedBox(height: 10),
          ColorProfilePreview(
            source: photo.rgb,
            sourceWidth: photo.width,
            sourceHeight: photo.height,
            profile: _draft,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.sizeOf(context);
    final name = _nameController.text.trim();
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: DialogTitleRow(
        title: widget.initial.name.isEmpty
            ? l10n.colorProfileEditorTitleNew
            : l10n.colorProfileEditorTitleEdit,
        closeTooltip: l10n.closeButton,
      ),
      content: SizedBox(
        // Two columns: the before/after pair on the left, the controls on
        // the right. Wider than the app's other dialogs by necessity — the
        // point is having the comparison and the control that drives it on
        // screen at the same time, which a single column could not do
        // without pushing one of them off the bottom.
        // Clamped to what the window can actually give: an AlertDialog
        // does not shrink a fixed-size child, it overflows, and darkmoon
        // is perfectly usable in a small window. Below the threshold the
        // preview column narrows first, since the controls have a floor
        // under which the sliders stop being usable.
        width: math.min(800.0, media.width - 96),
        height: math.min(620.0, media.height - 160),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: math.max(200.0, math.min(320.0, media.width - 96 - 460)),
              child: SingleChildScrollView(child: _buildPreview(l10n)),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: DarkmoonColors.textPrimary,
                    unselectedLabelColor: DarkmoonColors.textMuted,
                    indicatorColor: DarkmoonColors.accent,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: DarkmoonColors.divider,
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 12.5),
                    tabs: [
                      Tab(text: l10n.colorProfileEditorTabTone),
                      Tab(text: l10n.colorProfileEditorTabColor),
                      Tab(text: l10n.colorProfileEditorTabBase),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildToneTab(l10n),
                        _buildColorTab(l10n),
                        _buildBaseTab(l10n),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          // A profile with no name would be saved as "profile.json" and be
          // impossible to tell apart from the next one.
          onPressed: name.isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop(ColorProfileEditorResult.saved(_draft)),
          child: Text(l10n.presetSaveLabel),
        ),
      ],
    );
  }
}
