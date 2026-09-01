import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A single adjustment control: a name/value header above a slider. The
/// value can also be clicked and typed directly, matching the Python app's
/// `SliderControl`.
///
/// Dragging uses *relative* sensitivity (Meridian/Photoshop-style)
/// instead of Flutter's stock `Slider`, which maps its whole min-max range
/// across the track's fixed pixel width — for a -100..100 range on a
/// ~190px-wide track that's already ~1 unit per pixel of mouse movement,
/// so no amount of value precision in the code could make it feel fine-
/// grained; the track itself is just too physically narrow for that
/// range. Here, dragging by one pixel moves the value by an amount scaled
/// to the slider's own decimal precision (0.1 units/pixel for a 2-decimal,
/// -100..100 slider — landing on tenths per pixel while still covering the
/// full range in a reasonable drag distance — much coarser for
/// Temperature's 0-decimal, 48000-wide range, where fine per-pixel control
/// isn't the point). The thumb still renders at its proportional min-max
/// position for "where am I" feedback; it just no longer jumps to follow
/// the cursor 1:1.
class SliderRow extends StatefulWidget {
  const SliderRow({
    super.key,
    required this.name,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.decimals = 2,
    this.defaultValue,
    this.trackColors,
    this.valueSuffix = '',
    this.labelFontSize = 12.5,
    this.valueFontSize = 11.5,
    this.maxFullRangeDragPixels = _maxFullRangeDragPixels,
  });

  final String name;
  final double min;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int decimals;

  /// Appended to the displayed value (e.g. `'K'` for Temperature) —
  /// display only, never included in the editable text field so typing a
  /// new value stays a plain number.
  final String valueSuffix;

  /// Font sizes for the name label and the value readout/edit field —
  /// overridable for call sites that want a more prominent standalone
  /// control (e.g. the toolbar's preset Amount slider) rather than the
  /// default sizing tuned for many stacked rows in a narrow panel.
  final double labelFontSize;
  final double valueFontSize;

  /// Double-tapping the track resets to this value, if set — matches
  /// Meridian's double-click-to-reset. Null (the default) disables the
  /// gesture rather than silently resetting to some arbitrary value.
  final double? defaultValue;

  /// When set, the track is painted as a left-to-right gradient through
  /// these colors instead of the theme's flat active/inactive colors —
  /// used for color-affecting controls (Temperature, Tint, Vibrance,
  /// Saturation) so the track itself hints at the effect, Meridian-style.
  final List<Color>? trackColors;

  /// Overrides the cap on how many pixels a full min..max drag takes
  /// (see [_maxFullRangeDragPixels]'s doc) — raise this for a control
  /// where the default already-fine-grained feel still isn't precise
  /// enough (e.g. Straighten, where a whole-pixel nudge is too coarse
  /// to nail an exact horizon angle).
  final double maxFullRangeDragPixels;

  @override
  State<SliderRow> createState() => _SliderRowState();
}

/// Roughly one frame at 60Hz — propagating faster than the app can
/// actually redraw at wouldn't be visible anyway, so this is the cheapest
/// throttle that still feels instant.
const _dragPropagateThrottle = Duration(milliseconds: 16);

/// Reference track width (px) the sensitivity formula is tuned against —
/// not the widget's actual rendered width, just a fixed constant so
/// sensitivity doesn't shift with panel width changes.
const _referenceTrackWidth = 200.0;

/// Even for a high-precision, small-range slider (Exposure: -5..5, 2
/// decimals) a full-range drag must not take more than this many pixels,
/// or it feels stuck. Without the cap Exposure worked out to 0.0005
/// units/pixel — 20 000 px end to end.
const _maxFullRangeDragPixels = 480.0;

class _SliderRowState extends State<SliderRow> {
  bool _editing = false;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Local override of widget.value while actively dragging, so this
  /// widget's own thumb/number redraw instantly without waiting on the
  /// parent. Null when not dragging (widget.value is the source of truth).
  double? _dragValue;
  Timer? _propagateTimer;

  /// Deferred `onChangeEnd` for a plain track click — see [_onTrackTap]'s
  /// doc for why.
  Timer? _pendingClickCommitTimer;

  // decimals doubles as the drag step: most sliders use decimals: 0, so
  // this lands on exactly 1 unit/pixel (20, 21, 22, ...) — the old stock
  // Slider-like feel. Exposure is the one control with decimals: 1, which
  // steps by 0.1/pixel instead.
  double get _unitsPerPixel {
    final range = widget.max - widget.min;
    final precise = range / (_referenceTrackWidth * math.pow(10, widget.decimals));
    // ...but never so fine that a full-range drag exceeds the cap.
    return math.max(precise, range / widget.maxFullRangeDragPixels);
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _editing) {
        _commit();
      }
    });
  }

  @override
  void dispose() {
    _propagateTimer?.cancel();
    _pendingClickCommitTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    _controller.text = widget.value.toStringAsFixed(widget.decimals);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    setState(() => _editing = false);
    if (parsed == null) {
      return;
    }
    _pendingClickCommitTimer?.cancel();
    _pendingClickCommitTimer = null;
    final clamped = parsed.clamp(widget.min, widget.max);
    widget.onChanged(clamped);
    widget.onChangeEnd?.call(clamped);
  }

  void _scheduleUpdate(double next) {
    _pendingClickCommitTimer?.cancel();
    _pendingClickCommitTimer = null;
    setState(() => _dragValue = next);
    _propagateTimer ??= Timer(_dragPropagateThrottle, () {
      _propagateTimer = null;
      if (_dragValue != null) {
        widget.onChanged(_dragValue!);
      }
    });
  }

  void _onDragUpdate(double deltaX) {
    final current = _dragValue ?? widget.value;
    final next = (current + deltaX * _unitsPerPixel).clamp(
      widget.min,
      widget.max,
    );
    _scheduleUpdate(next);
  }

  void _onDragEnd() {
    _propagateTimer?.cancel();
    _propagateTimer = null;
    final finalValue = _dragValue;
    setState(() => _dragValue = null);
    if (finalValue != null) {
      widget.onChanged(finalValue);
      widget.onChangeEnd?.call(finalValue);
    }
  }

  void _resetToDefault() {
    final reset = widget.defaultValue;
    if (reset == null) {
      return;
    }
    _propagateTimer?.cancel();
    _propagateTimer = null;
    _pendingClickCommitTimer?.cancel();
    _pendingClickCommitTimer = null;
    setState(() => _dragValue = null);
    widget.onChanged(reset);
    widget.onChangeEnd?.call(reset);
  }

  /// Click anywhere on the track -> jump to the value at that x. The
  /// Material [Slider] insets its track by roughly the thumb radius each
  /// side; approximate that so the ends still reach min/max.
  static const _trackInset = 12.0;

  /// Double-click-to-reset is detected by hand (two [_onTrackTap] calls
  /// close in time and position) instead of `GestureDetector.onDoubleTap`:
  /// having a double-tap recognizer on the same detector as `onTapUp`
  /// makes Flutter hold every *single* tap's resolution back by
  /// `kDoubleTapTimeout` (~300ms) to see whether a second tap follows,
  /// which — stacked on top of the render debounce — read as "clicking
  /// the track doesn't update the preview" (it did, just ~300ms late,
  /// vs. dragging's instant per-frame feedback). Tracking it ourselves
  /// keeps a plain click-to-jump instant.
  static const _doubleTapTimeout = Duration(milliseconds: 300);
  static const _doubleTapSlopPx = 40.0;
  DateTime? _lastTapTime;
  double? _lastTapX;

  void _onTrackTap(double localX, double boxWidth) {
    final now = DateTime.now();
    final isDoubleTap = widget.defaultValue != null &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!) < _doubleTapTimeout &&
        _lastTapX != null &&
        (localX - _lastTapX!).abs() < _doubleTapSlopPx;
    // A third tap right after a recognized double-tap starts a fresh pair
    // instead of chaining into another reset.
    _lastTapTime = isDoubleTap ? null : now;
    _lastTapX = isDoubleTap ? null : localX;

    if (isDoubleTap) {
      // The first tap of this pair already fired onChanged (below) and
      // queued its onChangeEnd — cancel that queued commit so a double-
      // click never pushes two undo-history entries (jump-to-click-
      // position, then reset), just the one net reset.
      _pendingClickCommitTimer?.cancel();
      _pendingClickCommitTimer = null;
      _resetToDefault();
      return;
    }

    final usable = boxWidth - 2 * _trackInset;
    if (usable <= 0) {
      return;
    }
    final t = ((localX - _trackInset) / usable).clamp(0.0, 1.0);
    final raw = widget.min + t * (widget.max - widget.min);
    final f = math.pow(10, widget.decimals).toDouble();
    final v = ((raw * f).roundToDouble() / f).clamp(widget.min, widget.max);
    _propagateTimer?.cancel();
    _propagateTimer = null;
    setState(() => _dragValue = null);
    widget.onChanged(v);
    // onChangeEnd (history/catalog commit) is deferred by the same window
    // used to detect a double-tap above, and cancelled entirely if one
    // lands — a plain click still updates the value/live preview
    // instantly via onChanged, it just doesn't commit to undo history
    // until we're sure a second tap isn't about to reset it away.
    _pendingClickCommitTimer?.cancel();
    _pendingClickCommitTimer = Timer(_doubleTapTimeout, () {
      _pendingClickCommitTimer = null;
      widget.onChangeEnd?.call(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = (_dragValue ?? widget.value).clamp(
      widget.min,
      widget.max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: widget.labelFontSize,
                ),
              ),
            ),
            SizedBox(
              width: widget.valueFontSize > 12 ? 64 : 52,
              height: widget.valueFontSize > 12 ? 22 : 18,
              child: _editing
                  ? _buildEditField()
                  : _buildValueLabel(displayValue),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            key: const Key('sliderRowTrack'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) =>
                _onDragUpdate(details.delta.dx),
            onHorizontalDragEnd: (_) => _onDragEnd(),
            onHorizontalDragCancel: _onDragEnd,
            onTapUp: (details) =>
                _onTrackTap(details.localPosition.dx, constraints.maxWidth),
            child: IgnorePointer(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackShape: widget.trackColors == null
                      ? const RectangularSliderTrackShape()
                      : _GradientSliderTrackShape(widget.trackColors!),
                ),
                child: Slider(
                  min: widget.min,
                  max: widget.max,
                  value: displayValue,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValueLabel(double displayValue) {
    return GestureDetector(
      onTap: _startEditing,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${displayValue.toStringAsFixed(widget.decimals)}${widget.valueSuffix}',
            style: TextStyle(
              color: DarkmoonColors.textMuted,
              fontSize: widget.valueFontSize,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditField() {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: DarkmoonColors.textPrimary,
        fontSize: widget.valueFontSize,
      ),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        border: OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
      ],
      onSubmitted: (_) => _commit(),
    );
  }
}

/// Paints the whole track as one gradient (ignoring the usual active/
/// inactive split) so the color relationship stays visible across the
/// full range regardless of where the thumb currently sits — matching
/// Meridian's Temperature/Tint/Vibrance/Saturation track style.
class _GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  const _GradientSliderTrackShape(this.colors);

  final List<Color> colors;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required TextDirection textDirection,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final paint = Paint()
      ..shader = LinearGradient(colors: colors).createShader(trackRect);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(1)),
      paint,
    );
  }
}
