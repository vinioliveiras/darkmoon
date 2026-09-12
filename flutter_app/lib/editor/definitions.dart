// Top-level definitions the editor screen and its panels share: the
// slider specs, the colour profile modes, the preview frame and the
// edit snapshot.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// imports of its own — the split (2026-09-10) is for navigation, not
// decoupling. Imports live in editor_screen.dart.
part of '../editor_screen.dart';

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
    case 'ColorProfileAmount':
      return l10n.sliderColorProfileAmount;
    case 'Texture':
      return l10n.sliderTexture;
    case 'Clarity':
      return l10n.sliderClarity;
    case 'Dehaze':
      return l10n.sliderDehaze;
    case 'CameraColor':
      return l10n.sliderCameraColor;
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

/// RE-ENABLED 2026-09-01 under a scoped, safer design — see
/// [ColorProfileMode]/[_effectiveColorProfile]'s docs. Everything below
/// this line is the OLD (paused 2026-08-31, multiple real-bug incidents —
/// see project_darkmoon_color_profile.md's full trail) design's history,
/// kept for context; it does not describe the current one.
///
/// The old design paired this flag with `no_auto_bright` (libraw.dart) and
/// fit a global tone curve, both of which repeatedly amplified unrelated
/// bugs into visible ones (a Saturation/Vibrance hue-rotation bug, a
/// chroma-smoothing block artifact, an unresolved "overedited" cast
/// question) — every incident traced back to that tone curve's brightness
/// lift making some later stage's small pre-existing flaw large enough to
/// notice. The current profile (`assets/color_profiles/darkmoon_vivid
/// .json`, built 2026-09-01) has its tone curve forced to identity (no
/// longer fit at all — see `tool/build_color_profile.dart`'s header) and
/// is fit against today's normal decode (`no_auto_bright` stays off,
/// untouched, forever — this flag no longer needs it toggled in lockstep).
/// Loading is unconditional now; whether it ever *renders* is gated
/// per-photo by [ColorProfileMode] instead of this static flag — see
/// [_effectiveColorProfile]'s doc for why that's the safer boundary.
const bool _colorProfileEnabled = true;

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

/// How many thumbnails stay in memory across folder changes. Opening an
/// album used to drop every thumbnail and read the whole folder's back
/// from the disk cache (a stat and a lookup per photo); kept, going back
/// to an album is instant. 320 px JPEGs run 15-30 KB, so this is on the
/// order of 60 MB at the cap; the current folder's own are never evicted.
const _thumbnailMemoryCap = 2500;

/// From how many photos a move shows its progress on the loading overlay.
const _moveProgressThreshold = 10;

/// How long to wait after the last slider change before actually
/// re-rendering, restarted on every change — matches the Python app's
/// DEBOUNCE_MS. Keeps a fast slider drag from queuing a render per frame.
/// How many photos on each side of the selected one keep their decoded
/// edit source and rendered previews in memory (see [_trimPhotoCaches]).
///
/// These caches used to be cleared only on a folder change or a file
/// removal, so browsing a folder accumulated every photo ever selected:
/// a decoded EditSourcePair is several megabytes and a full-quality
/// ui.Image is tens, which is how a long session drifted into gigabytes.
///
/// 2 keeps arrow-key stepping through the filmstrip instant in both
/// directions without re-decoding, which is the only reason to hold a
/// photo other than the selected one at all.
const _photoCacheNeighborWindow = 2;

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
    this.dragSensitivity = 1.0,
  });

  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final int decimals;

  /// Track gradient for color-affecting controls, Meridian-style — null
  /// for everything else, which keeps the plain theme track.
  final List<Color>? gradientColors;

  /// Appended to the displayed value — e.g. 'K' for Temperature.
  final String valueSuffix;

  /// See [SliderRow.dragSensitivity].
  final double dragSensitivity;
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
    // Every section defaults to on (a brand-new photo has no catalog
    // entry yet, so the key is absent). EFFECTS (Grain + Vignette) was
    // off by default for a while (2026-08-31 – 2026-09-01): a film-look
    // preset that sets Grain/Texture/Sharpen together, applied while the
    // section was off, silently masked AI Enhance's improvement once
    // switched on. Reverted to defaulting on (2026-09-01, explicit user
    // direction, aware of the tradeoff) — a preset that sets a non-zero
    // Grain amount now applies it immediately again, same as it does for
    // every other section's sliders.
    return (values[_categoryEnabledKey(category)] ?? 1.0) == 0;
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

/// A selectable "color profile" for the COLOR PROFILE section — a
/// per-photo/per-preset pick (like [WbMode]), stored under
/// [colorProfileModeKey]. Deliberately a data-bearing (enhanced) enum
/// rather than a hardcoded if/else per mode: every field below is what
/// actually *defines* a profile, so a new profile is just a new enum
/// value with its own field values, never a new branch scattered through
/// the render/UI code. Not to be confused with [ColorProfile]
/// (`render/color_profile.dart`) — that's the per-hue hue/sat/lum + tone
/// correction *model* a profile loads from [profileAsset]; this enum is
/// the small, curated menu of *which* profile is active.
///
/// - [darkmoonDefault]: today's shipped look — Strength damped by
///   [calGlobalAmountCompression] ([dampened]), Contrast defaulting to
///   [calBaseContrast], no per-hue correction. The only mode with
///   [usesHueProfile] false — every other mode is explicitly scoped to
///   NEVER touch Default's render output, even once its own asset is
///   loaded (2026-09-01, explicit user request).
/// - [vivid] (named "Flat" until 2026-09-01, renamed by explicit user
///   request): the neutral, undamped starting point the resumed per-hue
///   "darkmoon Color" fit (see `project_darkmoon_color_profile.md`)
///   builds on — a faithful correction toward how Meridian's Adobe
///   Color profile renders the same RAW.
/// [pastel]/[noir] (hand-authored creative per-hue grades, shipped
/// 2026-09-01) and their siblings "Golden Hour"/"Teal & Orange" (removed
/// 2026-09-02) have all now been removed (2026-09-02, explicit user
/// request) — [darkmoonDefault]/[vivid] are the only two modes left. See
/// [colorProfileModeOf] for the index-migration this and the earlier
/// removal left behind; `tool/author_color_profiles.dart` still has the
/// generation methodology if a new hand-authored profile is ever wanted.
///
/// [vivid] defaults Contrast to [calBaseContrast] (2026-09-02, explicit
/// user request, raised from a literal 0) — the same constant
/// [darkmoonDefault] already used, not a separately hardcoded number, so
/// the two can't drift apart the next time [calBaseContrast] itself gets
/// re-tuned (real, if currently harmless, gap found 2026-09-02: it used
/// to be a hardcoded `80` literal that only coincidentally matched).
///
/// Picking any mode resets Strength to 100% and Contrast to
/// [contrastBaseline] (2026-09-01, explicit user request — same
/// "picking a mode resets its fields" convention [WbMode] already uses).
enum ColorProfileMode {
  /// No profile and no treatment: the photo arrives as decoded.
  ///
  /// [contrastBaseline] is 0 rather than [calBaseContrast] as of
  /// 2026-09-09 — see [_baseContrastFor].
  darkmoonDefault(
    contrastBaseline: 0,
    dampened: true,
    usesHueProfile: false,
    profileAsset: null,
  ),
  vivid(
    contrastBaseline: calBaseContrast,
    dampened: false,
    usesHueProfile: true,
    profileAsset: 'darkmoon_vivid.json',
  ),

  /// A profile the user authored, resolved by [customProfileIdKey] rather
  /// than by this entry — one enum member stands for all of them.
  ///
  /// Undamped like [vivid]: the user tuned the numbers themselves, so
  /// Strength at 100% should hand back exactly what they built.
  custom(
    contrastBaseline: calBaseContrast,
    dampened: false,
    usesHueProfile: true,
    profileAsset: null,
  );

  const ColorProfileMode({
    required this.contrastBaseline,
    required this.dampened,
    required this.usesHueProfile,
    required this.profileAsset,
  });

  /// What the "Color Profile Contrast" slider resets to when this mode
  /// is picked.
  final double contrastBaseline;

  /// Whether Strength's 100% position is damped by
  /// [calGlobalAmountCompression] (see [withGlobalEditAmountApplied])
  /// or an exact 1:1 pass-through.
  final bool dampened;

  /// Whether a fitted/authored per-hue [ColorProfile] renders under this
  /// mode — false only for [darkmoonDefault].
  final bool usesHueProfile;

  /// `assets/color_profiles/<profileAsset>` this mode loads into
  /// [_EditorScreenState._colorProfiles] — null for [darkmoonDefault]
  /// (the one mode that intentionally never has a per-hue table).
  final String? profileAsset;
}

/// Storage key for [ColorProfileMode] — see its own doc.
const colorProfileModeKey = 'ColorProfileMode';

/// [ColorProfileMode] currently selected for [values] (a flat
/// `{paramName: value}` map — the global layer's `_paramValues`, since
/// masks don't get their own profile) — the shared lookup every render-
/// and UI-facing spot that needs the mode reads through, so there's one
/// place that knows how the stored double maps back to the enum.
/// Storage key for the id of the user profile [ColorProfileMode.custom]
/// refers to — see [ColorProfile.id] for why it is a 32-bit number living
/// in a map of doubles.
const customProfileIdKey = 'ColorProfileCustomId';

/// What [ColorProfileMode.custom] is written as, instead of its enum
/// index.
///
/// Its index is 2, and 2 is exactly the number old saved photos carry for
/// modes that were removed in 2026-09-02's enum trimming — `pastel` after
/// round one, `goldenHour` before it. Storing the index would make every
/// one of those files claim to be a custom profile, referring to an id
/// that never existed. 100 is outside every index any version of this enum
/// has ever had.
const int customProfileStoredValue = 100;

int customProfileIdOf(Map<String, double> values) =>
    (values[customProfileIdKey] ?? 0.0).toInt();

double storedValueForColorProfileMode(ColorProfileMode mode) =>
    mode == ColorProfileMode.custom
    ? customProfileStoredValue.toDouble()
    : mode.index.toDouble();

ColorProfileMode colorProfileModeOf(Map<String, double> values) {
  final stored = (values[colorProfileModeKey] ?? 0.0).toInt();
  if (stored == customProfileStoredValue) {
    return ColorProfileMode.custom;
  }
  // Index migration: two rounds of enum trimming (2026-09-02) left old
  // saved photos/presets carrying stale indices. Original 6-entry enum
  // was [default, vivid, goldenHour, tealOrange, pastel, noir]; round 1
  // removed goldenHour/tealOrange (2,3), shifting pastel/noir to 2/3;
  // round 2 removed pastel/noir too, leaving only [default, vivid].
  // Every removed mode falls back to Default (0) rather than silently
  // rendering as whatever mode now happens to sit at that number.
  final index = switch (stored) {
    0 || 1 => stored, // default/vivid unaffected by either round
    _ => 0, // goldenHour/tealOrange/pastel/noir (any round's index) -> Default
  };
  return ColorProfileMode.values[index.clamp(
    0,
    ColorProfileMode.values.length - 1,
  )];
}

/// Storage key for the global Amount slider (below the preset list) —
/// lives in the same flat `_paramValues` map every other per-photo value
/// does, 0-200, default 100. Despite the default being the UI's "no-op"
/// position, this is NOT render-neutral — see [calGlobalAmountCompression]
/// and [withGlobalEditAmountApplied]'s doc for what this actually does at
/// render time.
const _globalEditAmountKey = 'GlobalEditAmount';

/// Default per-pass deposit rate for a new Flow-mask stroke — see
/// [BrushStroke.flow]'s doc. Matches Solstice's own default.
const defaultFlowAmount = 10.0;

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
///
/// The blend fraction is the UI's 0-200 value scaled down by
/// [calGlobalAmountCompression] (or, per key, by
/// [calGlobalAmountCompressionOverrides] instead when that key has its own
/// entry there — e.g. Exposure stays at fraction 1.0, undamped) — so the
/// default Amount (100%, the "no-op" UI position) still damps everything
/// to that fraction. There's no no-op fast path anymore: even the default
/// state now scales every value. Skipped when the active
/// [ColorProfileMode.dampened] is false (see its own doc) — an undamped
/// profile's Strength 100% means an exact 1:1 pass-through for every key,
/// override or not.
/// Families of runtime-built slider keys that share one compression
/// entry, longest first so a more specific family would win.
const _amountCompressionFamilies = ['Mixer', 'Grade'];

/// How much of [key]'s distance from its default survives at Amount 100%.
///
/// Exact entry first, then the family its key belongs to, then the global
/// value. The family step exists because the Colour Mixer's and Colour
/// Grading's key names are built at runtime — `MixerRedHue`,
/// `GradeShadowsSaturation` — so there are 36 of them and listing each
/// would be a wall of duplicates.
double _amountCompressionFor(String key) {
  final exact = calGlobalAmountCompressionOverrides[key];
  if (exact != null) {
    return exact;
  }
  for (final family in _amountCompressionFamilies) {
    if (key.startsWith(family)) {
      final value = calGlobalAmountCompressionOverrides[family];
      if (value != null) {
        return value;
      }
    }
  }
  return calGlobalAmountCompression;
}

Map<String, double> withGlobalEditAmountApplied(Map<String, double> values) {
  final amount = values[_globalEditAmountKey] ?? 100.0;
  final dampened = colorProfileModeOf(values).dampened;
  final defaults = _defaultParamValues();
  final scaleKeys = defaults.keys.toSet()
    ..remove('Temperature')
    ..remove('Tint')
    ..remove(_globalEditAmountKey)
    // The Colour Mixer and Colour Grading build their keys at runtime, so
    // they are not in [_defaultParamValues] and this loop simply never
    // reached them — the Amount slider did nothing at all to either, and a
    // preset whose look came mostly from the mixer ignored Amount
    // outright. Exactly the bug fixed for the tone curves on 2026-09-01,
    // still open here until 2026-09-08. Their neutral is 0, which is what
    // the `?? 0` below already gives them.
    ..addAll([
      for (final channel in _mixerChannels)
        for (final suffix in _hslSuffixes) 'Mixer$channel$suffix',
      for (final range in _gradeRanges)
        for (final suffix in _hslSuffixes) 'Grade$range$suffix',
    ]);
  final scaled = <String, double>{...values};
  for (final key in scaleKeys) {
    final value = values[key];
    if (value == null) {
      continue;
    }
    final compression = dampened ? _amountCompressionFor(key) : 1.0;
    final fraction = amount / 100.0 * compression;
    final base = defaults[key] ?? 0;
    scaled[key] = base + (value - base) * fraction;
  }
  return scaled;
}

// COLOR PROFILE was a section of its own until 2026-09-09. Its dropdown
// now leads WHITE BALANCE — the profile is chosen once per photo and then
// left alone, exactly the shape As Shot white balance has — and its two
// sliders (Strength, and the ColorProfileAmount contrast) moved into the
// profile editor, where a tone curve can be judged against the strength it
// is applied at. Nothing here replaced them, so neither appears in
// [_sections] any more.
const _sections = <String, List<_SliderSpec>>{
  'WHITE BALANCE': [
    // Both drag at a third of the usual speed: the ranges are wide and
    // the corrections small (see SliderRow.dragSensitivity).
    _SliderSpec(
      'Temperature',
      2000,
      50000,
      5500,
      decimals: 0,
      gradientColors: [Color(0xFF4FA6FF), Color(0xFFFFB454)],
      valueSuffix: 'K',
      dragSensitivity: 0.35,
    ),
    _SliderSpec(
      'Tint',
      -150,
      150,
      0,
      gradientColors: [Color(0xFF3DD16B), Color(0xFFE362D8)],
      dragSensitivity: 0.35,
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
    // Camera Color (2026-09-12): on a RAW, how much of the camera's own
    // per-hue colour rendering (fitted from its embedded JPEG) the photo
    // takes; on any other file, a plain saturation lift. 0 by default —
    // the user asked for the recovery to be a choice, not the opening
    // look.
    _SliderSpec('CameraColor', 0, 100, 0),
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
    // 40 (not 0) matches Meridian's own default RAW-import sharpening —
    // and this section's other three sliders (Radius 1.0, Detail 25) were
    // already set to Meridian's defaults, so Amount=0 was leaving the
    // group inconsistently "half off". A zero-edit photo now gets a small
    // baseline sharpen instead of the flat, unsharpened look competitors
    // like Solstice/Vitrine also avoid by baking in a similar default.
    _SliderSpec('SharpenAmount', 0, 150, 40),
    _SliderSpec('SharpenRadius', 0.5, 3.0, 1.0, decimals: 1),
    _SliderSpec('SharpenDetail', 0, 100, 25),
    _SliderSpec('SharpenMasking', 0, 100, 0),
  ],
};

/// "Color Profile Contrast" — the per-photo override of the fixed
/// [calBaseContrast] S-curve, read by [_baseContrastFor].
///
/// Outside [_sections] since 2026-09-09: its control lives in the colour
/// profile editor, not in the panel. It still has to be here, because
/// [_defaultParamValues] is what decides which keys exist at all — a key
/// missing from it is never seeded, never scaled by the Strength slider,
/// and never cleared by Reset. Same reasoning as [_vignetteSliders]
/// below, which is outside [_sections] for its own reasons and listed for
/// the same one.
///
/// Range raised 0-60 -> 0-100 -> 0-150 (2026-09-02, explicit user request
/// — "a boost").
const _colorProfileSliders = [
  _SliderSpec('ColorProfileAmount', 0, 150, calBaseContrast, decimals: 0),
];

/// Post-Crop Vignette sliders (Meridian's Effects panel) — global-only,
/// so kept out of [_sections] (which masks also render from) rather than
/// a fourth entry there.
const _vignetteSliders = [
  _SliderSpec('VignetteAmount', -100, 100, 0),
  _SliderSpec('VignetteMidpoint', 0, 100, 50),
  _SliderSpec('VignetteFeather', 0, 100, 50),
];

/// Film grain sliders (Meridian's Effects panel) — like [_vignetteSliders],
/// global-only, kept out of [_sections]. Ranges match Meridian's
/// `crs:GrainAmount` / `GrainSize` / `GrainFrequency`.
const _grainSliders = [
  _SliderSpec('GrainAmount', 0, 100, 0),
  _SliderSpec('GrainSize', 0, 100, 25),
  _SliderSpec('GrainRoughness', 0, 100, 50),
];

/// Meridian's parametric Tone Curve — four region sliders plus the three
/// split points that set where each region ends. Lives under the Tone
/// Curve editor; toggled off with the TONE CURVE section switch. Split
/// defaults 25/50/75 match Meridian (and Solstice's Curves.tsx).
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
    // from [withGlobalEditAmountApplied]'s own scaling set explicitly —
    // it must never scale itself.
    _globalEditAmountKey: 100.0,
    for (final specs in _sections.values)
      for (final spec in specs) spec.name: spec.defaultValue,
    // Vignette lives outside [_sections] (masks don't get Effects) but
    // still needs its non-zero neutrals (Midpoint/Feather = 50) in the
    // defaults map, or Reset / first-open / preset-merge would leave
    // those keys missing and the sliders would snap to 0.
    for (final spec in _colorProfileSliders) spec.name: spec.defaultValue,
    for (final spec in _vignetteSliders) spec.name: spec.defaultValue,
    for (final spec in _grainSliders) spec.name: spec.defaultValue,
    for (final spec in _parametricCurveSliders) spec.name: spec.defaultValue,
    // Lens Correction is also global-only (see RenderJob.lensCorrection's
    // doc comment) and lives outside [_sections] for the same reason as
    // Vignette above -- seeded from the params class's own defaults
    // (distortion/vignette amount = 100, matching Meridian's Profile
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
/// True on the platform where the command modifier is Cmd rather than
/// Ctrl.
///
/// Not a style preference: on macOS, Ctrl+Z is not undo — Cmd+Z is — and
/// Ctrl+click is a right-click. An editor whose Cmd+Z does nothing reads
/// as broken immediately, so every binding below picks the modifier by
/// platform instead of hardcoding `control: true`.
final bool _useCmdModifier = Platform.isMacOS;

/// Whether the platform's command modifier is currently held — Cmd on
/// macOS, Ctrl everywhere else. Used for the scroll-to-zoom gesture, which
/// is the same idea as the keyboard bindings.
bool get _commandModifierHeld => _useCmdModifier
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;

/// A [SingleActivator] on the platform's command modifier.
SingleActivator _cmdShortcut(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(
      key,
      control: !_useCmdModifier,
      meta: _useCmdModifier,
      shift: shift,
    );

/// One frame for the canvas, in whichever of the two shapes is actually
/// available.
///
/// [image] is a finished render's own pixels, uploaded straight from the
/// pipeline's output buffer — no JPEG encode on the way out and no decode
/// on the way in (see `render_job.dart`'s `RenderResult.previewRgba` for
/// what that round trip used to cost). [jpegBytes] is the stand-in shown
/// while that render is still pending — the camera's own embedded preview
/// where the RAW carries one, the small filmstrip thumbnail otherwise. It
/// stays a JPEG because that is the form both of those arrive in.
@immutable
/// A finished preview render as the editor consumes it: the frame as the
/// GPU's own image (painted as is) or as the CPU's pixels (uploaded first
/// — see `_decodePreviewImage`), plus the histogram and filmstrip
/// thumbnail both derive. Exactly one of [image] and [pixels] is set.
class PreviewRender {
  PreviewRender.gpu(GpuRenderResult result)
    : image = result.image,
      pixels = null,
      histogram = result.histogram,
      thumbnailBytes = result.thumbnailBytes;

  PreviewRender.cpu(RenderResult result)
    : image = null,
      pixels = result,
      histogram = result.histogram,
      thumbnailBytes = result.thumbnailBytes;

  final ui.Image? image;
  final RenderResult? pixels;
  final Histogram histogram;
  final Uint8List thumbnailBytes;
}

class PreviewFrame {
  const PreviewFrame.rendered(ui.Image this.image)
    : jpegBytes = null,
      decodeWidth = null,
      isSmallStandIn = false;

  const PreviewFrame.placeholder(
    Uint8List this.jpegBytes, {
    this.decodeWidth,
    this.isSmallStandIn = false,
  }) : image = null;

  final ui.Image? image;
  final Uint8List? jpegBytes;

  /// Caps the width [jpegBytes] is decoded at, or null for its own size.
  ///
  /// Null everywhere today. It was 2048 for the embedded preview, to hold
  /// down a decode that costs about 52 MB at the 4416px those files carry
  /// — real memory, spent on every selection while browsing. Removed on
  /// the user's call: the stand-in should be the camera's image at the
  /// quality the camera wrote it, not a reduction of it. Kept as a
  /// parameter because that trade-off is a setting away from mattering
  /// again on a machine with less to spare.
  final int? decodeWidth;

  /// True when [jpegBytes] is the 200px filmstrip thumbnail rather than
  /// the camera's own embedded preview.
  ///
  /// The two stand-ins want opposite treatment, which is the whole reason
  /// this exists. The filmstrip thumbnail has to be magnified several
  /// times to fill the viewport and is going to look wrong regardless, so
  /// the canvas blurs it and shows a spinner: provisional, and honest
  /// about it. The camera's embedded image is wider than the viewport and
  /// scaled *down* — softening that would hide the one thing it is there
  /// to show.
  final bool isSmallStandIn;

  /// True while this is a stand-in rather than a real render.
  bool get isPlaceholder => image == null;

  /// A copy holding its own handle on the same pixels.
  ///
  /// `ui.Image.clone()` keeps the underlying image alive until every
  /// handle is disposed, which is exactly what anything outliving the
  /// editor's own ownership needs: [_EditorScreenState._setPreviewImage]
  /// disposes a frame the moment its replacement lands, while the canvas
  /// cross-fade still has to paint the outgoing one for another ~220ms,
  /// and a readback still has to finish reading it. Painting or reading a
  /// disposed image throws.
  ///
  /// **Must be called while the owner still holds the image.** `clone()`
  /// throws `StateError` on an already-disposed one, so taking the handle
  /// late is not "slightly risky", it is broken — see
  /// `_FadingPreviewImageState`, which takes its handle on receipt for
  /// exactly this reason, and test/widgets/preview_frame_test.dart.
  ///
  /// A no-op for a placeholder frame — plain bytes need no handle.
  PreviewFrame cloneHandle() =>
      image == null ? this : PreviewFrame.rendered(image!.clone());

  /// Releases a handle taken by [cloneHandle]. Only ever call this on a
  /// frame [cloneHandle] returned — on a borrowed one it would dispose the
  /// editor's own image out from under the canvas.
  void disposeHandle() => image?.dispose();
}

/// Paints a [PreviewFrame] — [RawImage] for a rendered frame (the pixels
/// are already a `ui.Image`), [Image.memory] for the thumbnail stand-in.
Widget _previewFrameWidget(PreviewFrame frame, {BoxFit? fit}) {
  final image = frame.image;
  if (image != null) {
    // RawImage does not own the image it paints, so it must not dispose
    // it — the editor's own preview maps do that (see
    // _EditorScreenState._setPreviewImage).
    //
    // filterQuality is set explicitly to match what Image.memory used to
    // resolve to here: the canvas almost always scales the render to fit
    // the viewport, and RawImage's own default is not guaranteed to stay
    // the same as the Image widget's.
    return RawImage(
      image: image,
      fit: fit,
      filterQuality: FilterQuality.medium,
    );
  }
  return Image.memory(
    frame.jpegBytes!,
    fit: fit,
    gaplessPlayback: true,
    cacheWidth: frame.decodeWidth,
  );
}

// The `_paramValues` keys of the AI tools, Colorize and the White Balance
// mode. Top-level rather than `static const` on the State (2026-09-10) so
// the concern extensions in state_*.dart read them unqualified.
/// Per-photo markers for item 13's neural Enhance pipeline's two
/// independent passes (denoise, 2x super-resolution) — parallel to how
/// `'AiDenoiseLevel'` already persists the classical level, just not
/// slider values so they get their own keys. `> 0` means active. Live in
/// `_paramValues` for the same free per-photo persistence (catalog
/// save/restore, undo/redo history) every other param value already
/// gets — see `_onParamChanged`'s doc comment on why `_paramValues` is
/// replaced wholesale, not mutated, for history to track it correctly.
const _neuralDenoiseKey = 'AiNeuralDenoise';

const _neuralUpscaleKey = 'AiNeuralUpscale';

/// See `AiDenoiseDialog`'s `NeuralEnhanceChoice.upscaleSharpnessAmount` —
/// persisted the same way as [_neuralDenoiseAmountKey] below. Only
/// meaningful when [_neuralUpscaleKey] is on; defaults to `0` (DIS
/// alone, no Real-ESRGAN blend) for any photo that predates this slider.
const _upscaleSharpnessAmountKey = 'AiUpscaleSharpnessAmount';

/// See `AiDenoiseDialog`'s `NeuralEnhanceChoice.rawDenoise` — the PMRID
/// raw-domain pass, persisted the same way as the two flags above.
const _neuralRawDenoiseKey = 'AiNeuralRawDenoise';

/// See `AiDenoiseDialog`'s `NeuralEnhanceChoice.restoreDetail` — the
/// GaterV3 restore+sharpen pass, persisted the same way as the flags
/// above. `> 0` means active.
const _restoreDetailKey = 'AiRestoreDetail';

/// See `AiDenoiseDialog`'s `NeuralEnhanceChoice.restoreDetailAmount` —
/// 0-100, persisted the same way as [_upscaleSharpnessAmountKey].
/// Defaults to [defaultRestoreDetailAmount] when absent.
const _restoreDetailAmountKey = 'AiRestoreDetailAmount';

/// See `AiDenoiseDialog`'s `NeuralEnhanceChoice.detailSharpen` — the
/// GaterV3 sharpen pass, its own toggle since 2026-09-12. `> 0` means
/// active. A photo saved before the split has no such key: its Restore
/// detail ran both passes, so the key's absence reads as "the same as
/// Restore detail" — see [_detailSharpenOn] — and the photo keeps its look.
const _detailSharpenKey = 'AiDetailSharpen';

/// 0-100 blend of the sharpen pass; absent, it follows the restore
/// amount for the same reason.
const _detailSharpenAmountKey = 'AiDetailSharpenAmount';

bool _detailSharpenOn(Map<String, double> values) =>
    values.containsKey(_detailSharpenKey)
    ? (values[_detailSharpenKey] ?? 0.0) > 0
    : (values[_restoreDetailKey] ?? 0.0) > 0;

int _detailSharpenAmountOf(Map<String, double> values) =>
    (values[_detailSharpenAmountKey] ??
            values[_restoreDetailAmountKey] ??
            defaultDetailSharpenAmount.toDouble())
        .round();

/// See `AiDenoiseDialog`'s `NeuralEnhanceChoice.denoiseAmount` — 0-100,
/// persisted the same way as the two flags above. Defaults to
/// [defaultNeuralDenoiseAmount] when absent (a photo that predates this
/// slider, or one that's never had Denoise turned on before), matching
/// `NeuralEnhanceChoice`'s own default.
const _neuralDenoiseAmountKey = 'AiNeuralDenoiseAmount';

/// See `AiDenoiseDialog`'s `CloudDenoiseChoice.provider` — 0=off,
/// otherwise `CloudDenoiseProviderKind.values.indexOf(provider) + 1`.
/// Only the provider is persisted here; the API key itself is never
/// stored in `_paramValues`/the catalog (see `CloudDenoiseTokenStore`).
const _cloudDenoiseProviderKey = 'AiCloudDenoiseProvider';

/// Item 37's colorize (DDColor) toggle — persisted the same way as the
/// AI Enhance flags above, independent of them (mutually exclusive with
/// nothing; colorize can run on a photo regardless of Denoise/Upscale/
/// Restore detail state, since it replaces the base image the same way
/// those do, just for a different purpose). `> 0` means active.
const _colorizeKey = 'Colorize';

/// See `ColorizeDialog`'s `ColorizeChoice.intensityPercent` — 0-100,
/// persisted the same way as `_restoreDetailAmountKey`. Defaults to
/// [defaultColorizeIntensity] when absent.
const _colorizeIntensityKey = 'ColorizeIntensity';

/// How many object removals the photo's source carries (2026-09-12), 0 or
/// absent for none. The strokes themselves live in the store's
/// `inpaints`; this marker is what says the edit source is their result
/// and what the edited badge and Reset see.
const _inpaintKey = 'Inpaint';

/// The id of the brush layer the canvas paints while removal mode is on —
/// never in the mask stack, so the picker and the history never see it.
const _removeLayerId = 'removal';

const _wbModeKey = 'WhiteBalanceMode';

/// Every callback [_ControlsPanel] fires, as one object (2026-09-11).
/// The panel took each as its own constructor parameter — 52 of its 98 —
/// and the editor rebuilt the whole list every frame; they are all stable
/// tear-offs of the editor State's methods, so it builds this once.
class _ControlsPanelActions {
  const _ControlsPanelActions({
    required this.onWhiteBalanceMode,
    required this.onToggleWbEyedropper,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
    required this.onColorProfileChoiceChanged,
    required this.onCreateColorProfile,
    required this.onLevel,
    required this.onUpright,
    required this.onImportColorProfile,
    required this.onEditColorProfile,
    required this.onDuplicateColorProfile,
    required this.onRenameColorProfile,
    required this.onExportColorProfile,
    required this.onDeleteColorProfile,
    required this.onToneCurveChanged,
    required this.onToneCurveChangeEnd,
    required this.onColorCurveChanged,
    required this.onColorCurveChangeEnd,
    required this.onSelectMask,
    required this.onAddMask,
    required this.onToggleMaskEnabled,
    required this.onToggleMaskInverted,
    required this.onCloneMask,
    required this.onDeleteMask,
    required this.onMaskOpacityChanged,
    required this.onMaskOpacityChangeEnd,
    required this.onToggleMaskOverlayVisible,
    required this.onBrushRadiusChanged,
    required this.onBrushHardnessChanged,
    required this.onToggleBrushErase,
    required this.onUndoStroke,
    required this.onBrushFlowChanged,
    required this.onColorRangeToleranceChanged,
    required this.onColorRangeToleranceChangeEnd,
    required this.onColorRangeFeatherChanged,
    required this.onColorRangeFeatherChangeEnd,
    required this.onLinearFeatherChanged,
    required this.onLinearFeatherChangeEnd,
    required this.onRadialFeatherChanged,
    required this.onRadialFeatherChangeEnd,
    required this.onAiMaskFeatherChanged,
    required this.onAiMaskFeatherChangeEnd,
    required this.onDepthGeometryChanged,
    required this.onDepthGeometryChangeEnd,
    required this.onLuminanceToleranceChanged,
    required this.onLuminanceToleranceChangeEnd,
    required this.onLuminanceFeatherChanged,
    required this.onLuminanceFeatherChangeEnd,
    required this.onCropTransformChanged,
    required this.onCropTransformChangeEnd,
    required this.onCropAspectRatioChanged,
    required this.onToggleCropOverlay,
    required this.onResetCropTransform,
    required this.onStraighteningChanged,
    required this.onToggleGuidedMode,
    required this.onLensCorrectionChanged,
    required this.onLensCorrectionChangeEnd,
    required this.onToggleRemoveMode,
    required this.onRunRemoval,
    required this.onRemoveWithMask,
    required this.onToggleRemovalVisible,
    required this.onDeleteRemoval,
    required this.onRemoveGrowChanged,
    required this.onUndoRemoveStroke,
    required this.onClearRemoveStrokes,
  });

  final void Function(WbMode mode) onWhiteBalanceMode;

  final VoidCallback onToggleWbEyedropper;

  final void Function(String name, double value) onChanged;

  final void Function(String name, double value) onChangeEnd;

  final VoidCallback onReset;

  final ValueChanged<int> onColorProfileChoiceChanged;

  /// Opens the profile editor. Not a per-photo edit, which is why it
  /// is a separate callback rather than another dropdown value.
  final VoidCallback onCreateColorProfile;

  /// Measures the open photo and straightens it — Crop & Transform's Level
  /// button, and [levelBusy] while that runs.
  final VoidCallback onLevel;

  /// Fired by the Crop panel's Auto/Vertical/Full buttons — Level plus
  /// the perspective correction — and [uprightBusy] while that runs.
  final ValueChanged<UprightMode> onUpright;

  final VoidCallback onImportColorProfile;

  final VoidCallback onEditColorProfile;

  final VoidCallback onDuplicateColorProfile;

  final VoidCallback onRenameColorProfile;

  final VoidCallback onExportColorProfile;

  final VoidCallback onDeleteColorProfile;

  final ValueChanged<List<CurvePoint>> onToneCurveChanged;

  final ValueChanged<List<CurvePoint>> onToneCurveChangeEnd;

  final void Function(String channel, List<CurvePoint> points)
  onColorCurveChanged;

  final void Function(String channel, List<CurvePoint> points)
  onColorCurveChangeEnd;

  final ValueChanged<String> onSelectMask;

  final ValueChanged<MaskType> onAddMask;

  final VoidCallback onToggleMaskEnabled;

  final VoidCallback onToggleMaskInverted;

  final VoidCallback onCloneMask;

  final VoidCallback onDeleteMask;

  final ValueChanged<double> onMaskOpacityChanged;

  final ValueChanged<double> onMaskOpacityChangeEnd;

  final VoidCallback onToggleMaskOverlayVisible;

  final ValueChanged<double> onBrushRadiusChanged;

  final ValueChanged<double> onBrushHardnessChanged;

  final VoidCallback onToggleBrushErase;

  final VoidCallback onUndoStroke;

  final ValueChanged<double> onBrushFlowChanged;

  final ValueChanged<double> onColorRangeToleranceChanged;

  final ValueChanged<double> onColorRangeToleranceChangeEnd;

  final ValueChanged<double> onColorRangeFeatherChanged;

  final ValueChanged<double> onColorRangeFeatherChangeEnd;

  /// The linear gradient's fade width — see `LinearGradientGeometry.feather`.
  final ValueChanged<double> onLinearFeatherChanged;

  final ValueChanged<double> onLinearFeatherChangeEnd;

  /// The radial gradient's feather, 0..100 — see `RadialGradientGeometry.feather`.
  final ValueChanged<double> onRadialFeatherChanged;

  final ValueChanged<double> onRadialFeatherChangeEnd;

  /// Subject/Sky/Foreground edge softness — see `SubjectGeometry.feather`.
  final ValueChanged<double> onAiMaskFeatherChanged;

  final ValueChanged<double> onAiMaskFeatherChangeEnd;

  /// Both take the whole rewritten [DepthGeometry] — see
  /// `_EditorScreenState._onDepthGeometryChanged`.
  final ValueChanged<DepthGeometry> onDepthGeometryChanged;

  final ValueChanged<DepthGeometry> onDepthGeometryChangeEnd;

  final ValueChanged<double> onLuminanceToleranceChanged;

  final ValueChanged<double> onLuminanceToleranceChangeEnd;

  final ValueChanged<double> onLuminanceFeatherChanged;

  final ValueChanged<double> onLuminanceFeatherChangeEnd;

  final ValueChanged<CropTransformParams> onCropTransformChanged;

  final ValueChanged<CropTransformParams> onCropTransformChangeEnd;

  final ValueChanged<double?> onCropAspectRatioChanged;

  final VoidCallback onToggleCropOverlay;

  final VoidCallback onResetCropTransform;

  /// Object removal (2026-09-12): in and out of the mode, run the model
  /// over the painted strokes or over a mask of the stack, hide or delete
  /// one removal, the Expand setting, and edit the strokes.
  final VoidCallback onToggleRemoveMode;
  final VoidCallback onRunRemoval;
  final ValueChanged<String> onRemoveWithMask;
  final ValueChanged<int> onToggleRemovalVisible;
  final ValueChanged<int> onDeleteRemoval;
  final ValueChanged<double> onRemoveGrowChanged;
  final VoidCallback onUndoRemoveStroke;
  final VoidCallback onClearRemoveStrokes;

  /// Fires as the Straighten slider is dragged (true) and once it's
  /// released (false) — lets the crop overlay show a denser guide grid
  /// only while the user's actively trying to level a horizon (item 28).
  final ValueChanged<bool> onStraighteningChanged;

  final VoidCallback onToggleGuidedMode;

  final ValueChanged<LensCorrectionParams> onLensCorrectionChanged;

  final ValueChanged<LensCorrectionParams> onLensCorrectionChangeEnd;
}

/// The two tabs at the top of the left column (2026-09-11, user's
/// design): Albums — the library grid on the right — and Editor. The
/// column itself (album tree, recent files, presets or details) is the
/// same under both; only the right-hand side changes. The app's one tab
/// pattern (the theme's `tabBarTheme`), words only.
class _ModeTabs extends StatefulWidget {
  const _ModeTabs({required this.libraryMode, required this.onChanged});

  final bool libraryMode;
  final ValueChanged<bool> onChanged;

  @override
  State<_ModeTabs> createState() => _ModeTabsState();
}

class _ModeTabsState extends State<_ModeTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.libraryMode ? 0 : 1,
  );

  @override
  void didUpdateWidget(covariant _ModeTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = widget.libraryMode ? 0 : 1;
    if (_controller.index != index) {
      _controller.animateTo(index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: DarkmoonColors.panel,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: TabBar(
        controller: _controller,
        onTap: (index) => widget.onChanged(index == 0),
        tabs: [
          Tab(height: kTabHeight, text: l10n.tabAlbums),
          Tab(height: kTabHeight, text: l10n.tabEditor),
        ],
      ),
    );
  }
}

/// The bottom half of the left column in the Albums tab, where the
/// Editor tab shows presets: the selected photo's rating, colour label
/// and keywords (all editable here too) and its camera metadata.
class _LibraryDetailsPanel extends StatelessWidget {
  const _LibraryDetailsPanel({
    required this.file,
    required this.meta,
    required this.metadata,
    required this.onSetRating,
    required this.onSetLabel,
    required this.onEditTags,
  });

  final RawFile? file;
  final PhotoMeta? meta;
  final RawMetadata? metadata;
  final ValueChanged<int> onSetRating;
  final ValueChanged<String> onSetLabel;
  final VoidCallback onEditTags;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final file = this.file;
    // The presets panel's own header geometry, so the heading sits on
    // the same line under either tab and the switch between them reads
    // as one panel changing content, not two panels swapping.
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
      child: SizedBox(
        height: 24,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            l10n.libraryDetailsSection,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    );
    if (file == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              l10n.libraryDetailsEmpty,
              style: const TextStyle(
                color: DarkmoonColors.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      );
    }
    final tags = meta?.tags ?? const <String>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: kScrollbarGutter, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DarkmoonColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: RatingPicker(
              // Keyed on the photo and its rating so the row restarts
              // from the stored value when either changes underneath it.
              key: ValueKey('rating-${file.path}-${meta?.rating ?? 0}'),
              rating: meta?.rating ?? 0,
              onPick: onSetRating,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LabelPicker(
              key: ValueKey('label-${file.path}-${meta?.label ?? ''}'),
              label: meta?.label ?? '',
              onPick: onSetLabel,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 12),
                  child: Text(
                    l10n.libraryTagsLabel,
                    style: const TextStyle(
                      color: DarkmoonColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (tags.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            l10n.libraryNoTags,
                            style: const TextStyle(
                              color: DarkmoonColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      for (final tag in tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: DarkmoonColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              color: DarkmoonColors.textPrimary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Tooltip(
                  message: l10n.libraryEditTagsAction,
                  child: InkWell(
                    onTap: onEditTags,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        CupertinoIcons.pencil,
                        size: 14,
                        color: DarkmoonColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Divider(color: DarkmoonColors.divider, height: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: PhotoMetadataView(metadata: metadata),
          ),
        ],
      ),
    );
  }
}

/// The bottom of the left column in the Albums tab: the Settings and
/// About buttons the editor's toolbar carries, since that toolbar is not
/// shown there (2026-09-11, user's request). The same pill and segments.
class _LibraryColumnFooter extends StatelessWidget {
  const _LibraryColumnFooter({
    required this.onOpenSettings,
    required this.onOpenAbout,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: DarkmoonColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _ToolbarPill(
          height: _squareButtonSize,
          showChrome: false,
          children: [
            _ToolbarSegment(
              icon: CupertinoIcons.gear_alt,
              iconSize: _squareButtonIconSize,
              width: _squareButtonSize,
              onTap: onOpenSettings,
              tooltip: l10n.menuSettings,
            ),
            _ToolbarSegment(
              icon: CupertinoIcons.info_circle,
              iconSize: _squareButtonIconSize,
              width: _squareButtonSize,
              onTap: onOpenAbout,
              tooltip: l10n.menuAbout,
            ),
          ],
        ),
      ),
    );
  }
}
