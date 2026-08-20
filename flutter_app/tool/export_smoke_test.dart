// Standalone smoke test for the export pipeline: full-resolution decode ->
// render -> encode -> write. Exercises the same function the UI calls via
// `compute()`, at full res instead of the downscaled editing preview.
//
// Usage: dart run tool/export_smoke_test.dart <raw-file> [out-dir]
import 'dart:io';

import 'package:darkmoon/export/export_format.dart';
import 'package:darkmoon/export/export_job.dart';
import 'package:darkmoon/render/render_params.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/export_smoke_test.dart <raw-file> [out-dir]',
    );
    exit(1);
  }
  final path = args[0];
  final outDir = args.length > 1 ? args[1] : '.';

  for (final format in ExportFormat.values) {
    final destPath = '$outDir/export_smoke_test.${format.extension}';
    final watch = Stopwatch()..start();
    final result = await exportPhoto(
      ExportRequest(
        sourcePath: path,
        destPath: destPath,
        params: const RenderParams(
          temperature: 7000,
          exposure: 15,
          contrast: 10,
          vibrance: 25,
        ),
        format: format,
        quality: 92,
      ),
    );
    watch.stop();
    if (!result.success) {
      stderr.writeln('${format.label}: FAILED - ${result.error}');
      exit(2);
    }
    final size = File(destPath).lengthSync();
    // ignore: avoid_print
    print(
      '${format.label}: $size bytes in ${watch.elapsedMilliseconds}ms -> $destPath',
    );
  }
}
