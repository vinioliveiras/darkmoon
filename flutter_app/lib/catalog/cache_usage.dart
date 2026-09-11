import 'dart:io';

import 'package:path/path.dart' as p;

/// What darkmoon keeps on disk that can be thrown away and rebuilt.
///
/// Deliberately only the derived data. Presets, the edit catalog, curves
/// and masks live under the same `Documents/darkmoon` root and are *not*
/// here: they are the user's work, they are small, and putting them in a
/// meter next to a limit would invite treating them as reclaimable.
enum CacheCategory {
  /// Rendered editing previews, one per photo per resolution, plus the
  /// camera-match measurements that go with them.
  previews,

  /// Full-resolution decoded sources — a handful of megabytes each, and
  /// the reason a limit is needed at all.
  fullSources,

  /// The filmstrip's own small JPEGs. Included for completeness; they have
  /// never been the problem.
  thumbnails,

  /// Neural results: AI Enhance, AI masks, Colorize.
  ///
  /// Cheap to *store* and expensive to rebuild — minutes of inference, not
  /// seconds of decoding — so eviction leaves these alone even when the
  /// limit is exceeded. They are shown because they take real space and
  /// the user may want to clear them deliberately.
  aiResults,
}

/// How many bytes each [CacheCategory] currently occupies.
class CacheUsage {
  const CacheUsage(this.bytes);

  static const empty = CacheUsage({});

  final Map<CacheCategory, int> bytes;

  int operator [](CacheCategory category) => bytes[category] ?? 0;

  int get total => bytes.values.fold(0, (a, b) => a + b);

  /// The part a limit actually governs — see [enforceCacheLimit].
  int get evictable =>
      this[CacheCategory.previews] + this[CacheCategory.fullSources];
}

/// Every directory under [documentsDir] that belongs to a category, with
/// the category it belongs to.
///
/// `previews/` splits in two: a `native` directory anywhere inside it
/// holds full-resolution sources, everything else holds previews. That
/// split is by directory name rather than by file, because it is how the
/// cache is laid out — see `resolveNativeSourceCacheDir`.
Map<String, CacheCategory> _rootsIn(String documentsDir) {
  final base = p.join(documentsDir, 'darkmoon');
  return {
    p.join(base, 'previews'): CacheCategory.previews,
    p.join(base, 'camera_match'): CacheCategory.previews,
    p.join(base, 'thumbnails-320'): CacheCategory.thumbnails,
    p.join(base, 'ai_enhance_cache'): CacheCategory.aiResults,
    p.join(base, 'ai_mask_cache'): CacheCategory.aiResults,
    p.join(base, 'colorize_cache'): CacheCategory.aiResults,
  };
}

/// True when [path] sits inside a directory named `native` — the
/// full-resolution sources, which live under `previews/` but are their own
/// category.
bool _isFullSource(String path) => p.split(path).contains('native');

/// Adds up what each cache category occupies under [documentsDir].
///
/// Walks the directory tree, so it is real file I/O and belongs on a
/// background isolate — designed to run via `compute()`. A missing
/// directory counts as zero rather than failing: a fresh install has none
/// of them, and that is a legitimate answer, not an error.
CacheUsage measureCacheUsage(String documentsDir) {
  final bytes = <CacheCategory, int>{};
  _rootsIn(documentsDir).forEach((root, category) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      return;
    }
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final into =
            category == CacheCategory.previews && _isFullSource(entity.path)
            ? CacheCategory.fullSources
            : category;
        try {
          bytes[into] = (bytes[into] ?? 0) + entity.lengthSync();
        } catch (_) {
          // A file deleted between listing and measuring. Skip it.
        }
      }
    } on FileSystemException {
      // A directory that vanished, or one we cannot read. Everything
      // measured so far still counts.
    }
  });
  return CacheUsage(bytes);
}

/// Arguments for [enforceCacheLimit], which runs via `compute()`.
class CacheLimitRequest {
  const CacheLimitRequest(this.documentsDir, this.maxBytes);

  final String documentsDir;
  final int maxBytes;
}

/// Deletes cache files, oldest first, until [CacheUsage.evictable] fits
/// inside [CacheLimitRequest.maxBytes]. Returns how many bytes went.
///
/// **Oldest-modified first, across every namespace at once**, which is
/// what makes this also the cleanup for namespaces nobody uses any more.
/// Changing Settings > Preview Resolution starts a fresh directory and
/// abandons the old one; nothing ever touches it again, so its files are
/// the oldest in the tree and are the first to go. The 1.8 GB found on the
/// author's own machine (2026-09-09) was mostly two abandoned resolutions.
///
/// Whole files, not entries within them: the month files are rewritten as
/// a unit anyway, so this matches how they are produced and stays cheap.
///
/// [CacheCategory.aiResults] is never touched. Rebuilding a preview costs
/// a decode; rebuilding a colorized frame costs minutes of inference, and
/// silently throwing that away to reclaim disk would be a poor trade the
/// user never asked for.
///
/// Best-effort throughout — a locked file is skipped and retried on the
/// next run rather than aborting the sweep.
int enforceCacheLimit(CacheLimitRequest request) {
  final files = <({File file, int size, DateTime modified})>[];
  var total = 0;

  for (final entry in _rootsIn(request.documentsDir).entries) {
    if (entry.value != CacheCategory.previews) {
      continue;
    }
    final dir = Directory(entry.key);
    if (!dir.existsSync()) {
      continue;
    }
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        try {
          final stat = entity.statSync();
          files.add((file: entity, size: stat.size, modified: stat.modified));
          total += stat.size;
        } catch (_) {
          // Gone between listing and stat.
        }
      }
    } on FileSystemException {
      // Unreadable directory; carry on with what we have.
    }
  }

  if (total <= request.maxBytes) {
    return 0;
  }
  files.sort((a, b) => a.modified.compareTo(b.modified));

  var freed = 0;
  for (final entry in files) {
    if (total <= request.maxBytes) {
      break;
    }
    try {
      entry.file.deleteSync();
      total -= entry.size;
      freed += entry.size;
    } catch (_) {
      // Locked, or already gone. The next sweep retries.
    }
  }
  return freed;
}

/// Removes directories left empty by [enforceCacheLimit] — an abandoned
/// preview resolution otherwise stays visible as an empty folder forever.
///
/// Best-effort: a directory that still holds anything is left alone.
void removeEmptyCacheDirs(String documentsDir) {
  final base = Directory(p.join(documentsDir, 'darkmoon', 'previews'));
  if (!base.existsSync()) {
    return;
  }
  try {
    final dirs = base
        .listSync(recursive: true, followLinks: false)
        .whereType<Directory>()
        .toList();
    // Deepest first, so a parent emptied by its children going away is
    // itself removable in the same pass.
    dirs.sort((a, b) => p.split(b.path).length - p.split(a.path).length);
    for (final dir in dirs) {
      try {
        if (dir.listSync().isEmpty) {
          dir.deleteSync();
        }
      } catch (_) {
        // Skip.
      }
    }
  } on FileSystemException {
    // Nothing to do.
  }
}

/// `1.8 GB`, `412 MB`, `0 B` — the shape a storage meter reads in.
///
/// Binary units (1024), matching what the OS reports for the same folder,
/// so the number here and the number in the file manager agree.
String formatCacheBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // One decimal below 10 (1.8 GB reads better than 2 GB), none above
  // (412 MB, not 412.3 MB).
  return value < 10
      ? '${value.toStringAsFixed(1)} ${units[unit]}'
      : '${value.round()} ${units[unit]}';
}

/// Arguments for [clearCacheCategories], which runs via `compute()`.
class ClearCacheRequest {
  const ClearCacheRequest(this.documentsDir, this.categories);

  final String documentsDir;

  /// Which categories to empty. Passed as names rather than as the enum
  /// so the request survives the isolate boundary unambiguously.
  final Set<String> categories;

  factory ClearCacheRequest.of(
    String documentsDir,
    Set<CacheCategory> categories,
  ) => ClearCacheRequest(documentsDir, {for (final c in categories) c.name});

  bool wants(CacheCategory category) => categories.contains(category.name);
}

/// Deletes every file belonging to the requested categories, and returns
/// how many bytes went.
///
/// Unlike [enforceCacheLimit] this will happily empty the AI results —
/// automatic eviction must not throw away minutes of inference, but a
/// person asking for the space back is a different thing entirely, and
/// refusing them would just mean they delete the folder by hand.
///
/// Leaves the directories themselves behind: they are recreated on the
/// next write anyway, and a caller that wants them gone can follow with
/// [removeEmptyCacheDirs].
///
/// **The in-memory caches are not this function's problem.** Every
/// `ThumbnailCacheManager` keeps parsed month files in memory, so deleting
/// the files underneath one leaves it happily serving what it already
/// read. The caller has to rebuild those — see `_clearCaches`.
///
/// Best-effort per file: one locked entry does not abandon the rest.
int clearCacheCategories(ClearCacheRequest request) {
  var freed = 0;
  _rootsIn(request.documentsDir).forEach((root, category) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      return;
    }
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final actual =
            category == CacheCategory.previews && _isFullSource(entity.path)
            ? CacheCategory.fullSources
            : category;
        if (!request.wants(actual)) {
          continue;
        }
        try {
          final size = entity.lengthSync();
          entity.deleteSync();
          freed += size;
        } catch (_) {
          // Locked or already gone.
        }
      }
    } on FileSystemException {
      // Unreadable directory; the rest still goes.
    }
  });
  return freed;
}
