// Standalone smoke test for the editing-preview pipeline (full decode +
// downscale + JPEG encode) — the same function the UI calls via `compute()`.
//
// Usage: dart run tool/preview_smoke_test.dart <raw-file> [out.jpg]
import 'dart:io';

import 'package:darkmoon/native/preview_loader.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/preview_smoke_test.dart <raw-file> [out.jpg]');
    exit(1);
  }
  final path = args[0];
  final outPath = args.length > 1 ? args[1] : 'preview_smoke_test_out.jpg';

  final stopwatch = Stopwatch()..start();
  final bytes = decodeRawPreview(path);
  stopwatch.stop();

  if (bytes == null) {
    stderr.writeln('decodeRawPreview returned null for $path');
    exit(2);
  }
  File(outPath).writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('OK: ${bytes.length} JPEG bytes in ${stopwatch.elapsedMilliseconds}ms -> $outPath');
}
