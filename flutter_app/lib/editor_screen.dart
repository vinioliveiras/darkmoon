import 'dart:async';
import 'dart:io' show Directory, File;
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'catalog/catalog_store.dart';
import 'catalog/curve_store.dart';
import 'catalog/mask_store.dart';
import 'catalog/thumbnail_cache.dart';
import 'catalog/thumbnail_cache_dir.dart';
import 'export/export_job.dart';
import 'l10n/app_localizations.dart';
import 'native/edit_source.dart';
import 'native/thumbnail_loader.dart';
import 'presets/preset.dart';
import 'presets/preset_store.dart';
import 'presets/preset_xmp.dart';
import 'presets/preset_zip.dart';
import 'raw_files.dart';
import 'render/histogram.dart';
import 'render/mask.dart';
import 'render/render_job.dart';
import 'render/render_params.dart';
import 'render/tone_curve.dart';
import 'settings/app_settings.dart';
import 'theme.dart';
import 'widgets/brush_mask_overlay.dart';
import 'widgets/color_range_overlay.dart';
import 'widgets/color_wheel.dart';
import 'widgets/export_dialog.dart';
import 'widgets/folder_sidebar.dart';
import 'widgets/gradient_mask_overlay.dart';
import 'widgets/histogram_view.dart';
import 'widgets/mask_selector.dart';
import 'widgets/preset_panel.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/slider_row.dart';
import 'widgets/text_prompt_dialog.dart';
import 'widgets/tone_curve_editor.dart';

/// Maps a slider's stable internal key (also used for _paramValues,
/// RenderParams.fromValues, and catalog storage — must NOT be translated)
/// to its localized display label.
String _sliderLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'Temperature':
      return l10n.sliderTemperature;
    case 'Tint':
      return l10n.sliderTint;
    case 'Exposure':
      return l10n.sliderExposure;
    case 'Brightness':
      return l10n.sliderBrightness;
    case 'Contrast':
      return l10n.sliderContrast;
    case 'Highlights':
      return l10n.sliderHighlights;
    case 'Shadows':
      return l10n.sliderShadows;
    case 'Whites':
      return l10n.sliderWhites;
    case 'Blacks':
      return l10n.sliderBlacks;
    case 'Texture':
      return l10n.sliderTexture;
    case 'Clarity':
      return l10n.sliderClarity;
    case 'Dehaze':
      return l10n.sliderDehaze;
    case 'Vibrance':
      return l10n.sliderVibrance;
    case 'Saturation':
      return l10n.sliderSaturation;
    case 'AiDenoiseAmount':
      return l10n.sliderAiDenoiseAmount;
    case 'SharpenAmount':
      return l10n.sliderSharpenAmount;
    case 'SharpenRadius':
      return l10n.sliderSharpenRadius;
    case 'SharpenDetail':
      return l10n.sliderSharpenDetail;
    case 'SharpenMasking':
      return l10n.sliderSharpenMasking;
    case 'DenoiseLuminance':
      return l10n.sliderDenoiseLuminance;
    case 'DenoiseLuminanceDetail':
      return l10n.sliderDenoiseLuminanceDetail;
    case 'DenoiseLuminanceContrast':
      return l10n.sliderDenoiseLuminanceContrast;
    case 'DenoiseColor':
      return l10n.sliderDenoiseColor;
    case 'DenoiseColorDetail':
      return l10n.sliderDenoiseColorDetail;
    case 'DenoiseColorSmoothness':
      return l10n.sliderDenoiseColorSmoothness;
    case 'VignetteAmount':
      return l10n.sliderVignetteAmount;
    case 'VignetteMidpoint':
      return l10n.sliderVignetteMidpoint;
    case 'VignetteFeather':
      return l10n.sliderVignetteFeather;
    default:
      return key;
  }
}

/// Maps a section's stable internal key to its localized display label —
/// same reasoning as [_sliderLabel].
String _sectionLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'WHITE BALANCE':
      return l10n.sectionWhiteBalance;
    case 'TONE':
      return l10n.sectionTone;
    case 'PRESENCE':
      return l10n.sectionPresence;
    case 'DETAIL':
      return l10n.sectionDetail;
    case 'EFFECTS':
      return l10n.sectionEffects;
    default:
      return key;
  }
}

/// Zoom bounds and step, matching the Python app's MIN_ZOOM/MAX_ZOOM/ZOOM_STEP.
const double _minZoom = 0.1;
const double _maxZoom = 4.0;
const double _zoomStep = 1.15;

/// How long to wait after the last slider change before actually
/// re-rendering, restarted on every change — matches the Python app's
/// DEBOUNCE_MS. Keeps a fast slider drag from queuing a render per frame.
const _renderDebounce = Duration(milliseconds: 25);

/// How long to wait after the last slider change before writing the
/// catalog to disk, restarted on every change — matches the Python app's
/// CATALOG_SAVE_DEBOUNCE_MS. Switching photos or folders flushes
/// immediately instead of waiting for this.
const _catalogSaveDebounce = Duration(milliseconds: 800);

class _SliderSpec {
  const _SliderSpec(
    this.name,
    this.min,
    this.max,
    this.defaultValue, {
    this.decimals = 0,
    this.gradientColors,
  });

  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final int decimals;

  /// Track gradient for color-affecting controls, Lightroom-style — null
  /// for everything else, which keeps the plain theme track.
  final List<Color>? gradientColors;
}

const _sections = <String, List<_SliderSpec>>{
  'WHITE BALANCE': [
    _SliderSpec(
      'Temperature',
      2000,
      50000,
      5500,
      decimals: 0,
      gradientColors: [Color(0xFF4FA6FF), Color(0xFFFFB454)],
    ),
    _SliderSpec(
      'Tint',
      -100,
      100,
      0,
      gradientColors: [Color(0xFF3DD16B), Color(0xFFE362D8)],
    ),
  ],
  'TONE': [
    _SliderSpec('Exposure', -100, 100, 0, decimals: 1),
    _SliderSpec('Brightness', -100, 100, 0),
    _SliderSpec('Contrast', -100, 100, 0),
    _SliderSpec('Highlights', -100, 100, 0),
    _SliderSpec('Shadows', -100, 100, 0),
    _SliderSpec('Whites', -100, 100, 0),
    _SliderSpec('Blacks', -100, 100, 0),
  ],
  'PRESENCE': [
    _SliderSpec('Texture', -100, 100, 0),
    _SliderSpec('Clarity', -100, 100, 0),
    _SliderSpec('Dehaze', -100, 100, 0),
    _SliderSpec(
      'Vibrance',
      -100,
      100,
      0,
      gradientColors: [Color(0xFF9AA0A8), Color(0xFFE0483C)],
    ),
    _SliderSpec(
      'Saturation',
      -100,
      100,
      0,
      gradientColors: [Color(0xFF9AA0A8), Color(0xFFE0483C)],
    ),
  ],
  'DETAIL': [
    _SliderSpec('AiDenoiseAmount', 0, 100, 0),
    _SliderSpec('SharpenAmount', 0, 150, 0),
    _SliderSpec('SharpenRadius', 0.5, 3.0, 1.0, decimals: 1),
    _SliderSpec('SharpenDetail', 0, 100, 25),
    _SliderSpec('SharpenMasking', 0, 100, 0),
    _SliderSpec('DenoiseLuminance', 0, 100, 0),
    _SliderSpec('DenoiseLuminanceDetail', 0, 100, 50),
    _SliderSpec('DenoiseLuminanceContrast', 0, 100, 0),
    _SliderSpec('DenoiseColor', 0, 100, 0),
    _SliderSpec('DenoiseColorDetail', 0, 100, 50),
    _SliderSpec('DenoiseColorSmoothness', 0, 100, 50),
  ],
};

/// Post-Crop Vignette sliders (Lightroom's Effects panel) — global-only,
/// so kept out of [_sections] (which masks also render from) rather than
/// a fourth entry there.
const _vignetteSliders = [
  _SliderSpec('VignetteAmount', -100, 100, 0),
  _SliderSpec('VignetteMidpoint', 0, 100, 50),
  _SliderSpec('VignetteFeather', 0, 100, 50),
];

Map<String, double> _defaultParamValues() {
  return {
    for (final specs in _sections.values)
      for (final spec in specs) spec.name: spec.defaultValue,
    // Vignette lives outside [_sections] (masks don't get Effects) but
    // still needs its non-zero neutrals (Midpoint/Feather = 50) in the
    // defaults map, or Reset / first-open / preset-merge would leave
    // those keys missing and the sliders would snap to 0.
    for (final spec in _vignetteSliders) spec.name: spec.defaultValue,
  };
}

/// Main window: image viewer + toolbar, adjustment panel, and a filmstrip
/// that lists real RAW files from a chosen folder. Selecting a file decodes
/// its full RAW preview in the background (showing the fast embedded
/// thumbnail in the meantime).
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.onLanguageChanged});

  /// Applies a language change immediately app-wide — owned by DarkmoonApp
  /// since it controls MaterialApp's `locale`, not this screen.
  final ValueChanged<String> onLanguageChanged;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  List<RawFile> _files = const [];
  int? _selectedIndex;
  bool _loading = false;

  /// Whichever folder is actually loaded into [_files] right now — may be
  /// one of [AppSettings.libraryFolders] or one of its subfolders. Used to
  /// highlight the active folder in the sidebar.
  String? _currentFolder;
  final Map<String, Uint8List> _thumbnails = {};
  final Map<String, EditSourcePair> _editSources = {};
  final Map<String, Uint8List> _renderedPreviews = {};
  final Map<String, Histogram> _histograms = {};
  int _folderGeneration = 0;

  /// Unedited render of whichever photos have had Before/After turned on,
  /// computed lazily (only when first needed) since most photos are never
  /// compared this way.
  final Map<String, Uint8List> _neutralPreviews = {};
  bool _beforeAfterMode = false;

  /// Opt-in full-native-resolution decode, computed lazily per photo —
  /// pixel math over a full sensor's worth of megapixels instead of the
  /// ~1.7M-pixel editing preview is a real cost, so this only happens when
  /// the user explicitly asks for it. Dragging a slider still uses the
  /// small "live" resolution regardless, for responsiveness.
  final Map<String, EditSource> _fullQualitySources = {};
  bool _fullQualityMode = false;

  final TransformationController _viewController = TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  double _zoomScale = 1.0;

  /// Current slider values for whichever photo is selected — either that
  /// photo's saved edits from [_edits], or defaults if it has none yet.
  Map<String, double> _paramValues = _defaultParamValues();
  Timer? _renderDebounceTimer;
  int _renderRequestId = 0;

  /// True while decoding a newly-selected photo's edit source (always
  /// shown — this is the multi-second X-Trans-full-demosaic case). True
  /// while a render is taking more than [_slowRenderThreshold] (e.g.
  /// Clarity/Dehaze at full resolution) — gated by a delay so ordinary
  /// fast slider tweaks never flash it.
  bool _isDecodingPhoto = false;
  bool _isRenderingSlow = false;
  Timer? _slowRenderTimer;
  static const _slowRenderThreshold = Duration(seconds: 3);

  /// Real progress for the loading overlay while a folder's thumbnails are
  /// being decoded — [_thumbnailsTotal] is 0 until the file list is known.
  int _thumbnailsLoaded = 0;
  int _thumbnailsTotal = 0;

  /// Saved slider values per photo (absolute path), persisted to disk.
  /// Loaded once at startup; not guarded against edits made before that
  /// finishes, since reading a small JSON file is effectively instant next
  /// to how long opening a folder via a native file dialog takes.
  Map<String, Map<String, double>> _edits = {};
  Timer? _catalogSaveTimer;

  /// Saved Tone Curve + Color Curve control points per photo, persisted
  /// separately from [_edits] since a curve is a list of points, not a
  /// single double.
  Map<String, PhotoCurves> _photoCurves = {};

  /// The curves for whichever photo is selected — either that photo's
  /// saved curves from [_photoCurves], or the identity (no-op) curves.
  /// Mirrors how [_paramValues] tracks the selected photo's slider values.
  PhotoCurves _currentCurves = identityPhotoCurves;

  /// Saved mask stacks (Linear/Radial Gradient) per photo, persisted
  /// separately since a mask is structured data, not a single double.
  Map<String, List<MaskLayer>> _photoMasks = {};

  /// The mask stack for whichever photo is selected. Mirrors
  /// [_paramValues]/[_currentCurves]'s "live copy of the saved value"
  /// pattern.
  List<MaskLayer> _currentMasks = [];

  /// Which layer the controls panel is currently editing —
  /// [imageMaskId] (the whole photo, i.e. the existing global
  /// adjustments) or one of [_currentMasks]'s ids.
  String _activeMaskId = imageMaskId;

  /// Current brush tool settings — transient, not per-mask, matching how
  /// most paint tools keep one "current brush" you dab with (each stroke
  /// bakes in whatever these were at the time, so past strokes keep their
  /// own size/hardness/erase even after these change).
  double _brushRadius = 0.05;
  double _brushHardness = 0.5;
  bool _brushErase = false;

  /// The user's saved preset library — not per-photo, applies to whatever
  /// photo is selected when the user picks one.
  List<Preset> _presets = [];

  bool _exporting = false;

  AppSettings _settings = const AppSettings();

  late final AppLifecycleListener _lifecycleListener;

  /// Main-isolate-only (path_provider isn't guaranteed safe to call from
  /// the compute() isolates thumbnail decoding runs on, and it batches
  /// writes per month file, which needs a single owner). Null until
  /// resolveThumbnailCacheDir() resolves, which just means thumbnails
  /// decoded before then skip the cache for that one lookup.
  ThumbnailCacheManager? _thumbnailCache;

  @override
  void initState() {
    super.initState();
    unawaited(_loadEdits());
    unawaited(_loadPhotoCurves());
    unawaited(_loadPhotoMasks());
    unawaited(_loadPresetsState());
    unawaited(_loadSettings());
    unawaited(_loadThumbnailCache());
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequested,
    );
  }

  Future<void> _loadThumbnailCache() async {
    final dir = await resolveThumbnailCacheDir();
    if (!mounted) {
      return;
    }
    setState(() => _thumbnailCache = ThumbnailCacheManager(dir));
  }

  /// Makes sure the current photo's edits are actually on disk before the
  /// window closes — the debounced/fire-and-forget save elsewhere in this
  /// file wouldn't necessarily finish in time for a save made in the last
  /// moment before quitting. Also flushes any thumbnail cache writes that
  /// haven't been persisted yet (best-effort — losing those just means
  /// slower thumbnails next launch, not lost data, so this isn't awaited
  /// as strictly).
  Future<AppExitResponse> _handleExitRequested() async {
    await _flushCurrentEdits();
    await _thumbnailCache?.flush();
    return AppExitResponse.exit;
  }

  Future<void> _loadEdits() async {
    final edits = await loadCatalog();
    if (!mounted) {
      return;
    }
    setState(() => _edits = edits);
  }

  Future<void> _loadPhotoCurves() async {
    final curves = await loadPhotoCurves();
    if (!mounted) {
      return;
    }
    setState(() => _photoCurves = curves);
  }

  PhotoCurves _curvesFor(String path) =>
      _photoCurves[path] ?? identityPhotoCurves;

  Future<void> _loadPhotoMasks() async {
    final masks = await loadPhotoMasks();
    if (!mounted) {
      return;
    }
    setState(() => _photoMasks = masks);
  }

  List<MaskLayer> _masksFor(String path) => _photoMasks[path] ?? const [];

  Future<void> _loadPresetsState() async {
    final presets = await loadPresets();
    if (!mounted) {
      return;
    }
    setState(() => _presets = presets);
  }

  /// Applies [preset]'s slider values and curves to the selected photo —
  /// like every other adjustment, this only touches the global ("Image")
  /// layer, never the active mask, matching how real Lightroom presets
  /// don't carry local adjustments either.
  void _applyPreset(Preset preset) {
    if (_selectedIndex == null) {
      return;
    }
    setState(() {
      _paramValues = {..._defaultParamValues(), ...preset.values};
      _currentCurves = preset.curves;
    });
    _scheduleRender(live: false);
    unawaited(_flushCurrentEdits());
    if (preset.unsupportedAttributes.isNotEmpty) {
      unawaited(_showUnsupportedPresetAttributes(preset));
    }
  }

  Future<void> _showUnsupportedPresetAttributes(Preset preset) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.surfaceRaised,
        title: Text(l10n.presetUnsupportedTitle),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.presetUnsupportedMessage(preset.name)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final attribute in preset.unsupportedAttributes)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: DarkmoonColors.panel,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            attribute,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
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
      ),
    );
  }

  /// Whether [preset] is exactly what's currently applied to the selected
  /// photo — recomputed from the live values/curves rather than tracked
  /// separately, so it naturally clears the moment the user tweaks
  /// anything after applying, and never goes stale across photo switches.
  bool _matchesAppliedPreset(Preset preset) {
    final merged = {..._defaultParamValues(), ...preset.values};
    if (!mapEquals(_paramValues, merged)) {
      return false;
    }
    return listEquals(_currentCurves.tone, preset.curves.tone) &&
        listEquals(_currentCurves.red, preset.curves.red) &&
        listEquals(_currentCurves.green, preset.curves.green) &&
        listEquals(_currentCurves.blue, preset.curves.blue);
  }

  Future<void> _saveCurrentAsPreset() async {
    if (_selectedIndex == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final name = await showTextPromptDialog(
      context,
      title: l10n.presetSaveNewTitle,
    );
    if (name == null || !mounted) {
      return;
    }
    final preset = Preset(
      id: 'preset_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      values: Map<String, double>.from(_paramValues),
      curves: _currentCurves,
    );
    setState(() => _presets = [..._presets, preset]);
    unawaited(savePresets(_presets));
  }

  Future<void> _renamePreset(Preset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showTextPromptDialog(
      context,
      title: l10n.presetRenameTitle,
      initialValue: preset.name,
    );
    if (name == null || !mounted) {
      return;
    }
    setState(() {
      _presets = [
        for (final p in _presets)
          if (p.id == preset.id) p.copyWith(name: name) else p,
      ];
    });
    unawaited(savePresets(_presets));
  }

  Future<void> _deletePreset(Preset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.surfaceRaised,
        title: Text(l10n.confirmClearTitle),
        content: Text(l10n.presetDeleteConfirmMessage(preset.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.presetDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _presets = [
        for (final p in _presets)
          if (p.id != preset.id) p,
      ];
    });
    unawaited(savePresets(_presets));
  }

  Future<void> _deletePresets(List<Preset> presets) async {
    if (presets.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.surfaceRaised,
        title: Text(l10n.confirmClearTitle),
        content: Text(l10n.presetDeleteManyConfirmMessage(presets.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.presetDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final ids = {for (final preset in presets) preset.id};
    setState(() {
      _presets = [
        for (final p in _presets)
          if (!ids.contains(p.id)) p,
      ];
    });
    unawaited(savePresets(_presets));
  }

  Future<void> _exportPreset(Preset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final destPath = await FilePicker.saveFile(
      dialogTitle: l10n.presetExportDialogTitle,
      fileName: '${preset.name}.xmp',
      type: FileType.custom,
      allowedExtensions: ['xmp'],
    );
    if (destPath == null) {
      return;
    }
    await File(destPath).writeAsString(xmpFromPreset(preset));
  }

  /// Imports one or more `.xmp` presets, or `.zip` bundles of them (how
  /// Lightroom exports multiple presets at once) — each zip is unpacked
  /// and every `.xmp` inside it imported the same way a standalone file
  /// would be.
  Future<void> _importPresets() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.presetImportDialogTitle,
      type: FileType.custom,
      allowedExtensions: ['xmp', 'zip'],
      allowMultiple: true,
    );
    if (result == null) {
      return;
    }
    final imported = <Preset>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) {
        continue;
      }
      if (path.toLowerCase().endsWith('.zip')) {
        imported.addAll(await presetsFromZip(path));
        continue;
      }
      try {
        final xmlSource = await File(path).readAsString();
        final preset = presetFromXmp(
          xmlSource,
          fallbackName: p.basenameWithoutExtension(path),
        );
        if (preset != null) {
          imported.add(preset);
        }
      } catch (_) {
        // Skip files that aren't readable/valid XMP — best effort import.
      }
    }
    if (imported.isEmpty || !mounted) {
      return;
    }
    setState(() => _presets = [..._presets, ...imported]);
    unawaited(savePresets(_presets));
  }

  Future<void> _loadSettings() async {
    final settings = await loadSettings();
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
    final lastFolder = settings.lastActiveFolder;
    if (lastFolder != null && await Directory(lastFolder).exists()) {
      unawaited(_loadFolder(lastFolder));
    }
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(
        settings: _settings,
        onChanged: (next) {
          if (next.language != _settings.language) {
            widget.onLanguageChanged(next.language);
          }
          setState(() => _settings = next);
          unawaited(saveSettings(next));
        },
        onClearThumbnails: () => unawaited(_clearThumbnailCache()),
        onClearCatalog: () => unawaited(_clearCatalogData()),
      ),
    );
  }

  /// Deletes every cached thumbnail (disk + in-memory) and re-decodes the
  /// currently-open folder's, so the effect is visible right away instead
  /// of only affecting future folder opens.
  Future<void> _clearThumbnailCache() async {
    await _thumbnailCache?.clearAll();
    if (!mounted) {
      return;
    }
    setState(() => _thumbnails.clear());
    if (_files.isNotEmpty) {
      unawaited(_loadThumbnails(_files, _folderGeneration));
    }
  }

  /// Deletes every saved per-photo edit and resets the currently-open
  /// photo (if any) back to its defaults, so the effect is visible right
  /// away instead of only affecting the next app launch.
  Future<void> _clearCatalogData() async {
    await clearCatalog();
    await clearPhotoCurves();
    await clearPhotoMasks();
    if (!mounted) {
      return;
    }
    setState(() {
      _edits = {};
      _photoCurves = {};
      _photoMasks = {};
      _paramValues = _defaultParamValues();
      _currentCurves = identityPhotoCurves;
      _currentMasks = [];
      _activeMaskId = imageMaskId;
    });
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected != null) {
      unawaited(_renderPreview(selected.path));
    }
  }

  @override
  void dispose() {
    _renderDebounceTimer?.cancel();
    _catalogSaveTimer?.cancel();
    _slowRenderTimer?.cancel();
    _viewController.dispose();
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// Merges [path]'s saved values over the defaults rather than just
  /// picking out the default-slider keys, so keys the sliders in
  /// [_sections] don't know about — Color Mixer's 24 and Color Grading's
  /// 9, both keyed straight into this same flat map — survive a reload
  /// instead of being silently dropped.
  Map<String, double> _paramValuesFor(String path) {
    final saved = _edits[path];
    if (saved == null) {
      return _defaultParamValues();
    }
    return {..._defaultParamValues(), ...saved};
  }

  /// Writes the currently-selected photo's slider values into [_edits] and
  /// saves the catalog immediately, bypassing the debounce — used when
  /// navigating away from a photo (fire-and-forget) and when the app is
  /// about to quit (awaited, so the write actually finishes before exit).
  Future<void> _flushCurrentEdits() async {
    _catalogSaveTimer?.cancel();
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    _edits[selected.path] = Map<String, double>.from(_paramValues);
    _photoCurves[selected.path] = _currentCurves;
    _photoMasks[selected.path] = _currentMasks;
    await saveCatalog(_edits);
    await savePhotoCurves(_photoCurves);
    await savePhotoMasks(_photoMasks);
  }

  void _scheduleCatalogSave() {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    _catalogSaveTimer?.cancel();
    _catalogSaveTimer = Timer(_catalogSaveDebounce, () {
      _edits[selected.path] = Map<String, double>.from(_paramValues);
      _photoCurves[selected.path] = _currentCurves;
      _photoMasks[selected.path] = _currentMasks;
      unawaited(saveCatalog(_edits));
      unawaited(savePhotoCurves(_photoCurves));
      unawaited(savePhotoMasks(_photoMasks));
    });
  }

  /// Adds a folder to the sidebar's persistent library (File > Add Folder)
  /// and loads it into the main view.
  Future<void> _openFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.dialogOpenFolderTitle,
    );
    if (folder == null) {
      return;
    }
    if (!_settings.libraryFolders.contains(folder)) {
      final next = _settings.copyWith(
        libraryFolders: [..._settings.libraryFolders, folder],
      );
      setState(() => _settings = next);
      unawaited(saveSettings(next));
    }
    await _loadFolder(folder);
  }

  /// Navigates the main view to [folder] from a sidebar click, without
  /// touching the persisted library list (unlike [_openFolder]).
  Future<void> _selectSidebarFolder(String folder) async {
    if (folder == _currentFolder) {
      return;
    }
    await _loadFolder(folder);
  }

  /// Removes [folder] from the sidebar's library and persists the change.
  /// Clears the main view if it was showing that folder (or a subfolder of
  /// it), since its files are no longer reachable from the tree.
  void _removeLibraryFolder(String folder) {
    final next = _settings.copyWith(
      libraryFolders: _settings.libraryFolders
          .where((f) => f != folder)
          .toList(),
    );
    final current = _currentFolder;
    final showingRemoved =
        current != null && (current == folder || p.isWithin(folder, current));
    setState(() {
      _settings = next;
      if (showingRemoved) {
        _files = const [];
        _selectedIndex = null;
        _currentFolder = null;
        _thumbnails.clear();
        _editSources.clear();
        _renderedPreviews.clear();
        _histograms.clear();
        _neutralPreviews.clear();
        _beforeAfterMode = false;
        _fullQualitySources.clear();
      }
    });
    unawaited(saveSettings(next));
  }

  /// Opens just the one selected file — no folder scan, so the filmstrip
  /// only shows this single photo (unlike Open Folder, or a version of
  /// this that loaded the whole containing folder with focus on the file).
  Future<void> _openFile() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.dialogOpenFileTitle,
      type: FileType.custom,
      allowedExtensions: rawExtensions.map((ext) => ext.substring(1)).toList(),
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await _loadSingleFile(path);
    final next = _settings.withRecentFile(path);
    setState(() => _settings = next);
    unawaited(saveSettings(next));
  }

  /// Loads a single recently-opened file from the sidebar (moves it back to
  /// the front of the recent list rather than duplicating the entry).
  Future<void> _selectRecentFile(String path) async {
    await _loadSingleFile(path);
    final next = _settings.withRecentFile(path);
    setState(() => _settings = next);
    unawaited(saveSettings(next));
  }

  Future<void> _loadFolder(String folder, {String? selectPath}) async {
    unawaited(_flushCurrentEdits());
    final generation = ++_folderGeneration;
    _beginLoadingFiles();
    _currentFolder = folder;
    if (_settings.lastActiveFolder != folder) {
      final next = _settings.copyWith(lastActiveFolder: folder);
      _settings = next;
      unawaited(saveSettings(next));
    }
    final files = await listRawFiles(folder);
    if (!mounted || generation != _folderGeneration) {
      return;
    }
    final index = selectPath == null
        ? 0
        : files.indexWhere((f) => f.path == selectPath);
    final selectedIndex = files.isEmpty ? null : (index < 0 ? 0 : index);
    await _applyFiles(files, selectedIndex, generation);
  }

  Future<void> _loadSingleFile(String path) async {
    unawaited(_flushCurrentEdits());
    final generation = ++_folderGeneration;
    _beginLoadingFiles();
    DateTime modified;
    try {
      modified = (await File(path).stat()).modified;
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    if (!mounted || generation != _folderGeneration) {
      return;
    }
    await _applyFiles([RawFile(path, modified)], 0, generation);
  }

  void _beginLoadingFiles() {
    setState(() {
      _loading = true;
      _thumbnails.clear();
      _editSources.clear();
      _renderedPreviews.clear();
      _histograms.clear();
      _neutralPreviews.clear();
      _beforeAfterMode = false;
      _fullQualitySources.clear();
      _fullQualityMode = _settings.alwaysFullQuality;
      _thumbnailsLoaded = 0;
      _thumbnailsTotal = 0;
    });
  }

  /// Cancels whatever's currently loading — folder scan, thumbnail batch,
  /// photo decode, or a slow render — by invalidating the generation/
  /// request tokens those operations already check, so in-flight work
  /// discards its result instead of applying it once it (eventually)
  /// resolves, and resets the overlay state immediately.
  void _cancelLoading() {
    _folderGeneration++;
    _renderRequestId++;
    _slowRenderTimer?.cancel();
    setState(() {
      _loading = false;
      _isDecodingPhoto = false;
      _isRenderingSlow = false;
      _thumbnailsLoaded = 0;
      _thumbnailsTotal = 0;
    });
  }

  /// Applies a freshly-listed folder/file set, kicks off thumbnail loading
  /// (awaited, so the loading overlay's real progress reflects it) and the
  /// selected photo's decode/render (unawaited, so it proceeds in parallel
  /// rather than waiting behind the thumbnail batch).
  Future<void> _applyFiles(
    List<RawFile> files,
    int? selectedIndex,
    int generation,
  ) async {
    _resetZoom();
    setState(() {
      _files = files;
      _selectedIndex = selectedIndex;
      _thumbnailsTotal = files.length;
      _paramValues = selectedIndex == null
          ? _defaultParamValues()
          : _paramValuesFor(files[selectedIndex].path);
      _currentCurves = selectedIndex == null
          ? identityPhotoCurves
          : _curvesFor(files[selectedIndex].path);
      _currentMasks = selectedIndex == null
          ? []
          : _masksFor(files[selectedIndex].path);
      _activeMaskId = imageMaskId;
    });
    if (selectedIndex != null) {
      unawaited(
        _loadEditSourceAndRender(files[selectedIndex].path, generation),
      );
      if (_fullQualityMode) {
        unawaited(
          _loadFullQualityAndRender(files[selectedIndex].path, generation),
        );
      }
    }
    await _loadThumbnails(files, generation);
    if (!mounted || generation != _folderGeneration) {
      return;
    }
    setState(() => _loading = false);
  }

  Future<void> _loadThumbnails(List<RawFile> files, int generation) async {
    final queue = List<RawFile>.from(files);
    final cache = _thumbnailCache;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final file = queue.removeAt(0);
        // Cache lookup/store happens here in the main isolate (see
        // ThumbnailCacheManager) — only the actual decode, on a cache
        // miss, goes to a background isolate.
        var bytes = await cache?.lookup(file.path);
        final fromCache = bytes != null;
        bytes ??= await compute(decodeRawThumbnail, file.path);
        if (!mounted || generation != _folderGeneration) {
          return;
        }
        setState(() {
          _thumbnailsLoaded++;
          if (bytes != null) {
            _thumbnails[file.path] = bytes;
          }
        });
        if (bytes != null && !fromCache) {
          unawaited(cache?.store(file.path, bytes));
        }
      }
    }

    await Future.wait(
      List.generate(_settings.thumbnailConcurrency, (_) => worker()),
    );
    unawaited(cache?.flush());
  }

  void _selectIndex(int index) {
    if (index == _selectedIndex) {
      return;
    }
    unawaited(_flushCurrentEdits());
    final path = _files[index].path;
    _resetZoom();
    setState(() {
      _selectedIndex = index;
      _paramValues = _paramValuesFor(path);
      _currentCurves = _curvesFor(path);
      _currentMasks = _masksFor(path);
      _activeMaskId = imageMaskId;
    });
    unawaited(_loadEditSourceAndRender(path, _folderGeneration));
    if (_beforeAfterMode && !_neutralPreviews.containsKey(path)) {
      unawaited(_loadNeutralPreview(path));
    }
    if (_fullQualityMode) {
      unawaited(_loadFullQualityAndRender(path, _folderGeneration));
    }
  }

  /// Decodes the full editable RAW buffer for [path] (unless already
  /// cached) and renders it with the current slider values. Guarded by
  /// [generation] so a slow decode from a folder the user has since
  /// navigated away from can't clobber state after the fact.
  Future<void> _loadEditSourceAndRender(String path, int generation) async {
    var sources = _editSources[path];
    if (sources == null) {
      setState(() => _isDecodingPhoto = true);
      sources = await compute(decodeEditSources, path);
      if (!mounted || generation != _folderGeneration) {
        return;
      }
      setState(() => _isDecodingPhoto = false);
      if (sources == null) {
        return;
      }
      setState(() => _editSources[path] = sources!);
    }
    await _renderPreview(path);
  }

  /// Renders [path]'s cached edit source with the current slider values and
  /// caches the resulting JPEG + histogram + filmstrip thumbnail. Uses the
  /// smaller "live" resolution while [live] is true (a slider is actively
  /// being dragged) for speed — even in full-quality mode, since dragging
  /// needs to stay responsive regardless.
  Future<void> _renderPreview(String path, {bool live = false}) async {
    final sources = _editSources[path];
    if (sources == null) {
      return;
    }
    final requestId = ++_renderRequestId;
    _slowRenderTimer?.cancel();
    if (_isRenderingSlow) {
      // A previous, slower render just got superseded by this one — clear
      // the flag immediately; the timer below re-sets it if this render
      // also turns out to take more than a second.
      setState(() => _isRenderingSlow = false);
    }
    _slowRenderTimer = Timer(_slowRenderThreshold, () {
      if (mounted && requestId == _renderRequestId) {
        setState(() => _isRenderingSlow = true);
      }
    });
    final fullQualitySource = _fullQualityMode
        ? _fullQualitySources[path]
        : null;
    final job = RenderJob(
      source: live ? sources.live : (fullQualitySource ?? sources.preview),
      params: RenderParams.fromValues(_paramValues, curves: _currentCurves),
      masks: _currentMasks,
    );
    final result = await compute(renderJobToJpeg, job);
    _slowRenderTimer?.cancel();
    // A newer render (from further slider moves, or a different photo) has
    // since been requested — this result is stale, drop it.
    if (!mounted || requestId != _renderRequestId) {
      return;
    }
    setState(() {
      _isRenderingSlow = false;
      _renderedPreviews[path] = result.jpegBytes;
      _histograms[path] = result.histogram;
      // Keeps the filmstrip thumbnail in sync with the current edit
      // instead of staying frozen at the camera-original preview.
      _thumbnails[path] = result.thumbnailBytes;
    });
  }

  /// Renders [path] with neutral (default) params, for the Before/After
  /// comparison — independent of whatever edits are currently applied.
  Future<void> _loadNeutralPreview(String path) async {
    final sources = _editSources[path];
    if (sources == null) {
      return;
    }
    final result = await compute(
      renderJobToJpeg,
      RenderJob(source: sources.preview, params: const RenderParams()),
    );
    if (!mounted) {
      return;
    }
    setState(() => _neutralPreviews[path] = result.jpegBytes);
  }

  void _toggleBeforeAfter() {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    setState(() => _beforeAfterMode = !_beforeAfterMode);
    if (_beforeAfterMode &&
        selected != null &&
        !_neutralPreviews.containsKey(selected.path)) {
      unawaited(_loadNeutralPreview(selected.path));
    }
  }

  /// Decodes [path] at full native resolution (unless already cached) and
  /// re-renders once it's ready, replacing the downscaled preview. Guarded
  /// by [generation] the same way as _loadEditSourceAndRender.
  Future<void> _loadFullQualityAndRender(String path, int generation) async {
    if (!_fullQualitySources.containsKey(path)) {
      setState(() => _isDecodingPhoto = true);
      final source = await compute(decodeFullQualitySource, path);
      if (!mounted || generation != _folderGeneration) {
        return;
      }
      setState(() => _isDecodingPhoto = false);
      if (source == null) {
        return;
      }
      setState(() => _fullQualitySources[path] = source);
    }
    if (_fullQualityMode) {
      await _renderPreview(path);
    }
  }

  void _toggleFullQuality() {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    setState(() => _fullQualityMode = !_fullQualityMode);
    if (selected == null) {
      return;
    }
    if (_fullQualityMode) {
      unawaited(_loadFullQualityAndRender(selected.path, _folderGeneration));
    } else {
      // Switching back to the (already-decoded, so this is fast) downscaled
      // preview.
      unawaited(_renderPreview(selected.path));
    }
  }

  void _resetZoom() {
    _viewController.value = Matrix4.identity();
    setState(() => _zoomScale = 1.0);
  }

  void _zoomBy(double factor, {Offset? anchor}) {
    final newScale = (_zoomScale * factor).clamp(_minZoom, _maxZoom);
    final effectiveFactor = newScale / _zoomScale;
    if (effectiveFactor == 1.0) {
      return;
    }
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    final center =
        anchor ?? (box != null ? box.size.center(Offset.zero) : Offset.zero);
    final matrix = Matrix4.copy(_viewController.value)
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(effectiveFactor, effectiveFactor, effectiveFactor, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    _viewController.value = matrix;
    setState(() => _zoomScale = newScale);
  }

  void _zoomIn() => _zoomBy(_zoomStep);

  void _zoomOut() => _zoomBy(1 / _zoomStep);

  /// Ctrl+scroll zooms (anchored at the cursor); plain scroll does nothing,
  /// matching the Python app's wheelEvent behavior.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    final factor = event.scrollDelta.dy < 0 ? _zoomStep : 1 / _zoomStep;
    _zoomBy(factor, anchor: event.localPosition);
  }

  void _onParamChanged(String name, double value) {
    setState(() => _paramValues[name] = value);
    _scheduleRender(live: _settings.fastPreview);
    _scheduleCatalogSave();
  }

  void _onParamChangeEnd(String name, double value) {
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onToneCurveChanged(List<CurvePoint> points) {
    setState(() => _currentCurves = _currentCurves.copyWith(tone: points));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onToneCurveChangeEnd(List<CurvePoint> points) {
    setState(() => _currentCurves = _currentCurves.copyWith(tone: points));
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  PhotoCurves _withChannelCurve(String channel, List<CurvePoint> points) {
    switch (channel) {
      case 'red':
        return _currentCurves.copyWith(red: points);
      case 'green':
        return _currentCurves.copyWith(green: points);
      case 'blue':
        return _currentCurves.copyWith(blue: points);
    }
    throw ArgumentError.value(channel, 'channel');
  }

  void _onColorCurveChanged(String channel, List<CurvePoint> points) {
    setState(() => _currentCurves = _withChannelCurve(channel, points));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onColorCurveChangeEnd(String channel, List<CurvePoint> points) {
    setState(() => _currentCurves = _withChannelCurve(channel, points));
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _resetParams() {
    setState(() {
      _paramValues = _defaultParamValues();
      _currentCurves = identityPhotoCurves;
    });
    _scheduleRender(live: false);
    unawaited(_flushCurrentEdits());
  }

  /// The slider values the panel should currently show/edit — the global
  /// ones, or (when a mask is being edited) just that mask's own.
  Map<String, double> get _activeValues {
    if (_activeMaskId == imageMaskId) {
      return _paramValues;
    }
    return _activeMask?.values ?? const {};
  }

  MaskLayer? get _activeMask =>
      _currentMasks.where((m) => m.id == _activeMaskId).firstOrNull;

  void _onActiveChanged(String name, double value) {
    if (_activeMaskId == imageMaskId) {
      _onParamChanged(name, value);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(values: {...mask.values, name: value}),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onActiveChangeEnd(String name, double value) {
    if (_activeMaskId == imageMaskId) {
      _onParamChangeEnd(name, value);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(values: {...mask.values, name: value}),
    );
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Resets whatever's currently being edited — the global adjustments +
  /// curves when on the Image layer, or just the active mask's own
  /// values when one is selected.
  void _resetActive() {
    if (_activeMaskId == imageMaskId) {
      _resetParams();
      return;
    }
    _updateActiveMask((mask) => mask.copyWith(values: const {}));
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _updateActiveMask(MaskLayer Function(MaskLayer mask) update) {
    setState(() {
      _currentMasks = [
        for (final mask in _currentMasks)
          if (mask.id == _activeMaskId) update(mask) else mask,
      ];
    });
  }

  void _selectMask(String id) {
    setState(() => _activeMaskId = id);
  }

  void _addMask(MaskType type) {
    final l10n = AppLocalizations.of(context)!;
    final countOfType = _currentMasks.where((m) => m.type == type).length + 1;
    final baseName = switch (type) {
      MaskType.linearGradient => l10n.maskLinearGradient,
      MaskType.radialGradient => l10n.maskRadialGradient,
      MaskType.brush => l10n.maskBrush,
      MaskType.colorRange => l10n.maskColorRange,
    };
    final mask = MaskLayer(
      id: 'mask_${DateTime.now().microsecondsSinceEpoch}',
      name: '$baseName $countOfType',
      type: type,
    );
    setState(() {
      _currentMasks = [..._currentMasks, mask];
      _activeMaskId = mask.id;
    });
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _toggleActiveMaskEnabled() {
    _updateActiveMask((mask) => mask.copyWith(enabled: !mask.enabled));
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _toggleActiveMaskInverted() {
    _updateActiveMask((mask) => mask.copyWith(inverted: !mask.inverted));
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _deleteActiveMask() {
    setState(() {
      _currentMasks = [
        for (final mask in _currentMasks)
          if (mask.id != _activeMaskId) mask,
      ];
      _activeMaskId = imageMaskId;
    });
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onMaskGeometryChanged(MaskLayer updated) {
    setState(() {
      _currentMasks = [
        for (final mask in _currentMasks)
          if (mask.id == updated.id) updated else mask,
      ];
    });
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onMaskGeometryChangeEnd(MaskLayer updated) {
    setState(() {
      _currentMasks = [
        for (final mask in _currentMasks)
          if (mask.id == updated.id) updated else mask,
      ];
    });
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _setBrushRadius(double value) {
    setState(() => _brushRadius = value);
  }

  void _setBrushHardness(double value) {
    setState(() => _brushHardness = value);
  }

  void _toggleBrushErase() {
    setState(() => _brushErase = !_brushErase);
  }

  /// Drops the active brush mask's last stroke — the brush equivalent of
  /// undo, since strokes are kept as vector data rather than baked into a
  /// fixed bitmap.
  void _undoLastStroke() {
    final mask = _activeMask;
    if (mask == null || mask.brush.strokes.isEmpty) {
      return;
    }
    _updateActiveMask(
      (m) => m.copyWith(
        brush: m.brush.copyWith(
          strokes: m.brush.strokes.sublist(0, m.brush.strokes.length - 1),
        ),
      ),
    );
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onColorRangeToleranceChanged(double value) {
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(tolerance: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onColorRangeToleranceChangeEnd(double value) {
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(tolerance: value)),
    );
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onColorRangeFeatherChanged(double value) {
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(feather: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onColorRangeFeatherChangeEnd(double value) {
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(feather: value)),
    );
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Samples the currently-rendered preview at normalized ([nx], [ny]) and
  /// sets it as the active Color Range mask's reference color — "what you
  /// see is what you pick", matching the eyedropper's own preview surface.
  void _onSampleMaskColor(double nx, double ny) {
    final mask = _activeMask;
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (mask == null || mask.type != MaskType.colorRange || selected == null) {
      return;
    }
    final bytes = _renderedPreviews[selected.path];
    if (bytes == null) {
      return;
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return;
    }
    final px = (nx * (decoded.width - 1)).round().clamp(0, decoded.width - 1);
    final py = (ny * (decoded.height - 1)).round().clamp(0, decoded.height - 1);
    final pixel = decoded.getPixel(px, py);
    _updateActiveMask(
      (m) => m.copyWith(
        colorRange: m.colorRange.copyWith(
          r: pixel.r.toDouble(),
          g: pixel.g.toDouble(),
          b: pixel.b.toDouble(),
        ),
      ),
    );
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _scheduleRender({required bool live}) {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    _renderDebounceTimer?.cancel();
    _renderDebounceTimer = Timer(_renderDebounce, () {
      unawaited(_renderPreview(selected.path, live: live));
    });
  }

  Future<void> _exportCurrent() async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null || _exporting) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final options = await showDialog<ExportOptions>(
      context: context,
      builder: (_) => const ExportOptionsDialog(),
    );
    if (options == null) {
      return;
    }
    final baseName = p.basenameWithoutExtension(selected.path);
    final destPath = await FilePicker.saveFile(
      dialogTitle: l10n.exportPhotoDialogTitle,
      fileName: '${baseName}_edit.${options.format.extension}',
      type: FileType.custom,
      allowedExtensions: [options.format.extension],
    );
    if (destPath == null || !mounted) {
      return;
    }

    setState(() => _exporting = true);
    final result = await compute(
      exportPhoto,
      ExportRequest(
        sourcePath: selected.path,
        destPath: destPath,
        params: RenderParams.fromValues(_paramValues, curves: _currentCurves),
        masks: _currentMasks,
        format: options.format,
        quality: options.quality,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? l10n.exportSuccessMessage(result.destPath!)
              : l10n.exportFailureMessage(result.error!),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex != null ? _files[_selectedIndex!] : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.backslash): () {
          if (selected != null) {
            _toggleBeforeAfter();
          }
        },
      },
      child: Focus(autofocus: true, child: _buildScaffold(selected)),
    );
  }

  /// What the loading overlay should show right now, if anything — checked
  /// in priority order since only one can be shown at a time.
  _LoadingInfo? _overlayInfo(BuildContext context, RawFile? selected) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return _LoadingInfo(
        message: _thumbnailsTotal > 0
            ? l10n.loadingPhotos(_thumbnailsLoaded, _thumbnailsTotal)
            : l10n.loadingFolder,
        progress: _thumbnailsTotal > 0
            ? _thumbnailsLoaded / _thumbnailsTotal
            : null,
      );
    }
    if (_isDecodingPhoto && selected != null) {
      return _LoadingInfo(message: l10n.loadingImage(selected.name));
    }
    if (_isRenderingSlow) {
      return _LoadingInfo(message: l10n.applyingAdjustments);
    }
    return null;
  }

  Widget _buildScaffold(RawFile? selected) {
    return Scaffold(
      body: Column(
        children: [
          _TopMenuBar(
            onOpenFile: _openFile,
            onOpenFolder: _openFolder,
            onOpenSettings: _openSettings,
          ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 220,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: FolderSidebar(
                                    roots: _settings.libraryFolders,
                                    recentFiles: _settings.recentFiles,
                                    selectedPath: _currentFolder,
                                    onSelect: (path) =>
                                        unawaited(_selectSidebarFolder(path)),
                                    onRemove: _removeLibraryFolder,
                                    onSelectRecentFile: (path) =>
                                        unawaited(_selectRecentFile(path)),
                                  ),
                                ),
                                Container(
                                  height: 1,
                                  color: DarkmoonColors.divider,
                                ),
                                // Same flex as the FolderSidebar above —
                                // a fixed 50/50 split of the sidebar's
                                // height rather than growing with the
                                // preset count, with its own scroll once
                                // the list outgrows its half.
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Container(
                                      color: DarkmoonColors.panel,
                                      child: PresetPanel(
                                        presets: _presets,
                                        enabled: selected != null,
                                        isApplied: _matchesAppliedPreset,
                                        onApply: _applyPreset,
                                        onSaveNew: () =>
                                            unawaited(_saveCurrentAsPreset()),
                                        onImport: () =>
                                            unawaited(_importPresets()),
                                        onRename: (preset) =>
                                            unawaited(_renamePreset(preset)),
                                        onExport: (preset) =>
                                            unawaited(_exportPreset(preset)),
                                        onDelete: (preset) =>
                                            unawaited(_deletePreset(preset)),
                                        onDeleteMany: (presets) =>
                                            unawaited(_deletePresets(presets)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _ImageArea(
                              selected: selected,
                              thumbnail: selected == null
                                  ? null
                                  : _thumbnails[selected.path],
                              preview: selected == null
                                  ? null
                                  : _renderedPreviews[selected.path],
                              neutralPreview: selected == null
                                  ? null
                                  : _neutralPreviews[selected.path],
                              beforeAfterMode: _beforeAfterMode,
                              viewController: _viewController,
                              viewportKey: _viewportKey,
                              onPointerSignal: _handlePointerSignal,
                              editingMask:
                                  (_beforeAfterMode || selected == null)
                                  ? null
                                  : _activeMask,
                              editingSource: selected == null
                                  ? null
                                  : _editSources[selected.path]?.preview,
                              onMaskGeometryChanged: _onMaskGeometryChanged,
                              onMaskGeometryChangeEnd: _onMaskGeometryChangeEnd,
                              brushRadius: _brushRadius,
                              brushHardness: _brushHardness,
                              brushErase: _brushErase,
                              onSampleColor: _onSampleMaskColor,
                            ),
                          ),
                          _ControlsPanel(
                            values: _activeValues,
                            histogram: selected == null
                                ? null
                                : _histograms[selected.path],
                            onChanged: _onActiveChanged,
                            onChangeEnd: _onActiveChangeEnd,
                            onReset: _resetActive,
                            onExport: selected == null ? null : _exportCurrent,
                            exporting: _exporting,
                            enabled: selected != null,
                            curves: _currentCurves,
                            onToneCurveChanged: _onToneCurveChanged,
                            onToneCurveChangeEnd: _onToneCurveChangeEnd,
                            onColorCurveChanged: _onColorCurveChanged,
                            onColorCurveChangeEnd: _onColorCurveChangeEnd,
                            masks: _currentMasks,
                            activeMaskId: _activeMaskId,
                            onSelectMask: _selectMask,
                            onAddMask: _addMask,
                            onToggleMaskEnabled: _toggleActiveMaskEnabled,
                            onToggleMaskInverted: _toggleActiveMaskInverted,
                            onDeleteMask: _deleteActiveMask,
                            brushRadius: _brushRadius,
                            brushHardness: _brushHardness,
                            brushErase: _brushErase,
                            onBrushRadiusChanged: _setBrushRadius,
                            onBrushHardnessChanged: _setBrushHardness,
                            onToggleBrushErase: _toggleBrushErase,
                            onUndoStroke: _undoLastStroke,
                            onColorRangeToleranceChanged:
                                _onColorRangeToleranceChanged,
                            onColorRangeToleranceChangeEnd:
                                _onColorRangeToleranceChangeEnd,
                            onColorRangeFeatherChanged:
                                _onColorRangeFeatherChanged,
                            onColorRangeFeatherChangeEnd:
                                _onColorRangeFeatherChangeEnd,
                          ),
                        ],
                      ),
                    ),
                    _ViewerToolbar(
                      zoomLabel: _zoomScale == 1.0
                          ? AppLocalizations.of(context)!.zoomFit
                          : '${(_zoomScale * 100).round()}%',
                      beforeAfterMode: _beforeAfterMode,
                      beforeAfterEnabled: selected != null,
                      onZoomIn: _zoomIn,
                      onZoomOut: _zoomOut,
                      onZoomFit: _resetZoom,
                      onToggleBeforeAfter: selected == null
                          ? null
                          : _toggleBeforeAfter,
                      fullQualityMode: _fullQualityMode,
                      onToggleFullQuality: selected == null
                          ? null
                          : _toggleFullQuality,
                    ),
                    _Filmstrip(
                      files: _files,
                      selectedIndex: _selectedIndex,
                      thumbnails: _thumbnails,
                      onSelect: _selectIndex,
                    ),
                  ],
                ),
                Builder(
                  builder: (context) {
                    final info = _overlayInfo(context, selected);
                    return info == null
                        ? const SizedBox.shrink()
                        : _LoadingOverlay(info: info, onCancel: _cancelLoading);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopMenuBar extends StatelessWidget {
  const _TopMenuBar({
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: DarkmoonColors.background,
        border: Border(bottom: BorderSide(color: DarkmoonColors.divider)),
      ),
      child: Row(
        children: [
          PopupMenuButton<VoidCallback>(
            tooltip: '',
            color: DarkmoonColors.surfaceRaised,
            offset: const Offset(0, 26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: DarkmoonColors.border),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(value: onOpenFile, child: Text(l10n.menuOpenFile)),
              PopupMenuItem(
                value: onOpenFolder,
                child: Text(l10n.menuOpenFolder),
              ),
            ],
            onSelected: (callback) => callback(),
            child: _MenuBarLabel(l10n.menuFile),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onOpenSettings,
            child: _MenuBarLabel(l10n.menuSettings),
          ),
        ],
      ),
    );
  }
}

class _MenuBarLabel extends StatelessWidget {
  const _MenuBarLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: DarkmoonColors.textSecondary,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _ImageArea extends StatelessWidget {
  const _ImageArea({
    required this.selected,
    required this.thumbnail,
    required this.preview,
    required this.neutralPreview,
    required this.beforeAfterMode,
    required this.viewController,
    required this.viewportKey,
    required this.onPointerSignal,
    required this.editingMask,
    required this.editingSource,
    required this.onMaskGeometryChanged,
    required this.onMaskGeometryChangeEnd,
    required this.brushRadius,
    required this.brushHardness,
    required this.brushErase,
    required this.onSampleColor,
  });

  final RawFile? selected;
  final Uint8List? thumbnail;
  final Uint8List? preview;
  final Uint8List? neutralPreview;
  final bool beforeAfterMode;
  final TransformationController viewController;
  final GlobalKey viewportKey;
  final void Function(PointerSignalEvent) onPointerSignal;

  /// The mask currently being edited (Linear/Radial Gradient), if any —
  /// draws its draggable handles over the image. Null outside of
  /// Before/After mode having a real mask (not the "Image" layer)
  /// selected.
  final MaskLayer? editingMask;

  /// The currently-decoded edit source backing [preview] — only its
  /// width/height are used, to work out where `BoxFit.contain` placed the
  /// image so the mask handles line up with it.
  final EditSource? editingSource;
  final ValueChanged<MaskLayer> onMaskGeometryChanged;
  final ValueChanged<MaskLayer> onMaskGeometryChangeEnd;

  /// Current brush tool settings, used when [editingMask] is a Brush mask.
  final double brushRadius;
  final double brushHardness;
  final bool brushErase;

  /// Fires with normalized image coordinates when the user taps the image
  /// while a Color Range mask is active.
  final void Function(double nx, double ny) onSampleColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: viewportKey,
      color: DarkmoonColors.canvas,
      alignment: Alignment.center,
      child: _buildContent(l10n),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (selected == null) {
      return Text(
        l10n.emptyStateOpenFolder,
        textAlign: TextAlign.center,
        style: const TextStyle(color: DarkmoonColors.textMuted),
      );
    }
    // Prefer the full RAW decode; fall back to the fast embedded thumbnail
    // while it's still decoding, so something appears immediately.
    final bytes = preview ?? thumbnail;
    if (bytes == null) {
      return Text(
        l10n.decodingPhoto(selected!.name),
        textAlign: TextAlign.center,
        style: const TextStyle(color: DarkmoonColors.textMuted),
      );
    }
    if (beforeAfterMode) {
      // Both sides share the same viewController, so Ctrl+scroll/pan stays
      // in sync between them instead of only working in the single-image
      // view.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Falls back to the edited image until the neutral render finishes.
          Expanded(
            child: _zoomableLabeledImage(
              l10n.beforeLabel,
              neutralPreview ?? bytes,
            ),
          ),
          Container(width: 1, color: DarkmoonColors.divider),
          Expanded(child: _zoomableLabeledImage(l10n.afterLabel, bytes)),
        ],
      );
    }
    return _zoomableImage(bytes);
  }

  Widget _zoomableImage(Uint8List bytes) {
    return Listener(
      onPointerSignal: onPointerSignal,
      child: InteractiveViewer(
        transformationController: viewController,
        minScale: _minZoom,
        maxScale: _maxZoom,
        // InteractiveViewer has its own built-in pinch/trackpad scale
        // gesture handling that's entirely separate from the Listener
        // above — without this it zoomed on trackpad pinch/two-finger
        // scroll regardless of Ctrl, since that gesture never goes
        // through onPointerSignal at all. Panning (drag) stays enabled.
        scaleEnabled: false,
        child: _fittedImage(bytes),
      ),
    );
  }

  Widget _zoomableLabeledImage(String label, Uint8List bytes) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _zoomableImage(bytes),
        Positioned(
          left: 8,
          top: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // SizedBox.expand forces the image into the full available box regardless
  // of the source resolution (the "live" low-res render during a slider
  // drag is a different pixel size than the full-res one), so BoxFit.contain
  // always fits against the same fixed box — without this, the displayed
  // image visibly shrank and grew back as the source resolution changed.
  Widget _fittedImage(Uint8List bytes) {
    final mask = editingMask;
    final source = editingSource;
    return SizedBox.expand(
      child: mask == null || source == null
          ? Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)
          : LayoutBuilder(
              builder: (context, constraints) {
                final containerSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                    if (mask.type == MaskType.brush)
                      BrushMaskOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        mask: mask,
                        brushRadius: brushRadius,
                        brushHardness: brushHardness,
                        brushErase: brushErase,
                        onChanged: onMaskGeometryChanged,
                        onChangeEnd: onMaskGeometryChangeEnd,
                      )
                    else if (mask.type == MaskType.colorRange)
                      ColorRangeOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        onSample: onSampleColor,
                      )
                    else
                      GradientMaskOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        mask: mask,
                        onChanged: onMaskGeometryChanged,
                        onChangeEnd: onMaskGeometryChangeEnd,
                      ),
                  ],
                );
              },
            ),
    );
  }
}

/// What the loading overlay shows: a message, an optional real progress
/// fraction (null means indeterminate — no measurable sub-steps yet).
class _LoadingInfo {
  const _LoadingInfo({required this.message, this.progress});

  final String message;
  final double? progress;
}

/// A dark scrim with a centered card, shown over the whole editor area
/// (below the menu bar) during long operations like opening a folder —
/// real progress when [info.progress] is known, an indeterminate bar
/// otherwise, plus a way to cancel out of whatever's running.
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.info, required this.onCancel});

  final _LoadingInfo info;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = info.progress;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Container(
          width: 280,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          decoration: BoxDecoration(
            color: DarkmoonColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DarkmoonColors.border),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 14),
              Text(
                info.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DarkmoonColors.textPrimary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: progress == null
                      ? const LinearProgressIndicator(
                          backgroundColor: DarkmoonColors.border,
                          valueColor: AlwaysStoppedAnimation(
                            DarkmoonColors.accent,
                          ),
                        )
                      : LinearProgressIndicator(
                          value: progress,
                          backgroundColor: DarkmoonColors.border,
                          valueColor: const AlwaysStoppedAnimation(
                            DarkmoonColors.accent,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onCancel,
                  child: Text(l10n.cancelButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewerToolbar extends StatelessWidget {
  const _ViewerToolbar({
    required this.zoomLabel,
    required this.beforeAfterMode,
    required this.beforeAfterEnabled,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomFit,
    required this.onToggleBeforeAfter,
    required this.fullQualityMode,
    required this.onToggleFullQuality,
  });

  final String zoomLabel;
  final bool beforeAfterMode;
  final bool beforeAfterEnabled;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomFit;
  final VoidCallback? onToggleBeforeAfter;
  final bool fullQualityMode;
  final VoidCallback? onToggleFullQuality;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 44,
      color: DarkmoonColors.background,
      child: Row(
        children: [
          // Reserved space matching the folder/preset sidebar's width
          // above, so the controls below line up under the image viewer
          // rather than spreading to the far edge of the window — left
          // empty for now, for future buttons.
          const SizedBox(width: 220),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Not Flexible: every segment inside is either an icon or
                  // the fixed-width zoom-percent readout, neither of which
                  // has any room to give — letting this pill shrink would
                  // only crush the percentage text unreadable, never
                  // actually save space.
                  _ToolbarPill(
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.minus,
                        onTap: onZoomOut,
                      ),
                      _ToolbarSegment(
                        label: zoomLabel,
                        width: 40,
                        padded: false,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.add,
                        onTap: onZoomIn,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_up_left_arrow_down_right,
                        onTap: onZoomFit,
                        tooltip: l10n.fitToWindow,
                      ),
                    ],
                  ),
                  const Spacer(),
                  _ToolbarPill(
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.square_split_2x1,
                        selected: beforeAfterMode,
                        onTap: onToggleBeforeAfter,
                        tooltip: l10n.beforeAfterButton,
                      ),
                      _ToolbarSegment(
                        label: l10n.fullQualityShortLabel,
                        selected: fullQualityMode,
                        onTap: onToggleFullQuality,
                        tooltip: l10n.fullQualityButton,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Reserved space matching _ControlsPanel's width above — same
          // idea as the sidebar spacer on the left.
          const SizedBox(width: 280),
        ],
      ),
    );
  }
}

/// A macOS-style segmented-control shell: a single rounded, bordered pill
/// containing [children] (usually [_ToolbarSegment]s) laid out edge to
/// edge with hairline dividers between them, rather than each control
/// being its own separately-chromed Material button.
class _ToolbarPill extends StatelessWidget {
  const _ToolbarPill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: DarkmoonColors.surfaceRaised,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: DarkmoonColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(width: 1, color: DarkmoonColors.border),
            // Each segment decides for itself whether it can afford to
            // shrink (see _ToolbarSegment) — a blanket Flexible here would
            // give every segment equal shrink priority regardless of
            // whether it actually has room to give, which is exactly what
            // crushed the zoom percentage readout down to unreadable
            // before this while "Fit to window" barely budged.
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One segment of a [_ToolbarPill] — an icon or short label, flat-filled
/// with the accent color when [selected] rather than boxed in its own
/// bordered button. Plain [GestureDetector] rather than [InkWell]: the
/// selected fill is the only feedback state this needs, and skipping
/// Material's splash keeps it feeling like a native toggle instead of an
/// Android ripple.
class _ToolbarSegment extends StatelessWidget {
  const _ToolbarSegment({
    this.icon,
    this.label,
    this.selected = false,
    this.onTap,
    this.tooltip,
    this.width,
    this.padded = true,
  });

  final IconData? icon;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;
  final String? tooltip;
  final double? width;
  // A fixed-[width] segment (e.g. the zoom-percent readout) already sizes
  // itself to fit its content exactly — adding the usual label padding on
  // top would eat into that same fixed width and leave too little room for
  // the text, so callers with a known-tight width opt out of it here.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? DarkmoonColors.background
        : (onTap == null
              ? DarkmoonColors.textMuted
              : DarkmoonColors.textSecondary);
    final content = Container(
      width: width,
      height: double.infinity,
      alignment: Alignment.center,
      padding: padded
          ? const EdgeInsets.symmetric(horizontal: 7)
          : EdgeInsets.zero,
      color: selected ? DarkmoonColors.accent : Colors.transparent,
      child: icon != null
          ? Icon(icon, size: 14, color: foreground)
          : Text(
              label!,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: 11.5, color: foreground),
            ),
    );
    final tappable = onTap == null
        ? content
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: content,
            ),
          );
    final result = tooltip == null
        ? tappable
        : Tooltip(message: tooltip!, child: tappable);
    // Only a plain (non-fixed-width) label can safely give up space —
    // icons and the zoom-percent readout have nothing left to trim
    // without becoming unreadable/clipped, so only *this* case opts into
    // shrinking (and ellipsizing) inside its [_ToolbarPill].
    return icon == null && width == null ? Flexible(child: result) : result;
  }
}

/// A clickable section header with a chevron — Lightroom-style
/// collapse/expand toggle, shared by every panel section (sliders and
/// the Tone Curve alike).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.collapsed,
    required this.onTap,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Spacing lives here, outside the InkWell, so hovering/clicking the
      // gap above and below the header box doesn't register as a tap on
      // it — only the visible rectangle itself should react.
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: DarkmoonColors.surfaceRaised,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: DarkmoonColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                Icon(
                  collapsed
                      ? CupertinoIcons.chevron_right
                      : CupertinoIcons.chevron_down,
                  size: 13,
                  color: DarkmoonColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlsPanel extends StatefulWidget {
  const _ControlsPanel({
    required this.values,
    required this.histogram,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
    required this.onExport,
    required this.exporting,
    required this.enabled,
    required this.curves,
    required this.onToneCurveChanged,
    required this.onToneCurveChangeEnd,
    required this.onColorCurveChanged,
    required this.onColorCurveChangeEnd,
    required this.masks,
    required this.activeMaskId,
    required this.onSelectMask,
    required this.onAddMask,
    required this.onToggleMaskEnabled,
    required this.onToggleMaskInverted,
    required this.onDeleteMask,
    required this.brushRadius,
    required this.brushHardness,
    required this.brushErase,
    required this.onBrushRadiusChanged,
    required this.onBrushHardnessChanged,
    required this.onToggleBrushErase,
    required this.onUndoStroke,
    required this.onColorRangeToleranceChanged,
    required this.onColorRangeToleranceChangeEnd,
    required this.onColorRangeFeatherChanged,
    required this.onColorRangeFeatherChangeEnd,
  });

  final Map<String, double> values;
  final Histogram? histogram;
  final void Function(String name, double value) onChanged;
  final void Function(String name, double value) onChangeEnd;
  final VoidCallback onReset;
  final VoidCallback? onExport;
  final bool exporting;

  /// False when no photo is loaded — every control (sliders, reset,
  /// export) is locked rather than acting on a placeholder value.
  final bool enabled;

  final PhotoCurves curves;
  final ValueChanged<List<CurvePoint>> onToneCurveChanged;
  final ValueChanged<List<CurvePoint>> onToneCurveChangeEnd;
  final void Function(String channel, List<CurvePoint> points)
  onColorCurveChanged;
  final void Function(String channel, List<CurvePoint> points)
  onColorCurveChangeEnd;

  final List<MaskLayer> masks;
  final String activeMaskId;
  final ValueChanged<String> onSelectMask;
  final ValueChanged<MaskType> onAddMask;
  final VoidCallback onToggleMaskEnabled;
  final VoidCallback onToggleMaskInverted;
  final VoidCallback onDeleteMask;

  final double brushRadius;
  final double brushHardness;
  final bool brushErase;
  final ValueChanged<double> onBrushRadiusChanged;
  final ValueChanged<double> onBrushHardnessChanged;
  final VoidCallback onToggleBrushErase;
  final VoidCallback onUndoStroke;

  final ValueChanged<double> onColorRangeToleranceChanged;
  final ValueChanged<double> onColorRangeToleranceChangeEnd;
  final ValueChanged<double> onColorRangeFeatherChanged;
  final ValueChanged<double> onColorRangeFeatherChangeEnd;

  @override
  State<_ControlsPanel> createState() => _ControlsPanelState();
}

class _ControlsPanelState extends State<_ControlsPanel> {
  /// Section names the user has collapsed, Lightroom-style — every section
  /// starts expanded, matching the panel's previous (always-open) layout.
  final Set<String> _collapsed = {};

  /// Which Color Curve channel is currently shown in the editor — only one
  /// at a time, switched via the R/G/B tabs, matching Lightroom.
  String _activeColorChannel = 'red';

  /// Which Color Mixer band is currently shown — one of the 8 capitalized
  /// channel names used in the "Mixer" + channel + "Hue/Saturation/
  /// Luminance" slider keys (e.g. `'Red'`), switched via the dot picker.
  String _activeMixerChannel = 'Red';

  /// Which Color Grading range's wheel is currently shown — one of
  /// 'Shadows', 'Midtones', 'Highlights' (the "Grade" + range +
  /// "Hue/Saturation/Luminance" slider key prefix), switched via tabs.
  String _activeGradeRange = 'Shadows';

  void _toggleSection(String section) {
    setState(() {
      if (!_collapsed.add(section)) {
        _collapsed.remove(section);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    final histogram = widget.histogram;
    final onChanged = widget.onChanged;
    final onChangeEnd = widget.onChangeEnd;
    final onReset = widget.onReset;
    final onExport = widget.onExport;
    final exporting = widget.exporting;
    final enabled = widget.enabled;
    final curves = widget.curves;
    final onToneCurveChanged = widget.onToneCurveChanged;
    final onToneCurveChangeEnd = widget.onToneCurveChangeEnd;
    final onColorCurveChanged = widget.onColorCurveChanged;
    final onColorCurveChangeEnd = widget.onColorCurveChangeEnd;
    final isMaskActive = widget.activeMaskId != imageMaskId;
    final activeMask = widget.masks
        .where((m) => m.id == widget.activeMaskId)
        .firstOrNull;
    final isBrushActive = activeMask?.type == MaskType.brush;
    final isColorRangeActive = activeMask?.type == MaskType.colorRange;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: 280,
      color: DarkmoonColors.panel,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: exporting ? null : onExport,
                          style: ElevatedButton.styleFrom(
                            side: const BorderSide(
                              color: DarkmoonColors.accent,
                              width: 1.4,
                            ),
                          ),
                          icon: exporting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  CupertinoIcons.square_arrow_down,
                                  size: 16,
                                ),
                          label: Text(
                            exporting
                                ? l10n.exportingButton
                                : l10n.exportPanelButton,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      width: 40,
                      child: IconButton(
                        onPressed: onReset,
                        tooltip: l10n.resetTooltip,
                        icon: const Icon(
                          CupertinoIcons.arrow_2_circlepath,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MaskSelector(
                  masks: widget.masks,
                  activeId: widget.activeMaskId,
                  onSelect: widget.onSelectMask,
                  onAdd: widget.onAddMask,
                  onToggleEnabled: widget.onToggleMaskEnabled,
                  onToggleInverted: widget.onToggleMaskInverted,
                  onDelete: widget.onDeleteMask,
                ),
                if (isBrushActive) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SliderRow(
                      name: l10n.maskBrushSizeLabel,
                      min: 0.01,
                      max: 0.4,
                      value: widget.brushRadius,
                      decimals: 2,
                      onChanged: widget.onBrushRadiusChanged,
                      onChangeEnd: widget.onBrushRadiusChanged,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SliderRow(
                      name: l10n.maskBrushHardnessLabel,
                      min: 0,
                      max: 1,
                      value: widget.brushHardness,
                      decimals: 2,
                      onChanged: widget.onBrushHardnessChanged,
                      onChangeEnd: widget.onBrushHardnessChanged,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.maskBrushEraseLabel,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Switch(
                        value: widget.brushErase,
                        onChanged: (_) => widget.onToggleBrushErase(),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 32,
                        width: 32,
                        child: IconButton(
                          tooltip: l10n.maskUndoStrokeTooltip,
                          onPressed: widget.onUndoStroke,
                          icon: const Icon(
                            CupertinoIcons.arrow_uturn_left,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (isColorRangeActive) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color.fromARGB(
                            255,
                            activeMask!.colorRange.r.round().clamp(0, 255),
                            activeMask.colorRange.g.round().clamp(0, 255),
                            activeMask.colorRange.b.round().clamp(0, 255),
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: DarkmoonColors.border),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.colorRangeHint,
                          style: const TextStyle(
                            color: DarkmoonColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SliderRow(
                      name: l10n.colorRangeToleranceLabel,
                      min: 0,
                      max: 100,
                      value: activeMask.colorRange.tolerance,
                      onChanged: widget.onColorRangeToleranceChanged,
                      onChangeEnd: widget.onColorRangeToleranceChangeEnd,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SliderRow(
                      name: l10n.colorRangeFeatherLabel,
                      min: 0,
                      max: 100,
                      value: activeMask.colorRange.feather,
                      onChanged: widget.onColorRangeFeatherChanged,
                      onChangeEnd: widget.onColorRangeFeatherChangeEnd,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                HistogramView(histogram: histogram),
                for (final entry in _sections.entries) ...[
                  const SizedBox(height: 10),
                  if (entry.key != _sections.keys.first) const Divider(),
                  _SectionHeader(
                    label: _sectionLabel(l10n, entry.key),
                    collapsed: _collapsed.contains(entry.key),
                    onTap: () => _toggleSection(entry.key),
                  ),
                  if (!_collapsed.contains(entry.key))
                    for (final spec in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SliderRow(
                          name: _sliderLabel(l10n, spec.name),
                          min: spec.min,
                          max: spec.max,
                          value: values[spec.name] ?? spec.defaultValue,
                          decimals: spec.decimals,
                          defaultValue: spec.defaultValue,
                          trackColors: spec.gradientColors,
                          onChanged: (v) => onChanged(spec.name, v),
                          onChangeEnd: (v) => onChangeEnd(spec.name, v),
                        ),
                      ),
                  // Tone Curve/Color Curve/Color Mixer/Color Grading are
                  // global-only for now — masks support the basic 19
                  // sliders (White Balance/Tone/Presence/Detail) only.
                  // Placed after Detail rather than interleaved with the
                  // _sections loop, so Presence/Detail stay right after
                  // Tone, ahead of the advanced color tools.
                  if (entry.key == 'DETAIL' && !isMaskActive) ...[
                    const Divider(),
                    _SectionHeader(
                      label: l10n.sectionToneCurve,
                      collapsed: _collapsed.contains('TONE CURVE'),
                      onTap: () => _toggleSection('TONE CURVE'),
                    ),
                    if (!_collapsed.contains('TONE CURVE'))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ToneCurveEditor(
                          points: curves.tone,
                          onChanged: onToneCurveChanged,
                          onChangeEnd: onToneCurveChangeEnd,
                        ),
                      ),
                    const Divider(),
                    _SectionHeader(
                      label: l10n.sectionColorCurve,
                      collapsed: _collapsed.contains('COLOR CURVE'),
                      onTap: () => _toggleSection('COLOR CURVE'),
                    ),
                    if (!_collapsed.contains('COLOR CURVE')) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: _ColorChannelTabs(
                          active: _activeColorChannel,
                          onSelect: (channel) =>
                              setState(() => _activeColorChannel = channel),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ToneCurveEditor(
                          key: ValueKey(_activeColorChannel),
                          points: _channelPoints(curves, _activeColorChannel),
                          lineColor: _channelColor(_activeColorChannel),
                          onChanged: (points) =>
                              onColorCurveChanged(_activeColorChannel, points),
                          onChangeEnd: (points) => onColorCurveChangeEnd(
                            _activeColorChannel,
                            points,
                          ),
                        ),
                      ),
                    ],
                    const Divider(),
                    _SectionHeader(
                      label: l10n.sectionColorMixer,
                      collapsed: _collapsed.contains('COLOR MIXER'),
                      onTap: () => _toggleSection('COLOR MIXER'),
                    ),
                    if (!_collapsed.contains('COLOR MIXER')) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 10),
                        child: _MixerChannelDots(
                          active: _activeMixerChannel,
                          onSelect: (channel) =>
                              setState(() => _activeMixerChannel = channel),
                        ),
                      ),
                      for (final suffix in const [
                        'Hue',
                        'Saturation',
                        'Luminance',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SliderRow(
                            name: _mixerSliderLabel(l10n, suffix),
                            min: -100,
                            max: 100,
                            value:
                                values['Mixer$_activeMixerChannel$suffix'] ?? 0,
                            defaultValue: 0,
                            trackColors: [
                              DarkmoonColors.textMuted,
                              _mixerChannelColor(_activeMixerChannel),
                            ],
                            onChanged: (v) => onChanged(
                              'Mixer$_activeMixerChannel$suffix',
                              v,
                            ),
                            onChangeEnd: (v) => onChangeEnd(
                              'Mixer$_activeMixerChannel$suffix',
                              v,
                            ),
                          ),
                        ),
                    ],
                    const Divider(),
                    _SectionHeader(
                      label: l10n.sectionColorGrading,
                      collapsed: _collapsed.contains('COLOR GRADING'),
                      onTap: () => _toggleSection('COLOR GRADING'),
                    ),
                    if (!_collapsed.contains('COLOR GRADING')) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 10),
                        child: _GradeRangeTabs(
                          active: _activeGradeRange,
                          onSelect: (range) =>
                              setState(() => _activeGradeRange = range),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Center(
                          child: SizedBox(
                            width: 160,
                            child: ColorWheel(
                              key: ValueKey(_activeGradeRange),
                              hue: values['Grade${_activeGradeRange}Hue'] ?? 0,
                              saturation:
                                  values['Grade${_activeGradeRange}Saturation'] ??
                                  0,
                              onChanged: (hue, sat) {
                                onChanged('Grade${_activeGradeRange}Hue', hue);
                                onChanged(
                                  'Grade${_activeGradeRange}Saturation',
                                  sat,
                                );
                              },
                              onChangeEnd: (hue, sat) {
                                onChangeEnd(
                                  'Grade${_activeGradeRange}Hue',
                                  hue,
                                );
                                onChangeEnd(
                                  'Grade${_activeGradeRange}Saturation',
                                  sat,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SliderRow(
                          name: l10n.mixerLuminanceLabel,
                          min: -100,
                          max: 100,
                          value:
                              values['Grade${_activeGradeRange}Luminance'] ?? 0,
                          defaultValue: 0,
                          onChanged: (v) => onChanged(
                            'Grade${_activeGradeRange}Luminance',
                            v,
                          ),
                          onChangeEnd: (v) => onChangeEnd(
                            'Grade${_activeGradeRange}Luminance',
                            v,
                          ),
                        ),
                      ),
                    ],
                    const Divider(),
                    _SectionHeader(
                      label: l10n.sectionEffects,
                      collapsed: _collapsed.contains('EFFECTS'),
                      onTap: () => _toggleSection('EFFECTS'),
                    ),
                    if (!_collapsed.contains('EFFECTS'))
                      for (final spec in _vignetteSliders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SliderRow(
                            name: _sliderLabel(l10n, spec.name),
                            min: spec.min,
                            max: spec.max,
                            value: values[spec.name] ?? spec.defaultValue,
                            decimals: spec.decimals,
                            defaultValue: spec.defaultValue,
                            onChanged: (v) => onChanged(spec.name, v),
                            onChangeEnd: (v) => onChangeEnd(spec.name, v),
                          ),
                        ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<CurvePoint> _channelPoints(PhotoCurves curves, String channel) {
  switch (channel) {
    case 'red':
      return curves.red;
    case 'green':
      return curves.green;
    case 'blue':
      return curves.blue;
  }
  throw ArgumentError.value(channel, 'channel');
}

Color _channelColor(String channel) {
  switch (channel) {
    case 'red':
      return const Color(0xFFE0483C);
    case 'green':
      return const Color(0xFF3DD16B);
    case 'blue':
      return const Color(0xFF4FA6FF);
  }
  throw ArgumentError.value(channel, 'channel');
}

/// The 8 Color Mixer bands, in hue order — matches
/// [ColorMixerValues]'s channel order.
const _mixerChannels = [
  'Red',
  'Orange',
  'Yellow',
  'Green',
  'Aqua',
  'Blue',
  'Purple',
  'Magenta',
];

Color _mixerChannelColor(String channel) {
  switch (channel) {
    case 'Red':
      return const Color(0xFFE0483C);
    case 'Orange':
      return const Color(0xFFE8873C);
    case 'Yellow':
      return const Color(0xFFE0C93C);
    case 'Green':
      return const Color(0xFF3DD16B);
    case 'Aqua':
      return const Color(0xFF3CC9D1);
    case 'Blue':
      return const Color(0xFF4FA6FF);
    case 'Purple':
      return const Color(0xFF9B6FE0);
    case 'Magenta':
      return const Color(0xFFE362D8);
  }
  throw ArgumentError.value(channel, 'channel');
}

String _mixerChannelLabel(AppLocalizations l10n, String channel) {
  switch (channel) {
    case 'Red':
      return l10n.colorChannelRed;
    case 'Orange':
      return l10n.colorChannelOrange;
    case 'Yellow':
      return l10n.colorChannelYellow;
    case 'Green':
      return l10n.colorChannelGreen;
    case 'Aqua':
      return l10n.colorChannelAqua;
    case 'Blue':
      return l10n.colorChannelBlue;
    case 'Purple':
      return l10n.colorChannelPurple;
    case 'Magenta':
      return l10n.colorChannelMagenta;
  }
  throw ArgumentError.value(channel, 'channel');
}

String _mixerSliderLabel(AppLocalizations l10n, String suffix) {
  switch (suffix) {
    case 'Hue':
      return l10n.mixerHueLabel;
    case 'Saturation':
      return l10n.mixerSaturationLabel;
    case 'Luminance':
      return l10n.mixerLuminanceLabel;
  }
  throw ArgumentError.value(suffix, 'suffix');
}

/// The Color Mixer's 8-band channel picker — small colored dots (one per
/// hue band) rather than text tabs, since 8 text labels wouldn't fit the
/// panel's width. Matches Lightroom's own dot-based channel selector.
class _MixerChannelDots extends StatelessWidget {
  const _MixerChannelDots({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final channel in _mixerChannels)
          Tooltip(
            message: _mixerChannelLabel(l10n, channel),
            child: GestureDetector(
              onTap: () => onSelect(channel),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _mixerChannelColor(channel),
                  border: Border.all(
                    color: channel == active
                        ? DarkmoonColors.textPrimary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _gradeRangeLabel(AppLocalizations l10n, String range) {
  switch (range) {
    case 'Shadows':
      return l10n.sliderShadows;
    case 'Midtones':
      return l10n.gradeRangeMidtones;
    case 'Highlights':
      return l10n.sliderHighlights;
    case 'Global':
      return l10n.gradeRangeGlobal;
  }
  throw ArgumentError.value(range, 'range');
}

/// Shadows/Midtones/Highlights tab strip for the Color Grading panel —
/// one range's wheel is edited at a time, matching Lightroom.
class _GradeRangeTabs extends StatelessWidget {
  const _GradeRangeTabs({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  static const _ranges = ['Shadows', 'Midtones', 'Highlights', 'Global'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        for (final range in _ranges)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: range == active
                    ? DarkmoonColors.accent.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onSelect(range),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: range == active
                            ? DarkmoonColors.accent
                            : DarkmoonColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _gradeRangeLabel(l10n, range),
                      style: TextStyle(
                        color: range == active
                            ? DarkmoonColors.accent
                            : DarkmoonColors.textSecondary,
                        fontSize: 11,
                        fontWeight: range == active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// R/G/B tab strip for the Color Curve panel — one channel's curve is
/// edited at a time, matching Lightroom's per-channel Point Curve tabs.
class _ColorChannelTabs extends StatelessWidget {
  const _ColorChannelTabs({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  static const _channels = ['red', 'green', 'blue'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final channel in _channels)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _ColorChannelTab(
                channel: channel,
                selected: channel == active,
                onTap: () => onSelect(channel),
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorChannelTab extends StatelessWidget {
  const _ColorChannelTab({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final String channel;
  final bool selected;
  final VoidCallback onTap;

  String _label(AppLocalizations l10n) {
    switch (channel) {
      case 'red':
        return l10n.colorChannelRed;
      case 'green':
        return l10n.colorChannelGreen;
      case 'blue':
        return l10n.colorChannelBlue;
    }
    throw ArgumentError.value(channel, 'channel');
  }

  @override
  Widget build(BuildContext context) {
    final color = _channelColor(channel);
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: selected ? color.withValues(alpha: 0.22) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? color : DarkmoonColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            _label(l10n),
            style: TextStyle(
              color: selected ? color : DarkmoonColors.textSecondary,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _Filmstrip extends StatefulWidget {
  const _Filmstrip({
    required this.files,
    required this.selectedIndex,
    required this.thumbnails,
    required this.onSelect,
  });

  final List<RawFile> files;
  final int? selectedIndex;
  final Map<String, Uint8List> thumbnails;
  final ValueChanged<int> onSelect;

  @override
  State<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<_Filmstrip> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Mouse wheels report vertical scroll delta by default, but this list
  // scrolls horizontally — without this, plain wheel scroll over the
  // filmstrip does nothing (Flutter doesn't remap the axis on its own).
  // Ctrl+scroll is reserved for image zoom, so this only acts without it.
  void _handleWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        !_scrollController.hasClients) {
      return;
    }
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final target = (_scrollController.offset + delta).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final selectedIndex = widget.selectedIndex;
    final thumbnails = widget.thumbnails;
    final onSelect = widget.onSelect;
    if (files.isEmpty) {
      return Container(
        height: 114,
        color: DarkmoonColors.filmstrip,
        alignment: Alignment.center,
        child: Text(
          AppLocalizations.of(context)!.noFolderOpen,
          style: const TextStyle(color: DarkmoonColors.textMuted, fontSize: 11),
        ),
      );
    }
    return Container(
      height: 114,
      color: DarkmoonColors.filmstrip,
      child: Listener(
        onPointerSignal: _handleWheel,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final isSelected = index == selectedIndex;
              final thumbnail = thumbnails[file.path];
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onSelect(index),
                  child: Container(
                    width: 104,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? DarkmoonColors.accent.withValues(alpha: 0.28)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: double.infinity,
                              color: const Color(0xFF26262A),
                              alignment: Alignment.center,
                              child: thumbnail == null
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: DarkmoonColors.textMuted,
                                      ),
                                    )
                                  : Image.memory(thumbnail, fit: BoxFit.cover),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: DarkmoonColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
