import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../theme.dart';

/// Mirrors the Python app's `SettingsDialog`: every change applies and
/// saves immediately, rather than waiting for an OK/Cancel to accept.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.settings, required this.onChanged});

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late AppSettings _settings = widget.settings;

  void _update(AppSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DarkmoonColors.surfaceRaised,
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fast preview while dragging sliders'),
            value: _settings.fastPreview,
            onChanged: (v) => _update(_settings.copyWith(fastPreview: v)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('Thumbnail loading threads')),
              IconButton(
                onPressed: _settings.thumbnailConcurrency > 1
                    ? () => _update(_settings.copyWith(thumbnailConcurrency: _settings.thumbnailConcurrency - 1))
                    : null,
                icon: const Icon(Icons.remove, size: 16),
              ),
              SizedBox(
                width: 24,
                child: Text('${_settings.thumbnailConcurrency}', textAlign: TextAlign.center),
              ),
              IconButton(
                onPressed: _settings.thumbnailConcurrency < 16
                    ? () => _update(_settings.copyWith(thumbnailConcurrency: _settings.thumbnailConcurrency + 1))
                    : null,
                icon: const Icon(Icons.add, size: 16),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
