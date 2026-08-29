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
