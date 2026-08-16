import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A single adjustment control: a name/value header above a slider. The
/// value can also be clicked and typed directly, matching the Python app's
/// `SliderControl`.
///
/// The slider's value itself is controlled by the parent (value +
/// callbacks) since the editor needs the current value of every slider to
/// render the image — only whether the value label is currently being
/// edited is local, ephemeral UI state.
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

class _SliderRowState extends State<SliderRow> {
  bool _editing = false;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

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

  @override
  Widget build(BuildContext context) {
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
              child: _editing ? _buildEditField() : _buildValueLabel(),
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
            value: widget.value.clamp(widget.min, widget.max),
            onChanged: widget.onChanged,
            onChangeEnd: widget.onChangeEnd,
          ),
        ),
      ],
    );
  }

  Widget _buildValueLabel() {
    return GestureDetector(
      onTap: _startEditing,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            widget.value.toStringAsFixed(widget.decimals),
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
