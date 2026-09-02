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
Future<String> resolvePreviewCacheDir(int previewMaxDimension) async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(
    p.join(
      documents.path,
      'darkmoon',
      'previews',
      'v$rawDecodeFormatVersion',
      '${previewMaxDimension}px',
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
