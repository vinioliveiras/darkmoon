import 'package:flutter/material.dart';

import '../theme.dart';
import 'tone_curve_editor.dart' show kToneCurvePlotInset;

/// The three draggable split handles that set where the parametric Tone
/// Curve's four regions meet — Meridian draws them as triangles under the
/// curve graph, and this is that control.
///
/// Sits directly below `ToneCurveEditor` and shares its horizontal
/// geometry (see [kToneCurvePlotInset]), so a handle at 25% lines up with
/// the point on the curve above it that it actually splits.
///
/// The three split *sliders* stay in the panel. They are not redundant
/// with this: the sliders are the keyboard-reachable path and show the
/// numeric value, while dragging here is the fast one. Replacing them
/// outright with direct manipulation would have quietly removed keyboard
/// access to those three values.
///
/// [onChanged] fires continuously while dragging and [onChangeEnd] once
/// the gesture finishes, matching `SliderRow` — a live low-res preview
/// during the drag, the full-quality render and catalog write after it.
class ParametricSplitBar extends StatefulWidget {
  const ParametricSplitBar({
    super.key,
    required this.shadowSplit,
    required this.midtoneSplit,
    required this.highlightSplit,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double shadowSplit;
  final double midtoneSplit;
  final double highlightSplit;

  /// Reports by slider name (`ParamCurveShadowSplit` and friends) rather
  /// than by index, so the editor wires this straight into the same
  /// handlers the split sliders already use.
  final void Function(String name, double value) onChanged;
  final void Function(String name, double value) onChangeEnd;

  @override
  State<ParametricSplitBar> createState() => _ParametricSplitBarState();
}

/// Slider name, allowed range and default for each handle, left to right.
/// The ranges mirror `_parametricCurveSliders` in editor_screen.dart and
/// the defaults mirror `ParametricCurve`'s own.
typedef _SplitSpec = ({String name, double min, double max, double initial});

const List<_SplitSpec> _splits = [
  (name: 'ParamCurveShadowSplit', min: 5, max: 90, initial: 25),
  (name: 'ParamCurveMidtoneSplit', min: 10, max: 94, initial: 50),
  (name: 'ParamCurveHighlightSplit', min: 20, max: 98, initial: 75),
];

/// Keeps a handle from being dragged onto its neighbour, in the same
/// 0..100 units the splits use. `parametricCurvePoints` clamps by 0.02 in
/// 0..1 space for exactly this reason; matching it here means the control
/// cannot express a state the curve would then silently correct.
const _minSplitGap = 2.0;

const _barHeight = 16.0;
const _triangleHalfWidth = 6.0;
const _hitRadius = 14.0;

class _ParametricSplitBarState extends State<ParametricSplitBar> {
  int? _activeIndex;

  List<double> get _values => [
    widget.shadowSplit,
    widget.midtoneSplit,
    widget.highlightSplit,
  ];

  double _xFor(double value, double width) =>
      kToneCurvePlotInset + (value / 100.0) * (width - 2 * kToneCurvePlotInset);

  double _valueFor(double dx, double width) =>
      ((dx - kToneCurvePlotInset) / (width - 2 * kToneCurvePlotInset) * 100.0)
          .clamp(0.0, 100.0);

  int? _nearestHandle(double dx, double width) {
    var best = -1;
    var bestDistance = double.infinity;
    final values = _values;
    for (var i = 0; i < values.length; i++) {
      final distance = (_xFor(values[i], width) - dx).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return bestDistance <= _hitRadius ? best : null;
  }

  /// Clamps [raw] to the handle's own range and to its neighbours, so the
  /// three stay ordered however fast the pointer moves.
  double _clampForIndex(int index, double raw) {
    final values = _values;
    final spec = _splits[index];
    var lower = spec.min;
    var upper = spec.max;
    if (index > 0) {
      final neighbour = values[index - 1] + _minSplitGap;
      if (neighbour > lower) {
        lower = neighbour;
      }
    }
    if (index < values.length - 1) {
      final neighbour = values[index + 1] - _minSplitGap;
      if (neighbour < upper) {
        upper = neighbour;
      }
    }
    // The window can close entirely when the neighbours are already
    // touching. Calling clamp with lower > upper throws, and returning
    // `lower` regardless would shove the handle past its neighbour, which
    // is the ordering this method exists to protect. Staying put is the
    // only correct answer.
    if (upper < lower) {
      return values[index];
    }
    return raw.clamp(lower, upper);
  }

  /// Double-click-to-reset, recognised from the drag lifecycle itself
  /// rather than by adding a tap or double-tap recogniser to this
  /// detector. Both of those were tried and both broke dragging:
  ///
  ///  - `onDoubleTapDown` wins the gesture arena on pointer-down, so the
  ///    pan callbacks never fired at all and the handles could not be
  ///    dragged whatsoever.
  ///  - `onTapUp` is less severe but still costly: with a tap recogniser
  ///    competing, the pan only wins after the pointer travels `kPanSlop`
  ///    (36 logical pixels), so a handle would sit still through the first
  ///    third of an inch of drag. Unacceptable on a precision control.
  ///
  /// With pan as the sole recogniser it wins immediately and the handle
  /// tracks the pointer from the first pixel. A "click" is then simply a
  /// gesture that ended without any movement, which is what
  /// [_lastGestureMoved] records. `SliderRow` detects its own
  /// double-click by hand for a related reason.
  static const _doubleTapTimeout = Duration(milliseconds: 300);
  static const _doubleTapSlopPx = 40.0;
  DateTime? _lastDownTime;
  double? _lastDownX;
  bool _lastGestureMoved = false;

  void _handlePanDown(DragDownDetails details, double width) {
    final dx = details.localPosition.dx;
    final now = DateTime.now();
    final isDoubleClick =
        !_lastGestureMoved &&
        _lastDownTime != null &&
        now.difference(_lastDownTime!) < _doubleTapTimeout &&
        _lastDownX != null &&
        (dx - _lastDownX!).abs() < _doubleTapSlopPx;
    // A third click straight after a recognised pair starts a fresh one
    // rather than chaining into another reset.
    _lastDownTime = isDoubleClick ? null : now;
    _lastDownX = isDoubleClick ? null : dx;
    _lastGestureMoved = false;

    final index = _nearestHandle(dx, width);
    setState(() => _activeIndex = index);
    if (!isDoubleClick || index == null) {
      return;
    }
    final reset = _clampForIndex(index, _splits[index].initial);
    widget.onChanged(_splits[index].name, reset);
    widget.onChangeEnd(_splits[index].name, reset);
  }

  void _handlePanUpdate(DragUpdateDetails details, double width) {
    final index = _activeIndex;
    if (index == null) {
      return;
    }
    _lastGestureMoved = true;
    final next = _clampForIndex(
      index,
      _valueFor(details.localPosition.dx, width),
    );
    widget.onChanged(_splits[index].name, next);
  }

  void _handlePanEnd() {
    final index = _activeIndex;
    // Only a gesture that actually moved gets a commit. Committing a bare
    // click would kick off a full-quality render of a value nothing
    // changed.
    if (index != null && _lastGestureMoved) {
      widget.onChangeEnd(_splits[index].name, _values[index]);
    }
    setState(() => _activeIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Pan is deliberately the only recogniser here — see
            // [_handlePanDown]. onPanDown, not onPanStart, grabs the
            // handle: it fires on pointer-down, so the grab is decided
            // before any movement rather than after the drag is
            // recognised.
            onPanDown: (d) => _handlePanDown(d, width),
            onPanUpdate: (d) => _handlePanUpdate(d, width),
            onPanEnd: (_) => _handlePanEnd(),
            onPanCancel: _handlePanEnd,
            child: CustomPaint(
              painter: _SplitBarPainter(
                values: _values,
                activeIndex: _activeIndex,
              ),
              size: Size(width, _barHeight),
            ),
          ),
        );
      },
    );
  }
}

class _SplitBarPainter extends CustomPainter {
  const _SplitBarPainter({required this.values, required this.activeIndex});

  final List<double> values;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final left = kToneCurvePlotInset;
    final usable = size.width - 2 * kToneCurvePlotInset;

    // The four region bands. Without them the triangles are three marks on
    // an empty strip; with them it is visible that they bound Shadows,
    // Darks, Lights and Highlights — which is what the four sliders above
    // act on. The bands lighten left to right because the axis is input
    // luminance, the same axis as the curve graph directly above.
    final edges = [0.0, ...values, 100.0];
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTRB(
          left + usable * edges[i] / 100.0,
          size.height - 5,
          left + usable * edges[i + 1] / 100.0,
          size.height - 1,
        ),
        Paint()
          ..color = DarkmoonColors.textPrimary.withValues(
            alpha: 0.10 + 0.11 * i,
          ),
      );
    }

    for (var i = 0; i < values.length; i++) {
      final x = left + usable * values[i] / 100.0;
      // Pointing up, at the curve the handle splits.
      final path = Path()
        ..moveTo(x, size.height - 7)
        ..lineTo(x - _triangleHalfWidth, size.height + 2)
        ..lineTo(x + _triangleHalfWidth, size.height + 2)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = i == activeIndex
              ? DarkmoonColors.accent
              : DarkmoonColors.textSecondary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplitBarPainter oldDelegate) {
    if (oldDelegate.activeIndex != activeIndex) {
      return true;
    }
    for (var i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) {
        return true;
      }
    }
    return false;
  }
}
