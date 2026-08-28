import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../theme.dart';
import 'styled_dropdown.dart';

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
    this.nativeWidth,
    this.nativeHeight,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  /// The selected photo's sensor dimensions, if a photo is open — used to
  /// show the full-quality preview slider's percentage as a real pixel
  /// size, the same way the export dialog's resolution slider does.
  final int? nativeWidth;
  final int? nativeHeight;

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
    final theme = Theme.of(context);

    const labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: DarkmoonColors.textSecondary,
    );
    const hintStyle = TextStyle(
      fontSize: 11,
      color: DarkmoonColors.textMuted,
    );

    return AlertDialog(
      backgroundColor: DarkmoonColors.surfaceRaised,
      title: Text(
        l10n.settingsDialogTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Language
            Text(l10n.settingsLanguageLabel, style: labelStyle),
            const SizedBox(height: 8),
            StyledDropdown<String>(
              value: _settings.language,
              width: 170,
              items: [
                StyledDropdownItem(
                  value: 'auto',
                  label: l10n.settingsLanguageAuto,
                ),
                StyledDropdownItem(
                  value: 'en',
                  label: l10n.settingsLanguageEnglish,
                ),
                StyledDropdownItem(
                  value: 'pt',
                  label: l10n.settingsLanguagePortuguese,
                ),
              ],
              onChanged: (value) =>
                  _update(_settings.copyWith(language: value)),
            ),

            const SizedBox(height: 16),

            // Fast preview
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.settingsFastPreviewLabel, style: labelStyle),
              value: _settings.fastPreview,
              onChanged: (v) => _update(_settings.copyWith(fastPreview: v)),
            ),

            const SizedBox(height: 8),

            // Preview resolution
            Text(l10n.settingsPreviewResolutionLabel, style: labelStyle),
            const SizedBox(height: 8),
            StyledDropdown<int>(
              value: _settings.previewResolution,
              width: 170,
              items: [
                for (final size in previewResolutionOptions)
                  StyledDropdownItem(value: size, label: '$size px'),
              ],
              onChanged: (value) =>
                  _update(_settings.copyWith(previewResolution: value)),
            ),
            const SizedBox(height: 4),
            Text(l10n.settingsPreviewResolutionHint, style: hintStyle),

            const SizedBox(height: 16),

            // RAW only
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.settingsRawOnlyLabel, style: labelStyle),
              subtitle: Text(l10n.settingsRawOnlyHint, style: hintStyle),
              value: _settings.rawOnly,
              onChanged: (v) => _update(_settings.copyWith(rawOnly: v)),
            ),

            const SizedBox(height: 8),

            // GPU render
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.settingsGpuRenderLabel, style: labelStyle),
              subtitle: Text(l10n.settingsGpuRenderHint, style: hintStyle),
              value: _settings.useGpuRender,
              onChanged: (v) =>
                  _update(_settings.copyWith(useGpuRender: v)),
            ),

            const SizedBox(height: 8),

            // Dynamic full-resolution preview
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                l10n.settingsDynamicFullPreviewLabel,
                style: labelStyle,
              ),
              subtitle: Text(
                l10n.settingsDynamicFullPreviewHint,
                style: hintStyle,
              ),
              value: _settings.dynamicFullPreview,
              onChanged: (v) =>
                  _update(_settings.copyWith(dynamicFullPreview: v)),
            ),

            if (_settings.dynamicFullPreview) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.settingsFullQualityScaleLabel,
                        style: labelStyle,
                      ),
                    ),
                    Text(
                      '${_settings.fullQualityPercent}%',
                      style: hintStyle,
                    ),
                  ],
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackShape: const RectangularSliderTrackShape(),
                ),
                child: Slider(
                  min: 25,
                  max: 100,
                  divisions: 75,
                  value: _settings.fullQualityPercent.toDouble(),
                  onChanged: (v) => _update(
                    _settings.copyWith(fullQualityPercent: v.round()),
                  ),
                ),
              ),
              if (widget.nativeWidth != null && widget.nativeHeight != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 2),
                    child: Text(
                      l10n.exportRapidScaleResultLabel(
                        (widget.nativeWidth! *
                                _settings.fullQualityPercent /
                                100)
                            .round(),
                        (widget.nativeHeight! *
                                _settings.fullQualityPercent /
                                100)
                            .round(),
                      ),
                      style: hintStyle,
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 16),

            // Thumbnail threads
            Text(l10n.settingsThumbnailThreadsLabel, style: labelStyle),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: SizedBox()),
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
                  width: 28,
                  child: Text(
                    '${_settings.thumbnailConcurrency}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: DarkmoonColors.textPrimary,
                    ),
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

            const SizedBox(height: 16),

            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                l10n.settingsUserDataSection,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: DarkmoonColors.textMuted,
                ),
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
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
            side: const BorderSide(color: DarkmoonColors.border),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: DarkmoonColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}