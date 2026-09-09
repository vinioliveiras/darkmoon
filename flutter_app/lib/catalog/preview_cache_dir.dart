import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../native/raw_decode_format_version.dart';

/// Resolves (creating if needed) the directory cached edit-source previews
/// live in — `Documents/darkmoon/previews/v{rawDecodeFormatVersion}/
/// {resolution}px`, next to the thumbnail cache. Reuses
/// [ThumbnailCacheManager]'s exact on-disk format (see thumbnail_cache.dart)
/// with a second instance pointed here instead; nothing about that class is
/// actually thumbnail-specific.
///
/// Namespaced by [previewMaxDimension] (a *directory*, not part of the
/// cache key `ThumbnailCacheManager` itself computes) so that changing
/// Settings > Preview Resolution can't return a cached preview decoded at
/// the wrong size — it just lands in a different, initially-empty
/// namespace instead. Namespaced by [rawDecodeFormatVersion] the same way,
/// for the same reason but on decode-*params* changes instead of
/// resolution — see that constant's own doc comment.
Future<String> resolvePreviewCacheDir(
  int previewMaxDimension, {
  bool editEmbeddedJpeg = false,
}) async {
  final documents = await getApplicationDocumentsDirectory();
  // The two modes decode different pixels from the same file, so they
  // cannot share a directory: a cached entry carries no record of which
  // one wrote it, and serving the wrong one shows the wrong photograph
  // with nothing to indicate why. Embedded-JPEG mode ignores the
  // resolution cap entirely (see decodeEditSources), so it gets one
  // directory rather than one per setting.
  final bucket = editEmbeddedJpeg ? 'embedded' : '${previewMaxDimension}px';
  final dir = Directory(
    p.join(
      documents.path,
      'darkmoon',
      'previews',
      'v$rawDecodeFormatVersion',
      bucket,
    ),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

/// Deletes every sibling `v{N}` directory under `Documents/darkmoon/previews/`
/// whose `N` isn't the current [rawDecodeFormatVersion] — a version bump
/// (see that constant's own doc) makes every file under an old `vN` dead on
/// arrival (decoded with different params, never a valid cache hit again),
/// but nothing ever deleted them; they'd just sit there forever, one whole
/// copy of every cached preview/native-source per past bump. Best-effort,
/// same "never let a cleanup failure surface as a real error" shape as
/// [evictNativeSourceCache] — call once per app session (e.g. from
/// `initState`), not per photo; this walks the whole `previews/` directory.
///
/// Deliberately does NOT touch the `{resolution}px` subdirectories within
/// the *current* version — those are legitimate alternate caches for
/// different `AppSettings.previewResolution` choices the user might
/// switch back to, not dead versions.
Future<void> cleanupStalePreviewCacheVersions() async {
  try {
    final documents = await getApplicationDocumentsDirectory();
    final previewsDir = Directory(
      p.join(documents.path, 'darkmoon', 'previews'),
    );
    if (!await previewsDir.exists()) {
      return;
    }
    final currentName = 'v$rawDecodeFormatVersion';
    await for (final entity in previewsDir.list()) {
      if (entity is! Directory) {
        continue;
      }
      final name = p.basename(entity.path);
      if (name == currentName || !RegExp(r'^v\d+$').hasMatch(name)) {
        continue;
      }
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Skip a locked file; next launch retries.
      }
    }
  } catch (_) {
    // Ignore — this is opportunistic disk cleanup, not correctness-critical.
  }
}


/// Resolves (creating if needed) the directory the camera-match
/// measurements live in — `Documents/darkmoon/camera_match/
/// v{rawDecodeFormatVersion}`.
///
/// One number and a 33-point curve per photo, measured from the RAW's own
/// embedded JPEG (see `measureCameraMatch`). Tiny, but not cheap to
/// produce: it decodes that JPEG and walks two images, which on a 13 MP
/// preview was most of the time a warm open took before this cache
/// existed. It only ever has to happen once per file.
///
/// Its own directory rather than a slot in the preview cache: the match
/// describes the *file*, not the resolution it was previewed at, so it
/// survives a change to Settings > Preview Resolution — and it is equally
/// valid for the export, which never goes through the preview cache at
/// all. Versioned by [rawDecodeFormatVersion] because a change to the
/// decode params changes the decode the match was measured against.
///
/// Reuses [ThumbnailCacheManager] like the caches above; its sha1 of
/// path+mtime+size is exactly the invalidation this wants, since a
/// replaced file needs a fresh measurement.
Future<String> resolveCameraMatchCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(
    p.join(
      documents.path,
      'darkmoon',
      'camera_match',
      'v$rawDecodeFormatVersion',
    ),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
