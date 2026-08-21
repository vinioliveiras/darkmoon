import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cap concurrency at 8 even on many-core machines — thumbnail decode is
/// bottlenecked on the same LibRaw/JPEG-decode work per photo regardless
/// of core count, and spawning too many isolates at once just adds
/// scheduling overhead without much extra throughput.
int _defaultThumbnailConcurrency() => Platform.numberOfProcessors.clamp(2, 8);

/// Recent single-file opens are capped so the sidebar list doesn't grow
/// unbounded over months of use.
const _maxRecentFiles = 15;

/// App-wide settings, mirroring the Python app's `DEFAULT_SETTINGS` (minus
/// the thumbnail disk cache setting, since this port's cache doesn't have
/// a size/eviction knob yet to expose).
class AppSettings {
  const AppSettings({
    this.language = 'auto',
    this.fastPreview = true,
    this.useGpuRender = false,
    this.thumbnailConcurrency = 4,
    this.rawOnly = false,
    this.libraryFolders = const [],
    this.recentFiles = const [],
    this.lastActiveFolder,
  });

  /// 'auto' (follow the system language), 'en', or 'pt'.
  final String language;

  /// While true, actively dragging a slider re-renders against the smaller
  /// "live" resolution for speed; while false, every render uses full
  /// preview quality (slower to update while dragging).
  final bool fastPreview;

  /// Opt-in GPU-accelerated rendering (`lib/render/gpu/`) instead of the
  /// CPU pipeline — off by default (see project_gpu_render_plan.md's
  /// "What Happens to the CPU Path": GPU rendering is still new,
  /// unverified on the wide range of real Windows GPU/driver
  /// combinations the CPU path already handles reliably). Only takes
  /// effect when `isGpuRenderAvailable()`'s capability probe passes and
  /// the photo has no mask layers (masks aren't GPU-ported yet) —
  /// editor_screen.dart falls back to CPU silently otherwise.
  final bool useGpuRender;

  /// How many thumbnails to decode concurrently when a folder is opened.
  final int thumbnailConcurrency;

  /// When true, folders only show RAW files — common image formats (JPEG,
  /// PNG, etc.) are filtered out of the library entirely.
  final bool rawOnly;

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

  AppSettings copyWith({
    String? language,
    bool? fastPreview,
    bool? useGpuRender,
    int? thumbnailConcurrency,
    bool? rawOnly,
    List<String>? libraryFolders,
    List<String>? recentFiles,
    String? lastActiveFolder,
  }) => AppSettings(
    language: language ?? this.language,
    fastPreview: fastPreview ?? this.fastPreview,
    useGpuRender: useGpuRender ?? this.useGpuRender,
    thumbnailConcurrency: thumbnailConcurrency ?? this.thumbnailConcurrency,
    rawOnly: rawOnly ?? this.rawOnly,
    libraryFolders: libraryFolders ?? this.libraryFolders,
    recentFiles: recentFiles ?? this.recentFiles,
    lastActiveFolder: lastActiveFolder ?? this.lastActiveFolder,
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
      useGpuRender: raw['useGpuRender'] as bool? ?? defaults.useGpuRender,
      thumbnailConcurrency:
          (raw['thumbnailConcurrency'] as num?)?.toInt() ?? defaultConcurrency,
      rawOnly: raw['rawOnly'] as bool? ?? defaults.rawOnly,
      libraryFolders:
          (raw['libraryFolders'] as List?)?.cast<String>() ??
          defaults.libraryFolders,
      recentFiles:
          (raw['recentFiles'] as List?)?.cast<String>() ?? defaults.recentFiles,
      lastActiveFolder:
          raw['lastActiveFolder'] as String? ?? defaults.lastActiveFolder,
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
      'useGpuRender': settings.useGpuRender,
      'thumbnailConcurrency': settings.thumbnailConcurrency,
      'rawOnly': settings.rawOnly,
      'libraryFolders': settings.libraryFolders,
      'recentFiles': settings.recentFiles,
      'lastActiveFolder': settings.lastActiveFolder,
    }),
  );
  await tmp.rename(file.path);
}
