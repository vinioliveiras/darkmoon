import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/color_profile.dart';
import '../render/tone_curve.dart';
import '../theme.dart';
import 'dialog_chrome.dart';
import 'slider_row.dart';
import 'tone_curve_editor.dart';

/// Creates or edits a user-authored "darkmoon Color" profile.
///
/// Deliberately aligned to the right edge over the controls panel rather
/// than centred: the whole point is watching the photo change while you
/// work, and a centred modal would cover it. There is no preview widget
/// inside the dialog at all — [onDraftChanged] pushes the work-in-progress
/// profile into the editor, which renders it through the same GPU pipeline
/// everything else uses. What you see while editing is the real thing, not
/// an approximation of it.
///
/// [onDraftChanged] fires continuously (live, low-res preview) and
/// [onDraftSettled] once a gesture ends (full-quality), matching the
/// convention every slider in this app already follows.
class ColorProfileEditorDialog extends StatefulWidget {
  const ColorProfileEditorDialog({
    super.key,
    required this.initial,
    required this.existingNames,
    required this.onDraftChanged,
    required this.onDraftSettled,
  });

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

  List<Widget> _basicRange(
    AppLocalizations l10n,
    ({String key, int firstBin}) range,
  ) => [
    Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        _hueRangeLabel(l10n, range.key),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textSecondary),
      ),
    ),
    _slider(
      l10n.colorProfileEditorHue,
      _rangeValue(_hueShift, range.firstBin),
      -30,
      30,
      0,
      (v) => _setRange(_hueShift, range.firstBin, v),
    ),
    _slider(
      l10n.colorProfileEditorSaturation,
      (_rangeValue(_satMul, range.firstBin) - 1) * 100,
      -100,
      100,
      0,
      (v) => _setRange(_satMul, range.firstBin, 1 + v / 100),
    ),
    _slider(
      l10n.colorProfileEditorLuminance,
      (_rangeValue(_lumMul, range.firstBin) - 1) * 100,
      -100,
      100,
      0,
      (v) => _setRange(_lumMul, range.firstBin, 1 + v / 100),
    ),
  ];

  List<Widget> _advancedBin(AppLocalizations l10n, int bin) => [
    Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        // The bin's own hue, in degrees — the only label that means
        // anything at this granularity.
        '${bin * (360 ~/ colorProfileBins)}°',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: DarkmoonColors.textSecondary),
      ),
    ),
    _slider(l10n.colorProfileEditorHue, _hueShift[bin], -30, 30, 0, (v) {
      _hueShift[bin] = v;
    }),
    _slider(
      l10n.colorProfileEditorSaturation,
      (_satMul[bin] - 1) * 100,
      -100,
      100,
      0,
      (v) => _satMul[bin] = 1 + v / 100,
    ),
    _slider(
      l10n.colorProfileEditorLuminance,
      (_lumMul[bin] - 1) * 100,
      -100,
      100,
      0,
      (v) => _lumMul[bin] = 1 + v / 100,
    ),
  ];

  Widget _slider(
    String name,
    double value,
    double min,
    double max,
    double defaultValue,
    void Function(double) write,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SliderRow(
      name: name,
      min: min,
      max: max,
      value: value.clamp(min, max),
      defaultValue: defaultValue,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      // Right-aligned so the canvas stays visible behind it — see the class
      // doc. The preview *is* the photo.
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      title: DialogTitleRow(
        title: widget.initial.name.isEmpty
            ? l10n.colorProfileEditorTitleNew
            : l10n.colorProfileEditorTitleEdit,
        closeTooltip: l10n.closeButton,
      ),
      content: SizedBox(
        width: 420,
        height: 520,
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
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
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
              : () => Navigator.of(context).pop(_draft),
          child: Text(l10n.presetSaveLabel),
        ),
      ],
    );
  }
}
