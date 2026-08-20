import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../theme.dart';

/// Mirrors the Python app's `SettingsDialog`: every change applies and
/// saves immediately, rather than waiting for an OK/Cancel to accept. A
/// language change also applies immediately here — no restart needed,
/// since MaterialApp's `locale` just rebuilds when it changes.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onClearThumbnails,
    required this.onClearCatalog,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  /// Thumbnail cache and catalog live outside [AppSettings] (in
  /// EditorScreen's own state), so clearing them needs dedicated
  /// callbacks rather than going through [onChanged] like everything else
  /// on this dialog.
  final VoidCallback onClearThumbnails;
  final VoidCallback onClearCatalog;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late AppSettings _settings = widget.settings;

  void _update(AppSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  Future<void> _confirmAndRun(String message, VoidCallback action) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.surfaceRaised,
        title: Text(l10n.confirmClearTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.clearButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      action();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: DarkmoonColors.surfaceRaised,
      title: Text(l10n.settingsDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.settingsLanguageLabel)),
                DropdownButton<String>(
                  value: _settings.language,
                  items: [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(l10n.settingsLanguageAuto),
                    ),
                    DropdownMenuItem(
                      value: 'en',
                      child: Text(l10n.settingsLanguageEnglish),
                    ),
                    DropdownMenuItem(
                      value: 'pt',
                      child: Text(l10n.settingsLanguagePortuguese),
                    ),
                  ],
                  onChanged: (value) => _update(
                    _settings.copyWith(language: value ?? _settings.language),
                  ),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsRawOnlyLabel),
              subtitle: Text(l10n.settingsRawOnlyHint),
              value: _settings.rawOnly,
              onChanged: (v) => _update(_settings.copyWith(rawOnly: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(l10n.settingsThumbnailThreadsLabel)),
                IconButton(
                  onPressed: _settings.thumbnailConcurrency > 1
                      ? () => _update(
                          _settings.copyWith(
                            thumbnailConcurrency:
                                _settings.thumbnailConcurrency - 1,
                          ),
                        )
                      : null,
                  icon: const Icon(CupertinoIcons.minus, size: 15),
                ),
                SizedBox(
                  width: 24,
                  child: Text(
                    '${_settings.thumbnailConcurrency}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  onPressed: _settings.thumbnailConcurrency < 16
                      ? () => _update(
                          _settings.copyWith(
                            thumbnailConcurrency:
                                _settings.thumbnailConcurrency + 1,
                          ),
                        )
                      : null,
                  icon: const Icon(CupertinoIcons.add, size: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                l10n.settingsUserDataSection,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            _ClearDataRow(
              label: l10n.settingsClearThumbnailsButton,
              onPressed: () => _confirmAndRun(
                l10n.confirmClearThumbnailsMessage,
                widget.onClearThumbnails,
              ),
            ),
            _ClearDataRow(
              label: l10n.settingsClearRecentFilesButton,
              onPressed: () => _confirmAndRun(
                l10n.confirmClearRecentFilesMessage,
                () => _update(_settings.copyWith(recentFiles: const [])),
              ),
            ),
            _ClearDataRow(
              label: l10n.settingsClearCatalogButton,
              onPressed: () => _confirmAndRun(
                l10n.confirmClearCatalogMessage,
                widget.onClearCatalog,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.closeButton),
        ),
      ],
    );
  }
}

class _ClearDataRow extends StatelessWidget {
  const _ClearDataRow({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
          child: Text(label),
        ),
      ),
    );
  }
}
