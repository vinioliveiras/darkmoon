// The on-disk caches the editor keeps warm: thumbnails, previews,
// camera match, native sources, the cache root and its sweep.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State. `setState` is protected and an extension is not a subclass, so
// these go through the State's `_rebuild`. Split 2026-09-10 for navigation.
part of '../editor_screen.dart';

extension _EditorCaches on _EditorScreenState {
  Future<void> _loadThumbnailCache() async {
    final dir = await resolveThumbnailCacheDir();
    if (!mounted) {
      return;
    }
    _rebuild(() => _thumbnailCache = ThumbnailCacheManager(dir));
  }

  Future<void> _loadCameraMatchCache() async {
    final dir = await resolveCameraMatchCacheDir();
    if (!mounted) {
      return;
    }
    _rebuild(() => _cameraMatchCache = ThumbnailCacheManager(dir));
  }

  Future<void> _loadPreviewCache() async {
    final dir = await resolvePreviewCacheDir(
      _settings.previewResolution,
      editEmbeddedJpeg: _settings.editEmbeddedJpeg,
    );
    if (!mounted) {
      return;
    }
    _rebuild(() => _previewCache = ThumbnailCacheManager(dir));
  }

  Future<void> _loadNativeSourceCache() async {
    final dir = await resolveNativeSourceCacheDir();
    if (!mounted) {
      return;
    }
    _rebuild(() {
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
      // The sweep governs the whole previews tree now, not this
      // directory alone — a full-resolution source and a preview compete
      // for the same ceiling, so trimming them separately would let the
      // total sit at the sum of two caps.
      _scheduleCacheSweep();
    }
  }

  Future<void> _loadCacheRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!mounted) {
      return;
    }
    _cacheRoot = dir.path;
    // Directories abandoned by a decode-format bump are dead on arrival —
    // never a valid hit again — and nothing had ever deleted them. This
    // function has existed unused since it was written.
    unawaited(cleanupStalePreviewCacheVersions());
    await _sweepCaches();
  }

  /// How long after the last cache write the sweep runs.
  ///
  /// Long, deliberately. The sweep walks the whole cache tree, and every
  /// photo opened in a browsing session writes to that tree — running it
  /// per write would spend more time counting the cache than filling it,
  /// and the limit is a ceiling to stay under, not a quota to enforce to
  /// the byte.
  static const _cacheSweepDelay = Duration(seconds: 30);

  void _scheduleCacheSweep() {
    _cacheSweepTimer?.cancel();
    _cacheSweepTimer = Timer(_cacheSweepDelay, () {
      unawaited(_sweepCaches());
    });
  }

  /// Trims the rebuildable caches to [AppSettings.cacheMaxBytes] and
  /// re-measures what is left.
  ///
  /// Runs on a background isolate: it walks the whole cache tree, which on
  /// a large library is thousands of files, and doing that on the UI
  /// isolate would stutter the frame pump for the same reason a render
  /// does.
  Future<void> _sweepCaches() async {
    final root = _cacheRoot;
    if (root == null) {
      return;
    }
    if (_settings.cacheMaxBytes != unlimitedCacheBytes) {
      await compute(
        enforceCacheLimit,
        CacheLimitRequest(root, _settings.cacheMaxBytes),
      );
      await compute(removeEmptyCacheDirs, root);
    }
    await _refreshCacheUsage();
  }

  /// Empties the given cache categories, on disk and in memory.
  ///
  /// The in-memory half is the part that is easy to miss. Every
  /// [ThumbnailCacheManager] keeps the month files it has read parsed in
  /// memory, so deleting the files underneath one leaves it serving what
  /// it already has — the space comes back and the app carries on as if
  /// nothing happened, which looks exactly like the button being broken.
  /// Each affected manager is rebuilt against its now-empty directory.
  ///
  /// [_editSources] goes too when previews or full-resolution sources are
  /// cleared: those are the decoded buffers those caches exist to avoid
  /// re-deriving, and leaving them would mean the current photo keeps
  /// showing while everything backing it is gone.
  Future<void> _clearCaches(Set<CacheCategory> categories) async {
    final root = _cacheRoot;
    if (root == null || categories.isEmpty) {
      return;
    }
    await compute(clearCacheCategories, ClearCacheRequest.of(root, categories));
    await compute(removeEmptyCacheDirs, root);
    if (!mounted) {
      return;
    }

    if (categories.contains(CacheCategory.previews) ||
        categories.contains(CacheCategory.fullSources)) {
      await _loadPreviewCache();
      await _loadCameraMatchCache();
      await _loadNativeSourceCache();
    }
    if (categories.contains(CacheCategory.thumbnails)) {
      await _loadThumbnailCache();
    }
    if (!mounted) {
      return;
    }
    _rebuild(() {
      if (categories.contains(CacheCategory.previews) ||
          categories.contains(CacheCategory.fullSources) ||
          categories.contains(CacheCategory.aiResults)) {
        _editSources.clear();
        _embeddedPreviews.clear();
      }
      if (categories.contains(CacheCategory.thumbnails)) {
        _thumbnails.clear();
      }
    });

    // Put back what the user is actually looking at, rather than leaving
    // the viewport and the filmstrip empty until the next click.
    if (categories.contains(CacheCategory.thumbnails) && _files.isNotEmpty) {
      unawaited(_loadThumbnails(_files, _folderGeneration));
    }
    final selected = _selectedIndex == null ? null : _files[_selectedIndex!];
    if (selected != null && !_editSources.containsKey(selected.path)) {
      unawaited(_loadEditSourceAndRender(selected.path, _folderGeneration));
    }
    await _refreshCacheUsage();
  }

  Future<void> _refreshCacheUsage() async {
    final root = _cacheRoot;
    if (root == null) {
      return;
    }
    final usage = await compute(measureCacheUsage, root);
    if (!mounted) {
      return;
    }
    _rebuild(() => _cacheUsage = usage);
  }
}
