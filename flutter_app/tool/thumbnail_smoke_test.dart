// Standalone smoke test for the LibRaw FFI thumbnail path — no Flutter
// engine needed, since decodeRawThumbnail only touches dart:ffi and
// package:image. Handy for debugging without going through the UI.
//
// Note: raw_r.dll/vcomp140.dll must be discoverable from the working
// directory when running this directly with `dart run` (the built app gets
// them from windows/native/ via the CMake install step instead).
//
// Usage: dart run tool/thumbnail_smoke_test.dart <path-to-raw-file> [out.jpg]
import 'dart:io';

import 'package:darkmoon/native/thumbnail_loader.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/thumbnail_smoke_test.dart <raw-file> [out.jpg]');
    exit(1);
  }
  final path = args[0];
  final outPath = args.length > 1 ? args[1] : 'thumbnail_smoke_test_out.jpg';

  final stopwatch = Stopwatch()..start();
  final bytes = decodeRawThumbnail(path);
  stopwatch.stop();

  if (bytes == null) {
    stderr.writeln('decodeRawThumbnail returned null for $path');
    exit(2);
  }
  File(outPath).writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('OK: decoded ${bytes.length} JPEG bytes in ${stopwatch.elapsedMilliseconds}ms -> $outPath');
}
