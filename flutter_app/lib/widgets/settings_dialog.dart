import 'dart:io' show Process;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/dev_log.dart';
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../theme.dart';
import 'animated_dialog.dart';
import 'dialog_chrome.dart';
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

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late AppSettings _settings = widget.settings;
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _update(AppSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  /// Lets the user pick a `.onnx` file to use in place of the bundled
  /// NAFNet-SIDD-width64.onnx for the on-device Denoise pass — see
  /// `AppSettings.customDenoiseModelPath`'s doc for the drop-in-
  /// replacement constraint this comes with (not a generic model loader).
  Future<void> _pickCustomDenoiseModel() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.settingsCustomDenoiseModelPickerTitle,
      type: FileType.custom,
      allowedExtensions: ['onnx'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    _update(_settings.copyWith(customDenoiseModelPath: path));
  }

  Future<void> _confirmAndRun(String message, VoidCallback action) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.dialogBackground,
        shape: dialogShape,
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

  static const _labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: DarkmoonColors.textSecondary,
  );
  static const _hintStyle = TextStyle(
    fontSize: 11,
    color: DarkmoonColors.textMuted,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: DialogTitleRow(
        title: l10n.settingsDialogTitle,
        closeTooltip: l10n.closeButton,
      ),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabController,
              labelColor: DarkmoonColors.textPrimary,
              unselectedLabelColor: DarkmoonColors.textMuted,
              indicatorColor: DarkmoonColors.accent,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: DarkmoonColors.divider,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              labelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 12.5),
              tabs: [
                Tab(text: l10n.settingsTabGeneral),
                Tab(text: l10n.settingsTabPerformance),
                Tab(text: l10n.settingsTabColor),
                Tab(text: l10n.settingsTabData),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralTab(l10n),
                  _buildPerformanceTab(l10n),
                  _buildColorTab(l10n),
                  _buildDataTab(l10n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralTab(AppLocalizations l10n) {
    return SingleChildScrollView(
      child: SettingsGroup(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.settingsLanguageLabel, style: _labelStyle),
              ),
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
                  StyledDropdownItem(
                    value: 'de',
                    label: l10n.settingsLanguageGerman,
                  ),
                ],
                onChanged: (value) =>
                    _update(_settings.copyWith(language: value)),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsRawOnlyLabel, style: _labelStyle),
            subtitle: Text(l10n.settingsRawOnlyHint, style: _hintStyle),
            value: _settings.rawOnly,
            onChanged: (v) => _update(_settings.copyWith(rawOnly: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsAnimationsLabel, style: _labelStyle),
            subtitle: Text(l10n.settingsAnimationsHint, style: _hintStyle),
            value: _settings.animationsEnabled,
            onChanged: (v) => _update(_settings.copyWith(animationsEnabled: v)),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceTab(AppLocalizations l10n) {
    return SingleChildScrollView(
      child: SettingsGroup(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsFastPreviewLabel, style: _labelStyle),
            value: _settings.fastPreview,
            onChanged: (v) => _update(_settings.copyWith(fastPreview: v)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsPreviewResolutionLabel,
                      style: _labelStyle,
                    ),
                  ),
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
                ],
              ),
              const SizedBox(height: 4),
              Text(l10n.settingsPreviewResolutionHint, style: _hintStyle),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsGpuRenderLabel, style: _labelStyle),
            subtitle: Text(l10n.settingsGpuRenderHint, style: _hintStyle),
            value: _settings.useGpuRender,
            onChanged: (v) => _update(_settings.copyWith(useGpuRender: v)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  l10n.settingsDynamicFullPreviewLabel,
                  style: _labelStyle,
                ),
                subtitle: Text(
                  l10n.settingsDynamicFullPreviewHint,
                  style: _hintStyle,
                ),
                value: _settings.dynamicFullPreview,
                onChanged: (v) =>
                    _update(_settings.copyWith(dynamicFullPreview: v)),
              ),
              if (_settings.dynamicFullPreview) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.settingsFullQualityScaleLabel,
                        style: _labelStyle,
                      ),
                    ),
                    Text('${_settings.fullQualityPercent}%', style: _hintStyle),
                  ],
                ),
                Builder(
                  builder: (context) => SliderTheme(
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
                ),
                if (widget.nativeWidth != null && widget.nativeHeight != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
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
                        style: _hintStyle,
                      ),
                    ),
                  ),
              ],
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.settingsThumbnailThreadsLabel,
                  style: _labelStyle,
                ),
              ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsCustomDenoiseModelLabel, style: _labelStyle),
              const SizedBox(height: 4),
              Text(
                l10n.settingsCustomDenoiseModelHint,
                style: _hintStyle,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _settings.customDenoiseModelPath == null
                          ? l10n.settingsCustomDenoiseModelDefault
                          : p.basename(_settings.customDenoiseModelPath!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: DarkmoonColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _pickCustomDenoiseModel,
                    child: Text(l10n.settingsCustomDenoiseModelChooseButton),
                  ),
                  if (_settings.customDenoiseModelPath != null)
                    TextButton(
                      onPressed: () =>
                          _update(_settings.withDefaultDenoiseModel()),
                      child: Text(l10n.settingsCustomDenoiseModelResetButton),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorTab(AppLocalizations l10n) {
    return SingleChildScrollView(
      child: SettingsGroup(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsBaseContrastLabel,
                      style: _labelStyle,
                    ),
                  ),
                  Text(
                    _settings.baseContrast.round().toString(),
                    style: _hintStyle,
                  ),
                ],
              ),
              Builder(
                builder: (context) => SliderTheme(
                  data: SliderTheme.of(
                    context,
                  ).copyWith(trackShape: const RectangularSliderTrackShape()),
                  child: Slider(
                    min: 0,
                    max: 60,
                    divisions: 60,
                    value: _settings.baseContrast.clamp(0.0, 60.0),
                    onChanged: (v) => _update(
                      _settings.copyWith(baseContrast: v.roundToDouble()),
                    ),
                  ),
                ),
              ),
              Text(l10n.settingsBaseContrastHint, style: _hintStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataTab(AppLocalizations l10n) {
    return SingleChildScrollView(
      child: SettingsGroup(
        children: [
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
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsDevLoggingLabel, style: _labelStyle),
            subtitle: Text(l10n.settingsDevLoggingHint, style: _hintStyle),
            value: _settings.devLogging,
            onChanged: (v) {
              DevLog.setEnabled(v);
              _update(_settings.copyWith(devLogging: v));
            },
          ),
          _ClearDataRow(
            label: l10n.settingsOpenLogFolderButton,
            onPressed: () async {
              final dir = await resolveDevLogDir();
              await Process.run('explorer.exe', [dir.path]);
            },
          ),
        ],
      ),
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
