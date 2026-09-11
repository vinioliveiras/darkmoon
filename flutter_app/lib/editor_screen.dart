import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io' show Directory, File, Platform, Process;
import 'dart:ui' as ui;
import 'dart:ui' show AppExitResponse, ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'animations_config.dart';
import 'catalog/cache_usage.dart';
import 'catalog/ai_mask_cache_dir.dart';
import 'catalog/native_source_cache.dart';
import 'catalog/photo_meta_store.dart';
import 'catalog/preview_cache_dir.dart';
import 'catalog/sidecar_xmp.dart' show readSidecar;
import 'catalog/ai_enhance_cache.dart';
import 'catalog/ai_enhance_cache_dir.dart';
import 'catalog/cloud_denoise_cache.dart';
import 'catalog/cloud_denoise_cache_dir.dart';
import 'catalog/colorize_cache.dart';
import 'catalog/colorize_cache_dir.dart';
import 'catalog/thumbnail_cache.dart';
import 'catalog/thumbnail_cache_dir.dart';
import 'cloud_denoise/cloud_denoise_provider.dart';
import 'cloud_denoise/cloud_denoise_token_store.dart';
import 'diagnostics/dev_log.dart';
import 'editor/edit_history.dart';
import 'editor/photo_edit_store.dart';
import 'export/export_job.dart';
import 'export/export_metadata.dart';
import 'l10n/app_localizations.dart';
import 'native/camera_match.dart';
import 'native/common_image_thumbnail.dart';
import 'native/edit_source.dart';
import 'native/isolate_job.dart';
import 'native/edit_source_ai_enhance.dart';
import 'native/edit_source_cloud_denoise.dart';
import 'native/edit_source_colorize.dart';
import 'native/libraw.dart'
    show
        RawDecodeStage,
        RawMetadata,
        extractRawMetadata,
        extractRawThumbnailJpeg;
import 'native/thumbnail_loader.dart';
import 'presets/preset.dart';
import 'presets/preset_thumbnails.dart';
import 'presets/preset_store.dart';
import 'presets/preset_xmp.dart';
import 'profiles/color_profile_store.dart';
import 'presets/preset_zip.dart';
import 'raw_files.dart';
import 'render/ai_mask_resolver.dart';
import 'render/ai_denoise.dart';
import 'render/calibration.dart';
import 'render/ai_enhance_job.dart'
    show
        AiEnhanceCancellationToken,
        AiEnhanceModelInfo,
        AiEnhanceProgress,
        CustomDenoiseModelFallback;
import 'render/color_profile.dart';
import 'render/histogram.dart';
import 'render/hsl.dart';
import 'render/lens_correction.dart';
import 'render/luminance.dart' show luminanceRgb;
import 'render/mask.dart';
import 'render/gpu/gpu_capability.dart';
import 'render/gpu/gpu_pass.dart' show gpuCanRenderAtScale;
import 'render/gpu/render_job_gpu.dart';
import 'render/render.dart' show RenderStage;
import 'render/render_job.dart';
import 'render/crop_transform.dart';
import 'render/render_params.dart';
import 'render/tone_curve.dart';
import 'render/upright.dart';
import 'render/upright_auto.dart';
import 'render/white_balance.dart';
import 'settings/app_settings.dart';
import 'theme.dart';
import 'widgets/about_dialog.dart';
import 'widgets/ai_denoise_dialog.dart';
import 'widgets/color_profile_editor_dialog.dart';
import 'widgets/colorize_dialog.dart';
import 'widgets/animated_dialog.dart';
import 'widgets/brush_mask_overlay.dart';
import 'widgets/color_range_overlay.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/color_wheel.dart';
import 'widgets/dialog_chrome.dart' show dialogShape;
import 'widgets/export_dialog.dart';
import 'widgets/folder_sidebar.dart';
import 'widgets/ai_mask_overlay.dart';
import 'widgets/gradient_mask_overlay.dart';
import 'widgets/histogram_view.dart';
import 'widgets/lens_correction_panel.dart';
import 'widgets/mask_selector.dart';
import 'widgets/parametric_split_bar.dart';
import 'widgets/photo_metadata_view.dart';
import 'widgets/preset_panel.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/slider_row.dart';
import 'widgets/styled_dropdown.dart';
import 'widgets/text_prompt_dialog.dart';
import 'widgets/tone_curve_editor.dart';
import 'widgets/white_balance_eyedropper_overlay.dart';

part 'editor/definitions.dart';
part 'editor/image_area.dart';
part 'editor/viewer_toolbar.dart';
part 'editor/crop_transform_panel.dart';
part 'editor/section_widgets.dart';
part 'editor/controls_panel.dart';
part 'editor/filmstrip.dart';
part 'editor/state_caches.dart';
part 'editor/state_presets.dart';
part 'editor/state_ai_tools.dart';
part 'editor/state_zoom.dart';
part 'editor/state_color_profiles.dart';
part 'editor/state_ai_masks.dart';
part 'editor/state_masks.dart';
part 'editor/state_export.dart';

/// Main window: image viewer + toolbar, adjustment panel, and a filmstrip
/// that lists real RAW files from a chosen folder. Selecting a file decodes
/// its full RAW preview in the background (showing the fast embedded
/// thumbnail in the meantime).
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.onLanguageChanged,
    this.settingsOverride,
  });

  /// Applies a language change immediately app-wide — owned by DarkmoonApp
  /// since it controls MaterialApp's `locale`, not this screen.
  final ValueChanged<String> onLanguageChanged;

  /// Settings to open with instead of whatever is on disk.
  ///
  /// A seam for tests that need a layout other than the default one. The
  /// controls panel's tabbed mode is the case that forced it: the tabs
  /// filter which sections are built, and six of them are written outside
  /// `_sections` and were once emitted only on its DETAIL iteration — a
  /// coupling that made all six vanish from every other tab and that
  /// nothing else can observe once the flat list is the default (which it
  /// became 2026-09-09). Driving the real Settings dialog instead is not
  /// available: saving settings needs path_provider, which a widget test
  /// does not have.
  @visibleForTesting
  final AppSettings? settingsOverride;

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

  /// The camera's own JPEG, lifted whole out of each RAW.
  ///
  /// Every RAW already carries one, and it is not a thumbnail: on the
  /// X-T5 files this was measured against it is 4416x2944, against a
  /// 7752x5178 sensor — larger than the 1024px preview the editor renders
  /// for editing and larger than the full-quality one. The filmstrip was
  /// already extracting it and throwing all but 200 pixels away.
  ///
  /// Shown while the RAW decodes, in place of that 200px thumbnail. It is
  /// the camera's rendering rather than ours, so it is a stand-in and not
  /// the edit, but it is a sharp, correctly-coloured stand-in that arrives
  /// in a fraction of the time.
  final Map<String, Uint8List> _embeddedPreviews = {};

  /// The light preview-resolution render per photo — kept fresh by every
  /// settled render (phase 1). What the canvas shows when the dynamic
  /// full-quality preview is off.
  ///
  /// A decoded `ui.Image` rather than JPEG bytes: the render pipeline
  /// already produces pixels, so encoding them and having Flutter decode
  /// them straight back was pure overhead on every settled render. Every
  /// map here owns its images — replace or remove an entry only through
  /// [_setPreviewImage] / [_disposePreviewsFor] / [_disposeAllPreviews],
  /// which dispose the outgoing one.
  final Map<String, ui.Image> _renderedPreviews = {};

  final Map<String, Histogram> _histograms = {};

  /// Stores [image] as [path]'s entry in [map], disposing whatever it
  /// replaces. A `ui.Image` holds GPU-side memory that is only reclaimed
  /// on an explicit `dispose()` (the finalizer runs late and unreliably),
  /// and these are full frames — tens of megabytes each at full-quality
  /// resolution — replaced on every settled render.
  void _setPreviewImage(
    Map<String, ui.Image> map,
    String path,
    ui.Image? image,
  ) {
    final previous = map[path];
    if (identical(previous, image)) {
      return;
    }
    previous?.dispose();
    if (image == null) {
      map.remove(path);
    } else {
      map[path] = image;
    }
  }

  /// Evicts every photo outside [_photoCacheNeighborWindow] of the
  /// selected one from the memory caches that hold real pixel data.
  ///
  /// Bounds what browsing a folder can accumulate: without this, every
  /// photo the user ever selected kept its decoded edit source and its
  /// rendered previews for as long as the folder stayed open.
  ///
  /// [_thumbnails] and [_metadata] are deliberately left alone — a ~200px
  /// JPEG and a handful of numbers per photo, and the filmstrip needs all
  /// of them on screen at once anyway. [_neutralPreviews] is narrowed
  /// harder than the rest, to the selected photo alone: its entries are
  /// the largest, and it is never shown for a photo that is not the
  /// current one.
  void _trimPhotoCaches() {
    final selectedIndex = _selectedIndex;
    if (selectedIndex == null || selectedIndex >= _files.length) {
      return;
    }
    final selectedPath = _files[selectedIndex].path;
    final window = <String>{};
    for (
      var i = selectedIndex - _photoCacheNeighborWindow;
      i <= selectedIndex + _photoCacheNeighborWindow;
      i++
    ) {
      if (i >= 0 && i < _files.length) {
        window.add(_files[i].path);
      }
    }

    _editSources.removeWhere((path, _) => !window.contains(path));
    _embeddedPreviews.removeWhere((path, _) => !window.contains(path));
    _histograms.removeWhere((path, _) => !window.contains(path));
    _evictImages(_renderedPreviews, window);
    _evictImages(_neutralPreviews, {selectedPath});
  }

  /// [_trimPhotoCaches]'s helper for the `ui.Image` caches — same eviction,
  /// but each dropped entry has to be disposed (see [_setPreviewImage]).
  void _evictImages(Map<String, ui.Image> map, Set<String> keep) {
    map.removeWhere((path, image) {
      if (keep.contains(path)) {
        return false;
      }
      image.dispose();
      return true;
    });
  }

  /// Drops (and disposes) every cached render of [path] — used when the
  /// photo leaves the filmstrip.
  void _disposePreviewsFor(String path) {
    _renderedPreviews.remove(path)?.dispose();
    _neutralPreviews.remove(path)?.dispose();
  }

  /// [_disposePreviewsFor] for every photo at once — used when the whole
  /// filmstrip is replaced (folder change, close, refresh).
  void _disposeAllPreviews() {
    for (final map in [_renderedPreviews, _neutralPreviews]) {
      for (final image in map.values) {
        image.dispose();
      }
      map.clear();
    }
  }

  /// Uploads a finished render's pixels as a `ui.Image` the canvas can
  /// paint directly. `decodeImageFromPixels` is not a decode in the
  /// codec sense — there is no entropy coding to undo, just an upload —
  /// which is the whole point of [RenderResult.previewRgba].
  Future<ui.Image> _decodePreviewImage(RenderResult result) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      result.previewRgba,
      result.previewWidth,
      result.previewHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// The render to show on the canvas for [path].
  ///
  /// One render per photo now. There used to be a second, full-quality
  /// pass layered over this one; the preview renders at the sensor's own
  /// resolution by default, so it had nothing left to improve.
  ui.Image? _displayPreview(String path) => _renderedPreviews[path];

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

  /// Every bundled per-hue "darkmoon Color" profile (see
  /// [_loadColorProfile]), keyed by the [ColorProfileMode] it belongs to
  /// — one entry per mode with a non-null [ColorProfileMode.profileAsset]
  /// once loading finishes. Missing entry = no correction for that mode.
  final Map<ColorProfileMode, ColorProfile> _colorProfiles = {};

  /// [_colorProfiles]'s entry for the currently-active [ColorProfileMode],
  /// but only when that mode actually wants one
  /// ([ColorProfileMode.usesHueProfile]) — [ColorProfileMode.darkmoonDefault]
  /// must never render a per-hue correction, per explicit user request
  /// (2026-09-01) that this whole feature stay scoped to every mode
  /// *except* Default and leave its render output alone. Every render
  /// call site should read this, not [_colorProfiles] directly.
  ColorProfile? get _effectiveColorProfile {
    // The COLOR PROFILE section had an enable toggle, checked here, until
    // the section itself went away (2026-09-09). Deliberately not carried
    // over to WHITE BALANCE's toggle, and deliberately not left reading
    // the old key either: a photo saved with it off would keep rendering
    // without its profile, with no control anywhere able to say so or put
    // it back. Choosing Default in the dropdown is what "off" means now,
    // and that is a control the user can see.
    final mode = colorProfileModeOf(_paramValues);
    if (mode == ColorProfileMode.custom) {
      return _userColorProfiles[customProfileIdOf(_paramValues)];
    }
    return mode.usesHueProfile ? _colorProfiles[mode] : null;
  }

  /// Every user-authored profile currently on disk, keyed by
  /// [ColorProfile.id]. Loaded once at startup and refreshed whenever one
  /// is saved, imported or deleted.
  Map<int, ColorProfile> _userColorProfiles = const {};

  /// The user profile this photo asks for but which is not installed, if
  /// any — drives the warning under the dropdown.
  ///
  /// The photo keeps pointing at the missing id: [_effectiveColorProfile]
  /// simply resolves to null, so the render falls back to Default, but
  /// nothing rewrites `_paramValues`. Overwriting the reference here would
  /// be easy and quietly destructive — the photo would forget which
  /// profile it was built with, and importing that profile later would no
  /// longer bring its look back. Default is what gets *rendered*, never
  /// what gets *stored*.
  bool get _customProfileMissing {
    if (colorProfileModeOf(_paramValues) != ColorProfileMode.custom) {
      return false;
    }
    return !_userColorProfiles.containsKey(customProfileIdOf(_paramValues));
  }

  /// The base contrast to actually render with: the profile's fitted tone
  /// curve *replaces* the hand-tuned [calBaseContrast] S when it's present,
  /// so they don't stack. Otherwise reads the per-photo/per-preset
  /// "ColorProfileAmount" slider (2026-09-01) — previously a single global
  /// value in Settings, now saved with each photo/preset like every other
  /// slider, and subject to the same Amount-slider scaling
  /// ([_effectiveParamValues]).
  ///
  /// Per photo, not global, because [_colorProfileFor] can carry that
  /// photo's *own* fitted curve — the camera tone match — and that has to
  /// step aside the same way a profile's does.
  double _baseContrastFor(String? path) {
    // Default means untouched (2026-09-09, user's request). The S-curve is
    // a stand-in for a camera profile's baked-in contrast; under a mode
    // that says "no profile" it was still shaping every photo, most
    // visibly in embedded-JPEG mode, where the camera had already made
    // those decisions and there is nothing left to stand in for.
    if (colorProfileModeOf(_paramValues) == ColorProfileMode.darkmoonDefault) {
      return 0.0;
    }
    final profile = _colorProfileFor(path);
    return (profile != null && !profile.toneIsIdentity)
        ? 0.0
        : _effectiveParamValues()['ColorProfileAmount'] ?? calBaseContrast;
  }

  /// The camera's own tonality for [path], as a [ColorProfile.tone] curve
  /// — null when the file carried no embedded preview to fit against
  /// (every non-RAW source), or when the match is calibrated off.
  ///
  /// See [cameraToneCurve] and [calCameraToneMatch].
  List<double>? _baseToneCurveFor(String? path) {
    if (path == null || calCameraToneMatch <= 0) {
      return null;
    }
    final tone = _editSources[path]?.baseToneCurve;
    if (tone == null || calCameraToneMatch >= 1.0) {
      return tone;
    }
    // Part-way: blend toward identity, which is the same thing as
    // blending toward "no match at all".
    return [
      for (var i = 0; i < tone.length; i++)
        identityColorProfile.tone[i] +
            (tone[i] - identityColorProfile.tone[i]) * calCameraToneMatch,
    ];
  }

  /// [_effectiveColorProfile] with [path]'s camera tone curve fitted into
  /// its tone slot.
  ///
  /// The profile's tone slot is exactly the right vehicle: it is a
  /// luminance-only perceptual curve that both the CPU and the GPU path
  /// already apply, so the camera match needs no render stage of its own
  /// and cannot drift between the two.
  ///
  /// A profile that already carries a fitted tone curve of its own keeps
  /// it — two fitted curves must never stack, and the one the user chose
  /// outranks the one we measured.
  ColorProfile? _colorProfileFor(String? path) {
    final profile = _effectiveColorProfile;
    final tone = _baseToneCurveFor(path);
    if (tone == null) {
      return profile;
    }
    if (profile == null) {
      return ColorProfile(
        tone: tone,
        hueShift: identityColorProfile.hueShift,
        satMul: identityColorProfile.satMul,
        lumMul: identityColorProfile.lumMul,
        name: 'camera',
      );
    }
    if (!profile.toneIsIdentity) {
      return profile;
    }
    return ColorProfile(
      tone: tone,
      hueShift: profile.hueShift,
      satMul: profile.satMul,
      lumMul: profile.lumMul,
      name: profile.name,
      id: profile.id,
    );
  }

  /// The per-hue correction's actual blend strength — the "Color Profile
  /// Strength" slider (0-200%, [_globalEditAmountKey], labeled "Strength"
  /// in the COLOR PROFILE section) scaled to the 0..1 fraction
  /// [RenderParams.colorProfileStrength] expects. `applyColorProfile`
  /// itself clamps to [0,1], so 100-200% both mean "full strength" — same
  /// ceiling behavior every other slider already has once its own blend
  /// hits 1:1.
  ///
  /// Real bug fixed 2026-09-02: `RenderParams.fromValues`'s own
  /// `colorProfileStrength` parameter defaults to 1.0 and was never once
  /// passed at either of this file's two real render call sites — the
  /// slider visibly moved but the per-hue correction always rendered at
  /// full authored strength regardless, since nothing read the slider's
  /// value for it. `withGlobalEditAmountApplied` reads the same
  /// [_globalEditAmountKey] but only ever touches `_paramValues`'
  /// continuous sliders — the loaded [ColorProfile] tables live in
  /// [_colorProfiles], a separate structure it never reaches.
  double get _effectiveColorProfileStrength =>
      ((_paramValues[_globalEditAmountKey] ?? 100.0) / 100.0).clamp(0.0, 1.0);

  /// Unedited render of whichever photos have had Before/After turned on,
  /// computed lazily (only when first needed) since most photos are never
  /// compared this way.
  final Map<String, ui.Image> _neutralPreviews = {};
  bool _beforeAfterMode = false;

  /// Whether the Crop Overlay's draggable rectangle is shown over the
  /// image — a session-wide UI mode (like Meridian's crop tool toggle),
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
  /// photo's saved edits from [_store], or defaults if it has none yet.
  Map<String, double> _paramValues = _defaultParamValues();
  Timer? _renderDebounceTimer;
  int _renderRequestId = 0;

  /// Cancel flag of the CPU render in flight, set when that render is
  /// superseded (a newer request while it runs, a photo switch) so it
  /// stops between phases instead of finishing a frame nothing will
  /// paint — see [RenderJob.cancelFlagAddress]. Null while nothing is in
  /// flight. A live drag frame is never cancelled: at a drag's tick rate
  /// every frame would be superseded before it finished and none would
  /// ever land, so those run to completion as before.
  IsolateCancelFlag? _renderCancel;
  bool _renderInFlightLive = false;

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

  /// Which [RawDecodeStage] the photo currently being opened is on, or
  /// null before the first one arrives (and for a cache hit, which never
  /// runs a decode at all).
  ///
  /// The stages were always emitted — `decodeEditSourcesWithProgress`
  /// spawns a dedicated isolate precisely so they can cross back while the
  /// decode runs — and were thrown away, because what showed was an
  /// indeterminate spinner. See [_decodeProgress].
  RawDecodeStage? _photoDecodeStage;
  bool _isRenderingSlow = false;
  Timer? _slowRenderTimer;
  static const _slowRenderThreshold = Duration(seconds: 3);

  /// The decoded native-resolution source cache — same [ThumbnailCacheManager]
  /// month-file format / sha1 key as the thumbnail and preview caches, in
  /// its own `previews/native` namespace, trimmed by
  /// [evictNativeSourceCache] since these blobs are big.
  ThumbnailCacheManager? _nativeSourceCache;
  String? _nativeSourceCacheDir;

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

  /// Item 37's colorize (DDColor) — same three-state shape as the AI
  /// Denoise trio above ([_isRunningColorize] covers the model/decode
  /// step, [_isApplyingColorize]/[_colorizeDisabling] the quick render
  /// pass after), kept separate rather than reused since colorize is an
  /// independent toolbar action, not a Denoise-dialog choice.
  bool _isRunningColorize = false;
  bool _isApplyingColorize = false;
  bool _colorizeDisabling = false;
  RenderStage? _colorizeRenderStage;
  ColorizeCancellationToken? _colorizeCancellation;

  /// Guards [_openAiDenoiseDialog]/[_openColorizeDialog] against a rapid
  /// double-tap on their toolbar button stacking two dialogs on top of
  /// each other (2026-09-01, real bug found in testing) — `showDialog`'s
  /// own modal barrier only blocks *further* taps once the dialog is
  /// actually on screen; any async work before that call (there wasn't
  /// any here, but there was in `ColorizeDialog`'s case — see
  /// `probeColorizeGpuSupport`'s doc) leaves a real window for a second
  /// tap to land first. Set at entry, cleared once `showAnimatedDialog`'s
  /// own future resolves (dialog closed, choice made or cancelled) —
  /// covers the whole open-to-close span, not just the pre-dialog gap,
  /// since a `Navigator.pop` triggered by e.g. a keyboard shortcut could
  /// theoretically race a queued tap too.
  bool _openingToolbarDialog = false;

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

  /// Every photo's saved edits (slider values, curves, masks, applied
  /// preset), keyed by absolute path — see [PhotoEditStore]. The maps are
  /// read directly; writes go through it so the four files and the
  /// sidecars stay together.
  final _store = PhotoEditStore();
  Timer? _catalogSaveTimer;
  Timer? _thumbnailFlushTimer;

  /// The curves for whichever photo is selected — either that photo's
  /// saved curves from [_store], or the identity (no-op) curves.
  /// Mirrors how [_paramValues] tracks the selected photo's slider values.
  PhotoCurves _currentCurves = identityPhotoCurves;

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

  /// Armed while the colour-profile editor is waiting for a colour to be
  /// picked off the photo. The editor dialog is closed during this — see
  /// [ColorProfileEditorResult] — and [_pendingProfileDraft] holds its
  /// work until it reopens.
  bool _profileHueEyedropperActive = false;

  /// True while Level is measuring. The measurement is a per-pixel pass on
  /// another isolate and takes a moment on a large preview, so the button
  /// has to say it is working rather than look like it ignored the click.
  bool _levelBusy = false;
  bool _uprightBusy = false;

  /// The current photo rendered through each preset, for the preset
  /// list's previews. Fed by [_syncPresetThumbnails].
  final PresetThumbnailStore _presetThumbnails = PresetThumbnailStore();
  ColorProfile? _pendingProfileDraft;

  /// True while the Straighten slider is actively being dragged (item 28)
  /// — lets [CropOverlay] show a denser guide grid only during that
  /// interaction, matching Meridian. Session-only.
  bool _straighteningActive = false;

  void _setStraighteningActive(bool value) {
    if (_straighteningActive == value) {
      return;
    }
    setState(() => _straighteningActive = value);
  }

  /// True while the "Guided" upright tool (PENDING.md item 27) is active —
  /// see [CropOverlay.guidedModeActive]'s own doc for what it does.
  /// Session-only, same as [_straighteningActive]; turned off whenever the
  /// Crop tool itself closes (see [_toggleCropOverlay]) so it can't stay
  /// silently armed the next time Crop reopens.
  bool _guidedModeActive = false;

  void _toggleGuidedMode() {
    setState(() => _guidedModeActive = !_guidedModeActive);
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
  /// Overlay strength per mask type, fixed since 2026-09-07 — the slider
  /// that exposed it was removed at the user's request. The overlay still
  /// renders with these; they are just no longer adjustable, and are tuned
  /// per type because a brush stroke needs almost none while a colour
  /// range needs enough to see what it caught.
  final Map<MaskType, double> _maskOverlayOpacity = {
    MaskType.linearGradient: 0.15,
    MaskType.radialGradient: 0.00,
    MaskType.brush: 0.01,
    MaskType.colorRange: 0.20,
    MaskType.wholeImage: 0.00,
    MaskType.luminance: 0.20,
    MaskType.flow: 0.01,
    // The AI types have no geometry to preview, so their overlay *is* the
    // answer — it is the only way to see what the model selected, unlike a
    // gradient or a brush stroke where the shape is visible in the handles
    // whatever the shading does. Started at Color Range's 0.20 and raised
    // to 0.5 (2026-09-08, user): faint enough to read the photo through,
    // strong enough to judge an edge by.
    MaskType.subject: 0.50,
    MaskType.sky: 0.50,
    MaskType.foreground: 0.50,
    MaskType.depth: 0.50,
  };

  /// Resolved model output for the AI mask types, keyed by mask id, for
  /// the photo named by [_aiMaskMapsPath] and nothing else.
  ///
  /// One photo's worth rather than a cache across photos: these are ~700 KB
  /// each, the disk cache behind them makes a revisit cheap anyway, and
  /// this app has already had to go and bound several per-photo maps that
  /// grew without one (see the 2026-09-03 memory work).
  final Map<String, AiMaskMap> _aiMaskMaps = {};
  String? _aiMaskMapsPath;

  /// What each entry in [_aiMaskMaps] was computed for — mask type, prompt
  /// and frame geometry. A mask whose current signature differs from the
  /// one recorded here needs re-inference; one that matches is reused as
  /// the user drags unrelated sliders.
  final Map<String, String> _aiMaskSignatures = {};

  /// Mask ids currently being computed, and the ones whose model failed
  /// (with the reason) — both purely so the mask panel can say which of
  /// "thinking", "done" and "broken" it is.
  final Set<String> _aiMasksResolving = {};
  final Map<String, String> _aiMaskFailures = {};
  bool _aiMaskResolvePending = false;

  /// Resolved once per session, on the main isolate — `path_provider` is
  /// unavailable inside the isolate that does the actual work.
  String? _aiMaskCacheDir;

  /// Undo/redo for the currently selected photo, over snapshots of
  /// [_paramValues]/[_currentCurves]/[_currentMasks] — see [EditHistory]
  /// for the rules (per-photo scope, redo branch discarded on edit).
  final _history = EditHistory();

  /// [setState] for the concern extensions in `lib/editor/state_*.dart`:
  /// `setState` is protected, and an extension is not a subclass.
  void _rebuild(VoidCallback fn) => setState(fn);

  /// The controls panel's callbacks — see [_ControlsPanelActions].
  late final _panelActions = _ControlsPanelActions(
    onWhiteBalanceMode: _applyWbMode,
    onToggleWbEyedropper: _toggleWbEyedropper,
    onChanged: _onActiveChanged,
    onChangeEnd: _onActiveChangeEnd,
    onReset: _resetActive,
    onColorProfileChoiceChanged: _applyColorProfileChoice,
    onCreateColorProfile: _openColorProfileEditor,
    onLevel: _levelPhoto,
    onUpright: _uprightAuto,
    onImportColorProfile: _importColorProfile,
    onEditColorProfile: _editSelectedColorProfile,
    onDuplicateColorProfile: _duplicateSelectedColorProfile,
    onRenameColorProfile: _renameSelectedColorProfile,
    onExportColorProfile: _exportSelectedColorProfile,
    onDeleteColorProfile: _deleteSelectedColorProfile,
    onToneCurveChanged: _onActiveToneCurveChanged,
    onToneCurveChangeEnd: _onActiveToneCurveChangeEnd,
    onColorCurveChanged: _onActiveColorCurveChanged,
    onColorCurveChangeEnd: _onActiveColorCurveChangeEnd,
    onSelectMask: _selectMask,
    onAddMask: _addMask,
    onToggleMaskEnabled: _toggleActiveMaskEnabled,
    onToggleMaskInverted: _toggleActiveMaskInverted,
    onCloneMask: _cloneActiveMask,
    onDeleteMask: _deleteActiveMask,
    onMaskOpacityChanged: _onActiveMaskOpacityChanged,
    onMaskOpacityChangeEnd: _onActiveMaskOpacityChangeEnd,
    onToggleMaskOverlayVisible: _toggleMaskOverlayVisible,
    onBrushRadiusChanged: _setBrushRadius,
    onBrushHardnessChanged: _setBrushHardness,
    onToggleBrushErase: _toggleBrushErase,
    onUndoStroke: _undoLastStroke,
    onBrushFlowChanged: _setBrushFlow,
    onColorRangeToleranceChanged: _onColorRangeToleranceChanged,
    onColorRangeToleranceChangeEnd: _onColorRangeToleranceChangeEnd,
    onColorRangeFeatherChanged: _onColorRangeFeatherChanged,
    onColorRangeFeatherChangeEnd: _onColorRangeFeatherChangeEnd,
    onDepthGeometryChanged: _onDepthGeometryChanged,
    onDepthGeometryChangeEnd: _onDepthGeometryChangeEnd,
    onLuminanceToleranceChanged: _onLuminanceToleranceChanged,
    onLuminanceToleranceChangeEnd: _onLuminanceToleranceChangeEnd,
    onLuminanceFeatherChanged: _onLuminanceFeatherChanged,
    onLuminanceFeatherChangeEnd: _onLuminanceFeatherChangeEnd,
    onCropTransformChanged: _onCropTransformChanged,
    onCropTransformChangeEnd: _onCropTransformChangeEnd,
    onCropAspectRatioChanged: _setCropAspectRatio,
    onToggleCropOverlay: _toggleCropOverlay,
    onResetCropTransform: _resetCropTransform,
    onStraighteningChanged: _setStraighteningActive,
    onToggleGuidedMode: _toggleGuidedMode,
    onLensCorrectionChanged: _onLensCorrectionChanged,
    onLensCorrectionChangeEnd: _onLensCorrectionChangeEnd,
  );

  void _toggleWbEyedropper() =>
      setState(() => _wbEyedropperActive = !_wbEyedropperActive);

  /// Where every rebuildable cache lives — resolved once, since the
  /// storage meter and the sweep both need it and neither can call
  /// path_provider from an isolate.
  String? _cacheRoot;

  /// What the caches occupy, for the Settings storage meter. Null until
  /// measured; re-measured whenever something changes it.
  CacheUsage? _cacheUsage;

  Timer? _cacheSweepTimer;

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

  /// Where measured camera matches are kept between sessions — see
  /// [resolveCameraMatchCacheDir]. Null until that resolves, at which
  /// point [_withMeasuredCameraMatch] stops paying for the measurement on
  /// every open and starts paying for it once per file.
  ThumbnailCacheManager? _cameraMatchCache;

  @override
  void initState() {
    super.initState();
    _zoomAnimController = AnimationController(vsync: this);
    _zoomAnimCurve =
        CurvedAnimation(parent: _zoomAnimController, curve: Curves.easeOutCubic)
          ..addListener(() {
            final tween = _zoomAnimTween;
            if (tween != null) {
              _viewController.value = tween.evaluate(_zoomAnimCurve);
            }
          });
    unawaited(_loadEditStore());
    unawaited(_loadPresetsState());
    unawaited(_loadSettings());
    unawaited(_loadThumbnailCache());
    unawaited(_loadCameraMatchCache());
    unawaited(_loadCacheRoot());
    unawaited(_loadLensProfiles());
    unawaited(cleanupStalePreviewCacheVersions());
    if (_colorProfileEnabled) {
      unawaited(_loadColorProfile());
      unawaited(_loadUserColorProfiles());
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

  /// Loads the bundled lens correction database (a few MB JSON asset) --
  /// deliberately not awaited from [initState] (see every other `_load*`
  /// call there), so the first frame isn't blocked on it. If Lens
  /// Correction was already on for the photo showing when this finishes,
  /// the render it produced before now had nothing to resolve a profile
  /// against, so it's redone once the database is actually usable.
  /// Loads every bundled "darkmoon Color" per-hue correction — one per
  /// [ColorProfileMode] with a non-null [ColorProfileMode.profileAsset]
  /// (see `tool/build_color_profile.dart`/`tool/author_color_profiles
  /// .dart`) — into [_colorProfiles]. A missing individual asset just
  /// leaves that mode without a correction, same as before profiles
  /// existed; it doesn't block the others from loading. Not awaited from
  /// initState; a re-render is kicked once it lands so the open photo
  /// picks up whichever mode it's currently on.
  /// Reads the user's own profiles off disk into [_userColorProfiles].
  ///
  /// Called at startup and again after any save, import or delete, so the
  /// dropdown and the missing-profile warning both follow the folder
  /// rather than an in-memory copy that can drift from it.
  Future<void> _loadUserColorProfiles() async {
    final loaded = await loadUserColorProfiles();
    if (!mounted) {
      return;
    }
    setState(() => _userColorProfiles = loaded);
    // A photo already open may have been waiting on one of these: it would
    // have rendered with the Default fallback until now.
    if (_selectedIndex != null && _customProfileMissing == false) {
      _scheduleRender(live: false);
    }
  }

  Future<void> _loadColorProfile() async {
    final loaded = <ColorProfileMode, ColorProfile>{};
    for (final mode in ColorProfileMode.values) {
      final asset = mode.profileAsset;
      if (asset == null) {
        continue;
      }
      try {
        final raw = await rootBundle.loadString('assets/color_profiles/$asset');
        loaded[mode] = ColorProfile.decode(raw);
      } catch (_) {
        // Not bundled — fine, that mode just renders with no correction.
      }
    }
    if (!mounted || loaded.isEmpty) {
      return;
    }
    setState(() => _colorProfiles.addAll(loaded));
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
  /// moment before quitting.
  ///
  /// Every disk cache is flushed here too. Each one is written with an
  /// unawaited `flush()` at the point it is filled, which is normally
  /// enough — but "normally" means "unless the window closes in the next
  /// few milliseconds", and closing right after opening a photo is exactly
  /// when that happens. Losing one costs the next launch some work, not
  /// data; the point is that reopening a photo should be fast *because it
  /// was opened before*, and a lost flush quietly breaks that promise.
  ///
  /// Every cache with a `flush()` belongs in [_batchedCaches]. Missing one
  /// does not fail — it just makes the app slower in a way nothing points
  /// at, which is why they are enumerated in one place rather than listed
  /// again here.
  Future<AppExitResponse> _handleExitRequested() async {
    await _flushCurrentEdits();
    for (final cache in _batchedCaches) {
      await cache.flush();
    }
    return AppExitResponse.exit;
  }

  /// Every disk cache that holds writes in memory until flushed.
  ///
  /// The point of all three is that reopening a photo is fast *because it
  /// was opened before*; a write still sitting in memory when the window
  /// closes breaks that promise silently, and only for the photos opened
  /// last.
  Iterable<ThumbnailCacheManager> get _batchedCaches => [
    _thumbnailCache,
    _previewCache,
    _cameraMatchCache,
  ].whereType<ThumbnailCacheManager>();

  Future<void> _loadEditStore() async {
    await _store.load();
    if (!mounted) {
      return;
    }
    setState(() {
      // If the restored photo already has a preset marker, adopt it now
      // (its edit values were restored from the catalog on selection).
      final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
      if (selected != null && _appliedPresetId == null) {
        _appliedPresetId = _store.presets[selected.path];
      }
    });
  }

  PhotoCurves _curvesFor(String path) =>
      _store.curves[path] ?? identityPhotoCurves;

  List<MaskLayer> _masksFor(String path) => _store.masks[path] ?? const [];

  Future<void> _loadSettings() async {
    final settings = widget.settingsOverride ?? await loadSettings();
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
    } else {
      // No folder to restore — either there never was one, or the last
      // session was a single file (`lastActiveFolder` cleared by
      // `_loadSingleFile`'s `asSingleFileSession`). Reopen that file
      // directly instead of leaving the editor empty on launch.
      final lastFile = settings.lastActiveFile;
      if (lastFile != null) {
        unawaited(_loadSingleFile(lastFile));
      }
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
    _reloadCurrentFolderPreservingSelection();
  }

  /// Mirrors [_setRawOnly] — same "re-scan the open folder immediately"
  /// treatment for the sibling "Subfolder images" checkbox.
  void _setIncludeSubfolders(bool value) {
    final next = _settings.copyWith(includeSubfolders: value);
    setState(() => _settings = next);
    unawaited(saveSettings(next));
    _reloadCurrentFolderPreservingSelection();
  }

  void _reloadCurrentFolderPreservingSelection() {
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
        cacheUsage: _cacheUsage,
        onClearCaches: (categories) => unawaited(_clearCaches(categories)),
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
          // The embedded-JPEG toggle invalidates the same way, and more
          // completely: it changes *which pixels* the photo is, not just
          // how many of them.
          final previewResolutionChanged =
              next.previewResolution != _settings.previewResolution ||
              next.editEmbeddedJpeg != _settings.editEmbeddedJpeg;
          final cacheLimitChanged =
              next.cacheMaxBytes != _settings.cacheMaxBytes;
          setState(() {
            _settings = next;
            if (previewResolutionChanged) {
              _editSources.clear();
            }
          });
          unawaited(saveSettings(next));
          // A limit the user just lowered has to bite now, not on the
          // next launch — the meter is right there and would otherwise
          // sit above it, contradicting the setting beside it.
          if (cacheLimitChanged) {
            unawaited(_sweepCaches());
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
        },
        onClearThumbnails: () => unawaited(_clearThumbnailCache()),
        onClearCatalog: () => unawaited(_clearCatalogData()),
        onPruneMissing: () => unawaited(_pruneMissingCatalogEntries()),
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
    // The meter is very likely on screen right now — Settings is where
    // this button lives — so leaving it reporting the space that was just
    // reclaimed would read as the button having done nothing.
    unawaited(_refreshCacheUsage());
    if (_files.isNotEmpty) {
      unawaited(_loadThumbnails(_files, _folderGeneration));
    }
  }

  /// Deletes every saved per-photo edit and resets the currently-open
  /// photo (if any) back to its defaults, so the effect is visible right
  /// away instead of only affecting the next app launch.
  Future<void> _clearCatalogData() async {
    await _store.clear();
    if (!mounted) {
      return;
    }
    setState(() {
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

  /// Removes every catalog/curves/masks/preset/recent-file entry whose
  /// path no longer exists on disk — a targeted prune (Settings, item 2,
  /// 2026-09-01) rather than [_clearCatalogData]'s wipe-everything, for
  /// photos moved/renamed/deleted outside darkmoon whose stale entries
  /// would otherwise sit in these files forever (nothing else ever
  /// removes them).
  Future<void> _pruneMissingCatalogEntries() async {
    final paths = <String>{..._store.paths, ..._settings.recentFiles};
    final missing = <String>{};
    await Future.wait(
      paths.map((path) async {
        if (!await File(path).exists()) {
          missing.add(path);
        }
      }),
    );
    if (!mounted) {
      return;
    }
    if (missing.isEmpty) {
      _notify(
        detail: AppLocalizations.of(context)!.pruneMissingResultMessage(0),
      );
      return;
    }
    setState(() {
      _store.removeWhere(missing.contains);
      final next = _settings.copyWith(
        recentFiles: _settings.recentFiles
            .where((p) => !missing.contains(p))
            .toList(),
      );
      _settings = next;
      unawaited(saveSettings(next));
    });
    await _store.save();
    if (!mounted) {
      return;
    }
    _notify(
      detail: AppLocalizations.of(
        context,
      )!.pruneMissingResultMessage(missing.length),
    );
  }

  @override
  void dispose() {
    _renderDebounceTimer?.cancel();
    _catalogSaveTimer?.cancel();
    _cacheSweepTimer?.cancel();
    _slowRenderTimer?.cancel();
    _thumbnailFlushTimer?.cancel();
    _thumbnailUiFlushTimer?.cancel();
    _transientStatusTimer?.cancel();
    _completeVisibleThumbnailsReady();
    _viewController.dispose();
    _zoomAnimCurve.dispose();
    _zoomAnimController.dispose();
    _lifecycleListener.dispose();
    _shortcutsFocusNode.dispose();
    _presetThumbnails.dispose();
    super.dispose();
  }

  /// Merges [path]'s saved values over the defaults rather than just
  /// picking out the default-slider keys, so keys the sliders in
  /// [_sections] don't know about — Color Mixer's 24 and Color Grading's
  /// 9, both keyed straight into this same flat map — survive a reload
  /// instead of being silently dropped.
  Map<String, double> _paramValuesFor(String path) {
    final saved = _store.values[path];
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

  /// Writes the currently-selected photo's slider values into [_store] and
  /// saves the catalog immediately, bypassing the debounce — used when
  /// navigating away from a photo (fire-and-forget) and when the app is
  /// about to quit (awaited, so the write actually finishes before exit).
  Future<void> _flushCurrentEdits() async {
    _catalogSaveTimer?.cancel();
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    // Captured now, synchronously — not read back off _appliedPresetId
    // after the awaits below. This function is fired via `unawaited()`
    // (not a cancellable Timer like _scheduleCatalogSave), so if the user
    // switches photos while the saves are still in flight, _appliedPresetId
    // has already moved on to the *new* photo by the time this resumes —
    // writing that stale value would silently corrupt the previous
    // photo's applied-preset marker (a real bug: apply a preset, switch
    // away fast, switch back — the preset no longer shows as applied).
    final appliedPresetId = _appliedPresetId;
    _store.values[selected.path] = _catalogParams();
    _store.curves[selected.path] = _currentCurves;
    _store.masks[selected.path] = _currentMasks;
    await _store.saveEdits();
    _persistPhotoPreset(selected.path, appliedPresetId);
    _writeSidecarFor(selected.path);
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
      _store.values[selected.path] = _catalogParams();
      _store.curves[selected.path] = _currentCurves;
      _store.masks[selected.path] = _currentMasks;
      unawaited(_store.saveEdits());
      _persistPhotoPreset(selected.path, _appliedPresetId);
      _writeSidecarFor(selected.path);
    });
  }

  /// Mirrors [path]'s edits to its `.xmp` sidecar — the copy that travels
  /// with the file (Settings → Data; see sidecar_xmp.dart). Fire-and-
  /// forget: the sidecar writer logs its own failures.
  void _writeSidecarFor(String path) {
    if (!_settings.writeXmpSidecars) {
      return;
    }
    unawaited(_store.writeSidecar(path));
  }

  /// Sets [file]'s rating (0-5) — the store, its file and the sidecar.
  void _setRating(RawFile file, int rating) {
    final current = _store.meta[file.path] ?? const PhotoMeta();
    _setPhotoMeta(file.path, current.copyWith(rating: rating.clamp(0, 5)));
  }

  /// Sets [file]'s colour label (one of [photoLabelNames], or empty).
  void _setLabel(RawFile file, String label) {
    final current = _store.meta[file.path] ?? const PhotoMeta();
    _setPhotoMeta(file.path, current.copyWith(label: label));
  }

  void _setPhotoMeta(String path, PhotoMeta value) {
    setState(() => _store.setMeta(path, value));
    unawaited(_store.saveMeta());
    _writeSidecarFor(path);
  }

  /// The keyboard's 0-5 (rating) and 6-9 (label) on the selected photo,
  /// the way Meridian binds them; the current label pressed again clears.
  void _rateSelected(int rating) {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected != null) {
      _setRating(selected, rating);
    }
  }

  void _labelSelected(String label) {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    final current = _store.meta[selected.path]?.label ?? '';
    _setLabel(selected, current == label ? '' : label);
  }

  static const _digitKeys = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  /// Adopts [path]'s `.xmp` sidecar when the catalog knows nothing about
  /// the photo — it was edited on another machine, in another editor, or
  /// moved (the catalog is keyed by absolute path). A catalog entry wins
  /// otherwise: it is what this app wrote last.
  Future<void> _importSidecar(String path) async {
    if (!_settings.writeXmpSidecars) {
      return;
    }
    if (_store.contains(path)) {
      // Known photo: only a rating/label/tags it has none of yet can still
      // come from the file (given in another application).
      if (!_store.meta.containsKey(path)) {
        final sidecar = await readSidecar(path);
        if (sidecar != null && mounted && !_store.meta.containsKey(path)) {
          if (_store.adoptMeta(path, sidecar)) {
            setState(() {});
            unawaited(_store.saveMeta());
          }
        }
      }
      return;
    }
    final sidecar = await readSidecar(path);
    if (sidecar == null || !mounted) {
      return;
    }
    if (!sidecar.hasEdits) {
      if (!_store.meta.containsKey(path) && _store.adoptMeta(path, sidecar)) {
        setState(() {});
        unawaited(_store.saveMeta());
      }
      return;
    }
    // The user may have started editing while the file was being read.
    if (_store.contains(path) || (_catalogSaveTimer?.isActive ?? false)) {
      return;
    }
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    final isCurrentPhoto = selected?.path == path;
    setState(() {
      _store.adopt(path, sidecar);
      if (isCurrentPhoto) {
        _paramValues = _paramValuesFor(path);
        _currentCurves = _curvesFor(path);
        _currentMasks = _masksFor(path);
        _activeMaskId = imageMaskId;
        _appliedPresetId = _store.presets[path];
      }
    });
    if (isCurrentPhoto) {
      _resetHistory();
      // A no-op until the photo's own decode lands, which then renders
      // with the adopted values anyway.
      unawaited(_renderPreview(path));
    }
    unawaited(_store.save());
  }

  /// Syncs [_store]'s preset marker for [path] to [id] (set it, or drop it when
  /// null — no preset applied) and persists the file. [id] must be
  /// captured by the caller at the point [path] itself was captured, not
  /// read live off [_appliedPresetId] — see [_flushCurrentEdits]'s doc
  /// for the race that caused.
  void _persistPhotoPreset(String path, String? id) {
    if (id == null) {
      if (_store.presets.remove(path) == null) {
        return;
      }
    } else {
      if (_store.presets[path] == id) {
        return;
      }
      _store.presets[path] = id;
    }
    unawaited(_store.savePresets());
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
  /// badge. Checked against the *saved* catalog state ([_store]) rather
  /// than live in-editor state, so
  /// every thumbnail in the strip can be checked, not just the selected
  /// photo (whose RAW source may not even be decoded yet).
  /// [_defaultParamValues] built once for [_isPhotoEdited]: the table is
  /// static, and the check runs for every filmstrip tile on every rebuild
  /// — a 120-entry map per tile per frame was the audit's finding.
  late final Map<String, double> _defaultsForEditedBadge = Map.unmodifiable(
    _defaultParamValues(),
  );

  bool _isPhotoEdited(String path) {
    final masks = _store.masks[path];
    if (masks != null && masks.isNotEmpty) {
      return true;
    }
    final curves = _store.curves[path];
    if (curves != null && !curves.isIdentity) {
      return true;
    }
    final values = _store.values[path];
    if (values == null) {
      return false;
    }
    final defaults = _defaultsForEditedBadge;
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
        _disposeAllPreviews();
        _histograms.clear();
        _metadata.clear();
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
      _store.values.remove(path);
      _store.curves.remove(path);
      _store.masks.remove(path);
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
    await _store.saveEdits();
    _writeSidecarFor(path);
  }

  /// Right-click on the image — "Copy Edits" / "Paste Edits", the same
  /// idea as Meridian's Copy/Paste Settings but with no picker (everything
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
        const PopupMenuDivider(),
        PopupMenuItem(value: _resetActive, child: Text(l10n.resetTooltip)),
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
        values: {...(_store.values[file.path] ?? _freshParamValues(file.path))},
        curves: _store.curves[file.path] ?? identityPhotoCurves,
        masks: [...(_store.masks[file.path] ?? const [])],
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
      _store.values[file.path] = {...copied.values};
      _store.curves[file.path] = copied.curves;
      _store.masks[file.path] = [...copied.masks];
      _store.presets.remove(file.path);
    });
    unawaited(_store.save());
    _writeSidecarFor(file.path);
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
      _disposePreviewsFor(path);
      _histograms.remove(path);
      _metadata.remove(path);
      _store.values.remove(path);
      _store.curves.remove(path);

      if (removedIndex == _selectedIndex) {
        _selectedIndex = null;
      } else if (_selectedIndex != null && removedIndex < _selectedIndex!) {
        // Every index after the removed one shifted down by one — keep
        // pointing at the same photo, not whatever slid into its old slot.
        _selectedIndex = _selectedIndex! - 1;
      }
    });
    await _store.saveEdits();
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
        _disposeAllPreviews();
        _histograms.clear();
        _metadata.clear();
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
    final files = await listRawFiles(
      folder,
      rawOnly: _settings.rawOnly,
      includeSubfolders: _settings.includeSubfolders,
    );
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
    // Real bug (2026-09-01): without this, a single-file session (File >
    // Open File, or Recent Files) left `lastActiveFolder` pointing at
    // whatever folder was open before (or left it unset entirely, if none
    // ever was) — `_loadSettings` only restores via `_loadFolder`, so the
    // app either reopened the wrong folder or nothing at all on the next
    // launch, never this file.
    final next = _settings.asSingleFileSession(path);
    _settings = next;
    unawaited(saveSettings(next));
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
      _disposeAllPreviews();
      _histograms.clear();
      _metadata.clear();
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
    _renderCancel?.set();
    _slowRenderTimer?.cancel();
    _thumbnailUiFlushTimer?.cancel();
    _thumbnailUiFlushTimer = null;
    _completeVisibleThumbnailsReady();
    _exportCancellation?.cancel();
    _aiEnhanceCancellation?.cancel();
    _cloudDenoiseCancellation?.cancel();
    _colorizeCancellation?.cancel();
    setState(() {
      _loading = false;
      _isDecodingPhoto = false;
      _isRenderingSlow = false;
      _isApplyingAiDenoise = false;
      _isRunningNeuralEnhance = false;
      _aiEnhanceProgress = null;
      _isRunningCloudDenoise = false;
      _cloudDenoiseStage = null;
      _isApplyingColorize = false;
      _isRunningColorize = false;
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
          : _store.presets[files[selectedIndex].path];
    });
    _resetHistory();
    if (selectedIndex != null) {
      unawaited(_importSidecar(files[selectedIndex].path));
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

  /// Left/Right arrow key filmstrip navigation (2026-09-01, explicit user
  /// request) — [delta] is -1 (previous) or 1 (next). No-op past either
  /// end rather than wrapping around, matching how most photo browsers
  /// (including this one's own thumbnail-click selection) behave.
  void _selectAdjacentPhoto(int delta) {
    final current = _selectedIndex;
    if (current == null || _files.isEmpty) {
      return;
    }
    final next = current + delta;
    if (next < 0 || next >= _files.length) {
      return;
    }
    _selectIndex(next);
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
      // Restore the "applied preset" marker for this photo (persisted).
      _appliedPresetId = _store.presets[path];
    });
    _resetHistory();
    unawaited(_importSidecar(path));
    // Before kicking off this photo's own decode/render, drop whatever the
    // ones we've navigated away from were still holding.
    _trimPhotoCaches();
    unawaited(_saveLastActiveFile(path));
    // Started before the decode and not awaited: reading a JPEG that is
    // already in the file takes a fraction of what demosaicing the sensor
    // does, so this is what the viewport shows for most of the wait.
    unawaited(_loadEmbeddedPreview(path));
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
      final wantUpscaleSharpnessAmount =
          (_paramValues[_upscaleSharpnessAmountKey] ?? 0.0).round();
      final wantRestoreDetail = (_paramValues[_restoreDetailKey] ?? 0.0) > 0;
      final wantRestoreDetailAmount =
          (_paramValues[_restoreDetailAmountKey] ?? defaultRestoreDetailAmount)
              .round();
      final wantAnyEnhance =
          wantDenoise || wantUpscale || wantRawDenoise || wantRestoreDetail;
      // Colorize is a pass *inside* the Enhance pipeline when both are on,
      // so the combination lives under the Enhance cache with colorize
      // folded into its key — not under the colorize cache. Read here
      // (ahead of its own block below) so this lookup can key on it.
      final wantColorizeWithEnhance =
          wantAnyEnhance && (_paramValues[_colorizeKey] ?? 0.0) > 0;
      final wantComboColorizeIntensity =
          (_paramValues[_colorizeIntensityKey] ?? defaultColorizeIntensity)
              .round();
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
            upscaleSharpnessAmount: wantUpscaleSharpnessAmount,
            detailRestore: wantRestoreDetail,
            detailRestoreAmount: wantRestoreDetailAmount,
            colorize: wantColorizeWithEnhance,
            colorizeIntensityPercent: wantComboColorizeIntensity,
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

      // Same reasoning again, for item 37's colorize — mutually exclusive
      // with both of the above (see `_openColorizeDialog`'s doc), so at
      // most one of these three cache lookups ever actually finds
      // something.
      final wantColorize = (_paramValues[_colorizeKey] ?? 0.0) > 0;
      final wantColorizeIntensity = wantComboColorizeIntensity;
      // Colorize *alone* keeps its own dedicated cache; combined with
      // Enhance it was already resolved from the Enhance cache above.
      if (wantColorize && !wantAnyEnhance) {
        final cacheDir = await resolveColorizeCacheDir();
        if (mounted) {
          final cachedPng = await lookupColorizeCache(
            cacheDir,
            path,
            intensityPercent: wantColorizeIntensity,
          );
          if (cachedPng != null) {
            sources = await compute(
              decodeCachedColorizeSources,
              DecodeCachedColorizeArgs(cachedPng, _settings.previewResolution),
            );
            fromCache = sources != null;
          }
        }
      }
      final wantAnyPipeline =
          wantAnyEnhance || wantCloudProvider != null || wantColorize;

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
          (stage) {
            if (mounted && generation == _folderGeneration) {
              setState(() => _photoDecodeStage = stage);
            }
          },
          previewMaxDimension: _settings.previewResolution,
          editEmbeddedJpeg: _settings.editEmbeddedJpeg,
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
              _restoreDetailKey: 0.0,
              _cloudDenoiseProviderKey: 0.0,
              _colorizeKey: 0.0,
            };
          });
        }
      }

      if (!mounted || generation != _folderGeneration) {
        return;
      }
      setState(() {
        _isDecodingPhoto = false;
        _photoDecodeStage = null;
      });
      if (sources == null) {
        // A cache miss followed by a real decode failure this deep almost
        // always means the file itself is gone (moved/renamed/deleted
        // outside darkmoon, or its drive unmounted) rather than a
        // transient error — surface that instead of leaving the canvas
        // stuck on "decoding..." forever.
        setState(() => _missingFiles.add(path));
        return;
      }
      // A cache hit skipped decodeRawImage, and with it the one place
      // baseExposureStops is ever measured — so put it back before the
      // pair is handed to the renderer. Without this the photo renders at
      // LibRaw's auto-brightened exposure with nothing correcting it, and
      // blows its highlights out on every open after the first (reported
      // 2026-09-09; it looked fixed under measurement because a fresh
      // decode is exactly the case that already worked).
      sources = await _withMeasuredCameraMatch(path, sources);
      if (!mounted || generation != _folderGeneration) {
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
    _scheduleCacheSweep();
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
        editEmbeddedJpeg: _settings.editEmbeddedJpeg,
        lowPriority: true,
      );
      if (sources == null || !mounted || generation != _folderGeneration) {
        return;
      }
      // Same gap as the selection path's, and it reaches the user the same
      // way: a prewarmed pair goes straight into _editSources, so
      // selecting that photo later skips the decode block entirely and
      // never gets a chance to measure the offset.
      sources = await _withMeasuredCameraMatch(
        file.path,
        sources,
        lowPriority: true,
      );
      if (!mounted || generation != _folderGeneration) {
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
    final savedWb = _store.values[path]?.containsKey('Temperature') ?? false;
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
    // Every render passes through here — the debounced one, opening a
    // photo, applying a preset, undo — so this is the one place that
    // catches every way an AI mask can come into existence or go stale.
    // Deliberately not awaited: inference takes seconds, and until its map
    // lands the mask renders as empty rather than holding up the frame.
    unawaited(_resolveAiMasks(path));
    if (_renderInFlight) {
      _pendingRenderRequest = (path: path, live: live, onStage: onStage);
      if (!_renderInFlightLive) {
        _renderCancel?.set();
      }
      final completer = Completer<void>();
      _pendingRenderWaiters.add(completer);
      return completer.future;
    }
    _renderInFlight = true;
    _renderInFlightLive = live;
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
    final cancel = IsolateCancelFlag();
    _renderCancel = cancel;
    try {
      await _renderPreviewInner(path, sources, requestId, live, onStage);
    } on IsolateCancelled {
      // Superseded and stopped early — the request that replaced it is
      // about to run.
    } catch (e, st) {
      debugPrint('render failed: $e\n$st');
    } finally {
      // The worker has returned (or thrown) by here, so nothing reads the
      // flag any more.
      if (identical(_renderCancel, cancel)) {
        _renderCancel = null;
      }
      cancel.dispose();
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
    // still visible under the overlay's scrim, Meridian-style, instead
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
    RenderJob buildJob(EditSource src) => RenderJob(
      source: src,
      params: RenderParams.fromValues(
        _effectiveParamValues(),
        curves: _effectiveCurves,
        asShotKelvin: metadata?.asShotKelvin ?? wbDefaultKelvin,
        asShotTint: metadata?.asShotTint ?? wbDefaultTint,
        baseExposureStops: _baseExposureFor(path),
        baseContrast: _baseContrastFor(path),
        colorProfile: _colorProfileFor(path),
        colorProfileStrength: _effectiveColorProfileStrength,
      ),
      masks: _effectiveMasks,
      aiMaskMaps: _aiMaskMaps,
      cropTransform: cropTransform,
      lensCorrection: _lensCorrection,
      lensProfile: _resolvedLensProfileFor(path),
      focalLengthMm: metadata?.focalLengthMm ?? 0,
      apertureFNumber: metadata?.apertureFNumber ?? 0,
      // Live drag frames and the progress-tracked one-shot applies (AI
      // Denoise) run to completion — see _renderCancel.
      cancelFlagAddress: live || onStage != null
          ? null
          : _renderCancel?.address,
    );

    // Phase 1 — the quick render: the tiny `live` buffer while dragging,
    // the preview buffer for a settled edit. Always cheap, always shown.
    //
    // Cropping uses the `live` buffer for both. Every drag of a corner or
    // the rotate anchor re-runs the whole pipeline — geometry resample
    // included — and at preview resolution that is enough work to be felt
    // (2026-09-07, user's report). Nothing being judged while cropping
    // needs the detail: framing and horizon are decided from shape, and
    // the full-resolution render arrives the moment the overlay closes.
    final quickSource = (live || _cropOverlayActive)
        ? sources.live
        : sources.preview;
    final firstResult = await _runRenderJob(
      buildJob(quickSource),
      onStage: onStage,
      allowGpu: !live,
    );
    if (!mounted || requestId != _renderRequestId) {
      return;
    }
    // The GPU hands back the frame it painted; the CPU's pixels are
    // uploaded here.
    final firstImage =
        firstResult.image ?? await _decodePreviewImage(firstResult.pixels!);
    if (!mounted || requestId != _renderRequestId) {
      // Superseded while the upload was in flight — nothing will ever
      // paint this frame, and nothing else owns it yet.
      firstImage.dispose();
      return;
    }
    setState(() {
      _isRenderingSlow = false;
      _setPreviewImage(_renderedPreviews, path, firstImage);
      // Fade in a settled render (applied edit/preset/reset/undo/redo, or
      // a freshly-decoded photo's first frame) — never a live drag frame.
      if (!live) {
        _previewFadeGeneration++;
      }
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
  }

  /// GPU / CPU-parallel / progress-tracked dispatch for one render job —
  /// the [onStage] path (AI Denoise) wants real stage progress; otherwise
  /// GPU when [allowGpu] and available, else CPU-parallel via `compute()`.
  Future<PreviewRender> _runRenderJob(
    RenderJob job, {
    void Function(RenderStage stage)? onStage,
    bool allowGpu = false,
  }) async {
    if (onStage != null) {
      return PreviewRender.cpu(await renderJobToJpegWithProgress(job, onStage));
    }
    // The "darkmoon Color" profile is fully on the GPU as of 2026-09-04 —
    // both the per-hue correction and the tone curve (color_profile_gpu.dart,
    // color_profile.frag's uToneLut). There used to be a
    // `gpuMissingToneCurve` check here forcing CPU for any profile whose
    // tone curve was not the identity ramp, which was harmless only
    // because every profile shipped so far sets tone to identity by
    // design. User-authored profiles will not, so the check had to go
    // rather than quietly make every custom profile render on the CPU.
    // Radii scale with the frame now (RenderParams.renderScale), and the
    // GPU's box-blur shaders have a fixed maximum radius they would
    // silently truncate past — so a large enough full-quality render has
    // to go to the CPU, which has no such cap. Uses the source's own
    // dimensions: a crop only ever makes the rendered frame smaller, so
    // this errs toward CPU rather than toward a wrong blur.
    final gpuScaleOk = gpuCanRenderAtScale(
      job.params
          .withRenderScaleFor(job.source.width, job.source.height)
          .renderScale,
    );
    if (allowGpu && gpuScaleOk && _settings.useGpuRender) {
      // Probed once at launch (see initState), so this is settled by the
      // time any render runs — read synchronously to avoid awaiting a
      // known answer, which would push the render into the next microtask
      // for nothing.
      final probed = gpuRenderAvailableIfProbed ?? await isGpuRenderAvailable();
      if (probed) {
        return PreviewRender.gpu(await renderJobToImageGpu(job));
      }
    }
    return PreviewRender.cpu(await compute(renderJobToJpeg, job));
  }

  /// The photo's decoded native-resolution [EditSource] — from the
  /// in-memory full-quality source if it's this photo's, then the shared
  /// `previews/native` disk cache, then a fresh RAW decode that also warms
  /// the cache. Used by both the full-quality preview and export, so the
  /// slow RAW demosaic (especially X-Trans) is paid at most once per photo.
  ///
  /// The disk cache is skipped entirely for a common (non-RAW) image: real
  /// bug (2026-09-01) — the cache stores a JPEG (quality 96, but still
  /// lossy), so every export of an already-JPEG (or other lossy-format)
  /// source stacked an extra lossy generation on top of the file's own
  /// compression, on top of the final export's own JPEG encode. Unlike a
  /// RAW demosaic, decoding a common image is cheap enough (`package:image`
  /// straight off disk) that there's nothing worth caching — a fresh decode
  /// every time keeps the source exactly as lossy as the original file.
  Future<EditSource?> _loadNativeSource(
    String path, {
    required bool lowPriority,
  }) async {
    final request = FullQualityRequest(
      path,
      editEmbeddedJpeg: _settings.editEmbeddedJpeg,
    );
    // Embedded-JPEG mode skips the cache for the same reason a common
    // image does, and it is the same reason: there is no expensive
    // demosaic to skip, so a cache would only add a lossy generation and
    // a way for the two modes to serve each other's pixels.
    if (!isRawFile(path) || _settings.editEmbeddedJpeg) {
      return compute(
        lowPriority
            ? decodeFullQualitySourceLowPriority
            : decodeFullQualitySource,
        request,
      );
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
      request,
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
    int upscaleSharpnessAmount = 0,
    bool restoreDetail = false,
    int restoreDetailAmount = defaultRestoreDetailAmount,
    bool colorize = false,
    int colorizeIntensity = defaultColorizeIntensity,
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
      upscaleSharpnessAmount: upscaleSharpnessAmount,
      detailRestore: restoreDetail,
      detailRestoreAmount: restoreDetailAmount,
      colorize: colorize,
      colorizeIntensityPercent: colorizeIntensity,
    );
    if (cachedPng == null) {
      final ok = await _runNeuralEnhance(
        path,
        denoise: denoise,
        upscale: upscale,
        denoiseAmount: denoiseAmount,
        rawDenoise: rawDenoise,
        upscaleSharpnessAmount: upscaleSharpnessAmount,
        restoreDetail: restoreDetail,
        restoreDetailAmount: restoreDetailAmount,
        colorize: colorize,
        colorizeIntensity: colorizeIntensity,
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
        upscaleSharpnessAmount: upscaleSharpnessAmount,
        detailRestore: restoreDetail,
        detailRestoreAmount: restoreDetailAmount,
        colorize: colorize,
        colorizeIntensityPercent: colorizeIntensity,
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

  /// Export's colorize equivalent of [_loadEnhancedNativeSource] — same
  /// "re-run on a cache miss" behavior (colorize is on-device and free,
  /// same reasoning as AI Enhance, unlike the cloud-denoise cache-only
  /// choice above).
  Future<EditSource?> _loadColorizedNativeSource(
    String path, {
    required int intensityPercent,
  }) async {
    final cacheDir = await resolveColorizeCacheDir();
    if (!mounted) return null;
    var cachedPng = await lookupColorizeCache(
      cacheDir,
      path,
      intensityPercent: intensityPercent,
    );
    if (cachedPng == null) {
      final ok = await _runColorize(path, intensityPercent: intensityPercent);
      if (!mounted || !ok) {
        return null;
      }
      cachedPng = await lookupColorizeCache(
        cacheDir,
        path,
        intensityPercent: intensityPercent,
      );
    }
    if (cachedPng == null || !mounted) {
      return null;
    }
    return compute(decodeColorizeCacheEntry, cachedPng);
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
        // correction) and the camera's own base exposure — all of it is
        // part of the baseline rendering, like Meridian keeping the camera
        // profile, not a develop edit. Leaving the exposure out here would
        // make Before and After differ by a stop before a single slider
        // moved.
        params: RenderParams(
          exposure: _baseExposureFor(path),
          baseContrast: _baseContrastFor(path),
          colorProfile: _colorProfileFor(path),
        ),
      ),
    );
    final image = await _decodePreviewImage(result);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _setPreviewImage(_neutralPreviews, path, image));
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
      // Never leave Guided mode silently armed for the next time Crop
      // reopens — closing Crop always exits it too.
      if (!opening) {
        _guidedModeActive = false;
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
  /// the *next* drag to pick up — Meridian's aspect picker snaps the
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

  int _cloudProviderIndex(CloudDenoiseProviderKind? provider) =>
      provider == null
      ? 0
      : CloudDenoiseProviderKind.values.indexOf(provider) + 1;

  CloudDenoiseProviderKind? _cloudProviderFromIndex(int index) =>
      index <= 0 || index > CloudDenoiseProviderKind.values.length
      ? null
      : CloudDenoiseProviderKind.values[index - 1];

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
        // matching Meridian.
        if (name == 'Temperature' || name == 'Tint')
          _wbModeKey: WbMode.custom.index.toDouble(),
      };
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

  /// The canvas has one eyedropper overlay; this routes its sample to
  /// whichever tool armed it.
  void _onEyedropperSample(double nx, double ny) {
    if (_profileHueEyedropperActive) {
      unawaited(_sampleProfileHue(nx, ny));
      return;
    }
    _onSampleWhiteBalance(nx, ny);
  }

  /// Reads the hue under the pointer and reopens the profile editor on the
  /// range that owns it.
  Future<void> _sampleProfileHue(double nx, double ny) async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    final draft = _pendingProfileDraft;
    if (selected == null || draft == null) {
      return;
    }
    final pixel = await _samplePreviewPixel(selected.path, nx, ny);
    if (!mounted) {
      return;
    }
    setState(() {
      _profileHueEyedropperActive = false;
      _pendingProfileDraft = null;
    });
    if (pixel == null) {
      // Nothing readable under the pointer — reopen where we left off
      // rather than discarding the profile the user was building.
      await _openColorProfileEditor(initial: draft);
      return;
    }
    final (hue, _, _) = rgbToHsv(pixel.r, pixel.g, pixel.b);
    await _openColorProfileEditor(initial: draft, highlightHue: hue);
  }

  /// The open photo as a small packed-RGB buffer, for the profile editor's
  /// "current photo" preview source.
  ///
  /// Reads [_neutralPreviews], not the displayed render: the editor's
  /// preview applies the profile and nothing else, so handing it a frame
  /// that already carries the photo's exposure, curves and masks would
  /// make it impossible to tell which part of what you see is the profile.
  ///
  /// Downscaled hard. The preview re-runs applyColorProfile on the CPU for
  /// every frame of a slider drag, and a full-resolution buffer would turn
  /// that into a stutter for detail nobody can see in a 400px-wide box.
  Future<({Float32List rgb, int width, int height})?>
  _profilePreviewSource() async {
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return null;
    }
    // Render it if it is not there. Until 2026-09-07 this read the cache
    // and gave up: the neutral preview is only produced when Before/After
    // is switched on, so for anyone who had never used that mode the
    // profile editor simply showed no photo at all. The cache is keyed by
    // path and shared with Before/After, so this is not extra work — it is
    // the same render, just requested earlier.
    if (!_neutralPreviews.containsKey(selected.path)) {
      await _loadNeutralPreview(selected.path);
    }
    final neutral = _neutralPreviews[selected.path];
    if (neutral == null || !mounted) {
      return null;
    }
    // Own a handle across the readback — a render landing mid-await would
    // otherwise dispose this out from under us.
    final image = neutral.clone();
    final ByteData? bytes;
    try {
      bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
    if (bytes == null) {
      return null;
    }

    const targetWidth = 384;
    final scale = neutral.width <= targetWidth
        ? 1
        : (neutral.width / targetWidth).ceil();
    final w = neutral.width ~/ scale;
    final h = neutral.height ~/ scale;
    if (w < 1 || h < 1) {
      return null;
    }
    final rgba = bytes.buffer.asUint8List();
    final rgb = Float32List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final src = ((y * scale) * neutral.width + x * scale) * 4;
        final dst = (y * w + x) * 3;
        rgb[dst] = rgba[src].toDouble();
        rgb[dst + 1] = rgba[src + 1].toDouble();
        rgb[dst + 2] = rgba[src + 2].toDouble();
      }
    }
    return (rgb: rgb, width: w, height: h);
  }

  /// Measures how far the open photo is off level and straightens it.
  ///
  /// The Level mode of the Upright set (PENDING item 27). It reads the
  /// *neutral* preview, which renders with no geometry at all, so what
  /// comes back is the absolute angle to set rather than a correction to
  /// add to whatever Straighten already holds.
  ///
  /// Runs the per-pixel pass on another isolate: it is the same class of
  /// work as a render, and the button is disabled meanwhile so a second
  /// press cannot queue a second one.
  Future<void> _levelPhoto() async {
    if (_levelBusy) {
      return;
    }
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    setState(() => _levelBusy = true);
    try {
      final source = await _levelSource(selected.path);
      if (source == null || !mounted) {
        return;
      }
      final rotation = await compute(levelRotationForRequest, source);
      if (!mounted) {
        return;
      }
      if (rotation == null) {
        // Not a failure to report as an error: plenty of photographs have
        // nothing straight in them, and guessing would be worse than
        // saying so.
        _showTransientStatus(
          AppLocalizations.of(context)!.transformLevelNothingFound,
        );
        return;
      }
      _onCropTransformChangeEnd(
        _cropTransform.copyWith(straightenAngle: rotation),
      );
    } finally {
      if (mounted) {
        setState(() => _levelBusy = false);
      }
    }
  }

  /// Auto mode of the Upright set: levels the photo *and* corrects the
  /// perspective its edges reveal, in one press.
  ///
  /// Shares [_levelSource] and the same isolate discipline as
  /// [_levelPhoto]; what differs is that it writes three sliders instead
  /// of one, and that it replaces rather than adds — pressing Auto twice
  /// should land in the same place, not compound.
  Future<void> _uprightAuto(UprightMode mode) async {
    if (_uprightBusy) {
      return;
    }
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected == null) {
      return;
    }
    setState(() => _uprightBusy = true);
    try {
      final source = await _levelSource(selected.path);
      if (source == null || !mounted) {
        return;
      }
      final correction = await compute(
        uprightAutoForRequest,
        UprightAutoRequest(source.luma, source.width, source.height, mode),
      );
      if (!mounted) {
        return;
      }
      if (correction == null) {
        // Same judgement as Level: plenty of photographs have nothing
        // straight in them, and guessing would be worse than saying so.
        _showTransientStatus(
          AppLocalizations.of(context)!.transformAutoNothingFound,
        );
        return;
      }
      _onCropTransformChangeEnd(
        _cropTransform.copyWith(
          straightenAngle: correction.straightenAngle,
          vertical: correction.vertical,
          // Every mode writes this. The ones that do not correct the axis
          // report zero for it, and leaving a previous run's value behind
          // would make the modes compound instead of replace.
          horizontal: correction.horizontal,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _uprightBusy = false);
      }
    }
  }

  /// Where the Exposure slider's zero sits for [path]: how many stops the
  /// decode is from the brightness of the camera's own preview of the same
  /// shot.
  ///
  /// The exact shape of As Shot white balance, and for the same reason —
  /// the camera made a judgement about this photo and it is a better
  /// starting point than a fixed constant. Zero when the file carries no
  /// preview to compare against, which is every non-RAW source, so those
  /// keep opening exactly as they did.
  double _baseExposureFor(String? path) {
    if (path == null) {
      return 0;
    }
    // The tone curve already carries the camera's brightness — spending
    // the offset as well would apply the same correction twice.
    if (_baseToneCurveFor(path) != null) {
      return 0;
    }
    return _editSources[path]?.baseExposureStops ?? 0;
  }

  /// Points the preset thumbnails at whatever is selected now.
  ///
  /// Called from build, which is the one place that reliably runs after
  /// every change that matters — a different photo, its sources finishing
  /// their decode, the colour profile changing. [PresetThumbnailStore]
  /// makes that affordable: it compares the signature and returns
  /// immediately when nothing has changed, and defers its notification so
  /// that calling it mid-build cannot mark a listener dirty during the
  /// same build.
  void _syncPresetThumbnails() {
    final path = _selectedIndex == null ? null : _files[_selectedIndex!].path;
    final source = path == null ? null : _editSources[path]?.live;
    final profile = _colorProfileFor(path);
    _presetThumbnails.setSource(
      // Everything a thumbnail depends on except the preset itself. The
      // profile belongs here because a thumbnail is this photo seen
      // *through* it, so changing it makes every cached one wrong.
      signature: [
        path ?? '',
        profile?.name ?? '',
        // The camera tone curve rides in the profile's tone slot and is
        // per photo, so the profile's name no longer identifies it.
        profile?.tone.first ?? 0,
        profile?.tone.last ?? 0,
        _baseContrastFor(path),
        source?.width ?? 0,
      ].join('|'),
      source: source,
      paramsFor: (preset) => RenderParams.fromValues(
        preset.values,
        curves: preset.curves,
        asShotKelvin: path == null ? wbDefaultKelvin : _asShotFor(path).kelvin,
        asShotTint: path == null ? wbDefaultTint : _asShotFor(path).tint,
        // Or every thumbnail would be a stop away from the render it is
        // supposed to be previewing.
        baseExposureStops: _baseExposureFor(path),
        baseContrast: _baseContrastFor(path),
        colorProfile: profile,
      ),
    );
  }

  /// [sources] with its camera match ([EditSourcePair.baseToneCurve] and
  /// [EditSourcePair.baseExposureStops]) filled in when it is missing —
  /// which is exactly when the pair came out of a cache rather than a
  /// fresh RAW decode. Unchanged when it is already there (a real decode
  /// measured it) or when there is nothing to measure against.
  ///
  /// Every path that writes [_editSources] has to go through here. Missing
  /// one is not a visible failure: the photo simply renders at LibRaw's
  /// auto-brightened exposure, which reads as blown highlights rather than
  /// as anything pointing back at the cache.
  Future<EditSourcePair> _withMeasuredCameraMatch(
    String path,
    EditSourcePair sources, {
    bool lowPriority = false,
  }) async {
    if (sources.baseToneCurve != null || sources.baseExposureStops != null) {
      return sources;
    }
    // Nothing to match: in this mode the pixels *are* the camera's own
    // rendering, so a fit would only measure it against itself.
    if (_settings.editEmbeddedJpeg) {
      return sources;
    }
    final cached = await _readCameraMatch(path);
    if (cached != null) {
      return sources.withCameraMatch(cached);
    }
    final match = await _probeCameraMatch(
      path,
      sources.preview,
      lowPriority: lowPriority,
    );
    if (match.isEmpty) {
      return sources;
    }
    unawaited(_storeCameraMatch(path, match));
    return sources.withCameraMatch(match);
  }

  /// [path]'s camera match from disk, or null if it has never been
  /// measured (or the file has changed since — the cache key covers mtime
  /// and size, so a replaced file misses rather than returning a match for
  /// a photo that is no longer there).
  Future<CameraMatch?> _readCameraMatch(String path) async {
    final cache = _cameraMatchCache;
    if (cache == null) {
      return null;
    }
    final bytes = await cache.lookup(path);
    if (bytes == null) {
      return null;
    }
    try {
      return CameraMatch.fromJson(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      // A truncated or half-written entry. Measuring again is cheap
      // relative to getting this wrong, and the fresh write replaces it.
      return null;
    }
  }

  /// Best-effort, never awaited by callers: a failure here costs the next
  /// open of this photo one measurement, not correctness.
  Future<void> _storeCameraMatch(String path, CameraMatch match) async {
    final cache = _cameraMatchCache;
    if (cache == null) {
      return;
    }
    await cache.store(
      path,
      Uint8List.fromList(utf8.encode(jsonEncode(match.toJson()))),
    );
    unawaited(cache.flush());
  }

  /// [probeCameraMatch] for [path], reading the camera's own JPEG
  /// through the same cache the viewport stand-in uses — by the time a
  /// cache hit gets here it is normally already loaded, since
  /// [_selectIndex] starts that read first precisely because it is the
  /// cheap one.
  ///
  /// Null when the file carries no embedded JPEG to compare against (and
  /// for every non-RAW source), which is the same answer a fresh decode
  /// gives for those — they keep opening exactly as they did.
  Future<CameraMatch> _probeCameraMatch(
    String path,
    EditSource preview, {
    bool lowPriority = false,
  }) async {
    if (!isRawFile(path)) {
      return CameraMatch.none;
    }
    await _loadEmbeddedPreview(path);
    final embedded = _embeddedPreviews[path];
    if (embedded == null) {
      return CameraMatch.none;
    }
    return compute(
      lowPriority ? probeCameraMatchLowPriority : probeCameraMatch,
      (source: preview, embeddedJpeg: embedded),
    );
  }

  /// Reads the camera's own JPEG out of [path] into [_embeddedPreviews].
  ///
  /// Cheap next to a RAW decode and worth doing on every selection: it is
  /// what stands in for the render while that decode runs, and it is
  /// several times sharper than the filmstrip thumbnail that used to hold
  /// that place.
  ///
  /// Silent on failure. Not every RAW carries a JPEG preview, and one that
  /// does not simply keeps the old stand-in rather than reporting anything
  /// — nothing here is the photograph, only what is shown while the real
  /// one is on its way.
  Future<void> _loadEmbeddedPreview(String path) async {
    if (_embeddedPreviews.containsKey(path) || !isRawFile(path)) {
      return;
    }
    final bytes = await compute(extractRawThumbnailJpeg, path);
    if (bytes == null || !mounted) {
      return;
    }
    // The photo can be switched while this runs; keeping it is still
    // right (the cache is keyed by path and trimmed by proximity), but it
    // must not be allowed to redraw a viewport that has moved on.
    _embeddedPreviews[path] = bytes;
    if (_selectedIndex != null && _files[_selectedIndex!].path == path) {
      setState(() {});
    }
  }

  /// The neutral preview as luma, for [_levelPhoto] and [_uprightAuto].
  ///
  /// Box-averaged down rather than point-sampled. Nearest-neighbour would
  /// alias every edge into a staircase, and a staircased edge is exactly
  /// the case the estimator measures worst — averaging softens the edge,
  /// which is what carries the angle.
  Future<LevelRequest?> _levelSource(String path) async {
    if (!_neutralPreviews.containsKey(path)) {
      await _loadNeutralPreview(path);
    }
    final neutral = _neutralPreviews[path];
    if (neutral == null || !mounted) {
      return null;
    }
    final image = neutral.clone();
    final ByteData? bytes;
    try {
      bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
    if (bytes == null) {
      return null;
    }

    const target = 800;
    final step = neutral.width <= target ? 1 : (neutral.width / target).ceil();
    final w = neutral.width ~/ step;
    final h = neutral.height ~/ step;
    if (w < 8 || h < 8) {
      return null;
    }
    final rgba = bytes.buffer.asUint8List();
    final luma = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var count = 0;
        for (var sy = 0; sy < step; sy++) {
          for (var sx = 0; sx < step; sx++) {
            final i = ((y * step + sy) * neutral.width + x * step + sx) * 4;
            if (i + 2 >= rgba.length) {
              continue;
            }
            sum +=
                0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
            count++;
          }
        }
        luma[y * w + x] = count == 0 ? 0 : (sum / count).round().clamp(0, 255);
      }
    }
    return LevelRequest(luma, w, h);
  }

  /// [_paramValues] with every disabled category's sliders swapped for
  /// their defaults, then the whole result scaled by the global Amount
  /// slider — used wherever the render pipeline reads the global layer's
  /// param values (CPU preview, GPU preview, and export all read through
  /// this one function, so both get Amount applied automatically with no
  /// separate wiring). See [_withCategoriesApplied]'s and
  /// [withGlobalEditAmountApplied]'s own doc comments.
  Map<String, double> _effectiveParamValues() {
    final path = _selectedIndex == null ? null : _files[_selectedIndex!].path;
    final asShot = path == null
        ? (kelvin: wbDefaultKelvin, tint: wbDefaultTint)
        : _asShotFor(path);
    return withGlobalEditAmountApplied(
      _withCategoriesApplied(
        _paramValues,
        asShotKelvin: asShot.kelvin,
        asShotTint: asShot.tint,
      ),
    );
  }

  /// [_currentCurves] with Tone Curve/Color Curve reset to identity if
  /// either is disabled, then blended toward identity by the global Amount
  /// slider — the curve equivalent of [_effectiveParamValues], kept
  /// separate since curves don't live in the flat values map.
  ///
  /// Real bug (2026-09-01, user report): a preset that leans heavily on
  /// its Tone/Color Curve (vs. flat sliders) barely responded to Amount at
  /// all, while a slider-heavy preset responded strongly — because Amount
  /// only ever scaled [_paramValues] ([withGlobalEditAmountApplied]);
  /// curves stayed at full strength regardless. `lerpPhotoCurves` already
  /// existed for exactly this ("used for a preset's Amount slider", see
  /// its own doc in tone_curve.dart) and already had test coverage — it
  /// was just never actually wired in here.
  PhotoCurves get _effectiveCurves {
    final categoryApplied = _withCurveCategoriesApplied(
      _currentCurves,
      _paramValues,
    );
    final amount = _paramValues[_globalEditAmountKey] ?? 100.0;
    final compression = colorProfileModeOf(_paramValues).dampened
        ? calGlobalAmountCompression
        : 1.0;
    final fraction = amount / 100.0 * compression;
    return lerpPhotoCurves(identityPhotoCurves, categoryApplied, fraction);
  }

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

  EditSnapshot get _currentSnapshot => EditSnapshot(
    paramValues: _paramValues,
    curves: _currentCurves,
    masks: _currentMasks,
  );

  /// Starts a fresh history for the photo now showing, with its
  /// just-loaded state as the baseline — called whenever [_paramValues]/
  /// [_currentCurves]/[_currentMasks] are replaced wholesale by loading a
  /// photo's saved state (selection change, folder open), rather than by
  /// an edit the user made, so there's nothing to undo back to before it.
  void _resetHistory() => _history.reset(_currentSnapshot);

  /// Records the current state as a new history entry — call after
  /// committing an edit (every `...ChangeEnd`/one-shot-action callsite),
  /// never from a live/dragging callback, so a slider drag collapses into
  /// one undo step instead of one per pixel of mouse movement. See
  /// [EditHistory.push] for the no-op rule.
  void _pushHistory() => _history.push(_currentSnapshot);

  void _applySnapshot(EditSnapshot snapshot) {
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
    if (_history.undo() case final snapshot?) {
      _applySnapshot(snapshot);
    }
  }

  void _redo() {
    if (_history.redo() case final snapshot?) {
      _applySnapshot(snapshot);
    }
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

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex != null ? _files[_selectedIndex!] : null;
    _syncPresetThumbnails();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.backslash): () {
          if (selected != null) {
            _toggleBeforeAfter();
          }
        },
        _cmdShortcut(LogicalKeyboardKey.keyZ): _undo,
        _cmdShortcut(LogicalKeyboardKey.keyZ, shift: true): _redo,
        // Ctrl+Y is a Windows convention for redo; macOS has no equivalent
        // (Cmd+Shift+Z above is the one), but binding it costs nothing and
        // keeps muscle memory working for anyone moving between the two.
        _cmdShortcut(LogicalKeyboardKey.keyY): _redo,
        // Rating and colour label on the selected photo (2026-09-11), on
        // the keys every RAW editor uses: 0-5 stars, 6-9 red/yellow/
        // green/blue. A focused text field takes digits first, as with
        // every other binding here.
        for (var stars = 0; stars <= 5; stars++)
          SingleActivator(_digitKeys[stars]): () => _rateSelected(stars),
        for (var i = 0; i < 4; i++)
          SingleActivator(_digitKeys[6 + i]): () =>
              _labelSelected(photoLabelNames[i]),
        // Filmstrip navigation (2026-09-01, explicit user request) — a
        // focused text field (e.g. the Cloud AI token field) consumes
        // arrow keys itself for cursor movement before they ever reach
        // this CallbackShortcuts, same as every other binding here.
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _selectAdjacentPhoto(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _selectAdjacentPhoto(1),
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
        'detail-restore' => l10n.aiDenoiseEnhanceStageDetailRestore,
        'detail-sharpen' => l10n.aiDenoiseEnhanceStageDetailSharpen,
        'sharpen' => l10n.aiDenoiseEnhanceStageSharpen,
        'colorize' => l10n.aiDenoiseEnhanceStageColorize,
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
    if (_isRunningColorize) {
      return _LoadingInfo(message: l10n.colorizeStartingMessage);
    }
    if (_isDecodingPhoto) {
      final stage = _photoDecodeStage;
      return _LoadingInfo(
        message: switch (stage) {
          null || RawDecodeStage.opening => l10n.photoStageOpening,
          RawDecodeStage.unpacking => l10n.photoStageUnpacking,
          RawDecodeStage.processing => l10n.photoStageProcessing,
          RawDecodeStage.extracting => l10n.photoStageExtracting,
        },
        // Measured, not guessed (2026-09-09, two X-T5 frames at 3072px):
        // opening is under 15ms, unpacking ~4%, the demosaic ~60%, and
        // extracting the rest — which includes the camera-match
        // measurement taken from the same open handle. Scaled to leave
        // headroom, since the downscale, the cache encode and the first
        // render all still come after the last stage reports.
        progress: switch (stage) {
          null => 0.01,
          RawDecodeStage.opening => 0.02,
          RawDecodeStage.unpacking => 0.05,
          RawDecodeStage.processing => 0.10,
          RawDecodeStage.extracting => 0.60,
        },
      );
    }
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
    if (_isApplyingColorize) {
      final stage = _colorizeRenderStage;
      return _LoadingInfo(
        message: _colorizeDisabling
            ? l10n.colorizeDisablingMessage
            : l10n.colorizeApplyingMessage,
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
    // Which stand-in the viewport is showing, decided once: the canvas
    // needs it to know whether to blur, and the spinner beside it needs
    // the same answer. Reading _embeddedPreviews twice in two places is
    // how those two would drift apart.
    final embedded = selected == null ? null : _embeddedPreviews[selected.path];
    final small = selected == null ? null : _thumbnails[selected.path];
    final standIn = embedded ?? small;
    final standInIsSmall = embedded == null && small != null;
    return Scaffold(
      body: Column(
        children: [
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
                                    // Real bug report (2026-09-01): a
                                    // common-image entry stayed clickable
                                    // here even with "RAW files only" on,
                                    // and clicking it didn't open anything.
                                    // Hide it instead of leaving a dead
                                    // click target — same intent "RAW files
                                    // only" already has for folder scans.
                                    recentFiles: _settings.rawOnly
                                        ? _settings.recentFiles
                                              .where(isRawFile)
                                              .toList()
                                        : _settings.recentFiles,
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
                                    includeSubfolders:
                                        _settings.includeSubfolders,
                                    onIncludeSubfoldersChanged:
                                        _setIncludeSubfolders,
                                    onOpenFile: _openFile,
                                    onOpenFolder: _openFolder,
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
                                      thumbnails: _settings.presetThumbnails
                                          ? _presetThumbnails
                                          : null,
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
                                  // The camera's embedded preview once it
                                  // has been read, the 200px filmstrip
                                  // thumbnail until then — the second is
                                  // instant because the strip already had
                                  // it.
                                  thumbnail: standIn,
                                  thumbnailIsSmall: standInIsSmall,
                                  // Uncapped: full quality, by request.
                                  thumbnailDecodeWidth: null,
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
                                      (_wbEyedropperActive ||
                                          _profileHueEyedropperActive) &&
                                      !_beforeAfterMode,
                                  onSampleWhiteBalance: _onEyedropperSample,
                                  maskOverlayVisible:
                                      _maskOverlayVisible &&
                                      !_isAdjustingMaskValue,
                                  maskOverlayOpacity: _maskOverlayOpacity,
                                  aiMaskMaps: _aiMaskMaps,
                                  cropOverlayActive:
                                      !_beforeAfterMode && _cropOverlayActive,
                                  cropTransform: _cropTransform,
                                  cropAspectRatio: _cropAspectRatio,
                                  onCropTransformChanged:
                                      _onCropTransformChanged,
                                  onCropTransformChangeEnd:
                                      _onCropTransformChangeEnd,
                                  straighteningActive: _straighteningActive,
                                  guidedModeActive: _guidedModeActive,
                                  onSecondaryTapUp: _showImageContextMenu,
                                ),
                                // Only over the small stand-in. Once the
                                // camera's own image is up, the photo on
                                // screen is a real photograph at a real
                                // resolution, and a spinner on top of it
                                // says "wait" about something the user can
                                // already look at — the status line
                                // (_overlayInfo) carries the decode's
                                // progress instead.
                                if (_isDecodingPhoto &&
                                    selected != null &&
                                    standInIsSmall)
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
                            actions: _panelActions,
                            histogram: selected == null
                                ? null
                                : _histograms[selected.path],
                            metadata: selected == null
                                ? null
                                : _metadata[selected.path],
                            colorProfileMode: colorProfileModeOf(_paramValues),
                            colorProfileChoice: _colorProfileChoice,
                            userColorProfiles: _userColorProfiles,
                            customProfileMissing: _customProfileMissing,
                            levelBusy: _levelBusy,
                            uprightBusy: _uprightBusy,
                            tabbedLayout: _settings.tabbedControlsPanel,
                            tabIcons: _settings.tabbedControlsPanelIcons,
                            selectedProfileIsUsers:
                                _selectedUserColorProfile != null,
                            wbEyedropperActive: _wbEyedropperActive,
                            onExport: selected == null ? null : _exportCurrent,
                            exporting: _exporting,
                            enabled: selected != null,
                            curves: _activeCurves,
                            masks: _currentMasks,
                            activeMaskId: _activeMaskId,
                            maskOverlayVisible: _maskOverlayVisible,
                            maskOverlayOpacity: _maskOverlayOpacity,
                            brushRadius: _brushRadius,
                            brushHardness: _brushHardness,
                            brushErase: _brushErase,
                            brushFlow: _brushFlow,
                            aiMasksResolving: _aiMasksResolving,
                            aiMaskFailures: _aiMaskFailures,
                            cropOverlayActive: _cropOverlayActive,
                            cropTransform: _cropTransform,
                            cropAspectRatio: _cropAspectRatio,
                            guidedModeActive: _guidedModeActive,
                            lensCorrection: _lensCorrection,
                            lensProfiles: _lensProfiles,
                            resolvedLensProfile: selected == null
                                ? null
                                : _resolvedLensProfileFor(selected.path),
                          ),
                        ],
                      ),
                    ),
                    _ViewerToolbar(
                      onOpenSettings: _openSettings,
                      onOpenAbout: _openAbout,
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
                      canUndo: _history.canUndo,
                      canRedo: _history.canRedo,
                      onUndo: _undo,
                      onRedo: _redo,
                      aiDenoiseActive:
                          AiDenoiseParams.fromValues(_paramValues).level !=
                              null ||
                          (_paramValues[_neuralDenoiseKey] ?? 0.0) > 0 ||
                          (_paramValues[_neuralUpscaleKey] ?? 0.0) > 0 ||
                          (_paramValues[_neuralRawDenoiseKey] ?? 0.0) > 0 ||
                          (_paramValues[_restoreDetailKey] ?? 0.0) > 0 ||
                          (_paramValues[_cloudDenoiseProviderKey] ?? 0.0) > 0,
                      onOpenAiDenoise: selected == null
                          ? null
                          : _openAiDenoiseDialog,
                      colorizeActive: (_paramValues[_colorizeKey] ?? 0.0) > 0,
                      onOpenColorize: selected == null
                          ? null
                          : _openColorizeDialog,
                      cropOverlayActive: _cropOverlayActive,
                      onToggleCropOverlay: selected == null
                          ? null
                          : _toggleCropOverlay,
                      onExport: selected == null ? null : _exportCurrent,
                      exporting: _exporting,
                      onReset: _resetActive,
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
                      metaOf: (path) => _store.meta[path],
                      onSetRating: _setRating,
                      onSetLabel: _setLabel,
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
