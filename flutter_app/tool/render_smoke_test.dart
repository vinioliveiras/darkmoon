// Standalone smoke test for the edit pipeline: decode -> render (neutral,
// then with a few adjustments) -> encode. Exercises the same functions the
// UI calls via `compute()`.
//
// Usage: dart run tool/render_smoke_test.dart <raw-file> [out-prefix]
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:darkmoon/native/edit_source.dart';
import 'package:darkmoon/render/render_job.dart';
import 'package:darkmoon/render/render_params.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/render_smoke_test.dart <raw-file> [out-prefix]',
    );
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

  Future<void> renderAndSave(String label, RenderParams params) async {
    final watch = Stopwatch()..start();
    final result = await renderJobToJpeg(
      RenderJob(source: sources.preview, params: params),
    );
    watch.stop();
    // The render pipeline no longer emits a preview JPEG (the canvas
    // paints its pixels directly — see RenderResult.previewRgba), so this
    // smoke test encodes one itself just to have something to eyeball.
    final outPath = '${outPrefix}_$label.jpg';
    final jpeg = img.encodeJpg(
      img.Image.fromBytes(
        width: result.previewWidth,
        height: result.previewHeight,
        bytes: result.previewRgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      ),
      quality: 90,
    );
    File(outPath).writeAsBytesSync(jpeg);
    // ignore: avoid_print
    print(
      '$label: ${jpeg.length} JPEG bytes '
      '(hist max r=${result.histogram.red.reduce((a, b) => a > b ? a : b)}) '
      'in ${watch.elapsedMilliseconds}ms -> $outPath',
    );
  }

  await renderAndSave('neutral', const RenderParams());
  await renderAndSave(
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
  await renderAndSave('texture', const RenderParams(texture: 100));
  await renderAndSave('clarity', const RenderParams(clarity: 100));
  await renderAndSave('dehaze_positive', const RenderParams(dehaze: 80));
  await renderAndSave('dehaze_negative', const RenderParams(dehaze: -60));
}
