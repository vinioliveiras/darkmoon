import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../theme.dart';

/// Mirrors the Python app's `SettingsDialog`: every change applies and
/// saves immediately, rather than waiting for an OK/Cancel to accept. A
/// language change also applies immediately here — no restart needed,
/// since MaterialApp's `locale` just rebuilds when it changes.
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
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: DarkmoonColors.surfaceRaised,
      title: Text(l10n.settingsDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.settingsLanguageLabel)),
              DropdownButton<String>(
                value: _settings.language,
                items: [
                  DropdownMenuItem(value: 'auto', child: Text(l10n.settingsLanguageAuto)),
                  DropdownMenuItem(value: 'en', child: Text(l10n.settingsLanguageEnglish)),
                  DropdownMenuItem(value: 'pt', child: Text(l10n.settingsLanguagePortuguese)),
                ],
                onChanged: (value) => _update(_settings.copyWith(language: value ?? _settings.language)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsFastPreviewLabel),
            value: _settings.fastPreview,
            onChanged: (v) => _update(_settings.copyWith(fastPreview: v)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(l10n.settingsThumbnailThreadsLabel)),
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.closeButton)),
      ],
    );
  }
}
