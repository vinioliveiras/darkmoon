import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A single adjustment control: a name/value header above a slider. The
/// value can also be clicked and typed directly, matching the Python app's
/// `SliderControl`.
///
/// The slider's value is controlled by the parent (value + callbacks)
/// since the editor needs the current value of every slider to render the
/// image — but while actively dragging, this widget tracks the position
/// locally and only propagates to the parent every ~1 frame instead of on
/// every pointer tick. Without that, every tick triggered a full rebuild
/// of the entire editor (image, histogram, filmstrip, all other sliders)
/// via the parent's setState, which is what made dragging feel stuttery —
/// not a precision issue, the value itself was always a full-precision
/// double.
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

class _SliderRowState extends State<SliderRow> {
  bool _editing = false;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Local override of widget.value while actively dragging, so this
  /// widget's own thumb/number redraw instantly without waiting on the
  /// parent. Null when not dragging (widget.value is the source of truth).
  double? _dragValue;
  Timer? _propagateTimer;

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

  void _onDragChanged(double v) {
    setState(() => _dragValue = v);
    _propagateTimer ??= Timer(_dragPropagateThrottle, () {
      _propagateTimer = null;
      if (_dragValue != null) {
        widget.onChanged(_dragValue!);
      }
    });
  }

  void _onDragEnd(double v) {
    _propagateTimer?.cancel();
    _propagateTimer = null;
    setState(() => _dragValue = null);
    // Always send the exact final value, even if a throttled tick already
    // sent something close — onChangeEnd is what triggers the full-quality
    // render and catalog save, so it must reflect where the thumb actually
    // stopped.
    widget.onChanged(v);
    widget.onChangeEnd?.call(v);
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
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const RectangularSliderTrackShape(),
          ),
          child: Slider(
            min: widget.min,
            max: widget.max,
            value: displayValue,
            onChanged: _onDragChanged,
            onChangeEnd: _onDragEnd,
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
