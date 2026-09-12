import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolved once on the main isolate and handed to the worker —
/// `path_provider` is not isolate-safe, the same split every other cache
/// directory here follows.
Future<String> resolveInpaintCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon', 'inpaint_cache'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
