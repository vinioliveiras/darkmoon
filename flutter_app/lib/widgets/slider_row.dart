import 'package:flutter/material.dart';

import '../theme.dart';

/// A single adjustment control: a name/value header above a slider.
///
/// This is a layout-only port of the Python app's SliderControl for now —
/// it holds its own value locally. Wiring it up to a real image pipeline is a
/// later step.
class SliderRow extends StatefulWidget {
  const SliderRow({
    super.key,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.decimals = 2,
  });

  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final int decimals;

  @override
  State<SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<SliderRow> {
  late double _value = widget.defaultValue;

  String get _formatted => _value.toStringAsFixed(widget.decimals);

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
            Text(
              _formatted,
              style: const TextStyle(color: DarkmoonColors.textMuted, fontSize: 11.5),
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
            value: _value,
            onChanged: (v) => setState(() => _value = v),
          ),
        ),
      ],
    );
  }
}
