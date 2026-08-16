import 'package:flutter/material.dart';

import '../theme.dart';

/// A single adjustment control: a name/value header above a slider.
///
/// Controlled by the parent (value + callbacks) rather than holding its own
/// state, since the editor needs the current value of every slider to
/// render the image.
class SliderRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              value.toStringAsFixed(decimals),
              style: const TextStyle(color: DarkmoonColors.textMuted, fontSize: 11.5),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const RectangularSliderTrackShape(),
          ),
          child: Slider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}
