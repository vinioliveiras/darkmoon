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
    this.thumbnailConcurrency = 4,
    this.alwaysFullQuality = false,
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

  /// How many thumbnails to decode concurrently when a folder is opened.
  final int thumbnailConcurrency;

  /// When true, every photo opens in the full-native-resolution view by
  /// default instead of the downscaled editing preview (still overridable
  /// per-session via the viewer's Full Quality toggle).
  final bool alwaysFullQuality;

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
    int? thumbnailConcurrency,
    bool? alwaysFullQuality,
    List<String>? libraryFolders,
    List<String>? recentFiles,
    String? lastActiveFolder,
  }) => AppSettings(
    language: language ?? this.language,
    fastPreview: fastPreview ?? this.fastPreview,
    thumbnailConcurrency: thumbnailConcurrency ?? this.thumbnailConcurrency,
    alwaysFullQuality: alwaysFullQuality ?? this.alwaysFullQuality,
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
      thumbnailConcurrency:
          (raw['thumbnailConcurrency'] as num?)?.toInt() ?? defaultConcurrency,
      alwaysFullQuality:
          raw['alwaysFullQuality'] as bool? ?? defaults.alwaysFullQuality,
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
      'thumbnailConcurrency': settings.thumbnailConcurrency,
      'alwaysFullQuality': settings.alwaysFullQuality,
      'libraryFolders': settings.libraryFolders,
      'recentFiles': settings.recentFiles,
      'lastActiveFolder': settings.lastActiveFolder,
    }),
  );
  await tmp.rename(file.path);
}
