import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves (creating if needed) the directory the AI mask maps live in:
/// `Documents/darkmoon/ai_mask_cache`.
///
/// Same split as every other cache here — `path_provider` is main-isolate
/// only, so this is called once and the resolved path handed to the
/// isolate that does the lookups and writes (`ai_mask_cache.dart` itself
/// stays `path_provider`-free for exactly that reason).
///
/// Its own directory rather than a corner of the colorize or AI Enhance
/// cache because its entries have a different lifetime: those cache a
/// finished image the user asked for once, these cache a model's opinion
/// about a photo that every render of that photo re-reads.
Future<String> resolveAiMaskCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon', 'ai_mask_cache'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
