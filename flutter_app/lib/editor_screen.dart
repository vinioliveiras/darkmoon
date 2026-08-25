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
import 'catalog/preview_cache_dir.dart';
import 'catalog/thumbnail_cache.dart';
import 'catalog/thumbnail_cache_dir.dart';
import 'export/export_job.dart';
import 'l10n/app_localizations.dart';
import 'native/common_image_thumbnail.dart';
import 'native/edit_source.dart';
import 'native/libraw.dart' show RawMetadata, extractRawMetadata;
import 'native/thumbnail_loader.dart';
import 'presets/preset.dart';
import 'presets/preset_store.dart';
import 'presets/preset_xmp.dart';
import 'presets/preset_zip.dart';
import 'raw_files.dart';
import 'render/ai_denoise.dart';
import 'render/histogram.dart';
import 'render/mask.dart';
import 'render/gpu/gpu_capability.dart';
import 'render/gpu/render_job_gpu.dart';
import 'render/render.dart' show RenderStage;
import 'render/render_job.dart';
import 'render/crop_transform.dart';
import 'render/render_params.dart';
import 'render/tone_curve.dart';
import 'settings/app_settings.dart';
import 'theme.dart';
import 'widgets/about_dialog.dart';
import 'widgets/ai_denoise_dialog.dart';
import 'widgets/brush_mask_overlay.dart';
import 'widgets/color_range_overlay.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/color_wheel.dart';
import 'widgets/export_dialog.dart';
import 'widgets/folder_sidebar.dart';
import 'widgets/gradient_mask_overlay.dart';
import 'widgets/histogram_view.dart';
import 'widgets/mask_selector.dart';
import 'widgets/photo_metadata_view.dart';
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
    case 'SharpenAmount':
      return l10n.sliderSharpenAmount;
    case 'SharpenRadius':
      return l10n.sliderSharpenRadius;
    case 'SharpenDetail':
      return l10n.sliderSharpenDetail;
    case 'SharpenMasking':
      return l10n.sliderSharpenMasking;
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

/// How many files (starting right after the selected one) eagerly preload
/// (from cache, or a real RAW decode on a miss) when a folder opens — see
/// `_preloadPreviewCache`.
const _previewPreloadCount = 8;

/// How many of those preload slots run concurrently — each one that
/// misses the cache spawns its own RAW-decode Isolate, so this is a
/// tradeoff between finishing the batch quickly and not competing too
/// hard with the rest of startup (settings/catalog/thumbnail loads) for
/// CPU cores.
const _previewPreloadConcurrency = 3;

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
    this.valueSuffix = '',
  });

  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final int decimals;

  /// Track gradient for color-affecting controls, Lightroom-style — null
  /// for everything else, which keeps the plain theme track.
  final List<Color>? gradientColors;

  /// Appended to the displayed value — e.g. 'K' for Temperature.
  final String valueSuffix;
}

/// Storage key for a [_sections] category's on/off toggle — stored as a
/// synthetic entry inside the same flat `_paramValues` map every other
/// per-photo slider value already lives in (0 = disabled, absent/anything
/// else = enabled), so it rides along for free with catalog persistence,
/// undo/redo history, and photo switching without any separate storage.
String _categoryEnabledKey(String category) => '_categoryEnabled_$category';

/// Color Mixer/Color Grading channel and range names, and the shared
/// Hue/Saturation/Luminance suffix set both use — kept alongside
/// [_categoryEnabledKey] so [_withCategoriesApplied] can enumerate every
/// `Mixer{channel}{suffix}`/`Grade{range}{suffix}` key it needs to reset
/// without duplicating the widget-side lists ([_mixerChannels],
/// [_GradeRangeTabs._ranges]) that drive their pickers.
const _hslSuffixes = ['Hue', 'Saturation', 'Luminance'];
const _gradeRanges = ['Shadows', 'Midtones', 'Highlights', 'Global'];

/// Neutralizes every disabled category's contribution to [values] (a flat
/// `{paramName: value}` map — either the global layer's `_paramValues` or
/// one mask's own [MaskLayer.values]), swapping each disabled category's
/// slider-backed keys for their defaults. Curve-based categories (Tone
/// Curve/Color Curve) aren't handled here since they don't live in this
/// map — see [_withCurveCategoriesApplied]. Used wherever the render
/// pipeline reads param values, so a disabled category renders as if its
/// sliders were never touched, while the underlying stored values stay
/// untouched underneath (re-enabling restores them exactly).
Map<String, double> _withCategoriesApplied(Map<String, double> values) {
  bool disabled(String category) =>
      (values[_categoryEnabledKey(category)] ?? 1) == 0;
  final overrides = <String, double>{};
  for (final entry in _sections.entries) {
    if (disabled(entry.key)) {
      for (final spec in entry.value) {
        overrides[spec.name] = spec.defaultValue;
      }
    }
  }
  if (disabled('EFFECTS')) {
    for (final spec in _vignetteSliders) {
      overrides[spec.name] = spec.defaultValue;
    }
  }
  if (disabled('COLOR MIXER')) {
    for (final channel in _mixerChannels) {
      for (final suffix in _hslSuffixes) {
        overrides['Mixer$channel$suffix'] = 0.0;
      }
    }
  }
  if (disabled('COLOR GRADING')) {
    for (final range in _gradeRanges) {
      for (final suffix in _hslSuffixes) {
        overrides['Grade$range$suffix'] = 0.0;
      }
    }
  }
  return overrides.isEmpty ? values : {...values, ...overrides};
}

/// The curve-category counterpart to [_withCategoriesApplied] — Tone
/// Curve/Color Curve live in a [PhotoCurves], not the flat values map, so
/// disabling them means resetting curve fields to identity rather than
/// overriding map entries. [values] is whichever map ([MaskLayer.values]
/// for a mask's own curves, or the global `_paramValues` for
/// `_currentCurves`) carries that curve category's toggle flags.
PhotoCurves _withCurveCategoriesApplied(
  PhotoCurves curves,
  Map<String, double> values,
) {
  var result = curves;
  if ((values[_categoryEnabledKey('TONE CURVE')] ?? 1) == 0) {
    result = result.copyWith(tone: identityToneCurve);
  }
  if ((values[_categoryEnabledKey('COLOR CURVE')] ?? 1) == 0) {
    result = result.copyWith(
      red: identityToneCurve,
      green: identityToneCurve,
      blue: identityToneCurve,
    );
  }
  return result;
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
      valueSuffix: 'K',
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
    // 40 (not 0) matches Lightroom's own default RAW-import sharpening —
    // and this section's other three sliders (Radius 1.0, Detail 25) were
    // already set to Lightroom's defaults, so Amount=0 was leaving the
    // group inconsistently "half off". A zero-edit photo now gets a small
    // baseline sharpen instead of the flat, unsharpened look competitors
    // like RapidRAW/Vitrine also avoid by baking in a similar default.
    _SliderSpec('SharpenAmount', 0, 150, 40),
    _SliderSpec('SharpenRadius', 0.5, 3.0, 1.0, decimals: 1),
    _SliderSpec('SharpenDetail', 0, 100, 25),
    _SliderSpec('SharpenMasking', 0, 100, 0),
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

/// One point in a photo's edit history — everything Undo/Redo restores.
/// Deliberately excludes [_EditorScreenState._activeMaskId] (which layer
/// the panel is showing) and transient UI state like brush size/hardness:
/// those are "what you're looking at", not "what's been done to the
/// photo", so undoing an edit shouldn't also yank the panel to a different
/// mask than the one the user was just looking at.
class _EditSnapshot {
  const _EditSnapshot({
    required this.paramValues,
    required this.curves,
    required this.masks,
  });

  final Map<String, double> paramValues;
  final PhotoCurves curves;
  final List<MaskLayer> masks;
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

  /// True while the user has dismissed the loading overlay via "Hide" but
  /// the underlying operation is still running — the app stays usable
  /// (browsing the filmstrip, opening another photo) while it finishes in
  /// the background. Reset to false whenever a new loading state starts,
  /// so the next long operation shows its overlay again rather than
  /// staying permanently hidden from one dismissal.
  bool _loadingOverlayHidden = false;

  /// Whichever folder is actually loaded into [_files] right now — may be
  /// one of [AppSettings.libraryFolders] or one of its subfolders. Used to
  /// highlight the active folder in the sidebar.
  String? _currentFolder;
  final Map<String, Uint8List> _thumbnails = {};
  final Map<String, EditSourcePair> _editSources = {};
  final Map<String, Uint8List> _renderedPreviews = {};
  final Map<String, Histogram> _histograms = {};

  /// Camera/lens/exposure info per photo (absolute path), shown below the
  /// histogram — loaded lazily on selection (cheap: no unpack/demosaic
  /// needed, see [extractRawMetadata]) rather than eagerly for the whole
  /// folder, since it's supplementary info only the selected photo needs.
  final Map<String, RawMetadata?> _metadata = {};
  int _folderGeneration = 0;

  /// Unedited render of whichever photos have had Before/After turned on,
  /// computed lazily (only when first needed) since most photos are never
  /// compared this way.
  final Map<String, Uint8List> _neutralPreviews = {};
  bool _beforeAfterMode = false;

  /// Whether the Crop Overlay's draggable rectangle is shown over the
  /// image — a session-wide UI mode (like Lightroom's crop tool toggle),
  /// not per-photo state.
  bool _cropOverlayActive = false;

  /// Locked aspect ratio for the crop rectangle's drag handles, null for
  /// unconstrained ("Free") — a session-wide UI preference.
  double? _cropAspectRatio;

  final TransformationController _viewController = TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  double _zoomScale = 1.0;

  /// Current slider values for whichever photo is selected — either that
  /// photo's saved edits from [_edits], or defaults if it has none yet.
  Map<String, double> _paramValues = _defaultParamValues();
  Timer? _renderDebounceTimer;
  int _renderRequestId = 0;

  /// True while `_renderPreview`'s render call (GPU or CPU) is actually
  /// running — as opposed to `_renderDebounceTimer`, which just delays
  /// *starting* one. See `_renderPreview`'s own doc comment for why this
  /// guard exists: without it, rapid slider drags could pile up several
  /// overlapping full-pipeline renders, each already in flight past the
  /// debounce.
  bool _renderInFlight = false;

  /// The most recent render request that arrived while [_renderInFlight]
  /// was already true — run once that render finishes, replacing (not
  /// queuing behind) any earlier pending request, since only the latest
  /// slider state is worth ever actually rendering.
  ({String path, bool live, void Function(RenderStage stage)? onStage})?
  _pendingRenderRequest;

  /// Every caller currently `await`ing a coalesced-away `_renderPreview`
  /// call (see that method's doc comment) — all resolved together once
  /// [_pendingRenderRequest]'s eventual run finishes, since by then only
  /// the latest request's params were ever going to render anyway. Needed
  /// so `await _renderPreview(...)` call sites (initial photo load, the AI
  /// Denoise apply action's progress overlay) still see their render
  /// actually complete instead of returning the instant they got coalesced.
  final List<Completer<void>> _pendingRenderWaiters = [];

  /// True while decoding a newly-selected photo's edit source (always
  /// shown — this is the multi-second X-Trans-full-demosaic case). True
  /// while a render is taking more than [_slowRenderThreshold] (e.g.
  /// Clarity/Dehaze at full resolution) — gated by a delay so ordinary
  /// fast slider tweaks never flash it.
  bool _isDecodingPhoto = false;
  bool _isRenderingSlow = false;
  Timer? _slowRenderTimer;
  static const _slowRenderThreshold = Duration(seconds: 3);

  /// Which stage the in-progress AI Denoise render is on — see
  /// [RenderStage]. Only populated for that one render (see
  /// [_renderPreview]'s `onStage`), not routine slider-drag renders.
  RenderStage? _aiDenoiseRenderStage;

  /// True while the one-shot AI Denoise pass (picked from its toolbar
  /// dialog) is being computed and rendered — shown as its own loading
  /// overlay message rather than the generic "applying adjustments" one,
  /// since it's a deliberate action the user just confirmed rather than an
  /// incidental slow render.
  bool _isApplyingAiDenoise = false;

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

  /// Whether the active mask's on-canvas overlay (shaded coverage area,
  /// handles, brush cursor) is drawn — a session-wide UI preference, not
  /// per-photo state, so it isn't persisted with the catalog.
  bool _maskOverlayVisible = true;

  /// True for the duration of a slider drag on one of the active mask's
  /// own values (Tone/Presence/etc., opacity, Color Range tolerance/
  /// feather) — while true, the mask overlay is hidden regardless of
  /// [_maskOverlayVisible] so the shading doesn't hide the very change
  /// the user is dragging the slider to see. Doesn't apply to
  /// dragging the overlay itself (gradient handles, brush strokes),
  /// where hiding it would be counterproductive.
  bool _isAdjustingMaskValue = false;

  /// How opaque that overlay's shading is (0..1), one independent value per
  /// mask type — same session-wide preference scope as
  /// [_maskOverlayVisible]. Each type's own default matches what actually
  /// reads well for its shape: Brush's dabs already show the paint quite
  /// clearly even at 1%, while the gradient/color-range shading needs more
  /// to be visible at all.
  final Map<MaskType, double> _maskOverlayOpacity = {
    MaskType.linearGradient: 0.15,
    MaskType.radialGradient: 0.15,
    MaskType.brush: 0.01,
    MaskType.colorRange: 0.20,
  };

  /// How strongly the next-applied preset blends in, 0..150 — a
  /// session-wide UI preference (not persisted), set via the fixed slider
  /// under the preset list.
  double _presetAmount = 100;

  /// Edit-history stack for the currently selected photo — [_historyIndex]
  /// points at the snapshot matching the live [_paramValues]/
  /// [_currentCurves]/[_currentMasks] right now. Reset to a single
  /// baseline snapshot whenever the selected photo changes (undo/redo is
  /// scoped per photo, not across the whole session), and truncated past
  /// [_historyIndex] whenever a new edit is committed after having undone
  /// — the usual "undoing then editing discards the old redo branch" rule.
  final List<_EditSnapshot> _history = [];
  int _historyIndex = -1;

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

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

  /// ID of the preset currently applied to the selected photo (if any).
  /// Tracked separately from live values so the preset stays "active"
  /// even after the user changes _presetAmount; it only clears when
  /// the user makes a manual edit or switches photos.
  String? _appliedPresetId;

  bool _exporting = false;

  /// Which stage the in-progress export is on, so the loading overlay can
  /// show real (if stage-granular, not percentage-granular) progress
  /// instead of an indeterminate spinner for the whole export.
  ExportStage? _exportStage;

  AppSettings _settings = const AppSettings();

  late final AppLifecycleListener _lifecycleListener;

  /// Main-isolate-only (path_provider isn't guaranteed safe to call from
  /// the compute() isolates thumbnail decoding runs on, and it batches
  /// writes per month file, which needs a single owner). Null until
  /// resolveThumbnailCacheDir() resolves, which just means thumbnails
  /// decoded before then skip the cache for that one lookup.
  ThumbnailCacheManager? _thumbnailCache;

  /// Same on-disk format as [_thumbnailCache] (see thumbnail_cache.dart),
  /// pointed at a resolution-namespaced directory instead — caches
  /// [EditSourcePair.preview] itself (as a JPEG), not just a small grid
  /// thumbnail, so reselecting an already-opened photo can skip the RAW
  /// decode entirely. Re-pointed (a fresh instance, new directory) whenever
  /// Settings > Preview Resolution changes, so a stale-resolution cache is
  /// never returned — see `_openSettings`'s `previewResolutionChanged`
  /// branch. Null until [_loadPreviewCache] resolves, same reasoning as
  /// [_thumbnailCache] being nullable.
  ThumbnailCacheManager? _previewCache;

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

  Future<void> _loadPreviewCache() async {
    final dir = await resolvePreviewCacheDir(_settings.previewResolution);
    if (!mounted) {
      return;
    }
    setState(() => _previewCache = ThumbnailCacheManager(dir));
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
    await _previewCache?.flush();
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
  /// don't carry local adjustments either. Blended in at [_presetAmount]
  /// (Lightroom-style, 0-150%, set via the fixed slider under the preset
  /// list) rather than always committing to the preset's full values.
  void _applyPreset(Preset preset) {
    if (_selectedIndex == null) {
      return;
    }
    final fraction = _presetAmount / 100.0;
    final baseValues = _paramValues;
    final targetValues = {..._defaultParamValues(), ...preset.values};
    final blendedValues = {
      for (final key in {...baseValues.keys, ...targetValues.keys})
        key:
            (baseValues[key] ?? 0) +
            ((targetValues[key] ?? 0) - (baseValues[key] ?? 0)) * fraction,
    };
    setState(() {
      _paramValues = blendedValues;
      _currentCurves = lerpPhotoCurves(_currentCurves, preset.curves, fraction);
      _appliedPresetId = preset.id;
    });
    _pushHistory();
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

  /// Whether [preset] is the one currently applied to the selected photo.
  /// Tracked via [_appliedPresetId] which is set on apply and cleared on
  /// any manual edit, photo switch, reset, or file reload — so the preset
  /// stays highlighted even when the user changes _presetAmount, and only
  /// clears when they make a deliberate change.
  bool _matchesAppliedPreset(Preset preset) {
    return _appliedPresetId == preset.id;
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
    if (settings.useGpuRender) {
      // Only worth probing if the user has actually opted in — the probe
      // does real GPU work (shader compile + draw + readback), no reason
      // to pay that cost for every launch when the setting is off anyway.
      unawaited(isGpuRenderAvailable());
    }
    // Loaded here (after the real settings resolve, not in parallel from
    // initState) so it's pointed at the right resolution-namespaced
    // directory from the start, rather than the default's briefly.
    unawaited(_loadPreviewCache());
    final lastFolder = settings.lastActiveFolder;
    if (lastFolder != null && await Directory(lastFolder).exists()) {
      unawaited(_loadFolder(lastFolder, selectPath: settings.lastActiveFile));
    }
  }

  /// Persists [path] as the photo to reopen on next launch (see
  /// `_loadSettings`'s use of `AppSettings.lastActiveFile`) — called
  /// whenever the selected photo changes, mirroring how `_loadFolder`
  /// persists `lastActiveFolder`.
  Future<void> _saveLastActiveFile(String path) async {
    if (_settings.lastActiveFile == path) {
      return;
    }
    final next = _settings.copyWith(lastActiveFile: path);
    _settings = next;
    unawaited(saveSettings(next));
  }

  /// Mirrors the Settings dialog's "RAW files only" toggle, exposed
  /// directly in the folder browser too since it changes what that
  /// browser shows — re-scans the open folder immediately so the effect
  /// is visible right away rather than waiting for the next folder switch.
  void _setRawOnly(bool value) {
    final next = _settings.copyWith(rawOnly: value);
    setState(() => _settings = next);
    unawaited(saveSettings(next));
    final folder = _currentFolder;
    if (folder != null) {
      final selectedIndex = _selectedIndex;
      final selectPath = selectedIndex == null
          ? null
          : _files[selectedIndex].path;
      unawaited(_loadFolder(folder, selectPath: selectPath));
    }
  }

  void _openAbout() {
    showDialog<void>(
      context: context,
      builder: (_) => const DarkmoonAboutDialog(),
    );
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
          // Every cached EditSourcePair was decoded at the old preview
          // resolution — drop them so each photo picks up the new setting
          // next time it's selected, and redecode the one on screen right
          // now so the change is visible immediately instead of only on
          // the next photo switch.
          final previewResolutionChanged =
              next.previewResolution != _settings.previewResolution;
          setState(() {
            _settings = next;
            if (previewResolutionChanged) {
              _editSources.clear();
            }
          });
          unawaited(saveSettings(next));
          if (previewResolutionChanged) {
            unawaited(_loadPreviewCache());
            final selected = _selectedIndex == null
                ? null
                : _files[_selectedIndex!];
            if (selected != null) {
              unawaited(
                _loadEditSourceAndRender(selected.path, _folderGeneration),
              );
            }
          }
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
      _appliedPresetId = null;
    });
    _resetHistory();
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
        _metadata.clear();
        _neutralPreviews.clear();
        _beforeAfterMode = false;
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
    final files = await listRawFiles(folder, rawOnly: _settings.rawOnly);
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
      _loadingOverlayHidden = false;
      _thumbnails.clear();
      _editSources.clear();
      _renderedPreviews.clear();
      _histograms.clear();
      _metadata.clear();
      _neutralPreviews.clear();
      _beforeAfterMode = false;
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
      _isApplyingAiDenoise = false;
      _thumbnailsLoaded = 0;
      _thumbnailsTotal = 0;
    });
  }

  /// Dismisses the loading overlay without cancelling the underlying
  /// operation — it keeps running in the background (progress still
  /// updates the toolbar/panel state as usual), and the app stays
  /// interactive in the meantime.
  void _hideLoadingOverlay() {
    setState(() => _loadingOverlayHidden = true);
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
      _appliedPresetId = null;
    });
    _resetHistory();
    if (selectedIndex != null) {
      unawaited(_saveLastActiveFile(files[selectedIndex].path));
      unawaited(
        _loadEditSourceAndRender(files[selectedIndex].path, generation),
      );
    }
    unawaited(_preloadPreviewCache(files, selectedIndex, generation));
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
        bytes ??= await _decodeThumbnail(file);
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

  /// A JPEG common image (by far the usual case for a "loading photos is
  /// slow" complaint — camera/phone JPEGs run tens of megapixels) gets
  /// [decodeJpegThumbnailFast]'s scaled dart:ui decode instead of
  /// [decodeRawThumbnail]'s full-resolution `package:image` decode, which
  /// dominated thumbnail generation time for large files. Falls back to
  /// the general path on any failure (corrupt file, unusual JPEG variant
  /// the hand-rolled EXIF reader trips on, etc.) rather than losing the
  /// thumbnail outright. Every other case (RAW files, and the less
  /// commonly huge PNG/TIFF/WebP/BMP formats) keeps using the
  /// `compute()`-based background-isolate path unchanged.
  Future<Uint8List?> _decodeThumbnail(RawFile file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (!file.isRaw && (ext == '.jpg' || ext == '.jpeg')) {
      try {
        final bytes = await File(file.path).readAsBytes();
        final fast = await decodeJpegThumbnailFast(bytes);
        if (fast != null) {
          return fast;
        }
      } catch (_) {
        // Fall through to the general decode path below.
      }
    }
    return compute(decodeRawThumbnail, file.path);
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
      _appliedPresetId = null;
    });
    _resetHistory();
    unawaited(_saveLastActiveFile(path));
    unawaited(_loadEditSourceAndRender(path, _folderGeneration));
    if (_beforeAfterMode && !_neutralPreviews.containsKey(path)) {
      unawaited(_loadNeutralPreview(path));
    }
  }

  /// Decodes the full editable RAW buffer for [path] (unless already
  /// cached, in memory or on disk) and renders it with the current slider
  /// values. Guarded by [generation] so a slow decode from a folder the
  /// user has since navigated away from can't clobber state after the
  /// fact.
  Future<void> _loadEditSourceAndRender(String path, int generation) async {
    if (!_metadata.containsKey(path)) {
      unawaited(_loadMetadata(path, generation));
    }
    var sources = _editSources[path];
    if (sources == null) {
      setState(() {
        _isDecodingPhoto = true;
        _loadingOverlayHidden = false;
      });

      // Cache lookup/decode happens here in the main isolate/from a
      // compute() call (same split as ThumbnailCacheManager's own usage,
      // see _loadThumbnails) — only a genuine cache miss falls through to
      // the much more expensive RAW decode isolate below.
      final cachedJpeg = await _previewCache?.lookup(path);
      var fromCache = false;
      if (cachedJpeg != null) {
        sources = await compute(decodeEditSourcePairFromCachedJpeg, cachedJpeg);
        fromCache = sources != null;
      }

      // No per-stage progress consumer anymore (the small in-place spinner
      // is indeterminate — see _ImageArea's usage below), but
      // decodeEditSourcesWithProgress's dedicated Isolate is still what we
      // want over decodeEditSources' compute() for a genuine miss: see its
      // doc comment.
      sources ??= await decodeEditSourcesWithProgress(
        path,
        (_) {},
        previewMaxDimension: _settings.previewResolution,
      );

      if (!mounted || generation != _folderGeneration) {
        return;
      }
      setState(() => _isDecodingPhoto = false);
      if (sources == null) {
        return;
      }
      setState(() => _editSources[path] = sources!);
      if (!fromCache) {
        unawaited(_storePreviewCache(path, sources));
      }
    }
    await _renderPreview(path);
  }

  /// Persists a freshly RAW-decoded [sources] to the on-disk preview
  /// cache so the next time [path] is opened (this session or a future
  /// one) it can skip straight to [decodeEditSourcePairFromCachedJpeg]
  /// instead of a full RAW decode. Best-effort and never awaited by
  /// callers — a failure here just means the next open is slow again, not
  /// lost data.
  Future<void> _storePreviewCache(String path, EditSourcePair sources) async {
    final cache = _previewCache;
    if (cache == null) {
      return;
    }
    final jpegBytes = await compute(encodePreviewForCache, sources);
    await cache.store(path, jpegBytes);
    unawaited(cache.flush());
  }

  /// Warms [_editSources] for a small window of files starting at
  /// [selectedIndex] (the one right after the selected photo itself,
  /// which [_loadEditSourceAndRender] is already decoding in parallel) —
  /// a cache hit just decodes the cached JPEG, but a miss runs a real RAW
  /// decode and populates the cache for next time, same as
  /// [_loadEditSourceAndRender] itself does. That real-decode cost is
  /// deliberately spent here, in the background, right after launch —
  /// see main.dart's `_splashMinDuration`, whose fixed duration exists
  /// specifically to give this a real window to run in — rather than
  /// only ever happening reactively when the user clicks each thumbnail.
  ///
  /// Bounded to [_previewPreloadCount] files (run with a handful of
  /// workers in parallel — see [_previewPreloadConcurrency] — so it
  /// actually finishes within that window instead of one file at a time)
  /// so opening a folder with thousands of photos doesn't spend a long
  /// time decoding photos nobody's looked at yet.
  Future<void> _preloadPreviewCache(
    List<RawFile> files,
    int? selectedIndex,
    int generation,
  ) async {
    final cache = _previewCache;
    if (cache == null || files.isEmpty) {
      return;
    }
    final start = selectedIndex ?? 0;
    final queue = files.skip(start).take(_previewPreloadCount).toList();

    Future<void> preloadOne(RawFile file) async {
      if (!mounted || generation != _folderGeneration) {
        return;
      }
      if (_editSources.containsKey(file.path)) {
        return; // Already decoded (e.g. the selected photo, above).
      }
      final cachedJpeg = await cache.lookup(file.path);
      EditSourcePair? sources;
      var fromCache = false;
      if (cachedJpeg != null) {
        sources = await compute(decodeEditSourcePairFromCachedJpeg, cachedJpeg);
        fromCache = sources != null;
      }
      // Cache miss (or a corrupt cache entry) — a real decode, not
      // skipped, so this photo's cache exists by the time the user
      // actually selects it.
      sources ??= await decodeEditSourcesWithProgress(
        file.path,
        (_) {},
        previewMaxDimension: _settings.previewResolution,
      );
      if (sources == null || !mounted || generation != _folderGeneration) {
        return;
      }
      if (_editSources.containsKey(file.path)) {
        return; // Raced with a real selection/decode of this same photo.
      }
      setState(() => _editSources[file.path] = sources!);
      if (!fromCache) {
        unawaited(_storePreviewCache(file.path, sources));
      }
    }

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (!mounted || generation != _folderGeneration) {
          return;
        }
        await preloadOne(queue.removeAt(0));
      }
    }

    await Future.wait(
      List.generate(_previewPreloadConcurrency, (_) => worker()),
    );
  }

  /// Loads [path]'s camera/lens/exposure metadata (cheap — no unpack/
  /// demosaic needed) into [_metadata], cached so re-selecting the same
  /// photo doesn't re-read the file.
  Future<void> _loadMetadata(String path, int generation) async {
    final metadata = await compute(extractRawMetadata, path);
    if (!mounted || generation != _folderGeneration) {
      return;
    }
    setState(() => _metadata[path] = metadata);
  }

  /// Renders [path]'s cached edit source with the current slider values and
  /// caches the resulting JPEG + histogram + filmstrip thumbnail. Uses the
  /// smaller "live" resolution while [live] is true (a slider is actively
  /// being dragged) for speed; the settled view renders at the downscaled
  /// [EditSourcePair.preview] resolution otherwise.
  ///
  /// Coalesces overlapping calls via [_renderInFlight]/[_pendingRenderRequest]
  /// rather than letting them run concurrently: harmless for the CPU path
  /// (each render is a separate background isolate/thread, so several in
  /// flight at once just uses more cores), and also why GPU rendering
  /// (`AppSettings.useGpuRender`) stays off the `live` path entirely (see
  /// [_renderPreviewNow]) rather than relying on this guard alone — a rapid
  /// slider drag firing the 25ms debounce repeatedly once piled up several
  /// full GPU renders all competing for the one UI isolate they must run
  /// inline on (see `render_gpu.dart`'s doc comment), which is exactly what
  /// made the app go "Not Responding" during a fast drag. A coalesced-away
  /// call still counts as superseded for [_renderRequestId] purposes once
  /// its replacement actually runs, so the existing stale-result check
  /// below needs no changes.
  Future<void> _renderPreview(
    String path, {
    bool live = false,
    void Function(RenderStage stage)? onStage,
  }) async {
    final sources = _editSources[path];
    if (sources == null) {
      return;
    }
    if (_renderInFlight) {
      _pendingRenderRequest = (path: path, live: live, onStage: onStage);
      final completer = Completer<void>();
      _pendingRenderWaiters.add(completer);
      return completer.future;
    }
    _renderInFlight = true;
    try {
      await _renderPreviewNow(path, live: live, onStage: onStage);
    } finally {
      _renderInFlight = false;
      final pending = _pendingRenderRequest;
      final waiters = _pendingRenderWaiters.toList();
      _pendingRenderRequest = null;
      _pendingRenderWaiters.clear();
      if (pending != null) {
        unawaited(
          _renderPreview(
            pending.path,
            live: pending.live,
            onStage: pending.onStage,
          ).then(
            (_) {
              for (final w in waiters) {
                w.complete();
              }
            },
            onError: (Object e, StackTrace st) {
              for (final w in waiters) {
                w.completeError(e, st);
              }
            },
          ),
        );
      } else {
        for (final w in waiters) {
          w.complete();
        }
      }
    }
  }

  Future<void> _renderPreviewNow(
    String path, {
    bool live = false,
    void Function(RenderStage stage)? onStage,
  }) async {
    final sources = _editSources[path]!;
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
    // While the Crop Overlay is open, render the full straightened/
    // keystoned frame (no rectangular crop) so the discarded edges are
    // still visible under the overlay's scrim, Lightroom-style, instead
    // of the preview jumping to the already-cropped result mid-edit.
    final cropTransform = _cropOverlayActive
        ? _cropTransform.copyWith(
            cropLeft: 0,
            cropTop: 0,
            cropRight: 1,
            cropBottom: 1,
          )
        : _cropTransform;
    final job = RenderJob(
      source: live ? sources.live : sources.preview,
      params: RenderParams.fromValues(
        _effectiveParamValues(),
        curves: _effectiveCurves,
      ),
      masks: _effectiveMasks,
      cropTransform: cropTransform,
    );
    // The AI Denoise apply action wants real stage progress (it's the
    // slowest single-shot render); ordinary slider-drag renders stay on
    // plain compute() so the 25ms live-preview debounce doesn't pay a
    // fresh-isolate-spawn cost on every tick. GPU rendering (see
    // AppSettings.useGpuRender) only applies to the settled (non-`live`)
    // plain path: it can't run inside renderJobToJpegWithProgress's
    // dedicated isolate at all (dart:ui's GPU-backed primitives need the
    // main isolate), and deliberately stays off the `live` path even
    // though it *could* run there — every live-drag tick would then run a
    // full GPU render inline on the UI isolate instead of handing it to a
    // background isolate the way compute() does, which is what caused the
    // "Not Responding" freeze [_renderPreview]'s doc comment describes.
    final RenderResult result;
    if (onStage != null) {
      result = await renderJobToJpegWithProgress(job, onStage);
    } else if (!live &&
        _settings.useGpuRender &&
        await isGpuRenderAvailable()) {
      result = await renderJobToJpegGpu(job);
    } else {
      result = await compute(renderJobToJpeg, job);
    }
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

  void _toggleCropOverlay() {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    setState(() => _cropOverlayActive = !_cropOverlayActive);
    if (selected != null) {
      unawaited(_renderPreview(selected.path));
    }
  }

  void _setCropAspectRatio(double? ratio) {
    setState(() => _cropAspectRatio = ratio);
  }

  /// Opens the AI Denoise level dialog and, if the user confirms, bakes the
  /// chosen level into the current photo's params and re-renders — a
  /// deliberate one-shot action (with its own loading message) rather than
  /// a slider the user drags, matching the Lightroom/Photomator "pick a
  /// strength, apply" pattern.
  Future<void> _openAiDenoiseDialog() async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    final currentLevel = AiDenoiseParams.fromValues(_paramValues).level;
    final choice = await showDialog<AiDenoiseChoice>(
      context: context,
      builder: (_) => AiDenoiseDialog(initialLevel: currentLevel),
    );
    if (choice == null || !mounted) {
      return;
    }
    final level = choice.level;
    setState(() {
      _paramValues = {
        ..._paramValues,
        'AiDenoiseLevel': level == null
            ? 0.0
            : (AiDenoiseLevel.values.indexOf(level) + 1).toDouble(),
      };
      _isApplyingAiDenoise = true;
      _loadingOverlayHidden = false;
      _aiDenoiseRenderStage = null;
    });
    await _renderPreview(
      selected.path,
      onStage: (stage) {
        if (mounted) {
          setState(() => _aiDenoiseRenderStage = stage);
        }
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isApplyingAiDenoise = false;
      _aiDenoiseRenderStage = null;
    });
    _pushHistory();
    _scheduleCatalogSave();
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
    setState(() {
      _paramValues[name] = value;
      _appliedPresetId = null;
    });
    _scheduleRender(live: _settings.fastPreview);
    _scheduleCatalogSave();
  }

  void _onParamChangeEnd(String name, double value) {
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// [_paramValues] with every disabled category's sliders swapped for
  /// their defaults — used wherever the render pipeline reads the global
  /// layer's param values. See [_withCategoriesApplied]'s doc comment.
  Map<String, double> _effectiveParamValues() =>
      _withCategoriesApplied(_paramValues);

  /// [_currentCurves] with Tone Curve/Color Curve reset to identity if
  /// either is disabled — the curve equivalent of [_effectiveParamValues],
  /// kept separate since curves don't live in the flat values map.
  PhotoCurves get _effectiveCurves =>
      _withCurveCategoriesApplied(_currentCurves, _paramValues);

  /// [_currentMasks] with every mask's own disabled categories (values
  /// *and* curves) neutralized the same way the global layer's are —
  /// masks carry their own independent slider/curve values (see
  /// [MaskLayer.values]/[MaskLayer.curves]), so each one needs its own
  /// pass rather than sharing the global layer's toggle state.
  List<MaskLayer> get _effectiveMasks => [
    for (final mask in _currentMasks)
      mask.copyWith(
        values: _withCategoriesApplied(mask.values),
        curves: _withCurveCategoriesApplied(mask.curves, mask.values),
      ),
  ];

  /// Crop/Transform state, derived from the same flat `_paramValues` map
  /// every other global adjustment lives in — deliberately global-only
  /// (see [RenderJob.cropTransform]'s doc comment), so unlike
  /// [_activeValues] there's no mask-routing branch here.
  CropTransformParams get _cropTransform =>
      CropTransformParams.fromValues(_paramValues);

  void _onCropTransformChanged(CropTransformParams params) {
    setState(() => _paramValues = {..._paramValues, ...params.toValues()});
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onCropTransformChangeEnd(CropTransformParams params) {
    setState(() => _paramValues = {..._paramValues, ...params.toValues()});
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _resetCropTransform() {
    _onCropTransformChangeEnd(const CropTransformParams());
  }

  void _onToneCurveChanged(List<CurvePoint> points) {
    setState(() => _currentCurves = _currentCurves.copyWith(tone: points));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onToneCurveChangeEnd(List<CurvePoint> points) {
    setState(() => _currentCurves = _currentCurves.copyWith(tone: points));
    _pushHistory();
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
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _resetParams() {
    setState(() {
      _paramValues = _defaultParamValues();
      _currentCurves = identityPhotoCurves;
    });
    _pushHistory();
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

  /// The Tone Curve/Color Curve the panel should currently show/edit —
  /// mirrors [_activeValues]'s "global, or the active mask's own" split.
  PhotoCurves get _activeCurves {
    if (_activeMaskId == imageMaskId) {
      return _currentCurves;
    }
    return _activeMask?.curves ?? identityPhotoCurves;
  }

  MaskLayer? get _activeMask =>
      _currentMasks.where((m) => m.id == _activeMaskId).firstOrNull;

  void _onActiveToneCurveChanged(List<CurvePoint> points) {
    if (_activeMaskId == imageMaskId) {
      _onToneCurveChanged(points);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(curves: mask.curves.copyWith(tone: points)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onActiveToneCurveChangeEnd(List<CurvePoint> points) {
    if (_activeMaskId == imageMaskId) {
      _onToneCurveChangeEnd(points);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(curves: mask.curves.copyWith(tone: points)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  PhotoCurves _withActiveChannelCurve(
    PhotoCurves curves,
    String channel,
    List<CurvePoint> points,
  ) {
    switch (channel) {
      case 'red':
        return curves.copyWith(red: points);
      case 'green':
        return curves.copyWith(green: points);
      case 'blue':
        return curves.copyWith(blue: points);
    }
    throw ArgumentError.value(channel, 'channel');
  }

  void _onActiveColorCurveChanged(String channel, List<CurvePoint> points) {
    if (_activeMaskId == imageMaskId) {
      _onColorCurveChanged(channel, points);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(
        curves: _withActiveChannelCurve(mask.curves, channel, points),
      ),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onActiveColorCurveChangeEnd(String channel, List<CurvePoint> points) {
    if (_activeMaskId == imageMaskId) {
      _onColorCurveChangeEnd(channel, points);
      return;
    }
    _updateActiveMask(
      (mask) => mask.copyWith(
        curves: _withActiveChannelCurve(mask.curves, channel, points),
      ),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onActiveChanged(String name, double value) {
    if (_activeMaskId == imageMaskId) {
      _onParamChanged(name, value);
      return;
    }
    if (!_isAdjustingMaskValue) {
      setState(() => _isAdjustingMaskValue = true);
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
    setState(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (mask) => mask.copyWith(values: {...mask.values, name: value}),
    );
    _pushHistory();
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
    _updateActiveMask(
      (mask) => mask.copyWith(values: const {}, curves: identityPhotoCurves),
    );
    _pushHistory();
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

  void _toggleMaskOverlayVisible() {
    setState(() => _maskOverlayVisible = !_maskOverlayVisible);
  }

  void _setMaskOverlayOpacity(MaskType type, double value) {
    setState(() => _maskOverlayOpacity[type] = value);
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
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _toggleActiveMaskEnabled() {
    _updateActiveMask((mask) => mask.copyWith(enabled: !mask.enabled));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _toggleActiveMaskInverted() {
    _updateActiveMask((mask) => mask.copyWith(inverted: !mask.inverted));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onActiveMaskOpacityChanged(double value) {
    if (!_isAdjustingMaskValue) {
      setState(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask((mask) => mask.copyWith(opacity: value));
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onActiveMaskOpacityChangeEnd(double value) {
    setState(() => _isAdjustingMaskValue = false);
    _updateActiveMask((mask) => mask.copyWith(opacity: value));
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Duplicates the active mask into a new sibling layer — same geometry,
  /// slider values and curves, a fresh id, and a "copy" suffix on the
  /// name so it's distinguishable in the switch menu. The clone becomes
  /// the active
  /// layer, matching [_addMask]'s "select what you just created" feel.
  void _cloneActiveMask() {
    final l10n = AppLocalizations.of(context)!;
    final source = _currentMasks
        .where((m) => m.id == _activeMaskId)
        .firstOrNull;
    if (source == null) {
      return;
    }
    final clone = MaskLayer(
      id: 'mask_${DateTime.now().microsecondsSinceEpoch}',
      name: '${source.name} ${l10n.maskCloneSuffix}',
      type: source.type,
      linear: source.linear,
      radial: source.radial,
      brush: source.brush,
      colorRange: source.colorRange,
      enabled: source.enabled,
      inverted: source.inverted,
      opacity: source.opacity,
      values: Map<String, double>.from(source.values),
      curves: source.curves,
    );
    setState(() {
      _currentMasks = [..._currentMasks, clone];
      _activeMaskId = clone.id;
    });
    _pushHistory();
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
    _pushHistory();
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
    _pushHistory();
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
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onColorRangeToleranceChanged(double value) {
    if (!_isAdjustingMaskValue) {
      setState(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(tolerance: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onColorRangeToleranceChangeEnd(double value) {
    setState(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(tolerance: value)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onColorRangeFeatherChanged(double value) {
    if (!_isAdjustingMaskValue) {
      setState(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(feather: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onColorRangeFeatherChangeEnd(double value) {
    setState(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (m) => m.copyWith(colorRange: m.colorRange.copyWith(feather: value)),
    );
    _pushHistory();
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
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  _EditSnapshot get _currentSnapshot => _EditSnapshot(
    paramValues: _paramValues,
    curves: _currentCurves,
    masks: _currentMasks,
  );

  /// Starts a fresh history for the photo now showing, with its
  /// just-loaded state as the single undo-proof baseline — called
  /// whenever [_paramValues]/[_currentCurves]/[_currentMasks] are replaced
  /// wholesale by loading a photo's saved state (selection change, folder
  /// open), rather than by an edit the user made, so there's nothing to
  /// undo back to before it.
  void _resetHistory() {
    _history
      ..clear()
      ..add(_currentSnapshot);
    _historyIndex = 0;
  }

  /// Records the current state as a new history entry — call after
  /// committing an edit (every `...ChangeEnd`/one-shot-action callsite),
  /// never from a live/dragging callback, so a slider drag collapses into
  /// one undo step instead of one per pixel of mouse movement. Redoing
  /// back to this exact state and editing again would otherwise duplicate
  /// it, so a no-op push (state identical to the top of the stack) is
  /// skipped — comparing by reference is enough since every mutation site
  /// always builds a new Map/List/object rather than mutating in place.
  void _pushHistory() {
    final snapshot = _currentSnapshot;
    if (_history.isNotEmpty &&
        _historyIndex == _history.length - 1 &&
        identical(_history.last.paramValues, snapshot.paramValues) &&
        identical(_history.last.curves, snapshot.curves) &&
        identical(_history.last.masks, snapshot.masks)) {
      return;
    }
    // Truncate any redo branch past the current point before appending —
    // editing after an undo abandons the undone-away future, matching
    // every other editor's undo/redo convention.
    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(snapshot);
    _historyIndex = _history.length - 1;
  }

  void _applySnapshot(_EditSnapshot snapshot) {
    setState(() {
      _paramValues = snapshot.paramValues;
      _currentCurves = snapshot.curves;
      _currentMasks = snapshot.masks;
      if (_activeMaskId != imageMaskId &&
          !_currentMasks.any((m) => m.id == _activeMaskId)) {
        // The active mask no longer exists in the state being restored to
        // (e.g. undoing past its creation, or redoing past its deletion)
        // — fall back to the Image layer rather than pointing the panel
        // at a mask that isn't there.
        _activeMaskId = imageMaskId;
      }
    });
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _undo() {
    if (!_canUndo) {
      return;
    }
    _historyIndex--;
    _applySnapshot(_history[_historyIndex]);
  }

  void _redo() {
    if (!_canRedo) {
      return;
    }
    _historyIndex++;
    _applySnapshot(_history[_historyIndex]);
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

    setState(() {
      _exporting = true;
      _loadingOverlayHidden = false;
      _exportStage = null;
    });
    final result = await exportPhotoWithProgress(
      ExportRequest(
        sourcePath: selected.path,
        destPath: destPath,
        params: RenderParams.fromValues(
          _effectiveParamValues(),
          curves: _effectiveCurves,
        ),
        masks: _effectiveMasks,
        format: options.format,
        quality: options.quality,
        cropTransform: _cropTransform,
      ),
      (stage) {
        if (mounted) {
          setState(() => _exportStage = stage);
        }
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _exporting = false;
      _exportStage = null;
    });
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
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
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
    // Deliberately NOT handled here: _isDecodingPhoto (opening a single
    // photo) gets a small spinner centered over just the image area
    // instead of this full-screen overlay — see _ImageArea's usage in
    // _buildScaffold.
    if (_isApplyingAiDenoise) {
      final stage = _aiDenoiseRenderStage;
      return _LoadingInfo(
        message: l10n.aiDenoiseApplyingMessage,
        progress: switch (stage) {
          null => 0.0,
          RenderStage.denoising => 0.15,
          RenderStage.adjusting => 0.55,
          RenderStage.encoding => 0.85,
        },
      );
    }
    if (_isRenderingSlow) {
      return _LoadingInfo(message: l10n.applyingAdjustments);
    }
    if (_exporting) {
      final stage = _exportStage;
      return _LoadingInfo(
        message: switch (stage) {
          null || ExportStage.decoding => l10n.exportStageDecoding,
          ExportStage.rendering => l10n.exportStageRendering,
          ExportStage.encoding => l10n.exportStageEncoding,
          ExportStage.writing => l10n.exportStageWriting,
        },
        progress: switch (stage) {
          null => 0.0,
          ExportStage.decoding => 0.05,
          ExportStage.rendering => 0.3,
          ExportStage.encoding => 0.7,
          ExportStage.writing => 0.9,
        },
      );
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
            onOpenAbout: _openAbout,
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
                            // Same width as the right-side _ControlsPanel
                            // (_controlsPanelWidth) — was 220 vs. the right
                            // panel's 280, a visibly uneven two-column
                            // layout the user asked to fix.
                            width: _controlsPanelWidth,
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
                                    rawOnly: _settings.rawOnly,
                                    onRawOnlyChanged: _setRawOnly,
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
                              ],
                            ),
                          ),
                          Expanded(
                            child: Stack(
                              children: [
                                _ImageArea(
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
                                  onMaskGeometryChangeEnd:
                                      _onMaskGeometryChangeEnd,
                                  brushRadius: _brushRadius,
                                  brushHardness: _brushHardness,
                                  brushErase: _brushErase,
                                  onSampleColor: _onSampleMaskColor,
                                  maskOverlayVisible:
                                      _maskOverlayVisible &&
                                      !_isAdjustingMaskValue,
                                  maskOverlayOpacity: _maskOverlayOpacity,
                                  cropOverlayActive:
                                      !_beforeAfterMode && _cropOverlayActive,
                                  cropTransform: _cropTransform,
                                  cropAspectRatio: _cropAspectRatio,
                                  onCropTransformChanged:
                                      _onCropTransformChanged,
                                  onCropTransformChangeEnd:
                                      _onCropTransformChangeEnd,
                                ),
                                // Opening a photo (RAW decode, or a
                                // preview-cache hit) gets a small spinner
                                // over just this area instead of the
                                // full-screen _LoadingOverlay other
                                // operations use — see _overlayInfo's doc
                                // comment.
                                if (_isDecodingPhoto && selected != null)
                                  const Center(
                                    child: SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _ControlsPanel(
                            values: _activeValues,
                            histogram: selected == null
                                ? null
                                : _histograms[selected.path],
                            metadata: selected == null
                                ? null
                                : _metadata[selected.path],
                            onChanged: _onActiveChanged,
                            onChangeEnd: _onActiveChangeEnd,
                            onReset: _resetActive,
                            onExport: selected == null ? null : _exportCurrent,
                            exporting: _exporting,
                            enabled: selected != null,
                            curves: _activeCurves,
                            onToneCurveChanged: _onActiveToneCurveChanged,
                            onToneCurveChangeEnd: _onActiveToneCurveChangeEnd,
                            onColorCurveChanged: _onActiveColorCurveChanged,
                            onColorCurveChangeEnd: _onActiveColorCurveChangeEnd,
                            masks: _currentMasks,
                            activeMaskId: _activeMaskId,
                            onSelectMask: _selectMask,
                            onAddMask: _addMask,
                            onToggleMaskEnabled: _toggleActiveMaskEnabled,
                            onToggleMaskInverted: _toggleActiveMaskInverted,
                            onCloneMask: _cloneActiveMask,
                            onDeleteMask: _deleteActiveMask,
                            onMaskOpacityChanged: _onActiveMaskOpacityChanged,
                            onMaskOpacityChangeEnd:
                                _onActiveMaskOpacityChangeEnd,
                            maskOverlayVisible: _maskOverlayVisible,
                            onToggleMaskOverlayVisible:
                                _toggleMaskOverlayVisible,
                            maskOverlayOpacity: _maskOverlayOpacity,
                            onMaskOverlayOpacityChanged: _setMaskOverlayOpacity,
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
                            cropOverlayActive: _cropOverlayActive,
                            cropTransform: _cropTransform,
                            onCropTransformChanged: _onCropTransformChanged,
                            onCropTransformChangeEnd: _onCropTransformChangeEnd,
                            cropAspectRatio: _cropAspectRatio,
                            onCropAspectRatioChanged: _setCropAspectRatio,
                            onToggleCropOverlay: _toggleCropOverlay,
                            onResetCropTransform: _resetCropTransform,
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
                      canUndo: _canUndo,
                      canRedo: _canRedo,
                      onUndo: _undo,
                      onRedo: _redo,
                      aiDenoiseActive:
                          AiDenoiseParams.fromValues(_paramValues).level !=
                          null,
                      onOpenAiDenoise: selected == null
                          ? null
                          : _openAiDenoiseDialog,
                      cropOverlayActive: _cropOverlayActive,
                      onToggleCropOverlay: selected == null
                          ? null
                          : _toggleCropOverlay,
                      onExport: selected == null ? null : _exportCurrent,
                      exporting: _exporting,
                      onReset: _resetActive,
                      presetAmount: _presetAmount,
                      onPresetAmountChanged: (v) =>
                          setState(() => _presetAmount = v),
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
                    return info == null || _loadingOverlayHidden
                        ? const SizedBox.shrink()
                        : _LoadingOverlay(
                            info: info,
                            onCancel: _cancelLoading,
                            onHide: _hideLoadingOverlay,
                          );
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
    required this.onOpenAbout,
  });

  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAbout;

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
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onOpenAbout,
            child: _MenuBarLabel(l10n.menuAbout),
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
    required this.maskOverlayVisible,
    required this.maskOverlayOpacity,
    required this.cropOverlayActive,
    required this.cropTransform,
    required this.cropAspectRatio,
    required this.onCropTransformChanged,
    required this.onCropTransformChangeEnd,
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

  /// Whether the active mask's shaded overlay/handles are drawn — a
  /// user-toggleable UI preference, same for every mask type.
  final bool maskOverlayVisible;

  /// How opaque that overlay's shading is (0..1), independently per mask
  /// type — see [_EditorScreenState._maskOverlayOpacity].
  final Map<MaskType, double> maskOverlayOpacity;

  /// Whether the Crop Overlay's draggable rectangle is shown — mutually
  /// exclusive with mask editing (the caller only sets one at a time).
  final bool cropOverlayActive;
  final CropTransformParams cropTransform;
  final double? cropAspectRatio;
  final ValueChanged<CropTransformParams> onCropTransformChanged;
  final ValueChanged<CropTransformParams> onCropTransformChangeEnd;

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
    if (cropOverlayActive && source != null) {
      // Displayed frame is straightened/keystoned but not yet cropped
      // (see _EditorScreenState._renderPreview) — its dimensions match
      // the source's, swapped for an odd quarter-turn count, since
      // straighten/keystone/scale don't change the canvas span.
      final rotated = cropTransform.rotateQuarterTurns.isOdd;
      final frameWidth = rotated ? source.height : source.width;
      final frameHeight = rotated ? source.width : source.height;
      return SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final containerSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
                CropOverlay(
                  containerSize: containerSize,
                  imageWidth: frameWidth,
                  imageHeight: frameHeight,
                  params: cropTransform,
                  lockedAspectRatio: cropAspectRatio,
                  onChanged: onCropTransformChanged,
                  onChangeEnd: onCropTransformChangeEnd,
                ),
              ],
            );
          },
        ),
      );
    }
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
                        showOverlay: maskOverlayVisible,
                        overlayOpacity: maskOverlayOpacity[mask.type]!,
                      )
                    else if (mask.type == MaskType.colorRange)
                      ColorRangeOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        onSample: onSampleColor,
                        mask: mask,
                        previewJpegBytes: bytes,
                        showOverlay: maskOverlayVisible,
                        overlayOpacity: maskOverlayOpacity[mask.type]!,
                      )
                    else
                      GradientMaskOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        mask: mask,
                        onChanged: onMaskGeometryChanged,
                        onChangeEnd: onMaskGeometryChangeEnd,
                        showOverlay: maskOverlayVisible,
                        overlayOpacity: maskOverlayOpacity[mask.type]!,
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
  const _LoadingOverlay({
    required this.info,
    required this.onCancel,
    required this.onHide,
  });

  final _LoadingInfo info;
  final VoidCallback onCancel;

  /// Dismisses the overlay while letting the operation keep running in
  /// the background.
  final VoidCallback onHide;

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
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onCancel,
                      child: Text(l10n.cancelButton),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: onHide,
                      child: Text(l10n.hideButton),
                    ),
                  ),
                ],
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
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.aiDenoiseActive,
    required this.onOpenAiDenoise,
    required this.cropOverlayActive,
    required this.onToggleCropOverlay,
    required this.onExport,
    required this.exporting,
    required this.onReset,
    required this.presetAmount,
    required this.onPresetAmountChanged,
  });

  final String zoomLabel;
  final bool beforeAfterMode;
  final bool beforeAfterEnabled;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomFit;
  final VoidCallback? onToggleBeforeAfter;

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// True when a level is already applied to the current photo — shown as
  /// a filled/selected button, same convention as Before/After.
  final bool aiDenoiseActive;
  final VoidCallback? onOpenAiDenoise;

  final bool cropOverlayActive;
  final VoidCallback? onToggleCropOverlay;

  final VoidCallback? onExport;
  final bool exporting;
  final VoidCallback onReset;

  /// How strongly the next-applied preset blends in, 0..150% — see
  /// [_EditorScreenState._presetAmount]. Lives here (rather than in
  /// `PresetPanel`) so it sits in the toolbar's left spacer, under the
  /// preset list it affects, matching the width-alignment convention the
  /// two reserved spacers already follow.
  final double presetAmount;
  final ValueChanged<double> onPresetAmountChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 56,
      color: DarkmoonColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Lines up under the folder/preset sidebar above — holds the
          // preset Amount slider, right under the preset list it affects.
          // Matches _controlsPanelWidth exactly (was a narrower 220 that
          // didn't line up with the sidebar's actual 280px width, which
          // also threw off the zoom controls right after it in the Row
          // below). A larger label/value size than SliderRow's other call
          // sites, since this is a standalone toolbar control rather than
          // one of many stacked panel rows — it can afford to be more
          // readable.
          SizedBox(
            width: _controlsPanelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: _controlsPanelWidth - 28,
                  child: SliderRow(
                    name: l10n.presetAmountLabel,
                    min: 0,
                    max: 150,
                    value: presetAmount,
                    decimals: 0,
                    valueSuffix: '%',
                    defaultValue: 100,
                    labelFontSize: 13,
                    valueFontSize: 13,
                    onChanged: onPresetAmountChanged,
                  ),
                ),
              ),
            ),
          ),
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
                  // Centered in this Expanded region (a Spacer on both
                  // sides, not just before it) — the toolbar's most
                  // frequently-used controls, deliberately given the most
                  // visually prominent slot rather than sitting bunched
                  // against the right-aligned Crop/Denoise/Before-After
                  // group.
                  _ToolbarPill(
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_uturn_left,
                        onTap: canUndo ? onUndo : null,
                        tooltip: l10n.undoButton,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_2_circlepath,
                        onTap: onReset,
                        tooltip: l10n.resetTooltip,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_uturn_right,
                        onTap: canRedo ? onRedo : null,
                        tooltip: l10n.redoButton,
                      ),
                    ],
                  ),
                  const Spacer(),
                  _ToolbarPill(
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.crop,
                        selected: cropOverlayActive,
                        onTap: onToggleCropOverlay,
                        tooltip: l10n.cropButton,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.sparkles,
                        selected: aiDenoiseActive,
                        onTap: onOpenAiDenoise,
                        tooltip: l10n.aiDenoiseButton,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.square_split_2x1,
                        selected: beforeAfterMode,
                        onTap: onToggleBeforeAfter,
                        tooltip: l10n.beforeAfterButton,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Lines up under _ControlsPanel above — holds Export, so it
          // stays reachable regardless of how far the panel above has
          // been scrolled. Reset now lives between Undo/Redo instead.
          SizedBox(
            width: 280,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: exporting ? null : onExport,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          side: const BorderSide(
                            color: DarkmoonColors.border,
                            width: 1.0,
                          ),
                        ),
                        icon: exporting
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                CupertinoIcons.square_arrow_down,
                                size: 14,
                              ),
                        label: Text(
                          exporting
                              ? l10n.exportingButton
                              : l10n.exportPanelButton,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      height: 36,
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
/// Rotate/straighten/keystone sliders + crop aspect-ratio picker, shown
/// while the Crop Overlay is active — Lightroom's Crop Overlay + Transform
/// panels combined, since they share one geometric pipeline stage (see
/// `crop_transform.dart`).
class _CropTransformPanel extends StatelessWidget {
  const _CropTransformPanel({
    required this.params,
    required this.onChanged,
    required this.onChangeEnd,
    required this.aspectRatio,
    required this.onAspectRatioChanged,
    required this.onDone,
    required this.onReset,
  });

  final CropTransformParams params;
  final ValueChanged<CropTransformParams> onChanged;
  final ValueChanged<CropTransformParams> onChangeEnd;
  final double? aspectRatio;
  final ValueChanged<double?> onAspectRatioChanged;

  /// Closes the Crop Overlay, keeping whatever's currently set.
  final VoidCallback onDone;

  /// Resets crop/rotate/keystone back to identity, without closing the
  /// overlay — matches Lightroom's own Crop panel "Reset" behavior.
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DarkmoonColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DarkmoonColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cropAspectLabel,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in cropAspectPresets)
                _AspectChip(
                  label: preset.label,
                  selected: aspectRatio == preset.ratio,
                  onTap: () => onAspectRatioChanged(preset.ratio),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ToolbarPill(
            children: [
              _ToolbarSegment(
                icon: CupertinoIcons.rotate_left,
                tooltip: l10n.cropRotateLeftTooltip,
                onTap: () {
                  final next = params.copyWith(
                    rotateQuarterTurns: (params.rotateQuarterTurns - 1) % 4,
                  );
                  onChangeEnd(next);
                },
              ),
              _ToolbarSegment(
                icon: CupertinoIcons.rotate_right,
                tooltip: l10n.cropRotateRightTooltip,
                onTap: () {
                  final next = params.copyWith(
                    rotateQuarterTurns: (params.rotateQuarterTurns + 1) % 4,
                  );
                  onChangeEnd(next);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformStraightenLabel,
            min: -45,
            max: 45,
            value: params.straightenAngle,
            decimals: 1,
            defaultValue: 0,
            onChanged: (v) => onChanged(params.copyWith(straightenAngle: v)),
            onChangeEnd: (v) =>
                onChangeEnd(params.copyWith(straightenAngle: v)),
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformVerticalLabel,
            min: -100,
            max: 100,
            value: params.vertical,
            decimals: 0,
            defaultValue: 0,
            onChanged: (v) => onChanged(params.copyWith(vertical: v)),
            onChangeEnd: (v) => onChangeEnd(params.copyWith(vertical: v)),
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformHorizontalLabel,
            min: -100,
            max: 100,
            value: params.horizontal,
            decimals: 0,
            defaultValue: 0,
            onChanged: (v) => onChanged(params.copyWith(horizontal: v)),
            onChangeEnd: (v) => onChangeEnd(params.copyWith(horizontal: v)),
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformAspectLabel,
            min: -100,
            max: 100,
            value: params.aspect,
            decimals: 0,
            defaultValue: 0,
            onChanged: (v) => onChanged(params.copyWith(aspect: v)),
            onChangeEnd: (v) => onChangeEnd(params.copyWith(aspect: v)),
          ),
          const SizedBox(height: 10),
          SliderRow(
            name: l10n.transformScaleLabel,
            min: 100,
            max: 150,
            value: params.scale,
            decimals: 0,
            defaultValue: 100,
            onChanged: (v) => onChanged(params.copyWith(scale: v)),
            onChangeEnd: (v) => onChangeEnd(params.copyWith(scale: v)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: onReset,
                    child: Text(l10n.resetTooltip),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: FilledButton(
                    onPressed: onDone,
                    child: Text(l10n.cropDoneButton),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AspectChip extends StatelessWidget {
  const _AspectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DarkmoonColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? DarkmoonColors.accent : DarkmoonColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? DarkmoonColors.background
                  : DarkmoonColors.textSecondary,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed width of the right-hand controls column, and the horizontal inset
/// its scrolling content sits at. [_SectionHeader] needs both so it can
/// break back out of that inset and paint its bar edge-to-edge.
const _controlsPanelWidth = 280.0;
const _controlsPanelInset = 16.0;

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.enabled,
    this.onEnabledChanged,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  /// When non-null (only for the sections in [_sections], which map
  /// straight onto sliders — Tone Curve/Color Mixer/etc. have their own
  /// editors and aren't covered), shows a switch that turns off this
  /// whole category's contribution to the render without discarding its
  /// slider values, so the user can A/B a category the way a solo/mute
  /// button works in an audio mixer.
  final bool? enabled;
  final ValueChanged<bool>? onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Spacing lives here, outside the InkWell, so hovering/clicking the
      // gap above and below the header box doesn't register as a tap on
      // it — only the visible rectangle itself should react.
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      // The controls column insets its scrolling content by
      // [_controlsPanelInset] on each side; an OverflowBox lets this bar
      // grow back out to the full column width so it bleeds edge-to-edge
      // (no rounded corners, no side border). The inset is then re-added
      // as inner padding so the label/switch stay aligned with the
      // sliders. Centering a full-width child in the narrower slot cancels
      // the symmetric inset exactly. IntrinsicHeight caps the OverflowBox
      // to the header's own height — without it the box inherits the
      // Column's unbounded vertical constraint and blows up to infinity.
      child: IntrinsicHeight(
        child: OverflowBox(
          maxWidth: _controlsPanelWidth,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: _controlsPanelInset,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  color: DarkmoonColors.surfaceRaised,
                  border: Border(
                    top: BorderSide(color: DarkmoonColors.border),
                    bottom: BorderSide(color: DarkmoonColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: enabled == false
                              ? DarkmoonColors.textMuted
                              : null,
                        ),
                      ),
                    ),
                    if (enabled != null && onEnabledChanged != null) ...[
                      // SizedBox+FittedBox (not Transform.scale) so the
                      // switch's *layout* box shrinks along with its paint —
                      // Transform.scale only shrinks what's drawn, leaving the
                      // full-size unscaled switch still reserving space in the
                      // Row and forcing the whole header taller than it looks
                      // like it should be.
                      SizedBox(
                        width: 26,
                        height: 16,
                        child: FittedBox(
                          child: Switch(
                            value: enabled!,
                            onChanged: onEnabledChanged,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
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
        ),
      ),
    );
  }
}

class _ControlsPanel extends StatefulWidget {
  const _ControlsPanel({
    required this.values,
    required this.histogram,
    required this.metadata,
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
    required this.onCloneMask,
    required this.onDeleteMask,
    required this.onMaskOpacityChanged,
    required this.onMaskOpacityChangeEnd,
    required this.maskOverlayVisible,
    required this.onToggleMaskOverlayVisible,
    required this.maskOverlayOpacity,
    required this.onMaskOverlayOpacityChanged,
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
    required this.cropOverlayActive,
    required this.cropTransform,
    required this.onCropTransformChanged,
    required this.onCropTransformChangeEnd,
    required this.cropAspectRatio,
    required this.onCropAspectRatioChanged,
    required this.onToggleCropOverlay,
    required this.onResetCropTransform,
  });

  final Map<String, double> values;
  final Histogram? histogram;
  final RawMetadata? metadata;
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
  final VoidCallback onCloneMask;
  final VoidCallback onDeleteMask;
  final ValueChanged<double> onMaskOpacityChanged;
  final ValueChanged<double> onMaskOpacityChangeEnd;
  final bool maskOverlayVisible;
  final VoidCallback onToggleMaskOverlayVisible;
  final Map<MaskType, double> maskOverlayOpacity;
  final void Function(MaskType type, double value) onMaskOverlayOpacityChanged;

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

  final bool cropOverlayActive;
  final CropTransformParams cropTransform;
  final ValueChanged<CropTransformParams> onCropTransformChanged;
  final ValueChanged<CropTransformParams> onCropTransformChangeEnd;
  final double? cropAspectRatio;
  final ValueChanged<double?> onCropAspectRatioChanged;
  final VoidCallback onToggleCropOverlay;
  final VoidCallback onResetCropTransform;

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
  /// Only relevant in [_mixerViewMode] `'Mixer'` — `'HSL'` shows every
  /// channel at once instead.
  String _activeMixerChannel = 'Red';

  /// Color Mixer's own display mode, matching Lightroom's Mixer/HSL toggle
  /// for the same underlying data: `'Mixer'` shows one selected channel's
  /// three sliders at a time (the dot picker above); `'HSL'` shows three
  /// stacked groups (Hue, Saturation, Luminance), each listing all 8
  /// channels together, for comparing/adjusting across channels within one
  /// attribute rather than across attributes within one channel.
  String _mixerViewMode = 'Mixer';

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
    final enabled = widget.enabled;
    final curves = widget.curves;
    final onToneCurveChanged = widget.onToneCurveChanged;
    final onToneCurveChangeEnd = widget.onToneCurveChangeEnd;
    final onColorCurveChanged = widget.onColorCurveChanged;
    final onColorCurveChangeEnd = widget.onColorCurveChangeEnd;
    final activeMask = widget.masks
        .where((m) => m.id == widget.activeMaskId)
        .firstOrNull;
    final isBrushActive = activeMask?.type == MaskType.brush;
    final isColorRangeActive = activeMask?.type == MaskType.colorRange;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: _controlsPanelWidth,
      color: DarkmoonColors.panel,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Histogram + photo info are pinned at the very top of the
              // column so they stay put as the first item even while a
              // mask is being created/edited below — the mask UI and every
              // adjustment section scroll independently beneath them.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  _controlsPanelInset,
                  14,
                  _controlsPanelInset,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        l10n.histogramTitle,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    HistogramView(histogram: histogram),
                    PhotoMetadataView(metadata: widget.metadata),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    _controlsPanelInset,
                    0,
                    _controlsPanelInset,
                    14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.cropOverlayActive) ...[
                        _CropTransformPanel(
                          params: widget.cropTransform,
                          onChanged: widget.onCropTransformChanged,
                          onChangeEnd: widget.onCropTransformChangeEnd,
                          aspectRatio: widget.cropAspectRatio,
                          onAspectRatioChanged: widget.onCropAspectRatioChanged,
                          onDone: widget.onToggleCropOverlay,
                          onReset: widget.onResetCropTransform,
                        ),
                        const SizedBox(height: 12),
                      ],
                      MaskSelector(
                        masks: widget.masks,
                        activeId: widget.activeMaskId,
                        onSelect: widget.onSelectMask,
                        onAdd: widget.onAddMask,
                        onToggleEnabled: widget.onToggleMaskEnabled,
                        onToggleInverted: widget.onToggleMaskInverted,
                        onClone: widget.onCloneMask,
                        onDelete: widget.onDeleteMask,
                        onOpacityChanged: widget.onMaskOpacityChanged,
                        onOpacityChangeEnd: widget.onMaskOpacityChangeEnd,
                        overlayVisible: widget.maskOverlayVisible,
                        onToggleOverlayVisible:
                            widget.onToggleMaskOverlayVisible,
                        overlayOpacity: widget.maskOverlayOpacity,
                        onOverlayOpacityChanged:
                            widget.onMaskOverlayOpacityChanged,
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
                                  activeMask!.colorRange.r.round().clamp(
                                    0,
                                    255,
                                  ),
                                  activeMask.colorRange.g.round().clamp(0, 255),
                                  activeMask.colorRange.b.round().clamp(0, 255),
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: DarkmoonColors.border,
                                ),
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
                            decimals: 0,
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
                            decimals: 0,
                            onChanged: widget.onColorRangeFeatherChanged,
                            onChangeEnd: widget.onColorRangeFeatherChangeEnd,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      for (final entry in _sections.entries) ...[
                        const SizedBox(height: 10),
                        // `values`/`onChanged`/`onChangeEnd` already resolve to
                        // either the global layer or the active mask's own (see
                        // the comment below on Tone Curve/Color Mixer/etc.), so
                        // the toggle works identically for both — no separate
                        // mask-vs-global branch needed.
                        _SectionHeader(
                          label: _sectionLabel(l10n, entry.key),
                          collapsed: _collapsed.contains(entry.key),
                          onTap: () => _toggleSection(entry.key),
                          enabled:
                              (values[_categoryEnabledKey(entry.key)] ?? 1) !=
                              0,
                          onEnabledChanged: (v) {
                            final key = _categoryEnabledKey(entry.key);
                            onChanged(key, v ? 1 : 0);
                            onChangeEnd(key, v ? 1 : 0);
                          },
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
                                valueSuffix: spec.valueSuffix,
                                onChanged: (v) => onChanged(spec.name, v),
                                onChangeEnd: (v) => onChangeEnd(spec.name, v),
                              ),
                            ),
                        // Tone Curve/Color Curve/Color Mixer/Color Grading/
                        // Effects are available for masks too — `curves`/
                        // `onChanged`/`onChangeEnd` above already resolve to
                        // either the global state or the active mask's own
                        // (see _activeCurves/_onActiveChanged), so no extra
                        // mask-vs-global branching is needed here. Placed after
                        // Detail rather than interleaved with the _sections
                        // loop, so Presence/Detail stay right after Tone, ahead
                        // of the advanced color tools.
                        if (entry.key == 'DETAIL') ...[
                          _SectionHeader(
                            label: l10n.sectionToneCurve,
                            collapsed: _collapsed.contains('TONE CURVE'),
                            onTap: () => _toggleSection('TONE CURVE'),
                            enabled:
                                (values[_categoryEnabledKey('TONE CURVE')] ??
                                    1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('TONE CURVE');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
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
                          _SectionHeader(
                            label: l10n.sectionColorCurve,
                            collapsed: _collapsed.contains('COLOR CURVE'),
                            onTap: () => _toggleSection('COLOR CURVE'),
                            enabled:
                                (values[_categoryEnabledKey('COLOR CURVE')] ??
                                    1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('COLOR CURVE');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
                          ),
                          if (!_collapsed.contains('COLOR CURVE')) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: _ColorChannelTabs(
                                active: _activeColorChannel,
                                onSelect: (channel) => setState(
                                  () => _activeColorChannel = channel,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ToneCurveEditor(
                                key: ValueKey(_activeColorChannel),
                                points: _channelPoints(
                                  curves,
                                  _activeColorChannel,
                                ),
                                lineColor: _channelColor(_activeColorChannel),
                                onChanged: (points) => onColorCurveChanged(
                                  _activeColorChannel,
                                  points,
                                ),
                                onChangeEnd: (points) => onColorCurveChangeEnd(
                                  _activeColorChannel,
                                  points,
                                ),
                              ),
                            ),
                          ],
                          _SectionHeader(
                            label: l10n.sectionColorMixer,
                            collapsed: _collapsed.contains('COLOR MIXER'),
                            onTap: () => _toggleSection('COLOR MIXER'),
                            enabled:
                                (values[_categoryEnabledKey('COLOR MIXER')] ??
                                    1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('COLOR MIXER');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
                          ),
                          if (!_collapsed.contains('COLOR MIXER')) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 6,
                                bottom: 10,
                              ),
                              child: _MixerModeTabs(
                                active: _mixerViewMode,
                                onSelect: (mode) =>
                                    setState(() => _mixerViewMode = mode),
                              ),
                            ),
                            if (_mixerViewMode == 'Mixer') ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _MixerChannelDots(
                                  active: _activeMixerChannel,
                                  onSelect: (channel) => setState(
                                    () => _activeMixerChannel = channel,
                                  ),
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
                                        values['Mixer$_activeMixerChannel$suffix'] ??
                                        0,
                                    decimals: 0,
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
                            ] else
                              for (final suffix in const [
                                'Hue',
                                'Saturation',
                                'Luminance',
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          _mixerSliderLabel(l10n, suffix),
                                          style: TextStyle(
                                            color: DarkmoonColors.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                      for (final channel in _mixerChannels)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: SliderRow(
                                            name: _mixerChannelLabel(
                                              l10n,
                                              channel,
                                            ),
                                            min: -100,
                                            max: 100,
                                            value:
                                                values['Mixer$channel$suffix'] ??
                                                0,
                                            decimals: 0,
                                            defaultValue: 0,
                                            trackColors: [
                                              DarkmoonColors.textMuted,
                                              _mixerChannelColor(channel),
                                            ],
                                            onChanged: (v) => onChanged(
                                              'Mixer$channel$suffix',
                                              v,
                                            ),
                                            onChangeEnd: (v) => onChangeEnd(
                                              'Mixer$channel$suffix',
                                              v,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                          ],
                          _SectionHeader(
                            label: l10n.sectionColorGrading,
                            collapsed: _collapsed.contains('COLOR GRADING'),
                            onTap: () => _toggleSection('COLOR GRADING'),
                            enabled:
                                (values[_categoryEnabledKey('COLOR GRADING')] ??
                                    1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('COLOR GRADING');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
                          ),
                          if (!_collapsed.contains('COLOR GRADING')) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 6,
                                bottom: 10,
                              ),
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
                                    hue:
                                        values['Grade${_activeGradeRange}Hue'] ??
                                        0,
                                    saturation:
                                        values['Grade${_activeGradeRange}Saturation'] ??
                                        0,
                                    onChanged: (hue, sat) {
                                      onChanged(
                                        'Grade${_activeGradeRange}Hue',
                                        hue,
                                      );
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
                                    values['Grade${_activeGradeRange}Luminance'] ??
                                    0,
                                decimals: 0,
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
                          _SectionHeader(
                            label: l10n.sectionEffects,
                            collapsed: _collapsed.contains('EFFECTS'),
                            onTap: () => _toggleSection('EFFECTS'),
                            enabled:
                                (values[_categoryEnabledKey('EFFECTS')] ?? 1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('EFFECTS');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
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
            ],
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

/// Toggles the Color Mixer between its two display modes — matches
/// Lightroom's own Mixer/HSL tabs, which control the exact same 24
/// underlying values ("Mixer" + channel + "Hue/Saturation/Luminance"),
/// just grouped differently: by channel (below, one at a time) or by
/// attribute (all 8 channels stacked per Hue/Saturation/Luminance group).
class _MixerModeTabs extends StatelessWidget {
  const _MixerModeTabs({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  static const _modes = ['Mixer', 'HSL'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        for (final mode in _modes)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: mode == active
                    ? DarkmoonColors.accent.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onSelect(mode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: mode == active
                            ? DarkmoonColors.accent
                            : DarkmoonColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      mode == 'Mixer'
                          ? l10n.mixerModeMixerLabel
                          : l10n.mixerModeHslLabel,
                      style: TextStyle(
                        color: mode == active
                            ? DarkmoonColors.accent
                            : DarkmoonColors.textSecondary,
                        fontSize: 11,
                        fontWeight: mode == active
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
                            child: Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: double.infinity,
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
                                      : Image.memory(
                                          thumbnail,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                Positioned(
                                  left: 3,
                                  top: 3,
                                  child: _FileTypeBadge(
                                    label: file.typeLabel,
                                    isRaw: file.isRaw,
                                  ),
                                ),
                              ],
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

/// Small file-type pill shown over each filmstrip thumbnail's corner —
/// RAW extensions (RAF/CR2/NEF/...) get the accent color to stand out as
/// the app's primary format, common image formats (JPG/PNG/...) get a
/// neutral gray.
class _FileTypeBadge extends StatelessWidget {
  const _FileTypeBadge({required this.label, required this.isRaw});

  final String label;
  final bool isRaw;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: isRaw
            ? DarkmoonColors.accent.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isRaw ? DarkmoonColors.background : Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
