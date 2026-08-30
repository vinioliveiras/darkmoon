import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves (creating if needed) the directory cloud AI denoise results
/// live in: `Documents/darkmoon/cloud_denoise_cache`.
///
/// Kept separate from `ai_enhance_cache_dir.dart`'s directory even though
/// the pattern is identical — these two caches invalidate independently
/// (switching cloud provider/re-running a paid call is a very different
/// event from the free on-device pipeline re-running), and mixing them
/// would make "clear the AI Enhance cache" ambiguous about whether it also
/// discards results the user paid for.
///
/// `path_provider`-dependent, so this must be called once from the main
/// isolate; pass the resolved path into any background-isolate lookup/
/// write instead of calling this from one.
Future<String> resolveCloudDenoiseCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(
    p.join(documents.path, 'darkmoon', 'cloud_denoise_cache'),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
