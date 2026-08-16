// Standalone smoke test for the edit pipeline: decode -> render (neutral,
// then with a few adjustments) -> encode. Exercises the same functions the
// UI calls via `compute()`.
//
// Usage: dart run tool/render_smoke_test.dart <raw-file> [out-prefix]
import 'dart:io';

import 'package:darkmoon/native/edit_source.dart';
import 'package:darkmoon/render/render_job.dart';
import 'package:darkmoon/render/render_params.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/render_smoke_test.dart <raw-file> [out-prefix]');
    exit(1);
  }
  final path = args[0];
  final outPrefix = args.length > 1 ? args[1] : 'render_smoke_test';

  final decodeWatch = Stopwatch()..start();
  final sources = decodeEditSources(path);
  decodeWatch.stop();
  if (sources == null) {
    stderr.writeln('decodeEditSources returned null for $path');
    exit(2);
  }
  // ignore: avoid_print
  print(
    'decode: ${sources.preview.width}x${sources.preview.height} preview, '
    '${sources.live.width}x${sources.live.height} live, in ${decodeWatch.elapsedMilliseconds}ms',
  );

  void renderAndSave(String label, RenderParams params) {
    final watch = Stopwatch()..start();
    final result = renderJobToJpeg(RenderJob(source: sources.preview, params: params));
    watch.stop();
    final outPath = '${outPrefix}_$label.jpg';
    File(outPath).writeAsBytesSync(result.jpegBytes);
    // ignore: avoid_print
    print(
      '$label: ${result.jpegBytes.length} JPEG bytes '
      '(hist max r=${result.histogram.red.reduce((a, b) => a > b ? a : b)}) '
      'in ${watch.elapsedMilliseconds}ms -> $outPath',
    );
  }

  renderAndSave('neutral', const RenderParams());
  renderAndSave(
    'adjusted',
    const RenderParams(
      temperature: 8000,
      exposure: 30,
      contrast: 20,
      shadows: 40,
      highlights: -30,
      vibrance: 50,
      saturation: 15,
    ),
  );
  renderAndSave('texture', const RenderParams(texture: 100));
  renderAndSave('clarity', const RenderParams(clarity: 100));
  renderAndSave('dehaze_positive', const RenderParams(dehaze: 80));
  renderAndSave('dehaze_negative', const RenderParams(dehaze: -60));
}
