import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../native/edit_source.dart' show defaultPreviewMaxDimension;
import '../render/calibration.dart' show calBaseContrast;

/// Leave at least two cores for the UI isolate and the preview-cache
/// prewarm that runs alongside this batch when a folder opens — pinning
/// every core to thumbnail decode is what made opening a big folder freeze
/// the app. Capped at 5 even on many-core machines: thumbnail decode is
/// bottlenecked on the same LibRaw/JPEG-decode work per photo regardless
/// of core count, so more isolates past that just add scheduling overhead
/// without much extra throughput. Users who want it faster can still raise
/// the value in Settings.
int _defaultThumbnailConcurrency() =>
    (Platform.numberOfProcessors - 2).clamp(2, 4);

/// Recent single-file opens are capped so the sidebar list doesn't grow
/// unbounded over months of use.
const _maxRecentFiles = 15;

/// The discrete preview-resolution choices offered in Settings — a
/// long-edge pixel cap for the downscaled buffer the editor decodes and
/// renders against while editing (see `edit_source.dart`'s
/// `EditSourcePair.preview` and `defaultPreviewMaxDimension`). Export
/// always decodes at the sensor's native resolution regardless of this
/// setting, so this only trades editing-preview sharpness for decode/
/// render speed, never final output quality.
const List<int> previewResolutionOptions = [512, 768, 1024, 1280, 1600, 2048];

/// App-wide settings, mirroring the Python app's `DEFAULT_SETTINGS` (minus
/// the thumbnail disk cache setting, since this port's cache doesn't have
/// a size/eviction knob yet to expose).
class AppSettings {
  const AppSettings({
    this.language = 'auto',
    this.fastPreview = true,
    this.previewResolution = defaultPreviewMaxDimension,
    this.useGpuRender = true,
    this.dynamicFullPreview = false,
    this.fullQualityPercent = 30,
    this.baseContrast = calBaseContrast,
    this.thumbnailConcurrency = 4,
    this.rawOnly = false,
    this.devLogging = false,
    this.libraryFolders = const [],
    this.recentFiles = const [],
    this.lastActiveFolder,
    this.lastActiveFile,
  });

  /// 'auto' (follow the system language), 'en', or 'pt'.
  final String language;

  /// While true, actively dragging a slider re-renders against the smaller
  /// "live" resolution for speed; while false, every render uses full
  /// preview quality (slower to update while dragging).
  final bool fastPreview;

  /// The long-edge pixel cap the editor decodes/renders against while
  /// editing (see `edit_source.dart`'s `EditSourcePair.preview`) — one of
  /// [previewResolutionOptions]. Lower is faster to decode and re-render on
  /// every adjustment but softer on screen; export always uses the
  /// sensor's native resolution regardless of this setting.
  final int previewResolution;

  /// GPU-accelerated rendering (`lib/render/gpu/`) for the settled
  /// (non-drag) preview render, instead of the CPU pipeline — on by
  /// default now that the editing preview itself is downscaled (see
  /// [previewResolution]), which keeps each shader pass cheap. Only
  /// takes effect when
  /// `isGpuRenderAvailable()`'s capability probe passes;
  /// editor_screen.dart falls back to CPU silently otherwise (including
  /// for the whole live-drag path, deliberately kept off GPU — see
  /// `_renderPreviewNow`'s doc comment for the "Not Responding" freeze
  /// this avoids).
  final bool useGpuRender;

  /// When true, a beat after an edit settles the editor decodes the
  /// photo's *native*-resolution source once and, from then on, runs
  /// every settled render for that photo against it (downscaled to
  /// [fullQualityPercent] of native) instead of the small
  /// [previewResolution] buffer — so the on-screen image is near-full
  /// quality while editing. Live drags still use the tiny buffer. The
  /// decoded source is cached to disk so re-opening the photo skips the
  /// slow RAW demosaic. Off by default (it's meaningful extra work per
  /// settle).
  final bool dynamicFullPreview;

  /// Percent of the sensor's native resolution the full-quality editing
  /// preview ([dynamicFullPreview]) renders at — 30 by default, 100 for a
  /// true full-resolution render on every settle. Clamped to [25, 100].
  final int fullQualityPercent;

  /// Strength of the fixed "profile" contrast curve every photo gets before
  /// the tone sliders — darkmoon's stand-in for the S-curve the Adobe Color
  /// profile bakes into Lightroom's zero-edit render (see
  /// `render/calibration.dart`'s `calBaseContrast`, the factory value this
  /// defaults to). Same 0..100 scale as the Contrast slider; 0 disables it.
  /// Threaded into every render as `RenderParams.baseContrast`. Clamped to
  /// [0, 60].
  final double baseContrast;

  /// How many thumbnails to decode concurrently when a folder is opened.
  final int thumbnailConcurrency;

  /// When true, folders only show RAW files — common image formats (JPEG,
  /// PNG, etc.) are filtered out of the library entirely.
  final bool rawOnly;

  /// "Developer Mode" — when true, `DevLog` writes a timestamped diagnostic
  /// log (crashes, AI Enhance stage/GPU-CPU info, etc. — see
  /// `diagnostics/dev_log.dart`) to disk for bug reports. Off by default,
  /// so normal use never writes anything.
  final bool devLogging;

  /// Folders added to the sidebar's folder tree via File > Add Folder,
  /// persisted so they're still there next launch. Order is insertion
  /// order (most-recently-added last).
  final List<String> libraryFolders;

  /// Individual files opened via File > Open File, most-recently-opened
  /// first — a separate, flat list from [libraryFolders] since opening one
  /// file shouldn't pull its whole containing folder into the library.
  final List<String> recentFiles;

  /// The last folder shown in the main view, restored automatically on
  /// the next launch so the app reopens where you left off.
  final String? lastActiveFolder;

  /// The last-selected photo within [lastActiveFolder], restored as the
  /// initial selection (via `_loadFolder`'s `selectPath`) instead of
  /// always defaulting to index 0 — so the app reopens on the exact photo
  /// you were editing, not just the right folder.
  final String? lastActiveFile;

  AppSettings copyWith({
    String? language,
    bool? fastPreview,
    int? previewResolution,
    bool? useGpuRender,
    bool? dynamicFullPreview,
    int? fullQualityPercent,
    double? baseContrast,
    int? thumbnailConcurrency,
    bool? rawOnly,
    bool? devLogging,
    List<String>? libraryFolders,
    List<String>? recentFiles,
    String? lastActiveFolder,
    String? lastActiveFile,
  }) => AppSettings(
    language: language ?? this.language,
    fastPreview: fastPreview ?? this.fastPreview,
    previewResolution: previewResolution ?? this.previewResolution,
    useGpuRender: useGpuRender ?? this.useGpuRender,
    dynamicFullPreview: dynamicFullPreview ?? this.dynamicFullPreview,
    fullQualityPercent: (fullQualityPercent ?? this.fullQualityPercent).clamp(
      25,
      100,
    ),
    baseContrast: (baseContrast ?? this.baseContrast).clamp(0.0, 60.0),
    thumbnailConcurrency: thumbnailConcurrency ?? this.thumbnailConcurrency,
    rawOnly: rawOnly ?? this.rawOnly,
    devLogging: devLogging ?? this.devLogging,
    libraryFolders: libraryFolders ?? this.libraryFolders,
    recentFiles: recentFiles ?? this.recentFiles,
    lastActiveFolder: lastActiveFolder ?? this.lastActiveFolder,
    lastActiveFile: lastActiveFile ?? this.lastActiveFile,
  );

  /// [path] moved (or added) to the front of [recentFiles], deduplicated
  /// and capped at [_maxRecentFiles].
  AppSettings withRecentFile(String path) {
    final next = [path, ...recentFiles.where((f) => f != path)];
    return copyWith(
      recentFiles: next.length > _maxRecentFiles
          ? next.sublist(0, _maxRecentFiles)
          : next,
    );
  }
}

Future<File> _settingsFile() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return File(p.join(dir.path, 'flutter_settings.json'));
}

Future<AppSettings> loadSettings() async {
  final defaultConcurrency = _defaultThumbnailConcurrency();
  try {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return AppSettings(thumbnailConcurrency: defaultConcurrency);
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    const defaults = AppSettings();
    return AppSettings(
      language: raw['language'] as String? ?? defaults.language,
      fastPreview: raw['fastPreview'] as bool? ?? defaults.fastPreview,
      previewResolution:
          (raw['previewResolution'] as num?)?.toInt() ??
          defaults.previewResolution,
      useGpuRender: raw['useGpuRender'] as bool? ?? defaults.useGpuRender,
      dynamicFullPreview:
          raw['dynamicFullPreview'] as bool? ?? defaults.dynamicFullPreview,
      fullQualityPercent:
          ((raw['fullQualityPercent'] as num?)?.toInt() ??
                  defaults.fullQualityPercent)
              .clamp(25, 100),
      baseContrast:
          ((raw['baseContrast'] as num?)?.toDouble() ?? defaults.baseContrast)
              .clamp(0.0, 60.0),
      thumbnailConcurrency:
          (raw['thumbnailConcurrency'] as num?)?.toInt() ?? defaultConcurrency,
      rawOnly: raw['rawOnly'] as bool? ?? defaults.rawOnly,
      devLogging: raw['devLogging'] as bool? ?? defaults.devLogging,
      libraryFolders:
          (raw['libraryFolders'] as List?)?.cast<String>() ??
          defaults.libraryFolders,
      recentFiles:
          (raw['recentFiles'] as List?)?.cast<String>() ?? defaults.recentFiles,
      lastActiveFolder:
          raw['lastActiveFolder'] as String? ?? defaults.lastActiveFolder,
      lastActiveFile:
          raw['lastActiveFile'] as String? ?? defaults.lastActiveFile,
    );
  } catch (_) {
    return AppSettings(thumbnailConcurrency: defaultConcurrency);
  }
}

Future<void> saveSettings(AppSettings settings) async {
  final file = await _settingsFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(
    jsonEncode({
      'language': settings.language,
      'fastPreview': settings.fastPreview,
      'previewResolution': settings.previewResolution,
      'useGpuRender': settings.useGpuRender,
      'dynamicFullPreview': settings.dynamicFullPreview,
      'fullQualityPercent': settings.fullQualityPercent,
      'baseContrast': settings.baseContrast,
      'thumbnailConcurrency': settings.thumbnailConcurrency,
      'rawOnly': settings.rawOnly,
      'devLogging': settings.devLogging,
      'libraryFolders': settings.libraryFolders,
      'recentFiles': settings.recentFiles,
      'lastActiveFolder': settings.lastActiveFolder,
      'lastActiveFile': settings.lastActiveFile,
    }),
  );
  await tmp.rename(file.path);
}
