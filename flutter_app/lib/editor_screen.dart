import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'catalog/catalog_store.dart';
import 'catalog/thumbnail_cache.dart';
import 'catalog/thumbnail_cache_dir.dart';
import 'export/export_job.dart';
import 'l10n/app_localizations.dart';
import 'native/edit_source.dart';
import 'native/thumbnail_loader.dart';
import 'raw_files.dart';
import 'render/histogram.dart';
import 'render/render_job.dart';
import 'render/render_params.dart';
import 'settings/app_settings.dart';
import 'theme.dart';
import 'widgets/export_dialog.dart';
import 'widgets/histogram_view.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/slider_row.dart';

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
    this.decimals = 2,
  });

  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final int decimals;
}

const _sections = <String, List<_SliderSpec>>{
  'WHITE BALANCE': [
    _SliderSpec('Temperature', 2000, 50000, 5500, decimals: 0),
    _SliderSpec('Tint', -100, 100, 0),
  ],
  'TONE': [
    _SliderSpec('Exposure', -100, 100, 0),
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
    _SliderSpec('Vibrance', -100, 100, 0),
    _SliderSpec('Saturation', -100, 100, 0),
  ],
};

Map<String, double> _defaultParamValues() {
  return {
    for (final specs in _sections.values)
      for (final spec in specs) spec.name: spec.defaultValue,
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

  /// Saved slider values per photo (absolute path), persisted to disk.
  /// Loaded once at startup; not guarded against edits made before that
  /// finishes, since reading a small JSON file is effectively instant next
  /// to how long opening a folder via a native file dialog takes.
  Map<String, Map<String, double>> _edits = {};
  Timer? _catalogSaveTimer;

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

  Future<void> _loadSettings() async {
    final settings = await loadSettings();
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
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
      ),
    );
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

  Map<String, double> _paramValuesFor(String path) {
    final saved = _edits[path];
    if (saved == null) {
      return _defaultParamValues();
    }
    final defaults = _defaultParamValues();
    return {for (final key in defaults.keys) key: saved[key] ?? defaults[key]!};
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
    await saveCatalog(_edits);
  }

  void _scheduleCatalogSave() {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    _catalogSaveTimer?.cancel();
    _catalogSaveTimer = Timer(_catalogSaveDebounce, () {
      _edits[selected.path] = Map<String, double>.from(_paramValues);
      unawaited(saveCatalog(_edits));
    });
  }

  Future<void> _openFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.dialogOpenFolderTitle,
    );
    if (folder == null) {
      return;
    }
    await _loadFolder(folder);
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
  }

  Future<void> _loadFolder(String folder, {String? selectPath}) async {
    unawaited(_flushCurrentEdits());
    final generation = ++_folderGeneration;
    _beginLoadingFiles();
    final files = await listRawFiles(folder);
    if (!mounted || generation != _folderGeneration) {
      return;
    }
    final index = selectPath == null
        ? 0
        : files.indexWhere((f) => f.path == selectPath);
    final selectedIndex = files.isEmpty ? null : (index < 0 ? 0 : index);
    _applyFiles(files, selectedIndex, generation);
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
    _applyFiles([RawFile(path, modified)], 0, generation);
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
    });
  }

  void _applyFiles(List<RawFile> files, int? selectedIndex, int generation) {
    _resetZoom();
    setState(() {
      _files = files;
      _selectedIndex = selectedIndex;
      _loading = false;
      _paramValues = selectedIndex == null
          ? _defaultParamValues()
          : _paramValuesFor(files[selectedIndex].path);
    });
    unawaited(_loadThumbnails(files, generation));
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
        if (bytes != null) {
          setState(() => _thumbnails[file.path] = bytes!);
          if (!fromCache) {
            unawaited(cache?.store(file.path, bytes));
          }
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
      params: RenderParams.fromValues(_paramValues),
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

  void _resetParams() {
    setState(() => _paramValues = _defaultParamValues());
    _scheduleRender(live: false);
    unawaited(_flushCurrentEdits());
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
        params: RenderParams.fromValues(_paramValues),
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

  /// Which loading overlay message to show right now, if any — checked in
  /// priority order since only one can be shown at a time.
  String? _overlayMessage(BuildContext context, RawFile? selected) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return l10n.loadingFolder;
    }
    if (_isDecodingPhoto && selected != null) {
      return l10n.loadingImage(selected.name);
    }
    if (_isRenderingSlow) {
      return l10n.applyingAdjustments;
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
                              zoomScale: _zoomScale,
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
                              onPointerSignal: _handlePointerSignal,
                            ),
                          ),
                          _ControlsPanel(
                            values: _paramValues,
                            histogram: selected == null
                                ? null
                                : _histograms[selected.path],
                            onChanged: _onParamChanged,
                            onChangeEnd: _onParamChangeEnd,
                            onReset: _resetParams,
                            onExport: selected == null ? null : _exportCurrent,
                            exporting: _exporting,
                          ),
                        ],
                      ),
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
                    final message = _overlayMessage(context, selected);
                    return message == null
                        ? const SizedBox.shrink()
                        : _LoadingOverlay(message: message);
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
    required this.zoomScale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomFit,
    required this.onToggleBeforeAfter,
    required this.fullQualityMode,
    required this.onToggleFullQuality,
    required this.onPointerSignal,
  });

  final RawFile? selected;
  final Uint8List? thumbnail;
  final Uint8List? preview;
  final Uint8List? neutralPreview;
  final bool beforeAfterMode;
  final TransformationController viewController;
  final GlobalKey viewportKey;
  final double zoomScale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomFit;
  final VoidCallback? onToggleBeforeAfter;
  final bool fullQualityMode;
  final VoidCallback? onToggleFullQuality;
  final void Function(PointerSignalEvent) onPointerSignal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Expanded(
          child: Container(
            key: viewportKey,
            color: DarkmoonColors.canvas,
            alignment: Alignment.center,
            child: _buildContent(l10n),
          ),
        ),
        _ViewerToolbar(
          zoomLabel: zoomScale == 1.0
              ? l10n.zoomFit
              : '${(zoomScale * 100).round()}%',
          beforeAfterMode: beforeAfterMode,
          beforeAfterEnabled: onToggleBeforeAfter != null,
          onZoomIn: onZoomIn,
          onZoomOut: onZoomOut,
          onZoomFit: onZoomFit,
          onToggleBeforeAfter: onToggleBeforeAfter,
          fullQualityMode: fullQualityMode,
          onToggleFullQuality: onToggleFullQuality,
        ),
      ],
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
    return SizedBox.expand(
      child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }
}

/// A dark scrim with a thin indeterminate progress bar and message, shown
/// over the whole editor area (below the menu bar) during long operations
/// like opening a folder.
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 220,
              height: 2,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
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

  static final _compactButtonStyle = ElevatedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    textStyle: const TextStyle(fontSize: 12),
    minimumSize: Size.zero,
  );

  static final _compactIconButtonStyle = IconButton.styleFrom(
    padding: EdgeInsets.zero,
    minimumSize: const Size(26, 26),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: DarkmoonColors.background,
      child: Row(
        children: [
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove, size: 14),
            style: _compactIconButtonStyle,
          ),
          SizedBox(
            width: 30,
            child: Text(
              zoomLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DarkmoonColors.textSecondary,
                fontSize: 11.5,
              ),
            ),
          ),
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add, size: 14),
            style: _compactIconButtonStyle,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: ElevatedButton(
              onPressed: onZoomFit,
              style: _compactButtonStyle,
              child: Text(
                l10n.fitToWindow,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
          const Spacer(),
          Tooltip(
            message: l10n.fullQualityButton,
            child: IconButton(
              onPressed: onToggleFullQuality,
              style: fullQualityMode
                  ? _compactIconButtonStyle.copyWith(
                      backgroundColor: const WidgetStatePropertyAll(
                        DarkmoonColors.accent,
                      ),
                    )
                  : _compactIconButtonStyle,
              icon: const Icon(Icons.hd_outlined, size: 16),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: ElevatedButton(
              onPressed: onToggleBeforeAfter,
              style: beforeAfterMode
                  ? _compactButtonStyle.copyWith(
                      backgroundColor: const WidgetStatePropertyAll(
                        DarkmoonColors.accent,
                      ),
                    )
                  : _compactButtonStyle,
              child: Text(
                l10n.beforeAfterButton,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({
    required this.values,
    required this.histogram,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
    required this.onExport,
    required this.exporting,
  });

  final Map<String, double> values;
  final Histogram? histogram;
  final void Function(String name, double value) onChanged;
  final void Function(String name, double value) onChangeEnd;
  final VoidCallback onReset;
  final VoidCallback? onExport;
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: 280,
      color: DarkmoonColors.panel,
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
                      icon: exporting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download_outlined, size: 16),
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
                    icon: const Icon(Icons.refresh, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            HistogramView(histogram: histogram),
            for (final entry in _sections.entries) ...[
              const SizedBox(height: 10),
              if (entry.key != _sections.keys.first) const Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 2),
                child: Text(
                  _sectionLabel(l10n, entry.key),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              for (final spec in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SliderRow(
                    name: _sliderLabel(l10n, spec.name),
                    min: spec.min,
                    max: spec.max,
                    value: values[spec.name] ?? spec.defaultValue,
                    decimals: spec.decimals,
                    onChanged: (v) => onChanged(spec.name, v),
                    onChangeEnd: (v) => onChangeEnd(spec.name, v),
                  ),
                ),
            ],
          ],
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
                                ? const Icon(
                                    Icons.image_outlined,
                                    color: DarkmoonColors.textMuted,
                                    size: 22,
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
    );
  }
}
