import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../catalog/legacy_filename_migration.dart';
import '../diagnostics/dev_log.dart';

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
const List<int> previewResolutionOptions = [
  nativePreviewResolution,
  6144,
  4096,
  3072,
  2560,
  2048,
  1600,
  1280,
  1024,
  768,
  512,
];

/// The ceiling choices offered for the rebuildable disk caches, in bytes.
///
/// Previews and full-resolution sources only — see [CacheCategory]. Zero
/// means no ceiling, which is what the app did until 2026-09-09, when the
/// author's own install had reached 1.8 GB with nothing to stop it.
const List<int> cacheMaxBytesOptions = [
  1 * 1024 * 1024 * 1024,
  2 * 1024 * 1024 * 1024,
  5 * 1024 * 1024 * 1024,
  10 * 1024 * 1024 * 1024,
  20 * 1024 * 1024 * 1024,
  unlimitedCacheBytes,
];

/// The [AppSettings.cacheMaxBytes] value meaning "never evict".
///
/// Zero rather than a very large number, for the same reason
/// [nativePreviewResolution] is: every consumer has to branch on it, and a
/// merely-enormous cap would silently become a real one on a big library.
const int unlimitedCacheBytes = 0;

/// What [AppSettings.cacheMaxBytes] starts at.
///
/// Five gigabytes holds a few thousand previews or a few hundred
/// full-resolution sources — enough that ordinary browsing never evicts,
/// small enough that a forgotten install does not quietly fill a disk.
const int defaultCacheMaxBytes = 5 * 1024 * 1024 * 1024;

/// What [AppSettings.previewResolution] starts at.
///
/// Not [nativePreviewResolution]: a modern sensor's own resolution is a
/// lot of pixels to re-render on every slider move, and a few thousand on
/// the long edge is already past what the viewport can show. Native stays
/// one dropdown entry away for anyone who wants it.
const int defaultPreviewResolution = 3072;

/// The [AppSettings.previewResolution] value meaning "do not downscale at
/// all" — edit against the sensor's own resolution.
///
/// Zero rather than a large number, so it cannot be mistaken for a cap
/// that merely happens to be above every sensor. Every consumer has to
/// branch on it; [fitToMaxDimension] would read it as "shrink to nothing".
const int nativePreviewResolution = 0;

/// App-wide settings, mirroring the Python app's `DEFAULT_SETTINGS` (minus
/// the thumbnail disk cache setting, since this port's cache doesn't have
/// a size/eviction knob yet to expose).
class AppSettings {
  const AppSettings({
    this.language = 'auto',
    this.fastPreview = true,
    this.previewResolution = defaultPreviewResolution,
    this.editEmbeddedJpeg = false,
    this.cacheMaxBytes = defaultCacheMaxBytes,
    this.useGpuRender = true,
    this.tabbedControlsPanel = true,
    this.tabbedControlsPanelIcons = false,
    this.presetThumbnails = true,
    this.thumbnailConcurrency = 4,
    this.rawOnly = false,
    this.includeSubfolders = false,
    this.devLogging = false,
    this.libraryFolders = const [],
    this.recentFiles = const [],
    this.lastActiveFolder,
    this.lastActiveFile,
    this.customDenoiseModelPath,
    this.animationsEnabled = true,
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

  /// Edit a RAW as the camera's own JPEG rendering of the same shot,
  /// rather than as sensor data.
  ///
  /// The camera already made every decision a RAW leaves open — white
  /// balance, tone, colour, sharpening, noise reduction — and wrote the
  /// result into the file. Turning this on takes that image as the
  /// photograph and edits it the way any JPEG on disk would be edited:
  /// faster to open, and it starts from the look the camera intended
  /// rather than from a neutral decode. It gives up the latitude that
  /// makes a RAW a RAW — an 8-bit rendered image has far less to recover
  /// in a blown sky or a crushed shadow.
  ///
  /// [previewResolution] still applies: what that cap buys is a cheaper
  /// render on every slider move, which has nothing to do with where the
  /// pixels came from.
  ///
  /// Applies to the export and the neural pipelines too, not just the
  /// editing preview — see [decodeSourceImage].
  final bool editEmbeddedJpeg;

  /// Ceiling on the rebuildable disk caches, in bytes;
  /// [unlimitedCacheBytes] to never evict.
  ///
  /// Governs previews and full-resolution sources — everything that is a
  /// decode away from being rebuilt. AI results are excluded on purpose:
  /// they cost minutes of inference, not seconds of decoding, and
  /// reclaiming disk by throwing those away is not a trade to make on the
  /// user's behalf. See `enforceCacheLimit`.
  final int cacheMaxBytes;

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

  /// Whether the editing panel groups its sections into Adjust / Colour /
  /// Effects tabs, with Masks pinned above them, instead of listing all
  /// eleven sections in one scroll.
  ///
  /// Defaults on: it is the layout the panel was redesigned around, and
  /// the single list put Lens Correction a dozen section-heights below the
  /// Tone sliders. Off restores the flat list for anyone who would rather
  /// scroll than switch.
  final bool tabbedControlsPanel;

  /// Whether those tabs are marked with a glyph instead of a word.
  ///
  /// Defaults off: a word says which section it opens outright, where a
  /// glyph has to be learned first. Kept as a choice because the icons
  /// are the more compact of the two and some people prefer them once
  /// they know them. Means nothing while [tabbedControlsPanel] is off,
  /// and the Settings dialog hides it there.
  final bool tabbedControlsPanelIcons;

  /// Whether each preset in the list shows the current photo rendered
  /// through it.
  ///
  /// Defaults on: seeing what a preset does beats reading its name. Kept
  /// as a choice because it is not free — one render per visible preset,
  /// and a large library on a slow machine is exactly the case where
  /// turning it off is the right answer.
  final bool presetThumbnails;



  /// How many thumbnails to decode concurrently when a folder is opened.
  final int thumbnailConcurrency;

  /// When true, folders only show RAW files — common image formats (JPEG,
  /// PNG, etc.) are filtered out of the library entirely.
  final bool rawOnly;

  /// When true, a library folder's scan also descends into every nested
  /// subfolder instead of only its top level. Off by default — a
  /// subfolder is often an unrelated export/album a user wouldn't expect
  /// mixed into the top-level view.
  final bool includeSubfolders;

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

  /// An absolute path to a user-supplied `.onnx` file to use for the AI
  /// Enhance dialog's on-device Denoise pass, in place of the bundled
  /// default model — null (the default) means use the bundled
  /// model. Treated strictly as a drop-in replacement: the file must
  /// already follow the bundled model's own conventions (3-channel RGB,
  /// same-resolution in/out, "input"/"output" tensor names, [0,1]-
  /// normalized) — see `onnx_runtime.dart`'s `OnnxModelSpec.customPath`
  /// doc for why this app can't safely auto-detect a different
  /// convention (pixel normalization range in particular isn't
  /// recoverable from the ONNX graph itself). A model that doesn't match
  /// fails loudly (a real load/inference error surfaces to the user) —
  /// see `edit_source_ai_enhance.dart`'s fallback-to-default handling.
  final String? customDenoiseModelPath;

  /// Whether interface animations (section-card hover, segmented-tab
  /// selection slide, zoom transitions, the preview's fade-in after a
  /// committed edit) play at all. On by default; a plain instant
  /// snap when off, for users who find motion distracting or are on a
  /// slower machine where it reads as lag instead of polish.
  final bool animationsEnabled;

  AppSettings copyWith({
    String? language,
    bool? fastPreview,
    int? previewResolution,
    bool? editEmbeddedJpeg,
    int? cacheMaxBytes,
    bool? useGpuRender,
    bool? tabbedControlsPanel,
    bool? tabbedControlsPanelIcons,
    bool? presetThumbnails,
    int? thumbnailConcurrency,
    bool? rawOnly,
    bool? includeSubfolders,
    bool? devLogging,
    List<String>? libraryFolders,
    List<String>? recentFiles,
    String? lastActiveFolder,
    String? lastActiveFile,
    String? customDenoiseModelPath,
    bool? animationsEnabled,
  }) => AppSettings(
    language: language ?? this.language,
    fastPreview: fastPreview ?? this.fastPreview,
    previewResolution: previewResolution ?? this.previewResolution,
    editEmbeddedJpeg: editEmbeddedJpeg ?? this.editEmbeddedJpeg,
    cacheMaxBytes: cacheMaxBytes ?? this.cacheMaxBytes,
    useGpuRender: useGpuRender ?? this.useGpuRender,
    tabbedControlsPanel: tabbedControlsPanel ?? this.tabbedControlsPanel,
    tabbedControlsPanelIcons:
        tabbedControlsPanelIcons ?? this.tabbedControlsPanelIcons,
    presetThumbnails: presetThumbnails ?? this.presetThumbnails,
    thumbnailConcurrency: thumbnailConcurrency ?? this.thumbnailConcurrency,
    rawOnly: rawOnly ?? this.rawOnly,
    includeSubfolders: includeSubfolders ?? this.includeSubfolders,
    devLogging: devLogging ?? this.devLogging,
    libraryFolders: libraryFolders ?? this.libraryFolders,
    recentFiles: recentFiles ?? this.recentFiles,
    lastActiveFolder: lastActiveFolder ?? this.lastActiveFolder,
    lastActiveFile: lastActiveFile ?? this.lastActiveFile,
    customDenoiseModelPath:
        customDenoiseModelPath ?? this.customDenoiseModelPath,
    animationsEnabled: animationsEnabled ?? this.animationsEnabled,
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

  /// Resets [customDenoiseModelPath] back to null (use the bundled
  /// model) — a dedicated method rather than `copyWith(customDenoiseModelPath:
  /// null)` since `copyWith`'s `??` pattern can't distinguish "clear this"
  /// from "leave it alone" (same limitation every other nullable field
  /// here already has).
  AppSettings withDefaultDenoiseModel() => AppSettings(
    language: language,
    fastPreview: fastPreview,
    previewResolution: previewResolution,
    editEmbeddedJpeg: editEmbeddedJpeg,
    cacheMaxBytes: cacheMaxBytes,
    useGpuRender: useGpuRender,
    tabbedControlsPanel: tabbedControlsPanel,
    tabbedControlsPanelIcons: tabbedControlsPanelIcons,
    presetThumbnails: presetThumbnails,
    thumbnailConcurrency: thumbnailConcurrency,
    rawOnly: rawOnly,
    includeSubfolders: includeSubfolders,
    devLogging: devLogging,
    libraryFolders: libraryFolders,
    recentFiles: recentFiles,
    lastActiveFolder: lastActiveFolder,
    lastActiveFile: lastActiveFile,
    customDenoiseModelPath: null,
    animationsEnabled: animationsEnabled,
  );

  /// [lastActiveFolder] cleared (same `copyWith`-can't-null limitation as
  /// [withDefaultDenoiseModel]) — real bug fix (2026-09-01): opening a
  /// single file (via File > Open File or Recent Files) left whatever
  /// folder was last active still recorded here, so on the next launch
  /// `_loadSettings` restored that stale folder instead of the single
  /// file the user was actually editing (or, if no folder had ever been
  /// opened, restored nothing at all — `_loadSettings` only ever calls
  /// `_loadFolder`). Called from `_loadSingleFile` alongside
  /// `_saveLastActiveFile`, mirroring how `_loadFolder` records its own
  /// [lastActiveFolder].
  AppSettings asSingleFileSession(String path) => AppSettings(
    language: language,
    fastPreview: fastPreview,
    previewResolution: previewResolution,
    editEmbeddedJpeg: editEmbeddedJpeg,
    cacheMaxBytes: cacheMaxBytes,
    useGpuRender: useGpuRender,
    tabbedControlsPanel: tabbedControlsPanel,
    tabbedControlsPanelIcons: tabbedControlsPanelIcons,
    presetThumbnails: presetThumbnails,
    thumbnailConcurrency: thumbnailConcurrency,
    rawOnly: rawOnly,
    includeSubfolders: includeSubfolders,
    devLogging: devLogging,
    libraryFolders: libraryFolders,
    recentFiles: recentFiles,
    lastActiveFolder: null,
    lastActiveFile: path,
    customDenoiseModelPath: customDenoiseModelPath,
    animationsEnabled: animationsEnabled,
  );
}

Future<File> _settingsFile() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  await migrateLegacyFilename(
    dir,
    'flutter_settings.json',
    'darkmoon_settings.json',
  );
  return File(p.join(dir.path, 'darkmoon_settings.json'));
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
      editEmbeddedJpeg:
          raw['editEmbeddedJpeg'] as bool? ?? defaults.editEmbeddedJpeg,
      cacheMaxBytes:
          (raw['cacheMaxBytes'] as num?)?.toInt() ?? defaults.cacheMaxBytes,
      useGpuRender: raw['useGpuRender'] as bool? ?? defaults.useGpuRender,
      tabbedControlsPanel:
          raw['tabbedControlsPanel'] as bool? ?? defaults.tabbedControlsPanel,
      tabbedControlsPanelIcons:
          raw['tabbedControlsPanelIcons'] as bool? ??
          defaults.tabbedControlsPanelIcons,
      presetThumbnails:
          raw['presetThumbnails'] as bool? ?? defaults.presetThumbnails,
      thumbnailConcurrency:
          (raw['thumbnailConcurrency'] as num?)?.toInt() ?? defaultConcurrency,
      rawOnly: raw['rawOnly'] as bool? ?? defaults.rawOnly,
      includeSubfolders:
          raw['includeSubfolders'] as bool? ?? defaults.includeSubfolders,
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
      customDenoiseModelPath:
          raw['customDenoiseModelPath'] as String? ??
          defaults.customDenoiseModelPath,
      animationsEnabled:
          raw['animationsEnabled'] as bool? ?? defaults.animationsEnabled,
    );
  } catch (e, st) {
    // Every setting the user has ever changed silently reverts to its
    // default here, which reads as "the app forgot my settings" with
    // nothing to go on.
    DevLog.logError('loadSettings failed, falling back to defaults', e, st);
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
      'editEmbeddedJpeg': settings.editEmbeddedJpeg,
      'cacheMaxBytes': settings.cacheMaxBytes,
      'useGpuRender': settings.useGpuRender,
      'tabbedControlsPanel': settings.tabbedControlsPanel,
      'tabbedControlsPanelIcons': settings.tabbedControlsPanelIcons,
      'presetThumbnails': settings.presetThumbnails,
      'thumbnailConcurrency': settings.thumbnailConcurrency,
      'rawOnly': settings.rawOnly,
      'includeSubfolders': settings.includeSubfolders,
      'devLogging': settings.devLogging,
      'libraryFolders': settings.libraryFolders,
      'recentFiles': settings.recentFiles,
      'lastActiveFolder': settings.lastActiveFolder,
      'lastActiveFile': settings.lastActiveFile,
      'customDenoiseModelPath': settings.customDenoiseModelPath,
      'animationsEnabled': settings.animationsEnabled,
    }),
  );
  await tmp.rename(file.path);
}
