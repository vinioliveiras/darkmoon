// Standalone smoke test for the LibRaw FFI thumbnail path + its per-month
// disk cache — no Flutter engine needed, since decodeRawThumbnail and
// ThumbnailCacheManager only touch dart:io/dart:ffi/package:image/
// package:crypto. Handy for debugging without going through the UI.
//
// Note: raw_r.dll/vcomp140.dll must be discoverable from the working
// directory when running this directly with `dart run` (the built app gets
// them from windows/native/ via the CMake install step instead).
//
// Usage: dart run tool/thumbnail_smoke_test.dart <path-to-raw-file> [out.jpg]
import 'dart:io';

import 'package:darkmoon/catalog/thumbnail_cache.dart';
import 'package:darkmoon/native/thumbnail_loader.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/thumbnail_smoke_test.dart <raw-file> [out.jpg]',
    );
    exit(1);
  }
  final path = args[0];
  final outPath = args.length > 1 ? args[1] : 'thumbnail_smoke_test_out.jpg';
  final cacheDir = await Directory.systemTemp.createTemp(
    'darkmoon_thumb_cache_',
  );
  final cache = ThumbnailCacheManager(cacheDir.path);

  final coldWatch = Stopwatch()..start();
  final decoded = decodeRawThumbnail(path);
  coldWatch.stop();
  if (decoded == null) {
    stderr.writeln('decodeRawThumbnail returned null for $path');
    exit(2);
  }
  File(outPath).writeAsBytesSync(decoded);
  // ignore: avoid_print
  print(
    'cold (fresh decode): ${decoded.length} JPEG bytes in ${coldWatch.elapsedMilliseconds}ms -> $outPath',
  );

  await cache.store(path, decoded);
  await cache.flush();

  // A second manager instance, so this lookup has to actually read the
  // month file back from disk rather than reuse the first instance's
  // in-memory copy — proving the round trip through the file, not just
  // the in-memory map.
  final reopened = ThumbnailCacheManager(cacheDir.path);
  final warmWatch = Stopwatch()..start();
  final cached = await reopened.lookup(path);
  warmWatch.stop();
  if (cached == null) {
    stderr.writeln(
      'cache lookup returned null after store+flush — round trip failed',
    );
    exit(3);
  }
  // ignore: avoid_print
  print(
    'warm (cache hit, fresh manager): ${cached.length} JPEG bytes in ${warmWatch.elapsedMilliseconds}ms',
  );
  if (cached.length != decoded.length) {
    stderr.writeln(
      'WARNING: cached bytes length differs from the original decode',
    );
  }

  await cacheDir.delete(recursive: true);
}
