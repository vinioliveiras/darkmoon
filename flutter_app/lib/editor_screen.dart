import 'dart:async';
import 'dart:io' show Directory, File, Process;
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
import 'catalog/native_source_cache.dart';
import 'catalog/photo_preset_store.dart';
import 'catalog/preview_cache_dir.dart';
import 'catalog/ai_enhance_cache.dart';
import 'catalog/ai_enhance_cache_dir.dart';
import 'catalog/cloud_denoise_cache.dart';
import 'catalog/cloud_denoise_cache_dir.dart';
import 'catalog/thumbnail_cache.dart';
import 'catalog/thumbnail_cache_dir.dart';
import 'cloud_denoise/cloud_denoise_provider.dart';
import 'cloud_denoise/cloud_denoise_token_store.dart';
import 'diagnostics/dev_log.dart';
import 'export/export_job.dart';
import 'l10n/app_localizations.dart';
import 'native/common_image_thumbnail.dart';
import 'native/edit_source.dart';
import 'native/edit_source_ai_enhance.dart';
import 'native/edit_source_cloud_denoise.dart';
import 'native/libraw.dart' show RawMetadata, extractRawMetadata;
import 'native/thumbnail_loader.dart';
import 'presets/preset.dart';
import 'presets/preset_store.dart';
import 'presets/preset_xmp.dart';
import 'presets/preset_zip.dart';
import 'raw_files.dart';
import 'render/ai_denoise.dart';
import 'render/ai_enhance_job.dart'
    show
        AiEnhanceCancellationToken,
        AiEnhanceModelInfo,
        AiEnhanceProgress,
        CustomDenoiseModelFallback;
import 'render/color_profile.dart';
import 'render/histogram.dart';
import 'render/lens_correction.dart';
import 'render/luminance.dart' show luminanceRgb;
import 'render/mask.dart';
import 'render/gpu/gpu_capability.dart';
import 'render/gpu/render_job_gpu.dart';
import 'render/render.dart' show RenderStage;
import 'render/render_job.dart';
import 'render/crop_transform.dart';
import 'render/render_params.dart';
import 'render/tone_curve.dart';
import 'render/white_balance.dart';
import 'settings/app_settings.dart';
import 'theme.dart';
import 'widgets/about_dialog.dart';
import 'widgets/ai_denoise_dialog.dart';
import 'widgets/animated_dialog.dart';
import 'widgets/brush_mask_overlay.dart';
import 'widgets/color_range_overlay.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/color_wheel.dart';
import 'widgets/dialog_chrome.dart' show dialogShape;
import 'widgets/export_dialog.dart';
import 'widgets/folder_sidebar.dart';
import 'widgets/gradient_mask_overlay.dart';
import 'widgets/histogram_view.dart';
import 'widgets/lens_correction_panel.dart';
import 'widgets/mask_selector.dart';
import 'widgets/photo_metadata_view.dart';
import 'widgets/preset_panel.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/slider_row.dart';
import 'widgets/styled_dropdown.dart';
import 'widgets/text_prompt_dialog.dart';
import 'widgets/tone_curve_editor.dart';
import 'widgets/white_balance_eyedropper_overlay.dart';

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
    case 'GrainAmount':
      return l10n.sliderGrainAmount;
    case 'GrainSize':
      return l10n.sliderGrainSize;
    case 'GrainRoughness':
      return l10n.sliderGrainRoughness;
    case 'ParamCurveShadows':
      return l10n.sliderParamCurveShadows;
    case 'ParamCurveDarks':
      return l10n.sliderParamCurveDarks;
    case 'ParamCurveLights':
      return l10n.sliderParamCurveLights;
    case 'ParamCurveHighlights':
      return l10n.sliderParamCurveHighlights;
    case 'ParamCurveShadowSplit':
      return l10n.sliderParamCurveShadowSplit;
    case 'ParamCurveMidtoneSplit':
      return l10n.sliderParamCurveMidtoneSplit;
    case 'ParamCurveHighlightSplit':
      return l10n.sliderParamCurveHighlightSplit;
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

/// Temporary: while export perf is being profiled, the success snackbar
/// appends a per-stage timing breakdown (source / render sub-stages /
/// encode / write). Flip to true to bring it back. The underlying
/// instrumentation in `export_job.dart` / `render_parallel.dart` stays —
/// it's cheap and only surfaces here. Remove all of it (this flag + the
/// `timings` plumbing) once export is settled. See PENDING "Débitos".
const bool _showExportTimings = false;

/// Off again 2026-08-29: even after the isotonic-regression re-fit + the
/// stale-cache fix, real-photo testing still came back overexposed on the
/// backlit/hazy test photo — with a preset applied, which should have
/// pulled it back down. Three rounds of "fixed it" that weren't, once
/// tested live, is a sign the validation loop (my own eyeballing of a
/// couple of pairs) isn't catching what real use does. Paused rather than
/// spending a fourth round guessing — see
/// project_darkmoon_color_profile.md for what's been tried and why each
/// attempt fell short. The loader, RenderParams plumbing, GPU guard and
/// _effectiveBaseContrast fallback all stay in place for whenever this
/// gets picked back up with a better way to validate before shipping.
const bool _colorProfileEnabled = false;

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
/// hard with the rest of startup (settings/catalog/thumbnail loads, and
/// especially the thumbnail-decode batch) for CPU cores. Kept low
/// deliberately: these isolates also run at below-normal thread priority
/// (see [lowerBackgroundThreadPriority]).
const _previewPreloadConcurrency = 2;

/// [_preloadPreviewCache] holds off until the thumbnail batch has produced
/// at least this many thumbnails (or has finished) — enough to fill the
/// visible filmstrip, so speculative RAW decodes for photos nobody's
/// looked at don't compete with the thumbnails the user is waiting to
/// see. Past that point the two run concurrently, which is fine: the
/// preload isolates run at below-normal priority.
const _thumbnailsBeforePreload = 24;

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
Map<String, double> _withCategoriesApplied(
  Map<String, double> values, {
  double asShotKelvin = 5500,
  double asShotTint = 0,
}) {
  bool disabled(String category) {
    // Every other section defaults to on (a brand-new photo has no
    // catalog entry yet, so the key is absent) — EFFECTS (Grain +
    // Vignette) is the one exception, off by default like Lens
    // Correction's own `enabled` flag. Motivated by a real user report:
    // film-look presets often set Grain/Texture/Sharpen together, and a
    // grain layer added *after* AI Enhance's denoise pass visually
    // masked the whole improvement — defaulting Effects off keeps that
    // choice deliberate instead of silently inherited from a preset.
    final defaultEnabled = category == 'EFFECTS' ? 0.0 : 1.0;
    return (values[_categoryEnabledKey(category)] ?? defaultEnabled) == 0;
  }

  final overrides = <String, double>{};
  for (final entry in _sections.entries) {
    if (disabled(entry.key)) {
      for (final spec in entry.value) {
        // A disabled White Balance section means "no WB shift" — that's
        // the per-photo as-shot value, not the fixed 5500/0 default.
        overrides[spec.name] = switch (spec.name) {
          'Temperature' => asShotKelvin,
          'Tint' => asShotTint,
          _ => spec.defaultValue,
        };
      }
    }
  }
  if (disabled('EFFECTS')) {
    for (final spec in _vignetteSliders) {
      overrides[spec.name] = spec.defaultValue;
    }
    for (final spec in _grainSliders) {
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
  if (disabled('TONE CURVE')) {
    // The point Tone Curve is reset in _withCurveCategoriesApplied (it
    // lives in PhotoCurves); the parametric region sliders are flat map
    // entries, so they're reset here.
    for (final spec in _parametricCurveSliders) {
      overrides[spec.name] = spec.defaultValue;
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

/// Storage key for the global Amount slider (below the preset list) —
/// lives in the same flat `_paramValues` map every other per-photo value
/// does, 0-150, default 100 (no-op). See [_withGlobalEditAmountApplied]'s
/// doc for what this actually does at render time.
const _globalEditAmountKey = 'GlobalEditAmount';

/// Default per-pass deposit rate for a new Flow-mask stroke — see
/// [BrushStroke.flow]'s doc. Matches RapidRAW's own default.
const defaultFlowAmount = 10.0;

/// Broadcasts Settings > "Interface animations" down the whole editor
/// tree, so any widget that plays a transition (section-card hover,
/// segmented-tab slide, zoom, the preview's post-edit fade-in) can ask
/// [AnimationsConfig.duration] for its actual duration instead of every
/// one of those widgets needing its own `animationsEnabled` constructor
/// parameter threaded down from `_EditorScreenState`.
class AnimationsConfig extends InheritedWidget {
  const AnimationsConfig({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AnimationsConfig>()?.enabled ??
      true;

  /// [base] when animations are on, [Duration.zero] (an instant snap)
  /// when the user turned them off.
  static Duration duration(BuildContext context, Duration base) =>
      of(context) ? base : Duration.zero;

  @override
  bool updateShouldNotify(AnimationsConfig oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Scales every continuous slider's deviation from its own default by
/// [_globalEditAmountKey]'s current value — the render-time-only
/// mechanism behind the Amount slider. Applied once here, at the single
/// choke point every render (CPU preview, GPU preview, export) already
/// reads `_paramValues` through — see `_EditorScreenState
/// ._effectiveParamValues`'s doc — so neither renderer needs its own copy
/// of this math and every consumer inherits it automatically, with zero
/// GPU/CPU-parity risk (the renderers themselves never change; only the
/// numbers fed into them do).
///
/// Deliberately NOT the same design as the old preset-only Amount: that
/// one directly rewrote `_paramValues` (the values the sliders show) on
/// every drag, which both looked like the sliders were being dragged out
/// from under the user and silently discarded any manual tweaks made
/// since the preset was applied, and stopped doing anything at all once
/// a manual edit had cleared the "applied preset" tracking (Amount was
/// only ever wired back to `_applyPreset`). This version never touches a
/// single stored slider value — every slider always shows exactly what
/// was set (by a preset or by hand), and Amount uniformly damps/amplifies
/// how strongly *all* of it renders, so it keeps working no matter what's
/// been manually adjusted since, and the user can always push a slider
/// further in either direction on top of the current Amount setting (the
/// "ponto base" — base point — the user asked for).
///
/// Global-layer only — masks (`_effectiveMasks`) intentionally don't get
/// their own Amount control, so this is never applied to mask values.
///
/// Excludes Temperature/Tint, same reasoning `_applyPreset` used to
/// exclude them from its own (now-removed) blend: Kelvin/tint aren't
/// naturally 0-centered deltas the way Exposure/Contrast are, and scaling
/// them toward some default at render time would conflict with the
/// as-shot-relative math the White Balance model already does elsewhere.
/// Also excludes anything not in [_defaultParamValues] — the per-section
/// enable toggles, White Balance mode, preserve-brightness, Crop/
/// Transform, [_globalEditAmountKey] itself — none of which are
/// continuous "how much of an effect" sliders.
Map<String, double> _withGlobalEditAmountApplied(Map<String, double> values) {
  final amount = values[_globalEditAmountKey] ?? 100.0;
  if (amount == 100.0) {
    return values; // no-op fast path — the overwhelmingly common case.
  }
  final fraction = amount / 100.0;
  final defaults = _defaultParamValues();
  final scaleKeys = defaults.keys.toSet()
    ..remove('Temperature')
    ..remove('Tint')
    ..remove(_globalEditAmountKey);
  final scaled = <String, double>{...values};
  for (final key in scaleKeys) {
    final value = values[key];
    if (value == null) {
      continue;
    }
    final base = defaults[key] ?? 0;
    scaled[key] = base + (value - base) * fraction;
  }
  return scaled;
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
      -150,
      150,
      0,
      gradientColors: [Color(0xFF3DD16B), Color(0xFFE362D8)],
    ),
  ],
  'TONE': [
    _SliderSpec('Exposure', -5, 5, 0, decimals: 2),
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

/// Film grain sliders (Lightroom's Effects panel) — like [_vignetteSliders],
/// global-only, kept out of [_sections]. Ranges match Lightroom's
/// `crs:GrainAmount` / `GrainSize` / `GrainFrequency`.
const _grainSliders = [
  _SliderSpec('GrainAmount', 0, 100, 0),
  _SliderSpec('GrainSize', 0, 100, 25),
  _SliderSpec('GrainRoughness', 0, 100, 50),
];

/// Lightroom's parametric Tone Curve — four region sliders plus the three
/// split points that set where each region ends. Lives under the Tone
/// Curve editor; toggled off with the TONE CURVE section switch. Split
/// defaults 25/50/75 match Lightroom (and RapidRAW's Curves.tsx).
const _parametricCurveSliders = [
  _SliderSpec('ParamCurveShadows', -100, 100, 0),
  _SliderSpec('ParamCurveDarks', -100, 100, 0),
  _SliderSpec('ParamCurveLights', -100, 100, 0),
  _SliderSpec('ParamCurveHighlights', -100, 100, 0),
  _SliderSpec('ParamCurveShadowSplit', 5, 90, 25),
  _SliderSpec('ParamCurveMidtoneSplit', 10, 94, 50),
  _SliderSpec('ParamCurveHighlightSplit', 20, 98, 75),
];

Map<String, double> _defaultParamValues() {
  return {
    // Not a real slider — a synthetic entry so Reset/first-open/photo-
    // switch all naturally land on 100% (no-op) like everything else here,
    // without a separate special case anywhere else in this file. Removed
    // from [_withGlobalEditAmountApplied]'s own scaling set explicitly —
    // it must never scale itself.
    _globalEditAmountKey: 100.0,
    for (final specs in _sections.values)
      for (final spec in specs) spec.name: spec.defaultValue,
    // Vignette lives outside [_sections] (masks don't get Effects) but
    // still needs its non-zero neutrals (Midpoint/Feather = 50) in the
    // defaults map, or Reset / first-open / preset-merge would leave
    // those keys missing and the sliders would snap to 0.
    for (final spec in _vignetteSliders) spec.name: spec.defaultValue,
    for (final spec in _grainSliders) spec.name: spec.defaultValue,
    for (final spec in _parametricCurveSliders) spec.name: spec.defaultValue,
    // Lens Correction is also global-only (see RenderJob.lensCorrection's
    // doc comment) and lives outside [_sections] for the same reason as
    // Vignette above -- seeded from the params class's own defaults
    // (distortion/vignette amount = 100, matching Lightroom's Profile
    // checkbox starting at full strength) rather than repeating them here.
    ...const LensCorrectionParams().toValues(),
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

class _EditorScreenState extends State<EditorScreen>
    with TickerProviderStateMixin {
  List<RawFile> _files = const [];
  int? _selectedIndex;
  bool _loading = false;
  ExportCancellationToken? _exportCancellation;

  /// Set while [_runNeuralEnhance] is awaiting the AI Enhance isolate, so
  /// [_cancelLoading] (the overlay's Cancel button) can actually stop the
  /// wait instead of just resetting the UI while the isolate keeps running
  /// underneath it — same role as [_exportCancellation] for exports.
  AiEnhanceCancellationToken? _aiEnhanceCancellation;

  /// Same role as [_aiEnhanceCancellation], for [_runCloudDenoise] — a
  /// cloud provider call can hang on the network for a while, and Cancel
  /// should actually stop waiting on it.
  CloudDenoiseCancellationToken? _cloudDenoiseCancellation;

  /// Every loading operation now surfaces through the compact docked
  /// [_HiddenLoadingIndicator] rather than the dark modal [_LoadingOverlay]
  /// — so this is effectively always true. The modal and its "Hide" path
  /// ([_hideLoadingOverlay]) are kept wired up but never triggered; flip
  /// this back to `false` (and restore the per-operation resets that used
  /// to set it) to bring the modal back.
  bool _loadingOverlayHidden = true;

  /// Whichever folder is actually loaded into [_files] right now — may be
  /// one of [AppSettings.libraryFolders] or one of its subfolders. Used to
  /// highlight the active folder in the sidebar. Null while a single file
  /// (from Open File / the recent-files list) is what's loaded — see
  /// [_currentSingleFile].
  String? _currentFolder;

  /// The single file loaded into [_files] right now (via Open File or the
  /// sidebar's recent-files list), or null when a folder is loaded
  /// instead. Mutually exclusive with [_currentFolder]; used to highlight
  /// the active entry in the sidebar's recent-files list.
  String? _currentSingleFile;
  final Map<String, Uint8List> _thumbnails = {};
  final Map<String, EditSourcePair> _editSources = {};

  /// The light preview-resolution render per photo — kept fresh by every
  /// settled render (phase 1). What the canvas shows when the dynamic
  /// full-quality preview is off.
  final Map<String, Uint8List> _renderedPreviews = {};

  /// The full-quality render per photo (phase 2), when the dynamic preview
  /// is on. Invalidated the moment a new edit's phase-1 render lands, so a
  /// present entry is always current. Kept separate from [_renderedPreviews]
  /// so toggling the setting just switches which one the canvas reads —
  /// nothing has to be re-rendered.
  final Map<String, Uint8List> _fullQualityPreviews = {};
  final Map<String, Histogram> _histograms = {};

  /// The render to show on the canvas for [path]: the full-quality one
  /// when the dynamic preview is on and it exists, else the light preview.
  Uint8List? _displayPreview(String path) {
    if (_settings.dynamicFullPreview) {
      final fq = _fullQualityPreviews[path];
      if (fq != null) {
        return fq;
      }
    }
    return _renderedPreviews[path];
  }

  /// Bumped once per *settled* (non-live) render that lands for the
  /// currently-selected photo — an applied edit, preset, reset, undo,
  /// redo, or a freshly-decoded photo's first frame — telling
  /// `_ImageArea._fadingImage` to fade the change in instead of popping.
  /// Never bumped for a live drag frame (those already update instantly
  /// with no animation, by design — see [_scheduleRender]).
  int _previewFadeGeneration = 0;

  /// Camera/lens/exposure info per photo (absolute path), shown below the
  /// histogram — loaded lazily on selection (cheap: no unpack/demosaic
  /// needed, see [extractRawMetadata]) rather than eagerly for the whole
  /// folder, since it's supplementary info only the selected photo needs.
  final Map<String, RawMetadata?> _metadata = {};
  int _folderGeneration = 0;

  /// The bundled Lensfun database, loaded once at startup (see
  /// [_loadLensProfiles]) -- empty until then, which just means Lens
  /// Correction resolves no profile (and so applies no correction) for
  /// whatever's rendered before it finishes loading.
  List<LensProfile> _lensProfiles = const [];

  /// The fitted "darkmoon Color" profile, if bundled (see
  /// [_loadColorProfile]). Null = no correction.
  ColorProfile? _colorProfile;

  /// The base contrast to actually render with: the profile's fitted tone
  /// curve *replaces* the hand-tuned [calBaseContrast] S when it's present,
  /// so they don't stack.
  double get _effectiveBaseContrast =>
      (_colorProfile != null && !_colorProfile!.toneIsIdentity)
      ? 0.0
      : _settings.baseContrast;

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

  /// Drives an eased transition of [_viewController]'s matrix for the
  /// zoom +/-/Fit toolbar buttons — instant scroll-wheel/pinch zoom and
  /// the double-click zoom stay a direct jump (already continuous/
  /// immediate interactions in their own right), but a button click
  /// benefits from an animated hop between zoom levels. See
  /// [_animateViewMatrixTo].
  late final AnimationController _zoomAnimController;
  late final CurvedAnimation _zoomAnimCurve;
  Matrix4Tween? _zoomAnimTween;

  /// Eases [_viewController]'s matrix from wherever it is now to
  /// [target] — an instant snap when Settings > animations is off (see
  /// [AnimationsConfig]). Re-targeting mid-flight (e.g. mashing the
  /// zoom-in button) just restarts the animation from the matrix that's
  /// currently on screen, not the previous target.
  void _animateViewMatrixTo(Matrix4 target) {
    final duration = AnimationsConfig.duration(
      context,
      const Duration(milliseconds: 220),
    );
    if (duration == Duration.zero) {
      _viewController.value = target;
      return;
    }
    _zoomAnimTween = Matrix4Tween(begin: _viewController.value, end: target);
    _zoomAnimController
      ..duration = duration
      ..forward(from: 0);
  }

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

  /// Dynamic full-resolution preview (`AppSettings.dynamicFullPreview`):
  /// after an edit settles, [_dynamicPreviewTimer] fires
  /// [_runDynamicFullPreview] which re-renders the selected photo at the
  /// sensor's native resolution in the background and swaps it onto the
  /// canvas. Any new edit / photo switch cancels the timer and (via
  /// [_renderRequestId]) discards a result already in flight.
  Timer? _dynamicPreviewTimer;
  static const _dynamicPreviewDelay = Duration(milliseconds: 1400);

  /// The decoded native-resolution source cache — same [ThumbnailCacheManager]
  /// month-file format / sha1 key as the thumbnail and preview caches, in
  /// its own `previews/native` namespace, trimmed by
  /// [evictNativeSourceCache] since these blobs are big.
  ThumbnailCacheManager? _nativeSourceCache;
  String? _nativeSourceCacheDir;

  /// The selected photo's decoded native-resolution source, held only for
  /// that one photo (cleared on switch). Populated lazily the first time
  /// full-quality mode kicks in — from [_nativeSourceCache] if warm,
  /// otherwise a full RAW decode that then warms the cache.
  EditSource? _fullQualitySource;
  String? _fullQualitySourcePath;
  bool _decodingFullQuality = false;

  /// The native source downscaled once to [_fullQualityWorkingRes] — the
  /// buffer settled renders run against while full-quality mode is active
  /// for this photo. Cleared on photo switch / toggle-off / a change to
  /// the full-quality resolution setting.
  EditSource? _fullQualityScaled;

  bool _fullQualityReadyFor(String path) =>
      _fullQualitySourcePath == path && _fullQualitySource != null;

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

  /// True when the in-flight [_isApplyingAiDenoise] render is turning AI
  /// Denoise back *off* rather than applying/adjusting it — swaps the
  /// overlay message from "Applying" to "Disabling" so the wording
  /// matches what the user actually just did.
  bool _aiDenoiseDisabling = false;

  /// True while item 13's neural Enhance pipeline itself is running
  /// (`_runNeuralEnhance`) — this is the slow step (denoise + upscale
  /// through the ONNX models, 30s-2min on a full photo, worse on CPU
  /// fallback), so it needs its own loading overlay entry distinct from
  /// [_isApplyingAiDenoise] (which only covers the quick render pass
  /// *after* the enhanced source is ready). Without this, the dialog
  /// closed and nothing visible happened for the whole duration of the
  /// actual AI work — looked exactly like the button did nothing.
  bool _isRunningNeuralEnhance = false;

  /// Real per-tile progress for [_isRunningNeuralEnhance], forwarded from
  /// `decodeEditSourcesWithAiEnhance`'s `onStage` callback. Null while the
  /// pipeline hasn't reported a tile yet (cache lookup / RAW decode still
  /// in progress) — the overlay shows an indeterminate message then.
  AiEnhanceProgress? _aiEnhanceProgress;

  /// Same role as [_isRunningNeuralEnhance], for [_runCloudDenoise] — a
  /// cloud provider call is its own slow step (network upload + provider
  /// processing + download), distinct from [_isApplyingAiDenoise].
  bool _isRunningCloudDenoise = false;

  /// Coarse stage name ('uploading'/'processing'/'downloading', or a
  /// provider-specific one — see each `CloudDenoiseProvider`'s own
  /// `onStage` calls) for the loading overlay while [_isRunningCloudDenoise]
  /// — there's no per-tile progress the way the ONNX pipeline has, just
  /// this one linear HTTP flow.
  String? _cloudDenoiseStage;

  /// Real progress for the loading overlay while a folder's thumbnails are
  /// being decoded — [_thumbnailsTotal] is 0 until the file list is known.
  int _thumbnailsLoaded = 0;
  int _thumbnailsTotal = 0;

  /// Coalesces the rebuilds [_loadThumbnails]'s concurrent workers trigger
  /// as each thumbnail lands — see [_scheduleThumbnailUiFlush]. Non-null
  /// only while a flush is pending.
  Timer? _thumbnailUiFlushTimer;

  /// Completed once [_loadThumbnails] has filled the visible filmstrip (or
  /// finished the whole batch) — [_preloadPreviewCache] awaits it before
  /// starting any speculative RAW decode. Recreated per folder load; any
  /// prior one is completed when the next load starts or loading is
  /// cancelled, so a waiter never hangs.
  Completer<void>? _visibleThumbnailsReady;

  /// Saved slider values per photo (absolute path), persisted to disk.
  /// Loaded once at startup; not guarded against edits made before that
  /// finishes, since reading a small JSON file is effectively instant next
  /// to how long opening a folder via a native file dialog takes.
  Map<String, Map<String, double>> _edits = {};
  Timer? _catalogSaveTimer;
  Timer? _thumbnailFlushTimer;

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

  /// Which preset id was last applied to each photo — persisted (its own
  /// tiny file) so the Presets panel still marks a preset as applied after
  /// an app restart, not only within a session. Purely a UI hint; the
  /// actual edit lives in [_edits]/[_photoCurves].
  Map<String, String> _photoPresets = {};

  /// The mask stack for whichever photo is selected. Mirrors
  /// [_paramValues]/[_currentCurves]'s "live copy of the saved value"
  /// pattern.
  List<MaskLayer> _currentMasks = [];

  /// The last photo's edits copied via the image's right-click menu — a
  /// session-only clipboard (not persisted). Null = nothing copied yet, so
  /// "Paste Edits" stays disabled. Deliberately doesn't include crop/lens
  /// (those are framing/geometry, not "look" — pasting them onto a
  /// different photo would usually be wrong).
  ({Map<String, double> values, PhotoCurves curves, List<MaskLayer> masks})?
  _copiedEdits;

  /// Paths whose decode failed because the file itself couldn't be found —
  /// see [_loadEditSourceAndRender]. Session-only; a path is optimistically
  /// dropped and re-tried the next time it's selected, in case the file
  /// (or its drive) came back.
  final Set<String> _missingFiles = {};

  /// Which layer the controls panel is currently editing —
  /// [imageMaskId] (the whole photo, i.e. the existing global
  /// adjustments) or one of [_currentMasks]'s ids.
  String _activeMaskId = imageMaskId;

  /// Whether the active mask's on-canvas overlay (shaded coverage area,
  /// handles, brush cursor) is drawn — a session-wide UI preference, not
  /// per-photo state, so it isn't persisted with the catalog.
  bool _maskOverlayVisible = true;

  /// True while the White Balance eyedropper is armed — the next click on
  /// the preview samples a neutral and sets Temperature/Tint. Session-only.
  bool _wbEyedropperActive = false;

  /// True while the Straighten slider is actively being dragged (item 28)
  /// — lets [CropOverlay] show a denser guide grid only during that
  /// interaction, matching Lightroom. Session-only.
  bool _straighteningActive = false;

  void _setStraighteningActive(bool value) {
    if (_straighteningActive == value) {
      return;
    }
    setState(() => _straighteningActive = value);
  }

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
    MaskType.radialGradient: 0.00,
    MaskType.brush: 0.01,
    MaskType.colorRange: 0.20,
    MaskType.luminance: 0.20,
    MaskType.flow: 0.01,
  };

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

  /// Current Flow-mask tool setting — the per-pass deposit rate (0..100)
  /// baked into each new stroke at draw time, mirroring how [_brushRadius]
  /// etc. are live tool settings rather than derived from stored geometry.
  /// Only meaningful while a [MaskType.flow] mask is active.
  double _brushFlow = defaultFlowAmount;

  /// The user's saved preset library — not per-photo, applies to whatever
  /// photo is selected when the user picks one.
  List<Preset> _presets = [];

  /// ID of the preset currently applied to the selected photo (if any).
  /// Tracked separately from live values so the preset list keeps it
  /// highlighted even after the user changes the global Amount slider
  /// (see [_globalEditAmountKey]) — it only clears when the user makes a
  /// manual edit or switches photos.
  String? _appliedPresetId;

  bool _exporting = false;

  /// Which stage the in-progress export is on, so the loading overlay can
  /// show real (if stage-granular, not percentage-granular) progress
  /// instead of an indeterminate spinner for the whole export.
  ExportStage? _exportStage;

  /// A brief, non-cancellable confirmation shown in the same docked bar
  /// real loading operations use (see [_LoadingInfo.isStatus]) — e.g.
  /// "Done!" after an export, in place of a SnackBar for the common case
  /// (Developer Mode off) where the full technical detail a SnackBar can
  /// hold isn't needed, just a quick "it worked" beat. Cleared by
  /// [_transientStatusTimer] a few seconds after being set.
  String? _transientStatus;
  Timer? _transientStatusTimer;

  /// Shows [message] in the docked status bar for [duration], then clears
  /// it automatically — see [_transientStatus].
  void _showTransientStatus(String message, {Duration? duration}) {
    _transientStatusTimer?.cancel();
    setState(() => _transientStatus = message);
    _transientStatusTimer = Timer(duration ?? const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _transientStatus = null);
      }
    });
  }

  /// The result of a background operation (export, AI Enhance), reported
  /// the way that fits who's actually looking: Developer Mode on shows
  /// [detail] in full via a SnackBar with a copy button (raw paths,
  /// timings, error text — exactly what a bug report needs, and exactly
  /// what an everyday export doesn't); off, [status] (if given — pass
  /// null for a mid-operation FYI that isn't really a completion event,
  /// like the CPU-fallback notice) shows as a brief non-technical "Done!"
  /// beat in the docked status bar instead of a SnackBar.
  void _notify({required String detail, String? status}) {
    if (_settings.devLogging) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(detail),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.copyButton,
            onPressed: () => Clipboard.setData(ClipboardData(text: detail)),
          ),
        ),
      );
    } else if (status != null) {
      _showTransientStatus(status);
    }
  }

  AppSettings _settings = const AppSettings();

  late final AppLifecycleListener _lifecycleListener;

  /// Owns focus for the app-wide keyboard shortcuts (undo/redo, Before/
  /// After). A bare `Focus(autofocus: true)` only requests focus once, the
  /// first time it's inserted into the tree — after an alt-tab away and
  /// back, Flutter's embedding doesn't hand focus back to it on its own,
  /// so Ctrl+Z/Ctrl+Y silently stop doing anything until the user clicks
  /// something focusable. [_lifecycleListener]'s `onResume`/`onShow`
  /// explicitly reclaim it once the window is frontmost again.
  final FocusNode _shortcutsFocusNode = FocusNode(debugLabel: 'shortcuts');

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
    _zoomAnimController = AnimationController(vsync: this);
    _zoomAnimCurve = CurvedAnimation(
      parent: _zoomAnimController,
      curve: Curves.easeOutCubic,
    )..addListener(() {
      final tween = _zoomAnimTween;
      if (tween != null) {
        _viewController.value = tween.evaluate(_zoomAnimCurve);
      }
    });
    unawaited(_loadEdits());
    unawaited(_loadPhotoCurves());
    unawaited(_loadPhotoMasks());
    unawaited(_loadPhotoPresets());
    unawaited(_loadPresetsState());
    unawaited(_loadSettings());
    unawaited(_loadThumbnailCache());
    unawaited(_loadLensProfiles());
    if (_colorProfileEnabled) {
      unawaited(_loadColorProfile());
    }
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequested,
      // Alt-tabbing back to the window doesn't hand keyboard focus back to
      // any particular widget on its own — reclaim it for the shortcuts
      // scope explicitly. onShow/onResume can fire independently
      // depending on platform, so handle both the same way; requestFocus()
      // on an already-focused node is a harmless no-op.
      onResume: _reclaimShortcutsFocus,
      onShow: _reclaimShortcutsFocus,
    );
  }

  void _reclaimShortcutsFocus() {
    if (!_shortcutsFocusNode.hasFocus) {
      _shortcutsFocusNode.requestFocus();
    }
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

  Future<void> _loadNativeSourceCache() async {
    final dir = await resolveNativeSourceCacheDir();
    if (!mounted) {
      return;
    }
    setState(() {
      _nativeSourceCacheDir = dir;
      _nativeSourceCache = ThumbnailCacheManager(dir);
    });
  }

  /// Persists [jpegBytes] as [path]'s native-source cache entry and trims
  /// the cache if it's over budget. Native sources are written rarely
  /// (once per photo, ever), so — unlike the thumbnail batch — this
  /// flushes immediately rather than deferring.
  Future<void> _storeNativeSource(String path, List<int> jpegBytes) async {
    final cache = _nativeSourceCache;
    final dir = _nativeSourceCacheDir;
    if (cache == null) {
      return;
    }
    await cache.store(path, Uint8List.fromList(jpegBytes));
    await cache.flush();
    if (dir != null) {
      await evictNativeSourceCache(dir);
    }
  }

  /// Loads the bundled lens correction database (a few MB JSON asset) --
  /// deliberately not awaited from [initState] (see every other `_load*`
  /// call there), so the first frame isn't blocked on it. If Lens
  /// Correction was already on for the photo showing when this finishes,
  /// the render it produced before now had nothing to resolve a profile
  /// against, so it's redone once the database is actually usable.
  /// Loads the bundled "darkmoon Color" per-hue correction, if one has been
  /// fitted and dropped in (`assets/color_profiles/darkmoon_fuji.json` —
  /// see `tool/build_color_profile.dart`). Missing asset = no correction,
  /// same as before profiles existed. Not awaited from initState; a
  /// re-render is kicked once it lands so the open photo picks it up.
  Future<void> _loadColorProfile() async {
    ColorProfile? profile;
    try {
      final raw = await rootBundle.loadString(
        'assets/color_profiles/darkmoon_fuji.json',
      );
      profile = ColorProfile.decode(raw);
    } catch (_) {
      profile = null; // not bundled — fine
    }
    if (!mounted || profile == null) {
      return;
    }
    setState(() => _colorProfile = profile);
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected != null) {
      _scheduleRender(live: false);
    }
  }

  Future<void> _loadLensProfiles() async {
    final profiles = await LensProfileDatabase.load();
    if (!mounted) {
      return;
    }
    setState(() => _lensProfiles = profiles);
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected != null && _lensCorrection.enabled) {
      unawaited(_renderPreview(selected.path));
    }
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

  Future<void> _loadPhotoPresets() async {
    final photoPresets = await loadPhotoPresets();
    if (!mounted) {
      return;
    }
    setState(() {
      _photoPresets = photoPresets;
      // If the restored photo already has a preset marker, adopt it now
      // (its edit values were restored from the catalog on selection).
      final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
      if (selected != null && _appliedPresetId == null) {
        _appliedPresetId = _photoPresets[selected.path];
      }
    });
  }

  Future<void> _loadPresetsState() async {
    final presets = await loadPresets();
    if (!mounted) {
      return;
    }
    setState(() => _presets = presets);
  }

  /// Applies [preset]'s slider values and curves to the selected photo, at
  /// their full stored strength — like every other adjustment, this only
  /// touches the global ("Image") layer, never the active mask, matching
  /// how real Lightroom presets don't carry local adjustments either.
  ///
  /// Unlike this app's previous design, applying a preset no longer blends
  /// by the Amount slider under the preset list — [_globalEditAmountKey]
  /// is now a separate, persistent render-time multiplier over the
  /// *entire* current edit (this preset's values *and* whatever the
  /// sliders get manually adjusted to afterward), rather than something
  /// that rewrites `_paramValues` itself on every drag. See
  /// [_withGlobalEditAmountApplied]'s doc for why: the old design made
  /// dragging Amount visibly overwrite the right-hand sliders (confusing,
  /// and silently discarded any manual tweaks made since the preset was
  /// applied) and stopped doing anything at all once a manual edit had
  /// cleared [_appliedPresetId]. The new design fixes both — Amount keeps
  /// working regardless of what's been manually tweaked since, and never
  /// mutates a single slider's stored value.
  void _applyPreset(Preset preset) {
    if (_selectedIndex == null) {
      return;
    }
    // Only the continuous slider keys get overridden by the preset.
    // Everything else in the flat map — the per-section enable toggles
    // (_categoryEnabled_*), the White Balance mode, preserve-brightness,
    // [_globalEditAmountKey] itself — is a discrete/independent flag the
    // preset doesn't touch unless it explicitly sets it.
    final defaults = _defaultParamValues();
    final sliderKeys = defaults.keys.toSet()
      ..remove('Temperature')
      ..remove('Tint')
      // Amount is a separate, persistent setting (see
      // _withGlobalEditAmountApplied) — applying a preset never resets it.
      ..remove(_globalEditAmountKey);
    final newValues = <String, double>{..._paramValues};
    for (final key in sliderKeys) {
      newValues[key] = preset.values[key] ?? defaults[key] ?? 0;
    }
    for (final entry in preset.values.entries) {
      if (!sliderKeys.contains(entry.key) &&
          entry.key != 'Temperature' &&
          entry.key != 'Tint') {
        newValues[entry.key] = entry.value;
      }
    }
    // White Balance:
    //  - preset defines a real WB -> apply it (mode Custom, or the
    //    preset's own mode if it stored one);
    //  - preset defines none      -> reset to the photo's As Shot.
    // "Defines a real WB" ignores a bare 5500/0 with no mode key: that's
    // the old fixed neutral every pre-feature preset carries incidentally,
    // not an intended white-balance edit.
    final asShot = _asShotFor(_files[_selectedIndex!].path);
    final presetTemp = preset.values['Temperature'];
    final presetTint = preset.values['Tint'];
    final presetMode = preset.values[_wbModeKey];
    final presetDefinesWb =
        (presetTemp != null && presetTemp != wbDefaultKelvin) ||
        (presetTint != null && presetTint != wbDefaultTint) ||
        (presetMode != null && presetMode != WbMode.asShot.index.toDouble());
    if (presetDefinesWb) {
      newValues['Temperature'] = presetTemp ?? asShot.kelvin;
      newValues['Tint'] = presetTint ?? asShot.tint;
      newValues[_wbModeKey] = presetMode ?? WbMode.custom.index.toDouble();
    } else {
      newValues['Temperature'] = asShot.kelvin;
      newValues['Tint'] = asShot.tint;
      newValues[_wbModeKey] = WbMode.asShot.index.toDouble();
    }
    setState(() {
      _paramValues = newValues;
      _currentCurves = preset.curves;
      _appliedPresetId = preset.id;
    });
    _pushHistory();
    _scheduleRender(live: false);
    unawaited(_flushCurrentEdits());
    // Preset attributes this app can't render yet (see
    // Preset.unsupportedAttributes / preset_xmp.dart) are silently
    // ignored — no user-facing warning. The gap is tracked in the repo's
    // PENDING.md; the goal is full preset compatibility.
  }

  /// Whether [preset] is the one currently applied to the selected photo.
  /// Tracked via [_appliedPresetId] which is set on apply and cleared on
  /// any manual edit, photo switch, reset, or file reload — so the preset
  /// stays highlighted even when the user changes the global Amount
  /// slider (see [_globalEditAmountKey]), and only clears when they make
  /// a deliberate change.
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
    final draft = Preset(
      id: 'preset_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      // _catalogParams() drops Temperature/Tint while on "As Shot", so a
      // preset saved without a deliberate WB doesn't force one on other
      // photos.
      values: _catalogParams(),
      curves: _currentCurves,
    );
    final saved = await savePresetToFile(draft);
    if (!mounted) {
      return;
    }
    setState(() => _presets = _sortPresets([..._presets, saved]));
  }

  List<Preset> _sortPresets(List<Preset> presets) =>
      presets
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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
    final renamed = await renamePresetFile(preset, name);
    if (!mounted) {
      return;
    }
    setState(() {
      _presets = _sortPresets([
        for (final p in _presets)
          if (p.id == preset.id) renamed else p,
      ]);
      // The marker keys off the preset id (its file path), which the
      // rename changed — carry it over so the mark doesn't drop.
      if (_appliedPresetId == preset.id) {
        _appliedPresetId = renamed.id;
      }
    });
  }

  Future<void> _deletePreset(Preset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.dialogBackground,
        shape: dialogShape,
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
    await deletePresetFile(preset);
    if (!mounted) {
      return;
    }
    setState(() {
      _presets = [
        for (final p in _presets)
          if (p.id != preset.id) p,
      ];
    });
  }

  Future<void> _deletePresets(List<Preset> presets) async {
    if (presets.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.dialogBackground,
        shape: dialogShape,
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
    for (final preset in presets) {
      await deletePresetFile(preset);
    }
    if (!mounted) {
      return;
    }
    final ids = {for (final preset in presets) preset.id};
    setState(() {
      _presets = [
        for (final p in _presets)
          if (!ids.contains(p.id)) p,
      ];
    });
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

  /// Exports the multi-selected presets as a single `.zip` of `.xmp` files
  /// — the bulk counterpart to [_exportPreset], reachable from the Presets
  /// panel's selection-mode header.
  Future<void> _exportPresets(List<Preset> presets) async {
    if (presets.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final destPath = await FilePicker.saveFile(
      dialogTitle: l10n.presetExportManyDialogTitle,
      fileName: 'darkmoon-presets.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (destPath == null) {
      return;
    }
    await File(destPath).writeAsBytes(presetsToZipBytes(presets));
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
        imported.addAll(await importPresetsFromZipFile(path));
        continue;
      }
      final preset = await importPresetFromFile(path);
      if (preset != null) {
        imported.add(preset);
      }
    }
    if (imported.isEmpty || !mounted) {
      return;
    }
    setState(() => _presets = _sortPresets([..._presets, ...imported]));
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
    unawaited(_loadNativeSourceCache());
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
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => const DarkmoonAboutDialog(),
    );
  }

  void _openSettings() {
    final selectedMeta = _selectedIndex == null
        ? null
        : _metadata[_files[_selectedIndex!].path];
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(
        settings: _settings,
        nativeWidth: selectedMeta?.width,
        nativeHeight: selectedMeta?.height,
        onChanged: (next) {
          if (next.language != _settings.language) {
            widget.onLanguageChanged(next.language);
          }
          if (next.devLogging != _settings.devLogging) {
            DevLog.setEnabled(next.devLogging);
          }
          // Every cached EditSourcePair was decoded at the old preview
          // resolution — drop them so each photo picks up the new setting
          // next time it's selected, and redecode the one on screen right
          // now so the change is visible immediately instead of only on
          // the next photo switch.
          final previewResolutionChanged =
              next.previewResolution != _settings.previewResolution;
          final dynamicFullPreviewChanged =
              _settings.dynamicFullPreview != next.dynamicFullPreview;
          final fullQualityResChanged =
              next.dynamicFullPreview &&
              next.fullQualityPercent != _settings.fullQualityPercent;
          // The base "profile" contrast feeds every render — a change makes
          // every cached render stale, so drop them and re-render the open
          // photo now instead of only on the next photo switch.
          final baseContrastChanged =
              next.baseContrast != _settings.baseContrast;
          final currentPath = _selectedIndex == null
              ? null
              : _files[_selectedIndex!].path;
          setState(() {
            _settings = next;
            if (previewResolutionChanged) {
              _editSources.clear();
            }
            if (baseContrastChanged) {
              // Keep the open photo's current frame on screen until its
              // own re-render lands (below); the rest re-render on visit.
              _renderedPreviews.removeWhere((k, _) => k != currentPath);
              _fullQualityPreviews.removeWhere((k, _) => k != currentPath);
              _neutralPreviews.clear();
            }
            if (dynamicFullPreviewChanged && !next.dynamicFullPreview) {
              // Off: keep the caches — the canvas just switches to reading
              // [_renderedPreviews] (the light render, always kept fresh) —
              // but stop generating new full-quality renders.
              _dynamicPreviewTimer?.cancel();
              _fullQualitySource = null;
              _fullQualitySourcePath = null;
              _fullQualityScaled = null;
            } else if (fullQualityResChanged) {
              // Keep the decoded native source, just re-scale it next
              // render at the new percentage.
              _fullQualityScaled = null;
              _fullQualityPreviews.clear();
            }
          });
          unawaited(saveSettings(next));
          if (fullQualityResChanged ||
              (dynamicFullPreviewChanged && next.dynamicFullPreview)) {
            // Turned on (or changed the resolution) — kick a settled render
            // so full-quality mode re-engages for the open photo.
            final selected = _selectedIndex == null
                ? null
                : _files[_selectedIndex!];
            if (selected != null) {
              _scheduleRender(live: false);
            }
          }
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
          if (baseContrastChanged && currentPath != null) {
            _scheduleRender(live: false);
            if (_beforeAfterMode) {
              unawaited(_loadNeutralPreview(currentPath));
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
      _paramValues = _freshParamValues();
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
    _dynamicPreviewTimer?.cancel();
    _thumbnailFlushTimer?.cancel();
    _thumbnailUiFlushTimer?.cancel();
    _transientStatusTimer?.cancel();
    _completeVisibleThumbnailsReady();
    _viewController.dispose();
    _zoomAnimCurve.dispose();
    _zoomAnimController.dispose();
    _lifecycleListener.dispose();
    _shortcutsFocusNode.dispose();
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
      return _freshParamValues(path);
    }
    final base = {..._defaultParamValues(), ...saved};
    // No saved WB edit -> open on "As Shot" showing the camera's own
    // numbers, not a generic 5500 K.
    if (!saved.containsKey('Temperature')) {
      final asShot = _asShotFor(path);
      base['Temperature'] = asShot.kelvin;
      base['Tint'] = asShot.tint;
      base[_wbModeKey] = WbMode.asShot.index.toDouble();
    }
    return base;
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
    _edits[selected.path] = _catalogParams();
    _photoCurves[selected.path] = _currentCurves;
    _photoMasks[selected.path] = _currentMasks;
    await saveCatalog(_edits);
    await savePhotoCurves(_photoCurves);
    await savePhotoMasks(_photoMasks);
    _persistPhotoPreset(selected.path);
  }

  /// [_paramValues] as persisted to the catalog: Temperature/Tint/mode are
  /// dropped while the White Balance mode is "As Shot", so the camera
  /// as-shot value (which is metadata, not an edit) doesn't get frozen
  /// into the catalog or trip the filmstrip "edited" badge.
  Map<String, double> _catalogParams() {
    final out = Map<String, double>.from(_paramValues);
    final mode = (out[_wbModeKey] ?? 0).toInt();
    if (mode == WbMode.asShot.index) {
      out.remove('Temperature');
      out.remove('Tint');
      out.remove(_wbModeKey);
    }
    return out;
  }

  void _scheduleCatalogSave() {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    _catalogSaveTimer?.cancel();
    _catalogSaveTimer = Timer(_catalogSaveDebounce, () {
      _edits[selected.path] = _catalogParams();
      _photoCurves[selected.path] = _currentCurves;
      _photoMasks[selected.path] = _currentMasks;
      unawaited(saveCatalog(_edits));
      unawaited(savePhotoCurves(_photoCurves));
      unawaited(savePhotoMasks(_photoMasks));
      _persistPhotoPreset(selected.path);
    });
  }

  /// Syncs [_photoPresets] for [path] to the current [_appliedPresetId]
  /// (set it, or drop it when no preset is applied) and persists the file.
  void _persistPhotoPreset(String path) {
    final id = _appliedPresetId;
    if (id == null) {
      if (_photoPresets.remove(path) == null) {
        return;
      }
    } else {
      if (_photoPresets[path] == id) {
        return;
      }
      _photoPresets[path] = id;
    }
    unawaited(savePhotoPresets(_photoPresets));
  }

  /// Persists [thumbnailBytes] (the filmstrip thumbnail [_renderPreviewNow]
  /// just rendered from the current edit) to the on-disk thumbnail cache,
  /// so it reflects the edit on the next launch too — instead of only in
  /// [_thumbnails], which is lost on restart and left the filmstrip
  /// showing the camera-original preview again until the photo was
  /// reselected. Debounced the same way [_scheduleCatalogSave] is, so a
  /// burst of edits writes the cache's month file once, not once per edit.
  void _scheduleThumbnailCacheStore(String path, Uint8List thumbnailBytes) {
    final cache = _thumbnailCache;
    if (cache == null) {
      return;
    }
    unawaited(cache.store(path, thumbnailBytes));
    _thumbnailFlushTimer?.cancel();
    _thumbnailFlushTimer = Timer(_catalogSaveDebounce, () {
      unawaited(cache.flush());
    });
  }

  /// Whether [path] has any saved edit that isn't a fresh photo's defaults
  /// — curves, masks, or slider values — backing the filmstrip's "edited"
  /// badge. Checked against the *saved* catalog state ([_edits]/
  /// [_photoCurves]/[_photoMasks]) rather than live in-editor state, so
  /// every thumbnail in the strip can be checked, not just the selected
  /// photo (whose RAW source may not even be decoded yet).
  bool _isPhotoEdited(String path) {
    final masks = _photoMasks[path];
    if (masks != null && masks.isNotEmpty) {
      return true;
    }
    final curves = _photoCurves[path];
    if (curves != null && !curves.isIdentity) {
      return true;
    }
    final values = _edits[path];
    if (values == null) {
      return false;
    }
    final defaults = _defaultParamValues();
    final meta = _metadata[path];
    final asShotKelvin = meta?.asShotKelvin ?? wbDefaultKelvin;
    final asShotTint = meta?.asShotTint ?? wbDefaultTint;
    for (final entry in values.entries) {
      // Temperature/Tint sitting at the camera as-shot value (mode "As
      // Shot") is not a user edit even though it differs from 5500/0.
      if (entry.key == 'Temperature' && entry.value == asShotKelvin) {
        continue;
      }
      if (entry.key == 'Tint' && entry.value == asShotTint) {
        continue;
      }
      if (entry.key == _wbModeKey &&
          entry.value == WbMode.asShot.index.toDouble()) {
        continue;
      }
      if (entry.value != (defaults[entry.key] ?? 0)) {
        return true;
      }
    }
    return false;
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
        _fullQualityPreviews.clear();
        _histograms.clear();
        _metadata.clear();
        _neutralPreviews.clear();
        _beforeAfterMode = false;
      }
    });
    unawaited(saveSettings(next));
  }

  /// Resets [file]'s saved edits back to untouched — same fields
  /// [_resetActive] clears for the currently-open photo, but callable for
  /// ANY photo in the filmstrip (the context-menu entry point), not just
  /// whichever one happens to be selected right now.
  Future<void> _resetAllEditsFor(RawFile file) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.dialogBackground,
        shape: dialogShape,
        title: Text(l10n.filmstripResetEditsConfirmTitle),
        content: Text(l10n.filmstripResetEditsConfirmMessage(file.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.filmstripResetEditsAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final path = file.path;
    final isCurrentPhoto =
        _selectedIndex != null && _files[_selectedIndex!].path == path;
    setState(() {
      _edits.remove(path);
      _photoCurves.remove(path);
      _photoMasks.remove(path);
      if (isCurrentPhoto) {
        _paramValues = _freshParamValues(path);
        _currentCurves = identityPhotoCurves;
        _currentMasks = [];
        _activeMaskId = imageMaskId;
      }
    });
    if (isCurrentPhoto) {
      _resetHistory();
      unawaited(_renderPreview(path));
    }
    await saveCatalog(_edits);
    await savePhotoCurves(_photoCurves);
    await savePhotoMasks(_photoMasks);
  }

  /// Right-click on the image — "Copy Edits" / "Paste Edits", the same
  /// idea as Lightroom's Copy/Paste Settings but with no picker (everything
  /// copies: sliders, curves, masks — not crop/lens, see [_copiedEdits]'s
  /// own doc comment).
  Future<void> _showImageContextMenu(Offset globalPosition) async {
    if (_selectedIndex == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _copyEdits,
          child: Text(l10n.imageContextCopyEditsAction),
        ),
        PopupMenuItem(
          value: _copiedEdits == null ? null : _pasteEdits,
          enabled: _copiedEdits != null,
          child: Text(l10n.imageContextPasteEditsAction),
        ),
      ],
    );
    action?.call();
  }

  void _copyEdits() {
    setState(() {
      _copiedEdits = (
        values: {..._paramValues},
        curves: _currentCurves,
        masks: [..._currentMasks],
      );
    });
  }

  void _pasteEdits() {
    final copied = _copiedEdits;
    if (_selectedIndex == null || copied == null) {
      return;
    }
    setState(() {
      _paramValues = {...copied.values};
      _currentCurves = copied.curves;
      _currentMasks = [...copied.masks];
      _activeMaskId = imageMaskId;
      // A pasted edit isn't tied to the preset (if any) it came from.
      _appliedPresetId = null;
    });
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  bool get _hasCopiedEdits => _copiedEdits != null;

  /// [file]-scoped counterparts to [_copyEdits]/[_pasteEdits] for the
  /// filmstrip's context menu, which can target a photo other than the one
  /// currently open. The open photo still goes through the live in-memory
  /// state (history, live re-render, debounced save); any other photo's
  /// stored edits are read/written directly in the catalog maps and
  /// persisted right away — there's no "burst of edits" to debounce for a
  /// single background paste.
  bool _isSelected(RawFile file) =>
      _selectedIndex != null && _files[_selectedIndex!].path == file.path;

  void _copyEditsFor(RawFile file) {
    if (_isSelected(file)) {
      _copyEdits();
      return;
    }
    setState(() {
      _copiedEdits = (
        values: {...(_edits[file.path] ?? _freshParamValues(file.path))},
        curves: _photoCurves[file.path] ?? identityPhotoCurves,
        masks: [...(_photoMasks[file.path] ?? const [])],
      );
    });
  }

  void _pasteEditsFor(RawFile file) {
    final copied = _copiedEdits;
    if (copied == null) {
      return;
    }
    if (_isSelected(file)) {
      _pasteEdits();
      return;
    }
    setState(() {
      _edits[file.path] = {...copied.values};
      _photoCurves[file.path] = copied.curves;
      _photoMasks[file.path] = [...copied.masks];
      _photoPresets.remove(file.path);
    });
    unawaited(saveCatalog(_edits));
    unawaited(savePhotoCurves(_photoCurves));
    unawaited(savePhotoMasks(_photoMasks));
    unawaited(savePhotoPresets(_photoPresets));
  }

  /// Opens [file]'s containing folder in Windows Explorer with the file
  /// itself pre-selected — `explorer.exe /select,` is the standard way to
  /// do this; Explorer's own exit code is unreliable (it can return
  /// nonzero even on a completely successful reveal), so unlike other
  /// Process.run call sites in this app, the result isn't checked.
  Future<void> _revealInExplorer(RawFile file) async {
    // Verified empirically (this bit explorer.exe twice before landing
    // here): `/select,` and the path must be TWO separate elements of the
    // args array, with NO manual quoting around the path. Concatenating
    // them into one string — `'/select,${file.path}'`, with or without
    // added `"..."` — makes explorer.exe silently fail on any path
    // containing spaces and fall back to opening the user's Documents
    // folder instead of erroring, which is exactly the bug this fixes.
    await Process.run('explorer.exe', ['/select,', file.path]);
  }

  /// Sends [path] to the Recycle Bin instead of deleting it outright —
  /// `dart:io`'s `File.delete()` has no such option (it's a hard delete
  /// on every platform), so this shells out to the same
  /// `Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile` helper Windows
  /// Explorer's own "Delete" (not Shift+Delete) uses, via PowerShell —
  /// avoids pulling in a whole new Win32 FFI dependency just for this one
  /// call. Throws (via a nonzero exit code) if PowerShell itself reports
  /// failure, letting the caller's existing try/catch handle it the same
  /// way a failed `File.delete()` would have.
  Future<void> _moveToRecycleBin(String path) async {
    final escaped = path.replaceAll("'", "''");
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      "Add-Type -AssemblyName Microsoft.VisualBasic; "
          "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile("
          "'$escaped', "
          "'OnlyErrorDialogs', "
          "'SendToRecycleBin')",
    ]);
    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString().trim());
    }
  }

  /// Sends [file] to the Recycle Bin (after confirming) and forgets every
  /// piece of in-memory/persisted state keyed by its path — mirrors
  /// [_removeLibraryFolder]'s cleanup list, minus the fields that only
  /// make sense at folder granularity.
  Future<void> _deleteFile(RawFile file) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.dialogBackground,
        shape: dialogShape,
        title: Text(l10n.filmstripDeleteConfirmTitle),
        content: Text(l10n.filmstripDeleteConfirmMessage(file.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.filmstripDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final path = file.path;
    try {
      await _moveToRecycleBin(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(l10n.filmstripDeleteFailedMessage(file.name, '$e')),
          ),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final removedIndex = _files.indexWhere((f) => f.path == path);
    setState(() {
      _files = [
        for (final f in _files)
          if (f.path != path) f,
      ];
      _thumbnails.remove(path);
      _editSources.remove(path);
      _renderedPreviews.remove(path);
      _fullQualityPreviews.remove(path);
      _histograms.remove(path);
      _metadata.remove(path);
      _neutralPreviews.remove(path);
      _edits.remove(path);
      _photoCurves.remove(path);

      if (removedIndex == _selectedIndex) {
        _selectedIndex = null;
      } else if (_selectedIndex != null && removedIndex < _selectedIndex!) {
        // Every index after the removed one shifted down by one — keep
        // pointing at the same photo, not whatever slid into its old slot.
        _selectedIndex = _selectedIndex! - 1;
      }
    });
    await saveCatalog(_edits);
    await savePhotoCurves(_photoCurves);
    await savePhotoMasks(_photoMasks);
  }

  /// Opens just the one selected file — no folder scan, so the filmstrip
  /// only shows this single photo (unlike Open Folder, or a version of
  /// this that loaded the whole containing folder with focus on the file).
  Future<void> _openFile() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.dialogOpenFileTitle,
      type: FileType.custom,
      allowedExtensions: [
        ...rawExtensions,
        ...commonImageExtensions,
      ].map((ext) => ext.substring(1)).toList(),
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
    if (path == _currentSingleFile) {
      return;
    }
    await _loadSingleFile(path);
    final next = _settings.withRecentFile(path);
    setState(() => _settings = next);
    unawaited(saveSettings(next));
  }

  /// Drops [path] from the sidebar's recent-files list and persists the
  /// change. Clears the main view if it was showing that file, mirroring
  /// [_removeLibraryFolder].
  void _removeRecentFile(String path) {
    final next = _settings.copyWith(
      recentFiles: _settings.recentFiles.where((f) => f != path).toList(),
    );
    final showingRemoved = _currentSingleFile == path;
    setState(() {
      _settings = next;
      if (showingRemoved) {
        _files = const [];
        _selectedIndex = null;
        _currentSingleFile = null;
        _thumbnails.clear();
        _editSources.clear();
        _renderedPreviews.clear();
        _fullQualityPreviews.clear();
        _histograms.clear();
        _metadata.clear();
        _neutralPreviews.clear();
        _beforeAfterMode = false;
      }
    });
    unawaited(saveSettings(next));
  }

  Future<void> _loadFolder(String folder, {String? selectPath}) async {
    unawaited(_flushCurrentEdits());
    final generation = ++_folderGeneration;
    _beginLoadingFiles();
    _currentFolder = folder;
    _currentSingleFile = null;
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
    _currentFolder = null;
    _currentSingleFile = path;
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
      _fullQualityPreviews.clear();
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
    _dynamicPreviewTimer?.cancel();
    _thumbnailUiFlushTimer?.cancel();
    _thumbnailUiFlushTimer = null;
    _completeVisibleThumbnailsReady();
    _exportCancellation?.cancel();
    _aiEnhanceCancellation?.cancel();
    _cloudDenoiseCancellation?.cancel();
    setState(() {
      _loading = false;
      _isDecodingPhoto = false;
      _isRenderingSlow = false;
      _isApplyingAiDenoise = false;
      _isRunningNeuralEnhance = false;
      _aiEnhanceProgress = null;
      _isRunningCloudDenoise = false;
      _cloudDenoiseStage = null;
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
  /// rather than waiting behind the thumbnail batch). The preview-cache
  /// preload is also started here but internally waits for the visible
  /// thumbnails first — see [_preloadPreviewCache].
  Future<void> _applyFiles(
    List<RawFile> files,
    int? selectedIndex,
    int generation,
  ) async {
    _resetZoom();
    _dynamicPreviewTimer?.cancel();
    _fullQualitySource = null;
    _fullQualitySourcePath = null;
    _fullQualityScaled = null;
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
      _appliedPresetId = selectedIndex == null
          ? null
          : _photoPresets[files[selectedIndex].path];
    });
    _resetHistory();
    if (selectedIndex != null) {
      unawaited(_saveLastActiveFile(files[selectedIndex].path));
      unawaited(
        _loadEditSourceAndRender(files[selectedIndex].path, generation),
      );
    }
    // Recreate the gate the preload waits on (releasing any prior waiter),
    // then start both — the preload blocks on _loadThumbnails' progress.
    _completeVisibleThumbnailsReady();
    _visibleThumbnailsReady = Completer<void>();
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
        // Mutate state directly, then schedule one coalesced rebuild
        // instead of a setState per thumbnail: with several workers each
        // finishing a decode every few hundred ms, a rebuild apiece floods
        // the build pipeline and is a big part of what makes opening a
        // large folder feel unresponsive.
        _thumbnailsLoaded++;
        if (bytes != null) {
          _thumbnails[file.path] = bytes;
        }
        _scheduleThumbnailUiFlush();
        if (_thumbnailsLoaded >= _thumbnailsBeforePreload) {
          _completeVisibleThumbnailsReady();
        }
        if (bytes != null && !fromCache) {
          unawaited(cache?.store(file.path, bytes));
        }
      }
    }

    await Future.wait(
      List.generate(_settings.thumbnailConcurrency, (_) => worker()),
    );
    // Land the final counts immediately rather than waiting on a pending
    // coalesced flush.
    _thumbnailUiFlushTimer?.cancel();
    _thumbnailUiFlushTimer = null;
    if (mounted && generation == _folderGeneration) {
      setState(() {});
    }
    // Release the preload even for a folder with fewer than
    // _thumbnailsBeforePreload photos, or if workers exited early.
    _completeVisibleThumbnailsReady();
    unawaited(cache?.flush());
  }

  /// Completes [_visibleThumbnailsReady] once, if it's live and pending.
  void _completeVisibleThumbnailsReady() {
    final completer = _visibleThumbnailsReady;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Schedules a single catch-up [setState] for the batch of thumbnail
  /// fields [_loadThumbnails]'s workers mutate directly — folding a burst
  /// of concurrent decodes into ~one rebuild per frame-ish interval. The
  /// fields are already updated by the time this fires; the empty setState
  /// just marks the tree dirty.
  void _scheduleThumbnailUiFlush() {
    if (_thumbnailUiFlushTimer != null) {
      return;
    }
    _thumbnailUiFlushTimer = Timer(const Duration(milliseconds: 90), () {
      _thumbnailUiFlushTimer = null;
      if (mounted) {
        setState(() {});
      }
    });
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
    return compute(decodeRawThumbnailLowPriority, file.path);
  }

  void _selectIndex(int index) {
    if (index == _selectedIndex) {
      return;
    }
    unawaited(_flushCurrentEdits());
    final path = _files[index].path;
    _resetZoom();
    _dynamicPreviewTimer?.cancel();
    _fullQualitySource = null;
    _fullQualitySourcePath = null;
    _fullQualityScaled = null;
    setState(() {
      _selectedIndex = index;
      _paramValues = _paramValuesFor(path);
      _currentCurves = _curvesFor(path);
      _currentMasks = _masksFor(path);
      _activeMaskId = imageMaskId;
      // Restore the "applied preset" marker for this photo (persisted).
      _appliedPresetId = _photoPresets[path];
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
        // Optimistic retry: if this path was flagged missing before (the
        // file was gone, an external drive unmounted, ...), give it a
        // fresh chance now rather than staying stuck showing "not found"
        // forever even after it comes back.
        _missingFiles.remove(path);
      });

      var fromCache = false;

      // If AI Enhance is active for this photo (persisted in
      // _paramValues, already swapped to this path's values by
      // _selectIndex before this runs), its cache takes priority over the
      // plain preview cache below — otherwise reselecting/reopening a
      // photo would silently show the un-enhanced render while
      // _paramValues still claims Enhance is active (the same class of
      // bug that made export ignore Enhance entirely — see
      // _loadEnhancedNativeSource's doc).
      final wantDenoise = (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0;
      final wantUpscale = (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0;
      final wantRawDenoise = (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0;
      final wantDenoiseAmount =
          (_paramValues[_neuralDenoiseAmountKey] ?? defaultNeuralDenoiseAmount)
              .round();
      final wantAnyEnhance = wantDenoise || wantUpscale || wantRawDenoise;
      if (wantAnyEnhance) {
        final cacheDir = await resolveAiEnhanceCacheDir();
        if (mounted) {
          final cachedPng = await lookupAiEnhanceCache(
            cacheDir,
            path,
            denoise: wantDenoise,
            upscale: wantUpscale,
            rawDenoise: wantRawDenoise,
            denoiseStrengthPercent: wantDenoiseAmount,
            denoiseModelPath: _settings.customDenoiseModelPath,
          );
          if (cachedPng != null) {
            sources = await compute(
              decodeCachedAiEnhanceSources,
              DecodeCachedAiEnhanceArgs(cachedPng, _settings.previewResolution),
            );
            fromCache = sources != null;
          }
        }
      }

      // Same reasoning as the AI Enhance cache-first check above, for the
      // Cloud AI pipeline — otherwise reselecting/reopening a photo would
      // either show un-denoised pixels while _paramValues still claims a
      // provider is active, or (worse, since this one costs money) fall
      // through to a fresh paid API call for a photo it was already run
      // on. Mutually exclusive with wantAnyEnhance (see AiDenoiseDialog),
      // so only one of the two cache lookups ever actually runs.
      final wantCloudProvider = _cloudProviderFromIndex(
        (_paramValues[_cloudDenoiseProviderKey] ?? 0.0).round(),
      );
      if (wantCloudProvider != null) {
        final cacheDir = await resolveCloudDenoiseCacheDir();
        if (mounted) {
          final cachedPng = await lookupCloudDenoiseCache(
            cacheDir,
            path,
            wantCloudProvider,
          );
          if (cachedPng != null) {
            sources = await compute(
              decodeCachedCloudDenoiseSources,
              DecodeCachedCloudDenoiseArgs(
                cachedPng,
                _settings.previewResolution,
              ),
            );
            fromCache = sources != null;
          }
        }
      }
      final wantAnyPipeline = wantAnyEnhance || wantCloudProvider != null;

      // Cache lookup/decode happens here in the main isolate/from a
      // compute() call (same split as ThumbnailCacheManager's own usage,
      // see _loadThumbnails) — only a genuine cache miss falls through to
      // the much more expensive RAW decode isolate below. Skipped
      // entirely when Enhance/Cloud was wanted and already resolved
      // above — this plain cache holds the *pre*-pipeline render for this
      // path, never the processed one.
      if (sources == null && !wantAnyPipeline) {
        final cachedJpeg = await _previewCache?.lookup(path);
        if (cachedJpeg != null) {
          sources = await compute(
            decodeEditSourcePairFromCachedJpeg,
            cachedJpeg,
          );
          fromCache = sources != null;
        }
      }

      // No per-stage progress consumer anymore (the small in-place spinner
      // is indeterminate — see _ImageArea's usage below), but
      // decodeEditSourcesWithProgress's dedicated Isolate is still what we
      // want over decodeEditSources' compute() for a genuine miss: see its
      // doc comment.
      //
      // Deliberately NOT re-running the Cloud AI call here on a cache miss
      // (unlike the on-device Enhance pipeline, which does fall back to a
      // fresh RAW decode + local re-run): re-visiting a photo should never
      // silently trigger another paid API call — only the dialog's Apply
      // button does that, on purpose.
      if (sources == null) {
        sources = await decodeEditSourcesWithProgress(
          path,
          (_) {},
          previewMaxDimension: _settings.previewResolution,
        );
        if (wantAnyPipeline && sources != null && mounted) {
          // Enhance/Cloud was wanted but its cache missed (evicted/
          // cleared) and we just fell back to a plain decode — keep
          // _paramValues honest about what's actually showing instead of
          // leaving it claiming a pipeline is active over untouched
          // pixels.
          setState(() {
            _paramValues = {
              ..._paramValues,
              _neuralDenoiseKey: 0.0,
              _neuralUpscaleKey: 0.0,
              _neuralRawDenoiseKey: 0.0,
              _cloudDenoiseProviderKey: 0.0,
            };
          });
        }
      }

      if (!mounted || generation != _folderGeneration) {
        return;
      }
      setState(() => _isDecodingPhoto = false);
      if (sources == null) {
        // A cache miss followed by a real decode failure this deep almost
        // always means the file itself is gone (moved/renamed/deleted
        // outside darkmoon, or its drive unmounted) rather than a
        // transient error — surface that instead of leaving the canvas
        // stuck on "decoding..." forever.
        setState(() => _missingFiles.add(path));
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
  ///
  /// Starts only once the thumbnail batch has filled the visible filmstrip
  /// (see [_thumbnailsBeforePreload]), so the RAW decodes here never
  /// out-compete the thumbnails the user is waiting to see.
  Future<void> _preloadPreviewCache(
    List<RawFile> files,
    int? selectedIndex,
    int generation,
  ) async {
    final cache = _previewCache;
    if (cache == null || files.isEmpty) {
      return;
    }
    // Wait for the visible filmstrip to fill in before spending cores on
    // photos nobody's selected — see [_thumbnailsBeforePreload].
    await _visibleThumbnailsReady?.future;
    if (!mounted || generation != _folderGeneration) {
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
        sources = await compute(
          decodeEditSourcePairFromCachedJpegLowPriority,
          cachedJpeg,
        );
        fromCache = sources != null;
      }
      // Cache miss (or a corrupt cache entry) — a real decode, not
      // skipped, so this photo's cache exists by the time the user
      // actually selects it. Low priority: nobody's waiting on this photo
      // yet, so it must not out-compete the UI or the thumbnail batch.
      sources ??= await decodeEditSourcesWithProgress(
        file.path,
        (_) {},
        previewMaxDimension: _settings.previewResolution,
        lowPriority: true,
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
    final isCurrent =
        _selectedIndex != null && _files[_selectedIndex!].path == path;
    final savedWb = _edits[path]?.containsKey('Temperature') ?? false;
    setState(() {
      _metadata[path] = metadata;
      // The WB neutral reference is per-photo. A photo sitting on "As Shot"
      // with no saved WB edit was seeded with 5500/0 before its metadata
      // resolved — move the sliders onto the real camera value now.
      if (isCurrent && metadata != null && !savedWb) {
        final mode = (_paramValues[_wbModeKey] ?? 0).toInt();
        if (mode == WbMode.asShot.index) {
          _paramValues = {
            ..._paramValues,
            'Temperature': metadata.asShotKelvin,
            'Tint': metadata.asShotTint,
          };
        }
      }
    });
    if (isCurrent) {
      _scheduleRender(live: false);
    }
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
    try {
      await _renderPreviewInner(path, sources, requestId, live, onStage);
    } catch (e, st) {
      debugPrint('render failed: $e\n$st');
    } finally {
      // Always clear the slow-render flag — a throw anywhere above used to
      // leave "Applying adjustments" stuck on forever.
      _slowRenderTimer?.cancel();
      if (mounted && _isRenderingSlow && requestId == _renderRequestId) {
        setState(() => _isRenderingSlow = false);
      }
    }
  }

  Future<void> _renderPreviewInner(
    String path,
    EditSourcePair sources,
    int requestId,
    bool live,
    void Function(RenderStage stage)? onStage,
  ) async {
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
    final metadata = _metadata[path];
    // Once full-quality editing is active for this photo, a *second*
    // render pass against the native source (downscaled per
    // AppSettings.fullQualityPercent) follows the quick preview one below —
    // so applying a preset shows instantly at preview res, then sharpens.
    // `onStage != null` (the AI Denoise apply/remove) still gets a phase-2
    // pass — the progress bar just tracks phase 1 — so the canvas doesn't
    // stay at preview resolution after toggling denoise.
    final fullQuality =
        !live &&
        _settings.dynamicFullPreview &&
        _activeMaskId == imageMaskId &&
        !_cropOverlayActive &&
        !_beforeAfterMode &&
        _fullQualityReadyFor(path);

    RenderJob buildJob(EditSource src) => RenderJob(
      source: src,
      params: RenderParams.fromValues(
        _effectiveParamValues(),
        curves: _effectiveCurves,
        asShotKelvin: metadata?.asShotKelvin ?? wbDefaultKelvin,
        asShotTint: metadata?.asShotTint ?? wbDefaultTint,
        baseContrast: _effectiveBaseContrast,
        colorProfile: _colorProfile,
      ),
      masks: _effectiveMasks,
      cropTransform: cropTransform,
      lensCorrection: _lensCorrection,
      lensProfile: _resolvedLensProfileFor(path),
      focalLengthMm: metadata?.focalLengthMm ?? 0,
      apertureFNumber: metadata?.apertureFNumber ?? 0,
    );

    // Phase 1 — the quick render: the tiny `live` buffer while dragging,
    // the preview buffer for a settled edit. Always cheap, always shown.
    final firstResult = await _runRenderJob(
      buildJob(live ? sources.live : sources.preview),
      onStage: onStage,
      allowGpu: !live,
    );
    if (!mounted || requestId != _renderRequestId) {
      return;
    }
    setState(() {
      _isRenderingSlow = false;
      _renderedPreviews[path] = firstResult.jpegBytes;
      // Fade in a settled render (applied edit/preset/reset/undo/redo, or
      // a freshly-decoded photo's first frame) — never a live drag frame.
      if (!live) {
        _previewFadeGeneration++;
      }
      // This phase-1 render is newer than any full-quality one on file for
      // this photo — drop the stale full render so the canvas shows this
      // one until phase 2 (if any) replaces it.
      _fullQualityPreviews.remove(path);
      _histograms[path] = firstResult.histogram;
      // Keeps the filmstrip thumbnail in sync with the current edit —
      // only on the settled render (a live tick's thumbnail is superseded
      // almost immediately).
      if (!live) {
        _thumbnails[path] = firstResult.thumbnailBytes;
      }
    });
    if (!live) {
      _scheduleThumbnailCacheStore(path, firstResult.thumbnailBytes);
    }

    // Phase 2 — the full-quality render. Best-effort: if the downscale or
    // the render fails (a huge image, GPU OOM, …) the phase-1 preview
    // stays on screen instead of the app hanging.
    if (fullQuality) {
      EditSource? fqSource;
      try {
        fqSource = await _fullQualityRenderSource();
      } catch (e) {
        debugPrint('full-quality downscale failed: $e');
      }
      if (fqSource != null && mounted && requestId == _renderRequestId) {
        try {
          final fqResult = await _runRenderJob(
            buildJob(fqSource),
            allowGpu: true,
          );
          if (mounted && requestId == _renderRequestId) {
            setState(() {
              _fullQualityPreviews[path] = fqResult.jpegBytes;
              _histograms[path] = fqResult.histogram;
              _thumbnails[path] = fqResult.thumbnailBytes;
            });
          }
        } catch (e) {
          debugPrint('full-quality render failed: $e');
        }
      }
    }

    // A settled render just landed. Arm the native-source decode a beat
    // later — once it's available, subsequent settled renders get the
    // phase-2 pass. Fires once per photo. (Also after an AI Denoise
    // apply/remove, so that path engages full-quality mode too.)
    if (!live) {
      _maybeArmFullQualityDecode(path);
    }
  }

  /// GPU / CPU-parallel / progress-tracked dispatch for one render job —
  /// the [onStage] path (AI Denoise) wants real stage progress; otherwise
  /// GPU when [allowGpu] and available, else CPU-parallel via `compute()`.
  Future<RenderResult> _runRenderJob(
    RenderJob job, {
    void Function(RenderStage stage)? onStage,
    bool allowGpu = false,
  }) async {
    if (onStage != null) {
      return renderJobToJpegWithProgress(job, onStage);
    }
    // The GPU shader doesn't apply the "darkmoon Color" profile yet
    // (Phase 3) — falling through to it while a profile with a real tone
    // curve is active would render everything at LibRaw's dark baseline.
    // Force CPU until the shader port lands.
    final profileActive =
        job.params.colorProfile != null &&
        !job.params.colorProfile!.toneIsIdentity;
    if (allowGpu &&
        !profileActive &&
        _settings.useGpuRender &&
        await isGpuRenderAvailable()) {
      return renderJobToJpegGpu(job);
    }
    return compute(renderJobToJpeg, job);
  }

  /// Working resolution (long edge, px) full-quality settled renders run
  /// at — `AppSettings.fullQualityPercent` of the sensor's native long
  /// edge (60% by default), never below [AppSettings.previewResolution]
  /// (so it's never *worse* than the normal preview). Not zoom-dependent:
  /// once full-quality mode kicks in you're editing the near-full RAW, so
  /// re-rendering on every zoom change wasn't worth the jank. 100% renders
  /// the full sensor on every settle — sharp everywhere, but each settle
  /// pays a longer inline JPEG encode (see `render_job_gpu.dart`).
  int _fullQualityWorkingRes(EditSource native) {
    final nativeLong = native.width > native.height
        ? native.width
        : native.height;
    var target = (nativeLong * _settings.fullQualityPercent / 100).round();
    if (target < _settings.previewResolution) {
      target = _settings.previewResolution;
    }
    if (target > nativeLong) {
      target = nativeLong;
    }
    return target;
  }

  /// The native source downscaled to [_fullQualityWorkingRes] once, then
  /// reused for every settled render of this photo (the working res is
  /// constant now, so it never needs regenerating).
  Future<EditSource> _fullQualityRenderSource() async {
    final native = _fullQualitySource!;
    final cached = _fullQualityScaled;
    if (cached != null) {
      return cached;
    }
    final scaled = await compute(scaleEditSource, (
      source: native,
      maxDim: _fullQualityWorkingRes(native),
    ));
    _fullQualityScaled = scaled;
    return scaled;
  }

  void _maybeArmFullQualityDecode(String path) {
    if (!_settings.dynamicFullPreview ||
        _activeMaskId != imageMaskId ||
        _cropOverlayActive ||
        _beforeAfterMode ||
        _decodingFullQuality ||
        _fullQualityReadyFor(path)) {
      return;
    }
    _dynamicPreviewTimer?.cancel();
    _dynamicPreviewTimer = Timer(
      _dynamicPreviewDelay,
      () => unawaited(_ensureFullQualitySource(path)),
    );
  }

  /// The photo's decoded native-resolution [EditSource] — from the
  /// in-memory full-quality source if it's this photo's, then the shared
  /// `previews/native` disk cache, then a fresh RAW decode that also warms
  /// the cache. Used by both the full-quality preview and export, so the
  /// slow RAW demosaic (especially X-Trans) is paid at most once per photo.
  Future<EditSource?> _loadNativeSource(
    String path, {
    required bool lowPriority,
  }) async {
    if (_fullQualitySourcePath == path && _fullQualitySource != null) {
      return _fullQualitySource;
    }
    final cachedJpeg = await _nativeSourceCache?.lookup(path);
    EditSource? native;
    if (cachedJpeg != null) {
      native = await compute(decodeNativeSourceFromCachedJpeg, cachedJpeg);
    }
    native ??= await compute(
      lowPriority
          ? decodeFullQualitySourceLowPriority
          : decodeFullQualitySource,
      path,
    );
    if (native != null && cachedJpeg == null) {
      final toCache = native;
      unawaited(
        compute(
          encodeNativeSourceForCache,
          toCache,
        ).then((bytes) => _storeNativeSource(path, bytes)),
      );
    }
    return native;
  }

  /// Export's equivalent of [_loadNativeSource] for a photo with the AI
  /// Enhance pipeline active — the full-resolution enhanced buffer
  /// (already upscaled if [upscale] is true), not a plain RAW decode, so
  /// the exported file actually reflects Enhance instead of silently
  /// ignoring it (a real bug found via testing: exporting the same photo
  /// with Enhance on vs. off produced byte-identical files, because
  /// export always called [_loadNativeSource] regardless).
  ///
  /// Reuses [_runNeuralEnhance] on a cache miss — same progress/cancel/
  /// CPU-warning UI already wired for the dialog flow, and it writes the
  /// disk cache this then re-reads. The common case is a hit: this exact
  /// combination was already written to disk the moment the user picked
  /// it in the AI Denoise dialog. Returns null (caller falls back to
  /// [_loadNativeSource]) if the pipeline isn't cached and re-running it
  /// now also fails.
  Future<EditSource?> _loadEnhancedNativeSource(
    String path, {
    required bool denoise,
    required bool upscale,
    int denoiseAmount = 100,
    bool rawDenoise = false,
  }) async {
    final cacheDir = await resolveAiEnhanceCacheDir();
    if (!mounted) return null;
    var cachedPng = await lookupAiEnhanceCache(
      cacheDir,
      path,
      denoise: denoise,
      upscale: upscale,
      rawDenoise: rawDenoise,
      denoiseStrengthPercent: denoiseAmount,
      denoiseModelPath: _settings.customDenoiseModelPath,
    );
    if (cachedPng == null) {
      final ok = await _runNeuralEnhance(
        path,
        denoise: denoise,
        upscale: upscale,
        denoiseAmount: denoiseAmount,
        rawDenoise: rawDenoise,
      );
      if (!mounted || !ok) {
        return null;
      }
      cachedPng = await lookupAiEnhanceCache(
        cacheDir,
        path,
        denoise: denoise,
        upscale: upscale,
        rawDenoise: rawDenoise,
        denoiseStrengthPercent: denoiseAmount,
        denoiseModelPath: _settings.customDenoiseModelPath,
      );
    }
    if (cachedPng == null || !mounted) {
      return null;
    }
    return compute(decodeAiEnhanceCacheEntry, cachedPng);
  }

  /// Export's cloud-denoise equivalent of [_loadEnhancedNativeSource] —
  /// deliberately cache-only, unlike that one: [_loadEnhancedNativeSource]
  /// re-runs the on-device pipeline on a cache miss because that's free;
  /// silently firing a second paid API call just because export happened
  /// to run after the disk cache was cleared is not something this app
  /// should ever do on its own. A miss here returns null, so the caller
  /// falls back to [_loadNativeSource] (the plain, un-denoised source) —
  /// same "export something correct rather than something surprising and
  /// expensive" choice as the reselect cache-miss path in
  /// `_loadEditSourceAndRender`.
  Future<EditSource?> _loadCloudDenoisedNativeSource(
    String path,
    CloudDenoiseProviderKind provider,
  ) async {
    final cacheDir = await resolveCloudDenoiseCacheDir();
    if (!mounted) return null;
    final cachedPng = await lookupCloudDenoiseCache(cacheDir, path, provider);
    if (cachedPng == null) {
      return null;
    }
    return compute(decodeCloudDenoiseCacheEntry, cachedPng);
  }

  /// Decodes [path]'s native source and re-renders the settled view
  /// against it — from then on [_fullQualityReadyFor] is true for this
  /// photo and settled renders stay at full quality until it changes.
  Future<void> _ensureFullQualitySource(String path) async {
    if (!mounted ||
        !_settings.dynamicFullPreview ||
        _decodingFullQuality ||
        _fullQualityReadyFor(path)) {
      return;
    }
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected?.path != path) {
      return;
    }
    _decodingFullQuality = true;
    EditSource? native;
    try {
      native = await _loadNativeSource(path, lowPriority: true);
    } finally {
      _decodingFullQuality = false;
    }
    final stillSelected = _selectedIndex == null
        ? null
        : _files[_selectedIndex!];
    if (!mounted ||
        native == null ||
        stillSelected?.path != path ||
        !_settings.dynamicFullPreview) {
      return;
    }
    _fullQualitySource = native;
    _fullQualitySourcePath = path;
    _fullQualityScaled = null;
    // Re-render the settled view, now against the full source.
    _scheduleRender(live: false);
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
      RenderJob(
        source: sources.preview,
        // "Before" still gets the base profile (contrast curve + colour
        // correction) — it's part of the baseline rendering, like Lightroom
        // keeping the camera profile, not a develop edit.
        params: RenderParams(
          baseContrast: _effectiveBaseContrast,
          colorProfile: _colorProfile,
        ),
      ),
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
    final opening = !_cropOverlayActive;
    setState(() {
      _cropOverlayActive = opening;
      // Before/After and the crop overlay can't both be up — the split
      // view has nowhere to put the crop handles.
      if (opening && _beforeAfterMode) {
        _beforeAfterMode = false;
      }
    });
    // Crop handles are placed against the fitted frame — a leftover
    // zoom/pan would put them off-screen, so snap back to Fit on open.
    if (opening) {
      _resetZoom();
    }
    if (selected != null) {
      unawaited(_renderPreview(selected.path));
    }
  }

  /// Locks the crop rect to [ratio] and immediately re-fits it (centered,
  /// as large as the frame allows) instead of only recording the lock for
  /// the *next* drag to pick up — Lightroom's aspect picker snaps the
  /// selection the moment you click a ratio, it doesn't wait for you to
  /// touch a handle first.
  void _setCropAspectRatio(double? ratio) {
    setState(() => _cropAspectRatio = ratio);
    if (ratio == null) {
      return;
    }
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    final source = selected == null
        ? null
        : _editSources[selected.path]?.preview;
    if (source == null) {
      return;
    }
    final current = _cropTransform;
    final rotated = current.rotateQuarterTurns.isOdd;
    final frameWidth = rotated ? source.height : source.width;
    final frameHeight = rotated ? source.width : source.height;
    final imageAspect = frameWidth / frameHeight;
    // Same normalized-space conversion CropOverlay._dragCorner uses to
    // keep a locked ratio while dragging — kept in sync so picking a
    // ratio and then nudging a corner never fight each other.
    final normalizedRatio = ratio / imageAspect;
    final double w, h;
    if (normalizedRatio >= 1) {
      w = 1.0;
      h = 1.0 / normalizedRatio;
    } else {
      w = normalizedRatio;
      h = 1.0;
    }
    final left = (1 - w) / 2;
    final top = (1 - h) / 2;
    _onCropTransformChangeEnd(
      current.copyWith(
        cropLeft: left,
        cropTop: top,
        cropRight: left + w,
        cropBottom: top + h,
      ),
    );
  }

  /// Per-photo markers for item 13's neural Enhance pipeline's two
  /// independent passes (denoise, 2x super-resolution) — parallel to how
  /// `'AiDenoiseLevel'` already persists the classical level, just not
  /// slider values so they get their own keys. `> 0` means active. Live in
  /// `_paramValues` for the same free per-photo persistence (catalog
  /// save/restore, undo/redo history) every other param value already
  /// gets — see `_onParamChanged`'s doc comment on why `_paramValues` is
  /// replaced wholesale, not mutated, for history to track it correctly.
  static const _neuralDenoiseKey = 'AiNeuralDenoise';
  static const _neuralUpscaleKey = 'AiNeuralUpscale';

  /// See `AiDenoiseDialog`'s `NeuralEnhanceChoice.rawDenoise` — the PMRID
  /// raw-domain pass, persisted the same way as the two flags above.
  static const _neuralRawDenoiseKey = 'AiNeuralRawDenoise';

  /// See `AiDenoiseDialog`'s `NeuralEnhanceChoice.denoiseAmount` — 0-100,
  /// persisted the same way as the two flags above. Defaults to
  /// [defaultNeuralDenoiseAmount] when absent (a photo that predates this
  /// slider, or one that's never had Denoise turned on before), matching
  /// `NeuralEnhanceChoice`'s own default.
  static const _neuralDenoiseAmountKey = 'AiNeuralDenoiseAmount';

  /// See `AiDenoiseDialog`'s `CloudDenoiseChoice.provider` — 0=off,
  /// otherwise `CloudDenoiseProviderKind.values.indexOf(provider) + 1`.
  /// Only the provider is persisted here; the API key itself is never
  /// stored in `_paramValues`/the catalog (see `CloudDenoiseTokenStore`).
  static const _cloudDenoiseProviderKey = 'AiCloudDenoiseProvider';

  int _cloudProviderIndex(CloudDenoiseProviderKind? provider) =>
      provider == null
      ? 0
      : CloudDenoiseProviderKind.values.indexOf(provider) + 1;

  CloudDenoiseProviderKind? _cloudProviderFromIndex(int index) =>
      index <= 0 || index > CloudDenoiseProviderKind.values.length
      ? null
      : CloudDenoiseProviderKind.values[index - 1];

  /// Opens the AI Denoise dialog (Classic level picker / Enhance neural
  /// toggle / Cloud AI — see `AiDenoiseDialog`) and, if the user confirms a
  /// choice, applies it — a deliberate one-shot action (with its own
  /// loading message) rather than a slider the user drags, matching the
  /// Lightroom/Photomator "pick a strength, apply" pattern.
  Future<void> _openAiDenoiseDialog() async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    final currentLevel = AiDenoiseParams.fromValues(_paramValues).level;
    final neuralDenoise = (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0;
    final neuralUpscale = (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0;
    final neuralRawDenoise = (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0;
    final neuralDenoiseAmount =
        (_paramValues[_neuralDenoiseAmountKey] ?? defaultNeuralDenoiseAmount)
            .round();
    final cloudProvider = _cloudProviderFromIndex(
      (_paramValues[_cloudDenoiseProviderKey] ?? 0.0).round(),
    );
    final wasNeuralActive = neuralDenoise || neuralUpscale || neuralRawDenoise;
    final wasAnyPipelineActive = wasNeuralActive || cloudProvider != null;
    final rawDenoiseAvailable =
        isRawFile(selected.path) &&
        (_metadata[selected.path]?.isBayerCfa ?? false);
    final choice = await showAnimatedDialog<AiDenoiseChoice>(
      context: context,
      builder: (_) => AiDenoiseDialog(
        initialLevel: currentLevel,
        neuralDenoise: neuralDenoise,
        neuralUpscale: neuralUpscale,
        neuralDenoiseAmount: neuralDenoiseAmount,
        neuralRawDenoise: neuralRawDenoise,
        rawDenoiseAvailable: rawDenoiseAvailable,
        cloudProvider: cloudProvider,
      ),
    );
    if (choice == null || !mounted) {
      return;
    }

    switch (choice) {
      case ClassicDenoiseChoice(level: final level):
        setState(() {
          _paramValues = {
            ..._paramValues,
            'AiDenoiseLevel': level == null
                ? 0.0
                : (AiDenoiseLevel.values.indexOf(level) + 1).toDouble(),
            _neuralDenoiseKey: 0.0,
            _neuralUpscaleKey: 0.0,
            _neuralRawDenoiseKey: 0.0,
            _cloudDenoiseProviderKey: 0.0,
          };
        });
        // Switching away from a previously-enhanced source: _editSources
        // currently holds the neural-pipeline/cloud buffer, which the
        // classical per-render stage was never meant to run against.
        if (wasAnyPipelineActive) {
          await _revertToNormalEditSource(selected.path);
          if (!mounted) return;
        }
        await _applyAiDenoiseChoiceAndRender(
          selected.path,
          disabling: level == null,
        );
      case NeuralEnhanceChoice(
            denoise: final wantDenoise,
            upscale: final wantUpscale,
            denoiseAmount: final wantDenoiseAmount,
            rawDenoise: final wantRawDenoise,
          )
          when wantDenoise || wantUpscale || wantRawDenoise:
        setState(() {
          _paramValues = {
            ..._paramValues,
            _neuralDenoiseKey: wantDenoise ? 1.0 : 0.0,
            _neuralUpscaleKey: wantUpscale ? 1.0 : 0.0,
            _neuralDenoiseAmountKey: wantDenoiseAmount.toDouble(),
            _neuralRawDenoiseKey: wantRawDenoise ? 1.0 : 0.0,
            _cloudDenoiseProviderKey: 0.0,
            'AiDenoiseLevel': 0.0,
          };
        });
        final ok = await _runNeuralEnhance(
          selected.path,
          denoise: wantDenoise,
          upscale: wantUpscale,
          denoiseAmount: wantDenoiseAmount,
          rawDenoise: wantRawDenoise,
        );
        if (!mounted || !ok) {
          return;
        }
        await _applyAiDenoiseChoiceAndRender(selected.path);
      case NeuralEnhanceChoice():
        // All toggles off — equivalent to turning Enhance back off.
        setState(() {
          _paramValues = {
            ..._paramValues,
            _neuralDenoiseKey: 0.0,
            _neuralUpscaleKey: 0.0,
            _neuralRawDenoiseKey: 0.0,
          };
        });
        await _revertToNormalEditSource(selected.path);
        if (!mounted) return;
        await _applyAiDenoiseChoiceAndRender(selected.path, disabling: true);
      case CloudDenoiseChoice(
            provider: final wantProvider,
            apiKey: final wantApiKey,
          )
          when wantProvider != null && wantApiKey.isNotEmpty:
        await CloudDenoiseTokenStore.write(wantProvider, wantApiKey);
        if (!mounted) return;
        setState(() {
          _paramValues = {
            ..._paramValues,
            _neuralDenoiseKey: 0.0,
            _neuralUpscaleKey: 0.0,
            _neuralRawDenoiseKey: 0.0,
            _cloudDenoiseProviderKey: _cloudProviderIndex(
              wantProvider,
            ).toDouble(),
            'AiDenoiseLevel': 0.0,
          };
        });
        final ok = await _runCloudDenoise(
          selected.path,
          provider: wantProvider,
          apiKey: wantApiKey,
        );
        if (!mounted || !ok) {
          return;
        }
        await _applyAiDenoiseChoiceAndRender(selected.path);
      case CloudDenoiseChoice():
        // No provider picked (or an empty key) — equivalent to off.
        setState(() {
          _paramValues = {..._paramValues, _cloudDenoiseProviderKey: 0.0};
        });
        if (wasAnyPipelineActive) {
          await _revertToNormalEditSource(selected.path);
          if (!mounted) return;
        }
        await _applyAiDenoiseChoiceAndRender(selected.path, disabling: true);
    }
  }

  /// Re-decodes [path] the normal way (no neural enhance) and swaps it
  /// into `_editSources` — used when the user turns Enhance back off, or
  /// switches to a Classic level while Enhance was active, since
  /// `_editSources[path]` holds the enhanced (upscaled) buffer until
  /// something replaces it.
  Future<void> _revertToNormalEditSource(String path) async {
    final normalSources = await decodeEditSourcesWithProgress(
      path,
      (_) {},
      previewMaxDimension: _settings.previewResolution,
    );
    if (mounted && normalSources != null) {
      setState(() => _editSources[path] = normalSources);
    }
  }

  /// Runs item 13's neural Enhance pipeline (NAFNet-SIDD [denoise] and/or
  /// Real-ESRGAN 2x [upscale], disk-cached — see
  /// `native/edit_source_ai_enhance.dart`) for [path] and swaps the
  /// result into `_editSources`, so every later render/mask/export builds
  /// on the enhanced buffer instead of the plain decode. Returns false
  /// (having already reverted the `_neuralDenoiseKey`/`_neuralUpscaleKey`
  /// markers and shown a message) on failure, so the caller can skip
  /// rendering/history for a change that didn't actually happen.
  ///
  /// Owns [_isRunningNeuralEnhance]/[_aiEnhanceProgress] end-to-end (set
  /// on entry, cleared on every exit path) — this is the operation that
  /// can take 30s-2min, so without a loading overlay covering exactly
  /// this call the dialog just closes and appears to do nothing for that
  /// whole stretch.
  Future<bool> _runNeuralEnhance(
    String path, {
    required bool denoise,
    required bool upscale,
    int denoiseAmount = 100,
    bool rawDenoise = false,
  }) async {
    setState(() {
      _isRunningNeuralEnhance = true;
      _aiEnhanceProgress = null;
    });
    // The overlay's Cancel button (_cancelLoading) calls .cancel() on this
    // to actually stop waiting instead of just resetting the UI while the
    // isolate keeps running the ONNX inference underneath it.
    final cancellation = AiEnhanceCancellationToken();
    _aiEnhanceCancellation = cancellation;
    final cacheDir = await resolveAiEnhanceCacheDir();
    if (!mounted) return false;
    // Set the first time either model reports a CPU fallback, so the
    // "this will be slower" warning below only ever shows once per run
    // (there are two models, denoise then upscale) instead of twice.
    var cpuWarningShown = false;
    final sources = await decodeEditSourcesWithAiEnhance(
      path,
      cacheDir,
      (stage) {
        if (!mounted) return;
        if (stage is AiEnhanceProgress) {
          setState(() => _aiEnhanceProgress = stage);
        } else if (stage is AiEnhanceModelInfo) {
          DevLog.log(
            'AI Enhance model ${stage.modelName}: '
            '${stage.usingGpu ? "GPU (DirectML)" : "CPU fallback"}'
            '${stage.directMlError == null ? "" : " — DirectML error: ${stage.directMlError}"}',
            tag: 'ai-enhance',
          );
          if (!stage.usingGpu && !cpuWarningShown) {
            cpuWarningShown = true;
            // No non-dev status equivalent — the AI Denoise dialog itself
            // already warns about this before the user even applies (see
            // probeAiEnhanceGpuSupport), so this is purely a Dev Mode
            // detail at this point, not a first notice.
            _notify(
              detail: AppLocalizations.of(context)!.aiDenoiseEnhanceCpuWarning,
            );
          }
        } else if (stage is CustomDenoiseModelFallback) {
          DevLog.log(
            'Custom denoise model failed, fell back to default: ${stage.reason}',
            tag: 'ai-enhance',
          );
          _notify(
            detail: AppLocalizations.of(
              context,
            )!.aiDenoiseCustomModelFallbackMessage(stage.reason),
            status: AppLocalizations.of(
              context,
            )!.aiDenoiseCustomModelFallbackStatus,
          );
        }
      },
      enableDenoise: denoise,
      enableUpscale: upscale,
      enableRawDenoise: rawDenoise,
      denoiseStrengthPercent: denoiseAmount,
      customDenoiseModelPath: _settings.customDenoiseModelPath,
      previewMaxDimension: _settings.previewResolution,
      cancellationToken: cancellation,
    );
    _aiEnhanceCancellation = null;
    if (!mounted) {
      return false;
    }
    if (sources == null) {
      final wasCancelled = cancellation.isCancelled;
      setState(() {
        _paramValues = {
          ..._paramValues,
          _neuralDenoiseKey: 0.0,
          _neuralUpscaleKey: 0.0,
          _neuralRawDenoiseKey: 0.0,
        };
        _isRunningNeuralEnhance = false;
        _aiEnhanceProgress = null;
      });
      // A deliberate Cancel already reset the overlay in _cancelLoading —
      // showing "AI Enhance couldn't run" on top of that would misreport
      // the user's own action as a failure.
      if (!wasCancelled) {
        _notify(
          detail: AppLocalizations.of(context)!.aiDenoiseEnhanceFailedMessage,
          status: AppLocalizations.of(context)!.aiDenoiseEnhanceFailedStatus,
        );
      }
      return false;
    }
    setState(() {
      _editSources[path] = sources;
      _isRunningNeuralEnhance = false;
      _aiEnhanceProgress = null;
    });
    return true;
  }

  /// Runs the Cloud AI denoise pipeline (`native/edit_source_cloud_denoise
  /// .dart`, disk-cached — see `cloud_denoise_cache.dart` for why: this
  /// costs real money per call) for [path] and swaps the result into
  /// `_editSources`. Returns false (having already reverted
  /// `_cloudDenoiseProviderKey` and shown the real failure reason — a bad
  /// key, a provider error, a network failure — since unlike the local
  /// pipeline these are worth surfacing individually) on failure.
  ///
  /// Owns [_isRunningCloudDenoise]/[_cloudDenoiseStage] end-to-end, same
  /// role [_isRunningNeuralEnhance]/[_aiEnhanceProgress] play for the
  /// on-device pipeline.
  Future<bool> _runCloudDenoise(
    String path, {
    required CloudDenoiseProviderKind provider,
    required String apiKey,
  }) async {
    setState(() {
      _isRunningCloudDenoise = true;
      _cloudDenoiseStage = null;
    });
    final cancellation = CloudDenoiseCancellationToken();
    _cloudDenoiseCancellation = cancellation;
    final cacheDir = await resolveCloudDenoiseCacheDir();
    if (!mounted) return false;

    final result = await decodeEditSourcesWithCloudDenoise(
      path,
      cacheDir,
      (stage) {
        if (mounted) setState(() => _cloudDenoiseStage = stage);
      },
      provider: provider,
      apiKey: apiKey,
      previewMaxDimension: _settings.previewResolution,
      cancellationToken: cancellation,
    );
    _cloudDenoiseCancellation = null;
    if (!mounted) {
      return false;
    }

    switch (result) {
      case CloudDenoiseSuccess(sources: final sources):
        setState(() {
          _editSources[path] = sources;
          _isRunningCloudDenoise = false;
          _cloudDenoiseStage = null;
        });
        return true;
      case CloudDenoiseCancelled():
        // A deliberate Cancel already reset the overlay in _cancelLoading.
        setState(() {
          _paramValues = {..._paramValues, _cloudDenoiseProviderKey: 0.0};
          _isRunningCloudDenoise = false;
          _cloudDenoiseStage = null;
        });
        return false;
      case CloudDenoiseFailed(message: final message):
        setState(() {
          _paramValues = {..._paramValues, _cloudDenoiseProviderKey: 0.0};
          _isRunningCloudDenoise = false;
          _cloudDenoiseStage = null;
        });
        DevLog.log(message, tag: 'cloud-denoise');
        _notify(
          detail: AppLocalizations.of(
            context,
          )!.aiDenoiseCloudFailedMessage(message),
          status: AppLocalizations.of(context)!.aiDenoiseCloudFailedStatus,
        );
        return false;
    }
  }

  /// The loading-overlay/render/history/save sequence shared by every
  /// `_openAiDenoiseDialog` outcome, once `_paramValues`/`_editSources`
  /// already reflect the user's choice.
  Future<void> _applyAiDenoiseChoiceAndRender(
    String path, {
    bool disabling = false,
  }) async {
    setState(() {
      _isApplyingAiDenoise = true;
      _aiDenoiseDisabling = disabling;
      _aiDenoiseRenderStage = null;
    });
    await _renderPreview(
      path,
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

  /// Instant — used for "the view just needs to be Fit again" resets
  /// (switching photos, opening the Crop overlay) that aren't really a
  /// user-initiated zoom gesture, so animating them would just be a
  /// distracting flourish on top of an unrelated action.
  void _resetZoom() {
    _viewController.value = Matrix4.identity();
    setState(() => _zoomScale = 1.0);
  }

  /// The animated counterpart, for the toolbar's Fit button specifically.
  void _resetZoomAnimated() {
    _animateViewMatrixTo(Matrix4.identity());
    setState(() => _zoomScale = 1.0);
  }

  /// The matrix/scale a zoom by [factor] (centered on [anchor], or the
  /// viewport's own center) would land on, or null if [factor] wouldn't
  /// move [_zoomScale] at all (already at the min/max clamp).
  ({Matrix4 matrix, double scale})? _computeZoomTarget(
    double factor, {
    Offset? anchor,
  }) {
    final newScale = (_zoomScale * factor).clamp(_minZoom, _maxZoom);
    final effectiveFactor = newScale / _zoomScale;
    if (effectiveFactor == 1.0) {
      return null;
    }
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    final center =
        anchor ?? (box != null ? box.size.center(Offset.zero) : Offset.zero);
    final matrix = Matrix4.copy(_viewController.value)
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(effectiveFactor, effectiveFactor, effectiveFactor, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    return (matrix: matrix, scale: newScale);
  }

  /// Instant zoom — used for continuous gestures (Ctrl+scroll-wheel,
  /// double-click) that already have their own immediate feel; animating
  /// every tiny wheel tick would fight the gesture instead of following
  /// it.
  void _zoomBy(double factor, {Offset? anchor}) {
    final target = _computeZoomTarget(factor, anchor: anchor);
    if (target == null) {
      return;
    }
    _viewController.value = target.matrix;
    setState(() => _zoomScale = target.scale);
    // Zoom no longer triggers any render — full-quality mode renders at a
    // fixed working resolution (see [_fullQualityWorkingRes]).
  }

  /// The animated counterpart, for the toolbar's +/- buttons — a single
  /// discrete click benefits from an eased hop between zoom levels.
  void _zoomByAnimated(double factor) {
    final target = _computeZoomTarget(factor);
    if (target == null) {
      return;
    }
    _animateViewMatrixTo(target.matrix);
    setState(() => _zoomScale = target.scale);
  }

  void _zoomIn() => _zoomByAnimated(_zoomStep);

  void _zoomOut() => _zoomByAnimated(1 / _zoomStep);

  /// Fit-relative zoom level a double-click jumps to (item 25) — matches
  /// `_zoomScale`'s own "1.0 = Fit" convention (see `_ViewerToolbar`'s
  /// `zoomLabel`), not a literal 100%/200%-of-native-pixels figure, since
  /// darkmoon's zoom is defined relative to Fit rather than native
  /// resolution. 2.0 sits comfortably under `_maxZoom` (4.0) so a second
  /// double-click-in is still possible after the initial jump if wanted,
  /// while leaving Ctrl+scroll to reach the rest of the range.
  static const double _doubleTapZoomLevel = 2.0;

  /// Double-click on the image (item 25): zoom in centered on the click
  /// point if currently at Fit or below, or back out to Fit if already
  /// zoomed in — the same toggle Lightroom/Photoshop use, adapted to
  /// darkmoon's fit-relative zoom scale.
  void _onDoubleTapZoom(Offset localPosition) {
    if (_zoomScale > 1.0) {
      _resetZoom();
    } else {
      _zoomBy(_doubleTapZoomLevel / _zoomScale, anchor: localPosition);
    }
  }

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
      // A new Map, not an in-place mutation of the existing one —
      // _pushHistory's no-op check compares _paramValues by *reference*
      // (see _currentSnapshot/_pushHistory's own doc comment), so
      // mutating the same object here would make every snapshot taken
      // after this one `identical()` to whatever was pushed before it,
      // silently dropping every _onParamChangeEnd push for the rest of
      // the session — undo/redo across ordinary (non-mask) slider edits
      // would stop recording new steps entirely.
      _paramValues = {
        ..._paramValues,
        name: value,
        // Nudging Temperature/Tint by hand drops the WB mode to Custom,
        // matching Lightroom.
        if (name == 'Temperature' || name == 'Tint')
          _wbModeKey: WbMode.custom.index.toDouble(),
      };
      _appliedPresetId = null;
    });
    _scheduleRender(live: _settings.fastPreview);
    _scheduleCatalogSave();
  }

  static const _wbModeKey = 'WhiteBalanceMode';

  void _onParamChangeEnd(String name, double value) {
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// The Amount slider under the preset list — see
  /// [_globalEditAmountKey]/[_withGlobalEditAmountApplied]. Deliberately
  /// NOT [_onParamChanged]/[_onParamChangeEnd]: those clear
  /// [_appliedPresetId] on every change (a manual slider edit un-links
  /// the preset), but Amount isn't a manual edit to any one slider — the
  /// preset should stay highlighted in the list while its overall
  /// strength is being tuned, exactly like the old design already
  /// promised (see [_matchesAppliedPreset]'s doc).
  void _onGlobalEditAmountChanged(double value) {
    setState(() {
      _paramValues = {..._paramValues, _globalEditAmountKey: value};
    });
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onGlobalEditAmountChangeEnd(double value) {
    setState(() {
      _paramValues = {..._paramValues, _globalEditAmountKey: value};
    });
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// [_paramValues] with every disabled category's sliders swapped for
  /// their defaults, then the whole result scaled by the global Amount
  /// slider — used wherever the render pipeline reads the global layer's
  /// param values (CPU preview, GPU preview, and export all read through
  /// this one function, so both get Amount applied automatically with no
  /// separate wiring). See [_withCategoriesApplied]'s and
  /// [_withGlobalEditAmountApplied]'s own doc comments.
  Map<String, double> _effectiveParamValues() {
    final path = _selectedIndex == null ? null : _files[_selectedIndex!].path;
    final asShot = path == null
        ? (kelvin: wbDefaultKelvin, tint: wbDefaultTint)
        : _asShotFor(path);
    return _withGlobalEditAmountApplied(
      _withCategoriesApplied(
        _paramValues,
        asShotKelvin: asShot.kelvin,
        asShotTint: asShot.tint,
      ),
    );
  }

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

  /// Lens Correction state, derived from the same flat `_paramValues` map
  /// every other global adjustment lives in -- same reasoning as
  /// [_cropTransform] (global-only, not part of a mask's own values).
  LensCorrectionParams get _lensCorrection =>
      LensCorrectionParams.fromValues(_paramValues);

  void _onLensCorrectionChanged(LensCorrectionParams params) {
    setState(() => _paramValues = {..._paramValues, ...params.toValues()});
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onLensCorrectionChangeEnd(LensCorrectionParams params) {
    setState(() => _paramValues = {..._paramValues, ...params.toValues()});
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Resolves which [LensProfile] applies to [path] right now -- a manual
  /// override if the user picked one, else an auto-detected match against
  /// that photo's own EXIF (see `lens_correction.dart`'s
  /// [resolveLensProfile]). Used both to build each render's [RenderJob]
  /// and to drive the panel's "matched profile" display, so the two never
  /// show/apply a different profile than each other.
  LensProfile? _resolvedLensProfileFor(String? path) {
    if (path == null) {
      return null;
    }
    return resolveLensProfile(
      _lensProfiles,
      _metadata[path],
      _lensCorrection.manualProfileKeyHash,
    );
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

  /// Resets the whole photo back to its untouched state: global
  /// adjustments, curves, AND every mask — regardless of which layer is
  /// currently being edited. A partial reset (leaving masks behind) would
  /// be surprising for a button labeled "Reset", and there's no separate
  /// per-mask reset affordance, so this is the only way back to a blank
  /// slate.
  void _resetActive() {
    setState(() {
      _paramValues = _freshParamValues();
      _currentCurves = identityPhotoCurves;
      _currentMasks = [];
      _activeMaskId = imageMaskId;
      // Reset clears the edit — no preset is "applied" any more.
      _appliedPresetId = null;
    });
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
      MaskType.luminance => l10n.maskLuminance,
      MaskType.flow => l10n.maskFlow,
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

  void _setBrushFlow(double value) {
    setState(() => _brushFlow = value);
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

  void _onLuminanceToleranceChanged(double value) {
    if (!_isAdjustingMaskValue) {
      setState(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(tolerance: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onLuminanceToleranceChangeEnd(double value) {
    setState(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(tolerance: value)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  void _onLuminanceFeatherChanged(double value) {
    if (!_isAdjustingMaskValue) {
      setState(() => _isAdjustingMaskValue = true);
    }
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(feather: value)),
    );
    _scheduleRender(live: _settings.fastPreview);
  }

  void _onLuminanceFeatherChangeEnd(double value) {
    setState(() => _isAdjustingMaskValue = false);
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(feather: value)),
    );
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// Samples the currently-rendered preview at normalized ([nx], [ny]) and
  /// sets its luma as the active Luminance mask's target — mirrors
  /// [_onSampleMaskColor] but reduces the sampled pixel to brightness.
  void _onSampleMaskLuminance(double nx, double ny) {
    final mask = _activeMask;
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (mask == null || mask.type != MaskType.luminance || selected == null) {
      return;
    }
    final bytes = _displayPreview(selected.path);
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
    final luma = luminanceRgb(
      pixel.r.toDouble(),
      pixel.g.toDouble(),
      pixel.b.toDouble(),
    );
    _updateActiveMask(
      (m) => m.copyWith(luminance: m.luminance.copyWith(targetLuma: luma)),
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
    final bytes = _displayPreview(selected.path);
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

  /// The camera as-shot white balance for [path] (5500/0 for non-RAW or
  /// before its metadata resolves).
  ({double kelvin, double tint}) _asShotFor(String path) {
    final meta = _metadata[path];
    return (
      kelvin: meta?.asShotKelvin ?? wbDefaultKelvin,
      tint: meta?.asShotTint ?? wbDefaultTint,
    );
  }

  /// [_defaultParamValues] with Temperature/Tint seeded to the photo's
  /// camera as-shot white balance and the mode set to "As Shot" — the
  /// real "untouched" state now that the WB neutral is per-photo. Use this
  /// instead of `_defaultParamValues()` wherever `_paramValues` is reset.
  Map<String, double> _freshParamValues([String? path]) {
    final target =
        path ?? (_selectedIndex == null ? null : _files[_selectedIndex!].path);
    final asShot = target == null
        ? (kelvin: wbDefaultKelvin, tint: wbDefaultTint)
        : _asShotFor(target);
    return {
      ..._defaultParamValues(),
      'Temperature': asShot.kelvin,
      'Tint': asShot.tint,
      _wbModeKey: WbMode.asShot.index.toDouble(),
    };
  }

  /// Sets Temperature/Tint (and the stored mode) for a White Balance mode
  /// pick from the panel dropdown.
  void _applyWbMode(WbMode mode) {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    final asShot = _asShotFor(selected.path);
    ({double kelvin, double tint}) target;
    switch (mode) {
      case WbMode.asShot:
        target = asShot;
      case WbMode.custom:
        target = (
          kelvin: _paramValues['Temperature'] ?? asShot.kelvin,
          tint: _paramValues['Tint'] ?? asShot.tint,
        );
      case WbMode.auto:
        final src = _editSources[selected.path]?.preview;
        target = src == null
            ? asShot
            : grayWorldTempTint(
                src.rgbBytes,
                asShotKelvin: asShot.kelvin,
                asShotTint: asShot.tint,
              );
      default:
        final preset = wbModePreset(mode)!;
        target = (kelvin: preset.kelvin, tint: preset.tint);
    }
    setState(() {
      _paramValues = {
        ..._paramValues,
        'Temperature': target.kelvin,
        'Tint': target.tint,
        _wbModeKey: mode.index.toDouble(),
      };
      _appliedPresetId = null;
    });
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }

  /// White Balance eyedropper: samples a small neighbourhood of the
  /// decoded (pre-adjustment) source at normalized ([nx],[ny]) and solves
  /// for the Temperature/Tint that make it neutral.
  void _onSampleWhiteBalance(double nx, double ny) {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    final src = _editSources[selected.path]?.preview;
    if (src == null) {
      setState(() => _wbEyedropperActive = false);
      return;
    }
    final cx = (nx * (src.width - 1)).round().clamp(0, src.width - 1);
    final cy = (ny * (src.height - 1)).round().clamp(0, src.height - 1);
    var sumR = 0.0, sumG = 0.0, sumB = 0.0, n = 0;
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final x = cx + dx, y = cy + dy;
        if (x < 0 || y < 0 || x >= src.width || y >= src.height) {
          continue;
        }
        final i = (y * src.width + x) * 3;
        sumR += src.rgbBytes[i];
        sumG += src.rgbBytes[i + 1];
        sumB += src.rgbBytes[i + 2];
        n++;
      }
    }
    if (n == 0) {
      return;
    }
    final asShot = _asShotFor(selected.path);
    final res = solveNeutralizingTempTint(
      sumR / n,
      sumG / n,
      sumB / n,
      asShotKelvin: asShot.kelvin,
      asShotTint: asShot.tint,
    );
    setState(() {
      _wbEyedropperActive = false;
      _paramValues = {
        ..._paramValues,
        'Temperature': res.kelvin,
        'Tint': res.tint,
        _wbModeKey: WbMode.custom.index.toDouble(),
      };
      _appliedPresetId = null;
    });
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
    // A fresh edit invalidates any pending / in-flight full-res upgrade.
    _dynamicPreviewTimer?.cancel();
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
    final metadata = _metadata[selected.path];
    final options = await showAnimatedDialog<ExportOptions>(
      context: context,
      builder: (_) => ExportOptionsDialog(
        nativeWidth: metadata?.width,
        nativeHeight: metadata?.height,
      ),
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
      _exportCancellation = ExportCancellationToken();
      _exportStage = ExportStage.decoding;
    });

    // Skip the RAW demosaic in the export isolate if we already have (or
    // can cheaply get) the photo's decoded native source — the editor's
    // full-quality source, the shared cache, or one fresh decode that then
    // warms the cache for next time. This is the dominant export cost,
    // especially for X-Trans.
    //
    // If AI Enhance is active for this photo, that "native source" must
    // be the enhanced buffer, not a plain RAW decode — see
    // _loadEnhancedNativeSource's doc for the bug this fixes.
    final wantDenoise = (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0;
    final wantUpscale = (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0;
    final wantRawDenoise = (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0;
    final wantDenoiseAmount =
        (_paramValues[_neuralDenoiseAmountKey] ?? defaultNeuralDenoiseAmount)
            .round();
    final wantCloudProvider = _cloudProviderFromIndex(
      (_paramValues[_cloudDenoiseProviderKey] ?? 0.0).round(),
    );
    EditSource? nativeForExport;
    final srcSw = Stopwatch()..start();
    try {
      if (wantDenoise || wantUpscale || wantRawDenoise) {
        nativeForExport = await _loadEnhancedNativeSource(
          selected.path,
          denoise: wantDenoise,
          upscale: wantUpscale,
          denoiseAmount: wantDenoiseAmount,
          rawDenoise: wantRawDenoise,
        );
      } else if (wantCloudProvider != null) {
        nativeForExport = await _loadCloudDenoisedNativeSource(
          selected.path,
          wantCloudProvider,
        );
      }
      nativeForExport ??= await _loadNativeSource(
        selected.path,
        lowPriority: false,
      );
    } catch (_) {
      nativeForExport = null; // fall back to decoding in the export isolate
    }
    final srcMs = srcSw.elapsedMilliseconds;
    final srcTiming = nativeForExport == null
        ? null
        : (_fullQualitySourcePath == selected.path
              ? 'source (in memory) ${srcMs}ms'
              : 'source (decode+cache) ${srcMs}ms');
    if (!mounted || _exportCancellation?.isCancelled == true) {
      setState(() {
        _exporting = false;
        _exportStage = null;
      });
      return;
    }

    final result = await exportPhotoWithProgress(
      ExportRequest(
        sourcePath: selected.path,
        destPath: destPath,
        params: RenderParams.fromValues(
          _effectiveParamValues(),
          curves: _effectiveCurves,
          asShotKelvin: metadata?.asShotKelvin ?? wbDefaultKelvin,
          asShotTint: metadata?.asShotTint ?? wbDefaultTint,
          baseContrast: _effectiveBaseContrast,
          colorProfile: _colorProfile,
        ),
        masks: _effectiveMasks,
        format: options.format,
        quality: options.quality,
        cropTransform: _cropTransform,
        scalePercent: options.scalePercent,
        preDecodedRgb: nativeForExport?.rgbBytes,
        preDecodedWidth: nativeForExport?.width,
        preDecodedHeight: nativeForExport?.height,
      ),
      (stage) {
        if (mounted) {
          setState(() => _exportStage = stage);
        }
      },
      cancellationToken: _exportCancellation,
    );
    final wasCancelled = result.error == 'Export cancelled';
    _exportCancellation = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _exporting = false;
      _exportStage = null;
    });
    if (!wasCancelled) {
      final timingLine = _showExportTimings
          ? [
              if (srcTiming != null) srcTiming,
              if (result.timings != null) result.timings!,
            ].join('\n')
          : '';
      final detail = result.success
          ? '${l10n.exportSuccessMessage(result.destPath!)}'
                '${timingLine.isEmpty ? '' : '\n$timingLine'}'
          : l10n.exportFailureMessage(result.error!);
      _notify(
        detail: detail,
        status: result.success
            ? l10n.exportDoneStatus
            : l10n.exportFailedStatus,
      );
    }
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
      child: Focus(
        focusNode: _shortcutsFocusNode,
        autofocus: true,
        child: _buildScaffold(selected),
      ),
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
    // Checked before _isApplyingAiDenoise: the neural Enhance pipeline
    // itself (denoise + upscale through the ONNX models) is the slow part
    // of picking that choice — _isApplyingAiDenoise only covers the quick
    // render pass that follows once the enhanced source is ready.
    if (_isRunningNeuralEnhance) {
      final progress = _aiEnhanceProgress;
      if (progress == null) {
        return _LoadingInfo(message: l10n.aiDenoiseEnhanceStartingMessage);
      }
      final stageLabel = switch (progress.stage) {
        'upscale' => l10n.aiDenoiseEnhanceStageUpscale,
        'raw-denoise' => l10n.aiDenoiseEnhanceStageRawDenoise,
        _ => l10n.aiDenoiseEnhanceStageDenoise,
      };
      // A raw tile count (hundreds, for a full-res photo tiled into small
      // 256px-ish squares) isn't a meaningful number to show — percentage
      // is what the rest of the app's progress messages use too.
      final percent = progress.totalTiles == 0
          ? 0
          : (progress.tileIndex * 100 ~/ progress.totalTiles);
      return _LoadingInfo(
        message: l10n.aiDenoiseEnhanceTileProgress(stageLabel, percent),
        progress: progress.totalTiles == 0
            ? null
            : progress.tileIndex / progress.totalTiles,
      );
    }
    if (_isRunningCloudDenoise) {
      final stageMessage = switch (_cloudDenoiseStage) {
        'uploading' => l10n.aiDenoiseCloudStageUploading,
        'processing' => l10n.aiDenoiseCloudStageProcessing,
        'downloading' => l10n.aiDenoiseCloudStageDownloading,
        'decoding' => l10n.aiDenoiseCloudStageDecoding,
        _ => l10n.aiDenoiseCloudStartingMessage,
      };
      return _LoadingInfo(message: stageMessage);
    }
    // Deliberately NOT handled here: _isDecodingPhoto (opening a single
    // photo) gets a small spinner centered over just the image area
    // instead of this full-screen overlay — see _ImageArea's usage in
    // _buildScaffold.
    if (_isApplyingAiDenoise) {
      final stage = _aiDenoiseRenderStage;
      return _LoadingInfo(
        message: _aiDenoiseDisabling
            ? l10n.aiDenoiseDisablingMessage
            : l10n.aiDenoiseApplyingMessage,
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
    // Last: a genuinely new operation starting (any of the checks above)
    // always wins over a leftover "Done!" from whatever just finished.
    final transientStatus = _transientStatus;
    if (transientStatus != null) {
      return _LoadingInfo(message: transientStatus, isStatus: true);
    }
    return null;
  }

  Widget _buildScaffold(RawFile? selected) {
    return AnimationsConfig(
      enabled: _settings.animationsEnabled,
      child: _buildScaffoldContent(selected),
    );
  }

  Widget _buildScaffoldContent(RawFile? selected) {
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
                                    selectedRecentFile: _currentSingleFile,
                                    onSelect: (path) =>
                                        unawaited(_selectSidebarFolder(path)),
                                    onRemove: _removeLibraryFolder,
                                    onSelectRecentFile: (path) =>
                                        unawaited(_selectRecentFile(path)),
                                    onRemoveRecentFile: _removeRecentFile,
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
                                      onExportMany: (presets) =>
                                          unawaited(_exportPresets(presets)),
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
                                  fileMissing:
                                      selected != null &&
                                      _missingFiles.contains(selected.path),
                                  preview: selected == null
                                      ? null
                                      : _displayPreview(selected.path),
                                  previewFadeGeneration: _previewFadeGeneration,
                                  neutralPreview: selected == null
                                      ? null
                                      : _neutralPreviews[selected.path],
                                  beforeAfterMode: _beforeAfterMode,
                                  viewController: _viewController,
                                  viewportKey: _viewportKey,
                                  zoomScale: _zoomScale,
                                  onPointerSignal: _handlePointerSignal,
                                  onResetZoom: _resetZoomAnimated,
                                  onDoubleTapZoom: _onDoubleTapZoom,
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
                                  brushFlow: _brushFlow,
                                  onSampleColor: _onSampleMaskColor,
                                  onSampleLuminance: _onSampleMaskLuminance,
                                  wbEyedropperActive:
                                      _wbEyedropperActive && !_beforeAfterMode,
                                  onSampleWhiteBalance: _onSampleWhiteBalance,
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
                                  straighteningActive: _straighteningActive,
                                  onSecondaryTapUp: _showImageContextMenu,
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
                                // Every loading operation surfaces here now
                                // (see _loadingOverlayHidden) — a compact
                                // status line in the preview's own bottom
                                // breathing room
                                // (_ImageArea._verticalBreathingRoom) rather
                                // than a modal covering the editor.
                                if (_loadingOverlayHidden)
                                  Builder(
                                    builder: (context) {
                                      final info = _overlayInfo(
                                        context,
                                        selected,
                                      );
                                      if (info == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return Positioned(
                                        left: 16,
                                        right: 16,
                                        bottom: 12,
                                        child: Center(
                                          child: _HiddenLoadingIndicator(
                                            info: info,
                                            onCancel: _cancelLoading,
                                          ),
                                        ),
                                      );
                                    },
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
                            onWhiteBalanceMode: _applyWbMode,
                            wbEyedropperActive: _wbEyedropperActive,
                            onToggleWbEyedropper: () => setState(
                              () => _wbEyedropperActive = !_wbEyedropperActive,
                            ),
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
                            brushFlow: _brushFlow,
                            onBrushFlowChanged: _setBrushFlow,
                            onColorRangeToleranceChanged:
                                _onColorRangeToleranceChanged,
                            onColorRangeToleranceChangeEnd:
                                _onColorRangeToleranceChangeEnd,
                            onColorRangeFeatherChanged:
                                _onColorRangeFeatherChanged,
                            onColorRangeFeatherChangeEnd:
                                _onColorRangeFeatherChangeEnd,
                            onLuminanceToleranceChanged:
                                _onLuminanceToleranceChanged,
                            onLuminanceToleranceChangeEnd:
                                _onLuminanceToleranceChangeEnd,
                            onLuminanceFeatherChanged:
                                _onLuminanceFeatherChanged,
                            onLuminanceFeatherChangeEnd:
                                _onLuminanceFeatherChangeEnd,
                            cropOverlayActive: _cropOverlayActive,
                            cropTransform: _cropTransform,
                            onCropTransformChanged: _onCropTransformChanged,
                            onCropTransformChangeEnd: _onCropTransformChangeEnd,
                            cropAspectRatio: _cropAspectRatio,
                            onCropAspectRatioChanged: _setCropAspectRatio,
                            onToggleCropOverlay: _toggleCropOverlay,
                            onResetCropTransform: _resetCropTransform,
                            onStraighteningChanged: _setStraighteningActive,
                            lensCorrection: _lensCorrection,
                            onLensCorrectionChanged: _onLensCorrectionChanged,
                            onLensCorrectionChangeEnd:
                                _onLensCorrectionChangeEnd,
                            lensProfiles: _lensProfiles,
                            resolvedLensProfile: selected == null
                                ? null
                                : _resolvedLensProfileFor(selected.path),
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
                      onZoomFit: _resetZoomAnimated,
                      onToggleBeforeAfter: selected == null
                          ? null
                          : _toggleBeforeAfter,
                      canUndo: _canUndo,
                      canRedo: _canRedo,
                      onUndo: _undo,
                      onRedo: _redo,
                      aiDenoiseActive:
                          AiDenoiseParams.fromValues(_paramValues).level !=
                              null ||
                          (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0 ||
                          (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0 ||
                          (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0 ||
                          (_paramValues[_cloudDenoiseProviderKey] ?? 0.0) > 0,
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
                      presetAmount: _paramValues[_globalEditAmountKey] ?? 100.0,
                      onPresetAmountChanged: _onGlobalEditAmountChanged,
                      onPresetAmountChangeEnd: _onGlobalEditAmountChangeEnd,
                    ),
                    _Filmstrip(
                      files: _files,
                      selectedIndex: _selectedIndex,
                      thumbnails: _thumbnails,
                      onSelect: _selectIndex,
                      isEdited: _isPhotoEdited,
                      onResetEdits: (file) =>
                          unawaited(_resetAllEditsFor(file)),
                      onShowOnDisk: (file) =>
                          unawaited(_revealInExplorer(file)),
                      onDelete: (file) => unawaited(_deleteFile(file)),
                      onCopyEdits: _copyEditsFor,
                      onPasteEdits: _pasteEditsFor,
                      hasCopiedEdits: _hasCopiedEdits,
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
        color: DarkmoonColors.panel,
        border: Border(bottom: BorderSide(color: DarkmoonColors.dividerDark)),
      ),
      child: Row(
        children: [
          PopupMenuButton<VoidCallback>(
            tooltip: '',
            offset: const Offset(0, 26),
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
    required this.fileMissing,
    required this.preview,
    required this.neutralPreview,
    required this.beforeAfterMode,
    required this.viewController,
    required this.viewportKey,
    required this.zoomScale,
    required this.onPointerSignal,
    required this.onResetZoom,
    required this.onDoubleTapZoom,
    required this.editingMask,
    required this.editingSource,
    required this.onMaskGeometryChanged,
    required this.onMaskGeometryChangeEnd,
    required this.brushRadius,
    required this.brushHardness,
    required this.brushErase,
    required this.brushFlow,
    required this.onSampleColor,
    required this.onSampleLuminance,
    required this.wbEyedropperActive,
    required this.onSampleWhiteBalance,
    required this.maskOverlayVisible,
    required this.maskOverlayOpacity,
    required this.cropOverlayActive,
    required this.cropTransform,
    required this.cropAspectRatio,
    required this.onCropTransformChanged,
    required this.onCropTransformChangeEnd,
    required this.straighteningActive,
    required this.onSecondaryTapUp,
    required this.previewFadeGeneration,
  });

  final RawFile? selected;

  /// True when [selected]'s decode failed because the file itself is gone
  /// (moved/renamed/deleted outside darkmoon, or its drive unmounted) —
  /// takes priority over the "decoding..." fallback so the canvas doesn't
  /// spin forever on a decode that will never finish.
  final bool fileMissing;

  final Uint8List? preview;
  final Uint8List? neutralPreview;
  final bool beforeAfterMode;
  final TransformationController viewController;
  final GlobalKey viewportKey;

  /// Current pan/zoom factor, so the mask overlays can counter-scale their
  /// handles/outlines and stay a fixed screen size no matter the zoom.
  final double zoomScale;

  final void Function(PointerSignalEvent) onPointerSignal;

  /// "Fit" toolbar button — resets pan+zoom *and* the parent's
  /// `_zoomScale` (so the % readout and the +/- buttons stay in sync,
  /// which a bare `viewController.value = identity` doesn't do).
  final VoidCallback onResetZoom;

  /// Double-click on the image — zooms in centered on the click point if
  /// not already zoomed in, or back out to Fit if it is (the parent
  /// decides which, since that depends on its own `_zoomScale`).
  final ValueChanged<Offset> onDoubleTapZoom;

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

  /// Current brush tool settings, used when [editingMask] is a Brush or
  /// Flow mask.
  final double brushRadius;
  final double brushHardness;
  final bool brushErase;

  /// Per-pass deposit rate baked into new strokes — only meaningful when
  /// [editingMask] is a Flow mask (see [BrushStroke.flow]'s doc).
  final double brushFlow;

  /// Fires with normalized image coordinates when the user taps the image
  /// while a Color Range mask is active.
  final void Function(double nx, double ny) onSampleColor;

  /// Fires with normalized image coordinates when the user taps the image
  /// while a Luminance mask is active — mirrors [onSampleColor].
  final void Function(double nx, double ny) onSampleLuminance;

  /// Whether the White Balance eyedropper is armed — shows a tap target
  /// over the whole image regardless of the active layer.
  final bool wbEyedropperActive;
  final void Function(double nx, double ny) onSampleWhiteBalance;

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

  /// True while the Straighten slider is being dragged — [CropOverlay]
  /// shows a denser guide grid while this is set (item 28).
  final bool straighteningActive;

  /// Right-click on the image — opens the copy/paste-edits context menu.
  final void Function(Offset globalPosition) onSecondaryTapUp;

  /// See [_EditorScreenState._previewFadeGeneration]'s doc — changes
  /// only on a settled edit/preset/reset/undo/redo for the *same* photo,
  /// telling [_fadingImage] when to actually play the fade.
  final int previewFadeGeneration;

  /// Vertical breathing room around the fitted image — without this, a
  /// photo whose aspect ratio closely matches the viewport (most photos,
  /// since BoxFit.contain already maximizes it) sits flush against the
  /// top/bottom toolbar edges with zero margin, reading as cramped even
  /// though "Fit" is working exactly as designed.
  static const double _verticalBreathingRoom = 60;

  /// The main preview `Image`, wrapped so a settled render fades in
  /// (see [previewFadeGeneration]) instead of popping — a live drag
  /// frame doesn't bump the generation, so it updates in place with no
  /// animation, same as before this existed. Instant (no transition at
  /// all) when Settings > animations is off. A [Builder] rather than
  /// threading a `BuildContext` down from `build()` through several
  /// intermediate methods (`_zoomableImage`/`_fittedImage`/…) — any
  /// descendant context works for [AnimationsConfig.of].
  Widget _fadingImage(Uint8List bytes) {
    return Builder(
      builder: (context) => _FadingPreviewImage(
        bytes: bytes,
        fadeGeneration: previewFadeGeneration,
        duration: AnimationsConfig.duration(
          context,
          const Duration(milliseconds: 220),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          key: viewportKey,
          color: DarkmoonColors.canvas,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: _verticalBreathingRoom),
          child: _buildContent(l10n),
        ),
        // A sibling of the padded Container above, not a descendant of its
        // child — [_buildContent]'s own coordinate space starts *after*
        // that padding is applied, so a title positioned there at
        // `top: 14` would actually land 14px into the fitted image itself
        // (getting in the way of editing) rather than in the blank
        // breathing room genuinely reserved above it. Anchored here
        // instead, `top: 14` is 14px into that reserved margin, which the
        // image can never intrude into regardless of zoom/pan/aspect
        // ratio (the Container's padding — not this widget's zoom level —
        // is what carves out that space).
        _titleOverlay(),
      ],
    );
  }

  /// The photo's filename (minus extension) and its format badge, floating
  /// in the breathing room [_verticalBreathingRoom] leaves above the fitted
  /// image — always readable, and never over the photo itself, regardless
  /// of zoom/pan or Before/After mode.
  Widget _titleOverlay() {
    final file = selected;
    if (file == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    p.basenameWithoutExtension(file.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 6),
                _FileTypeBadge(label: file.typeLabel, isRaw: file.isRaw),
              ],
            ),
          ),
        ),
      ),
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
    if (fileMissing) {
      // Takes priority over any stale cached preview still sitting in
      // [preview]/[thumbnail] from before the file went away — showing an
      // outdated image here would be more misleading than showing nothing.
      return Text(
        l10n.photoNotFoundMessage(selected!.name),
        textAlign: TextAlign.center,
        style: const TextStyle(color: DarkmoonColors.textMuted),
      );
    }
    // Deliberately not falling back to the filmstrip [thumbnail] while
    // [preview] is still decoding — that produced a low-res, blurry
    // frame that then visibly popped to the sharp real render a moment
    // later. Simpler and calmer to just wait, then let the real preview
    // fade in on its own (see _fadingImage/_FadingPreviewImage).
    final bytes = preview;
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
    // Double-click zooms in (Lightroom/Photoshop-style, centered on the
    // click point) if not already zoomed in, or back out to Fit if it is
    // — but not while a mode with its own tap handling is active (mask
    // editing, crop overlay, eyedropper), where the tap-delay double-tap
    // introduces would make those laggy.
    final doubleTapZoomEnabled =
        editingMask == null && !cropOverlayActive && !wbEyedropperActive;
    // onDoubleTapDown fires (with the tap's position) just before
    // onDoubleTap itself, which carries no position of its own — capturing
    // it here and reading it back a moment later is the standard Flutter
    // pattern for a positioned double-tap gesture.
    Offset doubleTapPosition = Offset.zero;
    return Listener(
      onPointerSignal: onPointerSignal,
      child: GestureDetector(
        onDoubleTapDown: doubleTapZoomEnabled
            ? (details) => doubleTapPosition = details.localPosition
            : null,
        onDoubleTap: doubleTapZoomEnabled
            ? () => onDoubleTapZoom(doubleTapPosition)
            : null,
        onSecondaryTapUp: (details) => onSecondaryTapUp(details.globalPosition),
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
    if (wbEyedropperActive && source != null) {
      return SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _fadingImage(bytes),
                WhiteBalanceEyedropperOverlay(
                  containerSize: Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
                  imageWidth: source.width,
                  imageHeight: source.height,
                  onSample: onSampleWhiteBalance,
                ),
              ],
            );
          },
        ),
      );
    }
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
                _fadingImage(bytes),
                CropOverlay(
                  containerSize: containerSize,
                  imageWidth: frameWidth,
                  imageHeight: frameHeight,
                  params: cropTransform,
                  lockedAspectRatio: cropAspectRatio,
                  onChanged: onCropTransformChanged,
                  onChangeEnd: onCropTransformChangeEnd,
                  straighteningActive: straighteningActive,
                ),
              ],
            );
          },
        ),
      );
    }
    final noOverlay = mask == null || source == null;
    return SizedBox.expand(
      child: noOverlay
          ? _fadingImage(bytes)
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
                    if (mask.type == MaskType.brush ||
                        mask.type == MaskType.flow)
                      BrushMaskOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        zoomScale: zoomScale,
                        mask: mask,
                        brushRadius: brushRadius,
                        brushHardness: brushHardness,
                        brushErase: brushErase,
                        brushFlow: brushFlow,
                        onChanged: onMaskGeometryChanged,
                        onChangeEnd: onMaskGeometryChangeEnd,
                        showOverlay: maskOverlayVisible,
                        overlayOpacity: maskOverlayOpacity[mask.type]!,
                      )
                    else if (mask.type == MaskType.colorRange ||
                        mask.type == MaskType.luminance)
                      ColorRangeOverlay(
                        containerSize: containerSize,
                        imageWidth: source.width,
                        imageHeight: source.height,
                        onSample: mask.type == MaskType.luminance
                            ? onSampleLuminance
                            : onSampleColor,
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
                        zoomScale: zoomScale,
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

/// Shows [bytes], fading it in whenever [fadeGeneration] changes (a
/// settled edit/preset/reset/undo/redo — see `_ImageArea.previewFadeGeneration`'s
/// doc) rather than the [AnimatedSwitcher] this replaced, which
/// crossfaded the old and new image simultaneously — with both
/// partially transparent at once, the dark canvas behind them showed
/// through for a moment, reading as a "blink". Here the previous frame
/// stays fully opaque as a base layer the whole time; only the new
/// frame fades in on top of it, so the canvas is never exposed.
class _FadingPreviewImage extends StatefulWidget {
  const _FadingPreviewImage({
    required this.bytes,
    required this.fadeGeneration,
    required this.duration,
  });

  final Uint8List bytes;
  final int fadeGeneration;
  final Duration duration;

  @override
  State<_FadingPreviewImage> createState() => _FadingPreviewImageState();
}

class _FadingPreviewImageState extends State<_FadingPreviewImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The previous frame, kept as a fully-opaque base layer only while
  /// [_controller] is actively fading the new one in on top of it —
  /// cleared once the fade completes (or immediately, for an instant/
  /// live-drag update) so a stale frame doesn't linger in the tree.
  Uint8List? _previousBytes;

  bool get _shouldAnimate => widget.duration > Duration.zero;

  @override
  void initState() {
    super.initState();
    // The very first frame shown for a freshly-opened photo fades in
    // from nothing too (see _EditorScreenState._buildContent, which
    // shows a "decoding…" placeholder — not a previous image — until
    // this widget first mounts).
    _controller = AnimationController(
      vsync: this,
      value: _shouldAnimate ? 0.0 : 1.0,
      duration: widget.duration,
    );
    if (_shouldAnimate) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_FadingPreviewImage old) {
    super.didUpdateWidget(old);
    if (widget.fadeGeneration != old.fadeGeneration && _shouldAnimate) {
      setState(() => _previousBytes = old.bytes);
      _controller
        ..duration = widget.duration
        ..forward(from: 0);
    } else {
      // A live drag frame, or animations are off — swap instantly.
      if (_previousBytes != null) {
        setState(() => _previousBytes = null);
      }
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previousBytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (previous != null)
          Image.memory(previous, fit: BoxFit.contain, gaplessPlayback: true),
        FadeTransition(
          opacity: _controller,
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      ],
    );
  }
}

/// What the loading overlay shows: a message, an optional real progress
/// fraction (null means indeterminate — no measurable sub-steps yet).
class _LoadingInfo {
  const _LoadingInfo({
    required this.message,
    this.progress,
    this.isStatus = false,
  });

  final String message;
  final double? progress;

  /// True for a brief, non-cancellable confirmation (e.g. "Done!" after an
  /// export) rather than an actual in-progress operation — hides the
  /// Cancel button and the progress bar, neither of which mean anything
  /// once the operation they'd apply to has already finished.
  final bool isStatus;
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
          width: 300,
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

/// The compact loading status line every operation now shows (folder
/// open, AI denoise, slow render, export) — plain white text + bar with no
/// card or scrim, sitting in the preview's bottom breathing room so it
/// reads as chrome rather than a modal. The message and bar are centred on
/// the preview; the Cancel button is pinned to the right edge without
/// stealing width from the bar, so the status doesn't look off-centre.
class _HiddenLoadingIndicator extends StatelessWidget {
  const _HiddenLoadingIndicator({required this.info, required this.onCancel});

  final _LoadingInfo info;
  final VoidCallback onCancel;

  /// Fixed width so the bar length (and the centring) is stable regardless
  /// of message length — matches [_LoadingOverlay]'s card width.
  static const double _width = 300;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = info.progress;
    return SizedBox(
      width: _width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Balances the Cancel button on the right so the message
              // stays visually centred over the bar.
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  info.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                ),
              ),
              SizedBox(
                width: 24,
                height: 20,
                // A status message (e.g. "Done!") has nothing left running
                // to cancel — leave the space blank instead of a
                // meaningless button.
                child: info.isStatus
                    ? null
                    : IconButton(
                        onPressed: onCancel,
                        tooltip: l10n.cancelButton,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 20,
                        ),
                        // Override the app-wide IconButtonTheme's filled
                        // rounded-square + border — this bar is meant to
                        // read as bare chrome (see this class's doc
                        // comment), not another boxed toolbar button.
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: BorderSide.none,
                          shape: const CircleBorder(),
                        ),
                        iconSize: 15,
                        color: Colors.white,
                        icon: const Icon(CupertinoIcons.xmark),
                      ),
              ),
            ],
          ),
          // A status message doesn't have real progress to show — the bar
          // below is either genuine percent-complete or an indeterminate
          // "something's happening" spinner, neither of which applies once
          // the operation it described is already done.
          if (!info.isStatus) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: progress == null
                    ? const LinearProgressIndicator(
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      )
                    : LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Side length of the toolbar's square icon-only buttons (Fit to window,
/// Undo/Reset/Redo, Crop, AI Denoise, Before/After) — the toolbar's most
/// frequently-tapped controls, sized up from the default pill height (40)
/// and made exactly 1:1 rather than the usual wider-than-tall rectangle.
const double _squareButtonSize = 38;
const double _squareButtonIconSize = 16;

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
    required this.onPresetAmountChangeEnd,
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

  /// How strongly the *entire current edit* renders, 0..150% — see the
  /// top-level `_globalEditAmountKey`/`_withGlobalEditAmountApplied`.
  /// Lives here (rather than in `PresetPanel`) so it sits in the
  /// toolbar's left spacer, under the preset list, matching the
  /// width-alignment convention the two reserved spacers already follow
  /// — a purely visual placement choice at this point, not a sign this
  /// only affects presets.
  final double presetAmount;
  final ValueChanged<double> onPresetAmountChanged;
  final ValueChanged<double> onPresetAmountChangeEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 64,
      color: DarkmoonColors.panel,
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
                    onChangeEnd: onPresetAmountChangeEnd,
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
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.minus,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: onZoomOut,
                      ),
                      _ToolbarSegment(
                        label: zoomLabel,
                        width: _squareButtonSize,
                        padded: false,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.add,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: onZoomIn,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_up_left_arrow_down_right,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
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
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_uturn_left,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: canUndo ? onUndo : null,
                        tooltip: l10n.undoButton,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_2_circlepath,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: onReset,
                        tooltip: l10n.resetTooltip,
                      ),
                      _ToolbarSegment(
                        icon: CupertinoIcons.arrow_uturn_right,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        onTap: canRedo ? onRedo : null,
                        tooltip: l10n.redoButton,
                      ),
                    ],
                  ),
                  const Spacer(),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.crop,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        selected: cropOverlayActive,
                        onTap: onToggleCropOverlay,
                        tooltip: l10n.cropButton,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.sparkles,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
                        selected: aiDenoiseActive,
                        onTap: onOpenAiDenoise,
                        tooltip: l10n.aiDenoiseButton,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _ToolbarPill(
                    height: _squareButtonSize,
                    showChrome: false,
                    children: [
                      _ToolbarSegment(
                        icon: CupertinoIcons.square_split_2x1,
                        iconSize: _squareButtonIconSize,
                        width: _squareButtonSize,
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
          // Must match _controlsPanelWidth (not a separate literal): a
          // stale 280 here (_ControlsPanel is actually 300) shifted this
          // whole trailing slot 20px narrower than the real column above
          // it, which pushed the pill Row before it 20px too far right —
          // visibly spilling the rightmost pill (Before/After) into the
          // real right-column boundary.
          SizedBox(
            width: _controlsPanelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: _squareButtonSize,
                      child: ElevatedButton.icon(
                        onPressed: exporting ? null : onExport,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          // A step up from the standard (very subtle)
                          // border token — Export is the toolbar's one
                          // primary action, so its outline gets a little
                          // more presence without going full accent/white.
                          // Darker than textMuted (tried first, read as
                          // too light).
                          side: const BorderSide(
                            color: Color(0xFF45474A),
                            width: 1.0,
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
                          style: const TextStyle(fontSize: 12.5),
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
  const _ToolbarPill({
    required this.children,
    this.height = 40,
    this.showChrome = true,
  });

  final List<Widget> children;

  /// Lets a pill of purely square icon buttons (see [_ToolbarSegment]'s
  /// `width` matching this) stand out a bit larger than the default —
  /// e.g. Crop/AI Denoise/Before-After/Undo/Reset/Redo/Fit-to-window,
  /// which are tapped far more often than the zoom +/- pair.
  final double height;

  /// Whether the pill draws its background fill/border/segment dividers
  /// at all — off for the viewer toolbar's experiment in bare, boxless
  /// buttons. The shape (radius/clip) stays wired either way, so
  /// flipping this back to true restores the old boxed look exactly.
  final bool showChrome;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: showChrome
          ? BoxDecoration(
              color: DarkmoonColors.surfaceRaised,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: DarkmoonColors.border),
            )
          : BoxDecoration(borderRadius: BorderRadius.circular(7)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && showChrome)
              Container(width: 1, color: DarkmoonColors.border),
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
    this.iconSize = 16,
  });

  final IconData? icon;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;
  final String? tooltip;
  final double? width;
  final double iconSize;
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
          ? Icon(icon, size: iconSize, color: foreground)
          : Text(
              label!,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: 12.5, color: foreground),
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
    required this.onStraighteningChanged,
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

  /// See [_ControlsPanel.onStraighteningChanged].
  final ValueChanged<bool> onStraighteningChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DarkmoonColors.sectionCardBackground,
        borderRadius: BorderRadius.circular(10),
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
            // Nailing an exact horizon angle needs finer per-pixel
            // control than the default drag sensitivity gives — nearly
            // 3x the usual full-range drag distance.
            maxFullRangeDragPixels: 1400,
            onChanged: (v) {
              onStraighteningChanged(true);
              onChanged(params.copyWith(straightenAngle: v));
            },
            onChangeEnd: (v) {
              onStraighteningChanged(false);
              onChangeEnd(params.copyWith(straightenAngle: v));
            },
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
const _controlsPanelWidth = 300.0;
const _controlsPanelInset = 16.0;

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.enabled,
    this.onEnabledChanged,
    this.onHoverChanged,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  /// Reports hover enter/exit on just this header's own hit area, so the
  /// enclosing [_SectionCard] can highlight the *whole* card while only
  /// the header itself is actually hoverable/clickable.
  final ValueChanged<bool>? onHoverChanged;

  /// When non-null (only for the sections in [_sections], which map
  /// straight onto sliders — Tone Curve/Color Mixer/etc. have their own
  /// editors and aren't covered), shows a switch that turns off this
  /// whole category's contribution to the render without discarding its
  /// slider values, so the user can A/B a category the way a solo/mute
  /// button works in an audio mixer.
  final bool? enabled;
  final ValueChanged<bool>? onEnabledChanged;

  /// Bolder, larger, sentence-scale label — replaces the old tiny
  /// tight-tracked all-caps style with something closer to Photomator's
  /// plain bold section titles (no boxed background/border bar to match).
  static const _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: DarkmoonColors.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Spacing lives here, outside the InkWell, so hovering/clicking the
      // gap above and below the header doesn't register as a tap on it —
      // only the visible row itself should react. The larger bottom gap
      // keeps the first slider/editor from sitting flush against it.
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: MouseRegion(
        onEnter: (_) => onHoverChanged?.call(true),
        onExit: (_) => onHoverChanged?.call(false),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            // The enclosing MouseRegion already drives the whole
            // _SectionCard's hover tint — this InkWell's own default
            // hover/highlight overlay would otherwise paint a *second*,
            // smaller one on just the header row on top of it.
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: _labelStyle.copyWith(
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
                      width: 34,
                      height: 21,
                      child: FittedBox(
                        child: Switch(
                          value: enabled!,
                          onChanged: onEnabledChanged,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
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
    );
  }
}

/// Wraps a section's header and collapsible body together in one
/// rounded, bordered card sitting on the panel's own background —
/// Photomator-style grouped section, replacing the old flat list of
/// headers/sliders with no visual boundary between sections.
///
/// Builds [_SectionHeader] itself (rather than taking a pre-built header
/// widget) so it can wire up [_SectionHeader.onHoverChanged] and use that
/// to highlight the *whole* card on hover, even though only the header
/// itself is the actual hoverable/clickable hit area — hovering a slider
/// or curve editor in [body] must never trigger this.
class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.enabled,
    this.onEnabledChanged,
    required this.body,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onTap;
  final bool? enabled;
  final ValueChanged<bool>? onEnabledChanged;
  final Widget body;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _headerHovered = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AnimationsConfig.duration(
        context,
        const Duration(milliseconds: 120),
      ),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      decoration: BoxDecoration(
        color: _headerHovered
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: 0.03),
                DarkmoonColors.sectionCardBackground,
              )
            : DarkmoonColors.sectionCardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DarkmoonColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            label: widget.label,
            collapsed: widget.collapsed,
            onTap: widget.onTap,
            enabled: widget.enabled,
            onEnabledChanged: widget.onEnabledChanged,
            onHoverChanged: (hovered) =>
                setState(() => _headerHovered = hovered),
          ),
          widget.body,
        ],
      ),
    );
  }
}

/// Animates a section's content growing/shrinking under its
/// [_SectionHeader] instead of popping in/out — [child] stays mounted the
/// whole time (so its own state, e.g. a slider mid-drag, survives a
/// collapse/expand), just laid out at zero height and fully transparent
/// while [collapsed]. `ClipRect` hides the part of [child] that doesn't
/// fit during the animation (`AnimatedAlign`'s `heightFactor` shrinks the
/// space it's *given*, not [child]'s own painted size, so without the
/// clip it would bleed into the next section while collapsing).
class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({required this.collapsed, required this.child});

  final bool collapsed;
  final Widget child;

  static const _duration = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) {
    final duration = AnimationsConfig.duration(context, _duration);
    return ClipRect(
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: collapsed ? 0.0 : 1.0,
        child: AnimatedOpacity(
          duration: duration,
          curve: Curves.easeOutCubic,
          opacity: collapsed ? 0.0 : 1.0,
          child: child,
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
    required this.onLuminanceToleranceChanged,
    required this.onLuminanceToleranceChangeEnd,
    required this.onLuminanceFeatherChanged,
    required this.onLuminanceFeatherChangeEnd,
    required this.brushFlow,
    required this.onBrushFlowChanged,
    required this.cropOverlayActive,
    required this.cropTransform,
    required this.onCropTransformChanged,
    required this.onCropTransformChangeEnd,
    required this.cropAspectRatio,
    required this.onCropAspectRatioChanged,
    required this.onToggleCropOverlay,
    required this.onResetCropTransform,
    required this.onStraighteningChanged,
    required this.lensCorrection,
    required this.onLensCorrectionChanged,
    required this.onLensCorrectionChangeEnd,
    required this.lensProfiles,
    required this.resolvedLensProfile,
    required this.onWhiteBalanceMode,
    required this.wbEyedropperActive,
    required this.onToggleWbEyedropper,
  });

  final Map<String, double> values;
  final Histogram? histogram;
  final RawMetadata? metadata;
  final void Function(WbMode mode) onWhiteBalanceMode;
  final bool wbEyedropperActive;
  final VoidCallback onToggleWbEyedropper;
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

  /// Flow mask's live per-pass deposit-rate tool setting — shares the
  /// brush-drawing controls/state above, this is its one extra slider.
  final double brushFlow;
  final ValueChanged<double> onBrushFlowChanged;

  final ValueChanged<double> onColorRangeToleranceChanged;
  final ValueChanged<double> onColorRangeToleranceChangeEnd;
  final ValueChanged<double> onColorRangeFeatherChanged;
  final ValueChanged<double> onColorRangeFeatherChangeEnd;

  final ValueChanged<double> onLuminanceToleranceChanged;
  final ValueChanged<double> onLuminanceToleranceChangeEnd;
  final ValueChanged<double> onLuminanceFeatherChanged;
  final ValueChanged<double> onLuminanceFeatherChangeEnd;

  final bool cropOverlayActive;
  final CropTransformParams cropTransform;
  final ValueChanged<CropTransformParams> onCropTransformChanged;
  final ValueChanged<CropTransformParams> onCropTransformChangeEnd;
  final double? cropAspectRatio;
  final ValueChanged<double?> onCropAspectRatioChanged;
  final VoidCallback onToggleCropOverlay;
  final VoidCallback onResetCropTransform;

  /// Fires as the Straighten slider is dragged (true) and once it's
  /// released (false) — lets the crop overlay show a denser guide grid
  /// only while the user's actively trying to level a horizon (item 28).
  final ValueChanged<bool> onStraighteningChanged;

  final LensCorrectionParams lensCorrection;
  final ValueChanged<LensCorrectionParams> onLensCorrectionChanged;
  final ValueChanged<LensCorrectionParams> onLensCorrectionChangeEnd;
  final List<LensProfile> lensProfiles;

  /// The profile actually in effect for the selected photo right now --
  /// see `_resolvedLensProfileFor`'s doc comment.
  final LensProfile? resolvedLensProfile;

  @override
  State<_ControlsPanel> createState() => _ControlsPanelState();
}

class _ControlsPanelState extends State<_ControlsPanel> {
  /// Section names the user has collapsed, Lightroom-style — every section
  /// starts expanded, matching the panel's previous (always-open) layout.
  final Set<String> _collapsed = {};

  /// Drives the panel's own scroll position — used only to auto-scroll
  /// back to the top when the Crop & Transform panel opens (it's inserted
  /// at the very top of this list), since it would otherwise render
  /// off-screen above whatever section the user had scrolled down to
  /// (e.g. Effects), reading as "nothing happened" when Crop was tapped.
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_ControlsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cropOverlayActive && !oldWidget.cropOverlayActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.animateTo(
          0,
          duration: AnimationsConfig.duration(
            context,
            const Duration(milliseconds: 260),
          ),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// The camera as-shot White Balance for the current photo — the neutral
  /// reference the Temperature/Tint sliders default to.
  ({double kelvin, double tint}) get _asShot => (
    kelvin: widget.metadata?.asShotKelvin ?? wbDefaultKelvin,
    tint: widget.metadata?.asShotTint ?? wbDefaultTint,
  );

  /// The neutral point for the Temperature/Tint sliders — where the value
  /// marker sits and what a double-click resets to. It follows the
  /// selected White Balance mode: a fixed lighting preset uses that
  /// preset's Kelvin/Tint, everything else (As Shot / Auto / Custom) uses
  /// the camera as-shot. Null for any non-WB slider.
  double? _wbSliderFallback(String name) {
    if (name != 'Temperature' && name != 'Tint') {
      return null;
    }
    final modeIndex = (widget.values['WhiteBalanceMode'] ?? 0).toInt().clamp(
      0,
      WbMode.values.length - 1,
    );
    final preset = wbModePreset(WbMode.values[modeIndex]);
    if (preset != null) {
      return name == 'Temperature' ? preset.kelvin : preset.tint;
    }
    return name == 'Temperature' ? _asShot.kelvin : _asShot.tint;
  }

  String _wbModeLabel(AppLocalizations l10n, WbMode mode) => switch (mode) {
    WbMode.asShot => l10n.wbModeAsShot,
    WbMode.auto => l10n.wbModeAuto,
    WbMode.daylight => l10n.wbModeDaylight,
    WbMode.cloudy => l10n.wbModeCloudy,
    WbMode.shade => l10n.wbModeShade,
    WbMode.tungsten => l10n.wbModeTungsten,
    WbMode.fluorescent => l10n.wbModeFluorescent,
    WbMode.flash => l10n.wbModeFlash,
    WbMode.custom => l10n.wbModeCustom,
  };

  Widget _buildWhiteBalanceModeRow(
    AppLocalizations l10n,
    Map<String, double> values,
  ) {
    final modeIndex = (values['WhiteBalanceMode'] ?? 0).toInt().clamp(0, 8);
    return Row(
      children: [
        Expanded(
          child: StyledDropdown<int>(
            value: modeIndex,
            // Short fixed list — show every mode without a scroll.
            maxMenuHeight: 460,
            items: [
              for (final mode in WbMode.values)
                StyledDropdownItem(
                  value: mode.index,
                  label: _wbModeLabel(l10n, mode),
                ),
            ],
            onChanged: (i) => widget.onWhiteBalanceMode(WbMode.values[i]),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 34,
          height: 34,
          child: IconButton(
            tooltip: l10n.wbEyedropperTooltip,
            isSelected: widget.wbEyedropperActive,
            onPressed: widget.onToggleWbEyedropper,
            icon: const Icon(CupertinoIcons.eyedropper, size: 15),
          ),
        ),
      ],
    );
  }

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

  /// Builds one section: a [_SectionHeader] plus its collapsible body,
  /// wrapped together in a single [_SectionCard]. Returns a one-element
  /// list (not the widget directly) so call sites can keep spreading it
  /// into a `children:` list with `...`.
  List<Widget> _section(
    String key, {
    required String label,
    bool? enabled,
    ValueChanged<bool>? onEnabledChanged,
    required List<Widget> children,
  }) => [
    _SectionCard(
      label: label,
      collapsed: _collapsed.contains(key),
      onTap: () => _toggleSection(key),
      enabled: enabled,
      onEnabledChanged: onEnabledChanged,
      body: _CollapsibleSection(
        collapsed: _collapsed.contains(key),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  ];

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
    final isBrushActive =
        activeMask?.type == MaskType.brush || activeMask?.type == MaskType.flow;
    final isFlowActive = activeMask?.type == MaskType.flow;
    final isColorRangeActive = activeMask?.type == MaskType.colorRange;
    final isLuminanceActive = activeMask?.type == MaskType.luminance;
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
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Divider(
                        color: DarkmoonColors.divider,
                        height: 1,
                        thickness: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
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
                          onStraighteningChanged: widget.onStraighteningChanged,
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
                        if (isFlowActive)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SliderRow(
                              name: l10n.flowAmountLabel,
                              min: 1,
                              max: 100,
                              value: widget.brushFlow,
                              decimals: 0,
                              defaultValue: defaultFlowAmount,
                              onChanged: widget.onBrushFlowChanged,
                              onChangeEnd: widget.onBrushFlowChanged,
                            ),
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
                      if (isLuminanceActive) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Color.fromARGB(
                                  255,
                                  activeMask!.luminance.targetLuma
                                      .round()
                                      .clamp(0, 255),
                                  activeMask.luminance.targetLuma.round().clamp(
                                    0,
                                    255,
                                  ),
                                  activeMask.luminance.targetLuma.round().clamp(
                                    0,
                                    255,
                                  ),
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
                                l10n.luminanceHint,
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
                            name: l10n.luminanceToleranceLabel,
                            min: 0,
                            max: 100,
                            value: activeMask.luminance.tolerance,
                            decimals: 0,
                            onChanged: widget.onLuminanceToleranceChanged,
                            onChangeEnd: widget.onLuminanceToleranceChangeEnd,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SliderRow(
                            name: l10n.luminanceFeatherLabel,
                            min: 0,
                            max: 100,
                            value: activeMask.luminance.feather,
                            decimals: 0,
                            onChanged: widget.onLuminanceFeatherChanged,
                            onChangeEnd: widget.onLuminanceFeatherChangeEnd,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      for (final entry in _sections.entries) ...[
                        // `values`/`onChanged`/`onChangeEnd` already resolve to
                        // either the global layer or the active mask's own (see
                        // the comment below on Tone Curve/Color Mixer/etc.), so
                        // the toggle works identically for both — no separate
                        // mask-vs-global branch needed.
                        ..._section(
                          entry.key,
                          label: _sectionLabel(l10n, entry.key),
                          enabled:
                              (values[_categoryEnabledKey(entry.key)] ?? 1) !=
                              0,
                          onEnabledChanged: (v) {
                            final key = _categoryEnabledKey(entry.key);
                            onChanged(key, v ? 1 : 0);
                            onChangeEnd(key, v ? 1 : 0);
                          },
                          children: [
                            if (entry.key == 'WHITE BALANCE')
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 6,
                                  bottom: 14,
                                ),
                                child: _buildWhiteBalanceModeRow(l10n, values),
                              ),
                            for (final spec in entry.value)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SliderRow(
                                  name: _sliderLabel(l10n, spec.name),
                                  min: spec.min,
                                  max: spec.max,
                                  value:
                                      values[spec.name] ??
                                      _wbSliderFallback(spec.name) ??
                                      spec.defaultValue,
                                  decimals: spec.decimals,
                                  defaultValue:
                                      _wbSliderFallback(spec.name) ??
                                      spec.defaultValue,
                                  trackColors: spec.gradientColors,
                                  valueSuffix: spec.valueSuffix,
                                  onChanged: (v) => onChanged(spec.name, v),
                                  onChangeEnd: (v) => onChangeEnd(spec.name, v),
                                ),
                              ),
                            // (The old "preserve brightness on Tint" toggle
                            // was removed — the current WB model is
                            // luminance-normalised by construction, so it
                            // was a no-op. The param still exists, inert.)
                          ],
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
                          ..._section(
                            'TONE CURVE',
                            label: l10n.sectionToneCurve,
                            enabled:
                                (values[_categoryEnabledKey('TONE CURVE')] ??
                                    1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('TONE CURVE');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ToneCurveEditor(
                                  points: curves.tone,
                                  onChanged: onToneCurveChanged,
                                  onChangeEnd: onToneCurveChangeEnd,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  l10n.toneCurveParametricLabel,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: DarkmoonColors.textMuted,
                                      ),
                                ),
                              ),
                              for (final spec in _parametricCurveSliders)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SliderRow(
                                    name: _sliderLabel(l10n, spec.name),
                                    min: spec.min,
                                    max: spec.max,
                                    value:
                                        values[spec.name] ?? spec.defaultValue,
                                    decimals: spec.decimals,
                                    defaultValue: spec.defaultValue,
                                    onChanged: (v) => onChanged(spec.name, v),
                                    onChangeEnd: (v) =>
                                        onChangeEnd(spec.name, v),
                                  ),
                                ),
                            ],
                          ),
                          ..._section(
                            'COLOR CURVE',
                            label: l10n.sectionColorCurve,
                            enabled:
                                (values[_categoryEnabledKey('COLOR CURVE')] ??
                                    1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('COLOR CURVE');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 8,
                                ),
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
                                  onChangeEnd: (points) =>
                                      onColorCurveChangeEnd(
                                        _activeColorChannel,
                                        points,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          ..._section(
                            'COLOR MIXER',
                            label: l10n.sectionColorMixer,
                            enabled:
                                (values[_categoryEnabledKey('COLOR MIXER')] ??
                                    1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('COLOR MIXER');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
                            children: [
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
                                // Luminance re-enabled: color_mixer.dart now
                                // ports RapidRAW's apply_hsl_panel in full
                                // (scene-linear HSV, per-band Gaussian
                                // influence, saturation-gated), including its
                                // luma-preserving-then-adjusting Luminance
                                // term — a different code path from the one
                                // previously disabled after reports of it
                                // blowing out/pixelating pixels (that one
                                // relied on HSL lightness directly, not luma
                                // explicitly restored after the shift).
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
                                      trackColors: _mixerTrackColors(
                                        _activeMixerChannel,
                                        suffix,
                                      ),
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
                                              trackColors: _mixerTrackColors(
                                                channel,
                                                suffix,
                                              ),
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
                          ),
                          ..._section(
                            'COLOR GRADING',
                            label: l10n.sectionColorGrading,
                            enabled:
                                (values[_categoryEnabledKey('COLOR GRADING')] ??
                                    1) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('COLOR GRADING');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
                            children: [
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
                          ),
                          ..._section(
                            'EFFECTS',
                            label: l10n.sectionEffects,
                            // Off by default (unlike every other section) —
                            // see _withCategoriesApplied's disabled() doc.
                            enabled:
                                (values[_categoryEnabledKey('EFFECTS')] ?? 0) !=
                                0,
                            onEnabledChanged: (v) {
                              final key = _categoryEnabledKey('EFFECTS');
                              onChanged(key, v ? 1 : 0);
                              onChangeEnd(key, v ? 1 : 0);
                            },
                            children: [
                              for (final spec in [
                                ..._vignetteSliders,
                                ..._grainSliders,
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SliderRow(
                                    name: _sliderLabel(l10n, spec.name),
                                    min: spec.min,
                                    max: spec.max,
                                    value:
                                        values[spec.name] ?? spec.defaultValue,
                                    decimals: spec.decimals,
                                    defaultValue: spec.defaultValue,
                                    onChanged: (v) => onChanged(spec.name, v),
                                    onChangeEnd: (v) =>
                                        onChangeEnd(spec.name, v),
                                  ),
                                ),
                            ],
                          ),
                          ..._section(
                            'LENS CORRECTION',
                            label: l10n.sectionLensCorrection,
                            enabled: widget.lensCorrection.enabled,
                            onEnabledChanged: (v) =>
                                widget.onLensCorrectionChangeEnd(
                                  widget.lensCorrection.copyWith(enabled: v),
                                ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: LensCorrectionPanel(
                                  params: widget.lensCorrection,
                                  resolvedProfile: widget.resolvedLensProfile,
                                  allProfiles: widget.lensProfiles,
                                  cameraMake: widget.metadata?.cameraMake ?? '',
                                  onChanged: widget.onLensCorrectionChanged,
                                  onChangeEnd: widget.onLensCorrectionChangeEnd,
                                ),
                              ),
                            ],
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

/// The hue angle (degrees) each Color Mixer channel is centred on —
/// matches `color_mixer.dart` / the shader's `HSL_RANGES` centres.
double _mixerChannelHue(String channel) => switch (channel) {
  'Red' => 358.0,
  'Orange' => 25.0,
  'Yellow' => 60.0,
  'Green' => 115.0,
  'Aqua' => 180.0,
  'Blue' => 225.0,
  'Purple' => 280.0,
  'Magenta' => 330.0,
  _ => 0.0,
};

/// Track gradient for a Color Mixer slider — the Hue slider runs through
/// the channel's actual neighbouring hues (Lightroom-style), Saturation
/// grey→colour, Luminance dark→light of the colour.
List<Color> _mixerTrackColors(String channel, String suffix) {
  final hue = _mixerChannelHue(channel);
  Color at(double h, double s, double v) =>
      HSVColor.fromAHSV(1, h % 360, s, v).toColor();
  switch (suffix) {
    case 'Hue':
      return [
        at(hue - 42, 0.85, 0.95),
        at(hue, 0.85, 0.95),
        at(hue + 42, 0.85, 0.95),
      ];
    case 'Luminance':
      return [at(hue, 0.7, 0.22), at(hue, 0.85, 0.92), at(hue, 0.2, 1.0)];
    default: // Saturation
      return [const Color(0xFF6C6C72), at(hue, 0.9, 0.95)];
  }
}

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
    return _SegmentedTabs<String>(
      items: _modes,
      active: active,
      onSelect: onSelect,
      labelOf: (mode) =>
          mode == 'Mixer' ? l10n.mixerModeMixerLabel : l10n.mixerModeHslLabel,
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
    return _SegmentedTabs<String>(
      items: _ranges,
      active: active,
      onSelect: onSelect,
      labelOf: (range) => _gradeRangeLabel(l10n, range),
    );
  }
}

/// A single rounded, bordered capsule holding equal-width segments, the
/// active one highlighted by a borderless flat-fill pill rather than
/// each segment carrying its own border — softer, Photomator-style
/// segmented control shared by [_GradeRangeTabs] and [_ColorChannelTabs].
class _SegmentedTabs<T> extends StatelessWidget {
  const _SegmentedTabs({
    required this.items,
    required this.active,
    required this.onSelect,
    required this.labelOf,
    this.colorOf,
  });

  final List<T> items;
  final T active;
  final ValueChanged<T> onSelect;
  final String Function(T item) labelOf;

  /// Per-segment highlight color when selected — defaults to the app's
  /// monochrome accent everywhere except [_ColorChannelTabs], which
  /// color-codes each channel to match the curve editor itself.
  final Color Function(T item)? colorOf;

  static const _duration = Duration(milliseconds: 200);
  static const _padding = 3.0;

  @override
  Widget build(BuildContext context) {
    final activeIndex = items.indexOf(active);
    return Container(
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: DarkmoonColors.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: DarkmoonColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth =
              (constraints.maxWidth - _padding * 2) / items.length;
          return Stack(
            children: [
              // The sliding highlight — a single pill that animates its
              // *position* between segments (not a per-segment fade),
              // matching the standard segmented-control feel (iOS tab
              // bars, Photomator's own range picker).
              AnimatedPositioned(
                duration: AnimationsConfig.duration(context, _duration),
                curve: Curves.easeOut,
                left: segmentWidth * activeIndex,
                width: segmentWidth,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: (colorOf?.call(active) ?? DarkmoonColors.accent)
                        .withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: _SegmentedTab(
                        label: labelOf(item),
                        selected: item == active,
                        color: colorOf?.call(item) ?? DarkmoonColors.accent,
                        onTap: () => onSelect(item),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentedTab extends StatelessWidget {
  const _SegmentedTab({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        // The sliding highlight pill lives behind this in the parent
        // Stack — only the text color/weight animates here.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Align(
            child: AnimatedDefaultTextStyle(
              duration: AnimationsConfig.duration(context, _duration),
              curve: Curves.easeOut,
              style: TextStyle(
                color: selected ? color : DarkmoonColors.textSecondary,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        ),
      ),
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
    final l10n = AppLocalizations.of(context)!;
    return _SegmentedTabs<String>(
      items: _channels,
      active: active,
      onSelect: onSelect,
      labelOf: (channel) => _colorChannelLabel(l10n, channel),
      colorOf: _channelColor,
    );
  }
}

String _colorChannelLabel(AppLocalizations l10n, String channel) {
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

class _Filmstrip extends StatefulWidget {
  const _Filmstrip({
    required this.files,
    required this.selectedIndex,
    required this.thumbnails,
    required this.onSelect,
    required this.isEdited,
    required this.onResetEdits,
    required this.onShowOnDisk,
    required this.onDelete,
    required this.onCopyEdits,
    required this.onPasteEdits,
    required this.hasCopiedEdits,
  });

  final List<RawFile> files;
  final int? selectedIndex;
  final Map<String, Uint8List> thumbnails;
  final ValueChanged<int> onSelect;

  /// Whether a photo has any saved edit — shows a small badge over its
  /// thumbnail when true.
  final bool Function(String path) isEdited;

  /// Right-click menu actions — each takes the photo it was invoked on,
  /// not necessarily the currently-selected one (right-clicking a
  /// non-selected thumbnail acts on that thumbnail, matching how a file
  /// manager's context menu works).
  final ValueChanged<RawFile> onResetEdits;
  final ValueChanged<RawFile> onShowOnDisk;
  final ValueChanged<RawFile> onDelete;
  final ValueChanged<RawFile> onCopyEdits;
  final ValueChanged<RawFile> onPasteEdits;

  /// Whether there's anything to paste right now — disables "Paste Edits"
  /// in the context menu otherwise, same as the main canvas's own menu.
  final bool hasCopiedEdits;

  @override
  State<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<_Filmstrip> {
  final _scrollController = ScrollController();

  /// Key on the currently-selected thumbnail, so [Scrollable.ensureVisible]
  /// can centre it exactly (handling the list padding / viewport math the
  /// rough jump below only approximates).
  final _selectedItemKey = GlobalKey();

  /// Thumbnail slot width (104) plus the 6px right padding between slots —
  /// the stride from one thumbnail's left edge to the next's.
  static const _slotStride = 110.0;
  static const _slotWidth = 104.0;
  static const _listPadding = 8.0;

  @override
  void initState() {
    super.initState();
    _recenterAfterLayout(animated: false);
  }

  @override
  void didUpdateWidget(_Filmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-center when the selection moves, or when a new folder's files
    // arrive (startup restores the last photo, but the strip would
    // otherwise sit at offset 0 with that photo scrolled off-screen).
    final selectionMoved = widget.selectedIndex != oldWidget.selectedIndex;
    final filesChanged = widget.files.length != oldWidget.files.length;
    if ((selectionMoved || filesChanged) && widget.selectedIndex != null) {
      _recenterAfterLayout(animated: selectionMoved && !filesChanged);
    }
  }

  /// The strip and its scroll position aren't laid out yet on the frame a
  /// folder first loads (and on startup the restored folder can take a
  /// while), so retry over the next second or so until the controller has
  /// real content dimensions.
  void _recenterAfterLayout({required bool animated, int attempt = 0}) {
    if (attempt > 40) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
        _centerOnSelected(animated: animated);
      } else {
        _recenterAfterLayout(animated: animated, attempt: attempt + 1);
      }
    });
  }

  /// Scrolls so the selected thumbnail sits in the middle of the strip
  /// (clamped at the ends, so the first/last few photos don't leave a gap).
  /// A rough jump gets the target item built, then [Scrollable.ensureVisible]
  /// on its key nudges it to exact centre.
  void _centerOnSelected({required bool animated}) {
    final index = widget.selectedIndex;
    if (index == null || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final slotCenter = _listPadding + index * _slotStride + _slotWidth / 2;
    final rough = (slotCenter - position.viewportDimension / 2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (animated && (rough - position.pixels).abs() > 1) {
      _scrollController.animateTo(
        rough,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(rough);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final ctx = _selectedItemKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: animated
              ? const Duration(milliseconds: 160)
              : Duration.zero,
          curve: Curves.easeOut,
        );
      }
    });
  }

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

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    RawFile file,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: () => widget.onCopyEdits(file),
          child: Text(l10n.imageContextCopyEditsAction),
        ),
        PopupMenuItem(
          value: widget.hasCopiedEdits ? () => widget.onPasteEdits(file) : null,
          enabled: widget.hasCopiedEdits,
          child: Text(l10n.imageContextPasteEditsAction),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => widget.onResetEdits(file),
          child: Text(l10n.filmstripResetEditsAction),
        ),
        PopupMenuItem(
          value: () => widget.onShowOnDisk(file),
          child: Text(l10n.filmstripShowOnDiskAction),
        ),
        PopupMenuItem(
          value: () => widget.onDelete(file),
          child: Text(l10n.filmstripDeleteAction),
        ),
      ],
    );
    action?.call();
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
        color: DarkmoonColors.canvas,
        alignment: Alignment.center,
        child: Text(
          AppLocalizations.of(context)!.noFolderOpen,
          style: const TextStyle(color: DarkmoonColors.textMuted, fontSize: 11),
        ),
      );
    }
    return Container(
      height: 114,
      color: DarkmoonColors.canvas,
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
              final edited = widget.isEdited(file.path);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onSelect(index),
                  onSecondaryTapUp: (details) =>
                      _showContextMenu(context, details.globalPosition, file),
                  child: Container(
                    key: isSelected ? _selectedItemKey : null,
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
                                  // A step lighter than the filmstrip's own
                                  // canvas background — using canvas here
                                  // too (tried first) made the thumbnail
                                  // card invisible against the strip.
                                  color: DarkmoonColors.dropdownBackground,
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
                                          gaplessPlayback: true,
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
                                if (edited)
                                  const Positioned(
                                    right: 3,
                                    top: 3,
                                    child: _EditedBadge(),
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

/// Small pencil badge shown over a filmstrip thumbnail's corner when
/// [_EditorScreenState._isPhotoEdited] is true for that photo — a filled
/// dot rather than a pill (unlike [_FileTypeBadge]) since it carries no
/// label, just a yes/no signal, matching Lightroom's own edited-photo
/// indicator.
class _EditedBadge extends StatelessWidget {
  const _EditedBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context)!.filmstripEditedTooltip,
      child: Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: DarkmoonColors.accent.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(
          CupertinoIcons.pencil,
          size: 9,
          color: DarkmoonColors.background,
        ),
      ),
    );
  }
}
