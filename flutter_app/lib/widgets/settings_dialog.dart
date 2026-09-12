import 'dart:io' show Process;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/dev_log.dart';
import '../l10n/app_localizations.dart';
import '../catalog/cache_usage.dart';
import 'cache_storage_meter.dart';
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
    this.cacheUsage,
    this.onClearCaches,
    this.onRemoveSidecars,
    required this.onClearCatalog,
    required this.onPruneMissing,
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

  /// What the disk caches occupy, for the storage meter — null while the
  /// first measurement is still running.
  final CacheUsage? cacheUsage;

  /// Empties the given cache categories — see `_clearCaches`. Null leaves
  /// the storage meter read-only.
  final void Function(Set<CacheCategory> categories)? onClearCaches;

  /// Deletes the `.xmp` files this app wrote beside the library's photos
  /// (Data tab), for the user who turned sidecars off.
  final Future<void> Function()? onRemoveSidecars;
  final VoidCallback onClearCatalog;

  /// Removes saved edits/curves/masks/presets/recent-file entries for
  /// photos that no longer exist on disk — a targeted prune rather than
  /// [onClearCatalog]'s wipe-everything.
  final VoidCallback onPruneMissing;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late AppSettings _settings = widget.settings;
  late final TabController _tabController = TabController(
    length: 3,
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
  /// default denoise model for the on-device Denoise pass — see
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
      contentPadding: dialogScrollContentPadding,
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              // The content below keeps kScrollbarGutter clear on the
              // right for the scrollbar; the bar and its rule take the
              // same inset so the two line up.
              padding: const EdgeInsets.only(right: kScrollbarGutter),
              child: TabBar(
                // The theme's indicator erases the bar's rule with the
                // controls panel's background; on a dialog that is the
                // wrong near-black and shows as a seam.
                indicator: const BrowserTabIndicator(
                  background: DarkmoonColors.dialogBackground,
                ),
                controller: _tabController,
                tabs: [
                  Tab(height: kTabHeight, text: l10n.settingsTabGeneral),
                  Tab(height: kTabHeight, text: l10n.settingsTabPerformance),
                  Tab(height: kTabHeight, text: l10n.settingsTabData),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralTab(l10n),
                  _buildPerformanceTab(l10n),
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
      padding: const EdgeInsets.only(right: kScrollbarGutter),
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
          Row(
            children: [
              Expanded(
                child: Text(l10n.settingsPanelLayoutLabel, style: _labelStyle),
              ),
              StyledDropdown<bool>(
                value: _settings.tabbedControlsPanel,
                width: 170,
                items: [
                  StyledDropdownItem(
                    value: true,
                    label: l10n.settingsPanelLayoutTabbed,
                  ),
                  StyledDropdownItem(
                    value: false,
                    label: l10n.settingsPanelLayoutFlat,
                  ),
                ],
                onChanged: (value) =>
                    _update(_settings.copyWith(tabbedControlsPanel: value)),
              ),
            ],
          ),
          // Only while there are tabs to label. Shown when there are not,
          // it is a control with nothing to act on.
          if (_settings.tabbedControlsPanel)
            Row(
              children: [
                Expanded(
                  child: Text(l10n.settingsTabStyleLabel, style: _labelStyle),
                ),
                StyledDropdown<bool>(
                  value: _settings.tabbedControlsPanelIcons,
                  width: 170,
                  items: [
                    StyledDropdownItem(
                      value: false,
                      label: l10n.settingsTabStyleText,
                    ),
                    StyledDropdownItem(
                      value: true,
                      label: l10n.settingsTabStyleIcons,
                    ),
                  ],
                  onChanged: (value) => _update(
                    _settings.copyWith(tabbedControlsPanelIcons: value),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(l10n.settingsPanelLayoutHint, style: _hintStyle),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsPresetThumbnailsLabel, style: _labelStyle),
            subtitle: Text(
              l10n.settingsPresetThumbnailsHint,
              style: _hintStyle,
            ),
            value: _settings.presetThumbnails,
            onChanged: (v) => _update(_settings.copyWith(presetThumbnails: v)),
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
            title: Text(
              l10n.settingsIncludeSubfoldersLabel,
              style: _labelStyle,
            ),
            value: _settings.includeSubfolders,
            onChanged: (v) => _update(_settings.copyWith(includeSubfolders: v)),
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
      padding: const EdgeInsets.only(right: kScrollbarGutter),
      child: SettingsGroup(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsFastPreviewLabel, style: _labelStyle),
            value: _settings.fastPreview,
            onChanged: (v) => _update(_settings.copyWith(fastPreview: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsEditEmbeddedJpegLabel, style: _labelStyle),
            subtitle: Text(
              l10n.settingsEditEmbeddedJpegHint,
              style: _hintStyle,
            ),
            value: _settings.editEmbeddedJpeg,
            onChanged: (v) => _update(_settings.copyWith(editEmbeddedJpeg: v)),
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
                        StyledDropdownItem(
                          value: size,
                          label: size == nativePreviewResolution
                              ? l10n.settingsPreviewResolutionNative
                              : '$size px',
                        ),
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
              Text(l10n.settingsCustomDenoiseModelHint, style: _hintStyle),
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
          const SizedBox(height: 18),
          // Generative Replace: the Remove panel's fourth fill talks to a
          // Solstice-compatible middleware the user runs — only an
          // address to give it, nothing bundled.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsGenerativeUrlLabel, style: _labelStyle),
              const SizedBox(height: 4),
              Text(l10n.settingsGenerativeUrlHint, style: _hintStyle),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('settings-generative-url'),
                initialValue: _settings.generativeReplaceUrl,
                decoration: InputDecoration(
                  hintText: l10n.settingsGenerativeUrlPlaceholder,
                  isDense: true,
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: DarkmoonColors.textPrimary,
                ),
                onChanged: (v) =>
                    _update(_settings.copyWith(generativeReplaceUrl: v.trim())),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataTab(AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: kScrollbarGutter),
      child: SettingsGroup(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.settingsXmpSidecarLabel, style: _labelStyle),
            subtitle: Text(l10n.settingsXmpSidecarHint, style: _hintStyle),
            value: _settings.writeXmpSidecars,
            onChanged: (v) => _update(_settings.copyWith(writeXmpSidecars: v)),
          ),
          if (widget.onRemoveSidecars != null)
            _ClearDataRow(
              label: l10n.settingsRemoveSidecarsButton,
              onPressed: () => _confirmAndRun(
                l10n.confirmRemoveSidecarsMessage,
                widget.onRemoveSidecars!,
              ),
            ),
          const SizedBox(height: 6),
          CacheStorageMeter(
            usage: widget.cacheUsage,
            maxBytes: _settings.cacheMaxBytes,
            onClear: widget.onClearCaches == null
                ? null
                : (category) => _confirmAndRun(
                    // AI results get their own wording. Every other
                    // category comes back on its own the next time a photo
                    // is opened; these cost minutes of inference each, and
                    // a message that treats the two the same would be
                    // understating what is about to be thrown away.
                    category == CacheCategory.aiResults
                        ? l10n.confirmClearAiCacheMessage
                        : l10n.confirmClearCacheMessage(
                            CacheStorageMeter.labelOf(l10n, category),
                          ),
                    () => widget.onClearCaches!({category}),
                  ),
          ),
          if (widget.onClearCaches != null)
            _ClearDataRow(
              label: l10n.settingsClearAllCachesButton,
              onPressed: () => _confirmAndRun(
                l10n.confirmClearAllCachesMessage,
                () => widget.onClearCaches!(CacheCategory.values.toSet()),
              ),
            ),
          const SizedBox(height: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsCacheLimitLabel,
                      style: _labelStyle,
                    ),
                  ),
                  StyledDropdown<int>(
                    value: _settings.cacheMaxBytes,
                    width: 170,
                    items: [
                      for (final bytes in cacheMaxBytesOptions)
                        StyledDropdownItem(
                          value: bytes,
                          label: bytes == unlimitedCacheBytes
                              ? l10n.settingsCacheLimitUnlimited
                              : formatCacheBytes(bytes),
                        ),
                    ],
                    onChanged: (value) =>
                        _update(_settings.copyWith(cacheMaxBytes: value)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(l10n.settingsCacheLimitHint, style: _hintStyle),
            ],
          ),
          const SizedBox(height: 4),
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
          _ClearDataRow(
            label: l10n.settingsPruneMissingButton,
            onPressed: () => _confirmAndRun(
              l10n.confirmPruneMissingMessage,
              widget.onPruneMissing,
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
