import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves (creating if needed) the directory the AI Enhance (item 13 —
/// NAFNet-SIDD denoise + DIS 2x upscale) result cache lives in:
/// `Documents/darkmoon/ai_enhance_cache`.
///
/// One file per photo (not batched into month files like the thumbnail/
/// preview caches) — these buffers are full-resolution, 2x-upscaled RGB,
/// easily tens of MB each, nothing like a thumbnail's few hundred KB.
/// `path_provider`-dependent, so (like `resolveThumbnailCacheDir`) this
/// must be called once from the main isolate; pass the resolved path into
/// isolate-run lookups/writes instead of calling this from one.
Future<String> resolveAiEnhanceCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon', 'ai_enhance_cache'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
