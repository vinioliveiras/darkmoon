import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves (creating if needed) the directory item 37's colorize (DDColor)
/// result cache lives in: `Documents/darkmoon/colorize_cache`. Same
/// reasoning as `ai_enhance_cache_dir.dart` (full-resolution RGB buffers,
/// one file per photo, `path_provider`-dependent so this must be called
/// once from the main isolate and the resolved path passed into
/// isolate-run lookups/writes) — kept as its own cache/directory rather
/// than folded into the AI Enhance one since colorize is an independent
/// pipeline with its own cache key shape (no denoise/upscale dimensions).
Future<String> resolveColorizeCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon', 'colorize_cache'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
