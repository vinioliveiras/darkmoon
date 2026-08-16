import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A single adjustment control: a name/value header above a slider. The
/// value can also be clicked and typed directly, matching the Python app's
/// `SliderControl`.
///
/// Dragging uses *relative* sensitivity (Lightroom/Photoshop-style)
/// instead of Flutter's stock `Slider`, which maps its whole min-max range
/// across the track's fixed pixel width — for a -100..100 range on a
/// ~190px-wide track that's already ~1 unit per pixel of mouse movement,
/// so no amount of value precision in the code could make it feel fine-
/// grained; the track itself is just too physically narrow for that
/// range. Here, dragging by one pixel moves the value by an amount scaled
/// to the slider's own decimal precision (0.01 units/pixel for a 2-decimal,
/// -100..100 slider — enough to actually land on hundredths — much
/// coarser for Temperature's 0-decimal, 48000-wide range, where fine
/// per-pixel control isn't the point). The thumb still renders at its
/// proportional min-max position for "where am I" feedback; it just no
/// longer jumps to follow the cursor 1:1.
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
  });

  final String name;
  final double min;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int decimals;

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

class _SliderRowState extends State<SliderRow> {
  bool _editing = false;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Local override of widget.value while actively dragging, so this
  /// widget's own thumb/number redraw instantly without waiting on the
  /// parent. Null when not dragging (widget.value is the source of truth).
  double? _dragValue;
  Timer? _propagateTimer;

  double get _unitsPerPixel => (widget.max - widget.min) / (_referenceTrackWidth * math.pow(10, widget.decimals));

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
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    _controller.text = widget.value.toStringAsFixed(widget.decimals);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    setState(() => _editing = false);
    if (parsed == null) {
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max);
    widget.onChanged(clamped);
    widget.onChangeEnd?.call(clamped);
  }

  void _scheduleUpdate(double next) {
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
    final next = (current + deltaX * _unitsPerPixel).clamp(widget.min, widget.max);
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

  @override
  Widget build(BuildContext context) {
    final displayValue = (_dragValue ?? widget.value).clamp(widget.min, widget.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.name, style: Theme.of(context).textTheme.bodyMedium),
            ),
            SizedBox(
              width: 52,
              height: 18,
              child: _editing ? _buildEditField() : _buildValueLabel(displayValue),
            ),
          ],
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => _onDragUpdate(details.delta.dx),
          onHorizontalDragEnd: (_) => _onDragEnd(),
          onHorizontalDragCancel: _onDragEnd,
          child: IgnorePointer(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackShape: const RectangularSliderTrackShape(),
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
            displayValue.toStringAsFixed(widget.decimals),
            style: const TextStyle(color: DarkmoonColors.textMuted, fontSize: 11.5),
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
      style: const TextStyle(color: DarkmoonColors.textPrimary, fontSize: 11.5),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        border: OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
      onSubmitted: (_) => _commit(),
    );
  }
}
