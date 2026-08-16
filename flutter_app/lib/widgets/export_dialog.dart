import 'package:flutter/material.dart';

import '../export/export_format.dart';
import '../theme.dart';

class ExportOptions {
  const ExportOptions({required this.format, required this.quality});

  final ExportFormat format;
  final int quality;
}

/// Format + JPEG quality picker shown before the save-file dialog, mirroring
/// the Python app's `ExportOptionsDialog`. Resolves with `null` if
/// cancelled.
class ExportOptionsDialog extends StatefulWidget {
  const ExportOptionsDialog({super.key});

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  ExportFormat _format = ExportFormat.png;
  int _quality = 95;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DarkmoonColors.surfaceRaised,
      title: const Text('Export Photo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Format')),
              DropdownButton<ExportFormat>(
                value: _format,
                items: [
                  for (final format in ExportFormat.values)
                    DropdownMenuItem(value: format, child: Text(format.label)),
                ],
                onChanged: (value) => setState(() => _format = value ?? _format),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Text('Quality')),
              SizedBox(
                width: 160,
                child: Slider(
                  min: 1,
                  max: 100,
                  divisions: 99,
                  value: _quality.toDouble(),
                  label: '$_quality',
                  onChanged: _format.supportsQuality ? (v) => setState(() => _quality = v.round()) : null,
                ),
              ),
              SizedBox(width: 28, child: Text('$_quality', textAlign: TextAlign.end)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ExportOptions(format: _format, quality: _quality)),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
