// ignore_for_file: avoid_print
// Runs the four AI mask models once on a synthetic frame and writes each
// map out with the provider's name, plus the time it took — so the same
// run under DARKMOON_ONNX_EP=cpu and under =webgpu can be compared pixel
// for pixel. A GPU answer has to be looked at, not only timed: LaMa on
// WebGPU came back plausible by every number and wrong (2026-09-12).
//
//   DARKMOON_NATIVE_DIR=<bundle> DARKMOON_PROBE_OUT=<dir> \
//     DARKMOON_ONNX_EP=cpu dart run tool/ai_mask_gpu_probe.dart
//   ... then the same with DARKMOON_ONNX_EP=webgpu, and diff the .pgm files.
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/ai_mask_models.dart';
import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:darkmoon/render/mask.dart';

void main() {
  final out = Platform.environment['DARKMOON_PROBE_OUT'] ?? '.';
  final ep = Platform.environment['DARKMOON_ONNX_EP'] ?? 'default';
  const w = 640, h = 480;
  // A sky over a ground with a dark figure: enough for every model to
  // say something.
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      final sky = y < 220;
      final figure = y > 200 && (x - 320).abs() < 60 && y < 420;
      rgb[i] = figure ? 40 : (sky ? 120 : 110);
      rgb[i + 1] = figure ? 35 : (sky ? 170 + y ~/ 6 : 120);
      rgb[i + 2] = figure ? 45 : (sky ? 235 : 70);
    }
  }
  void dump(String name, AiMaskMap map, int ms) {
    final header =
        'P5 ${map.width} ${map.height} 255${String.fromCharCode(10)}';
    File(
      '$out/${name}_$ep.pgm',
    ).writeAsBytesSync([...header.codeUnits, ...map.data]);
    var sum = 0;
    for (final v in map.data) {
      sum += v;
    }
    print(
      '  $name [$ep]: ${map.width}x${map.height}, mean '
      '${(sum / map.data.length).toStringAsFixed(1)}, $ms ms',
    );
  }

  var sw = Stopwatch()..start();
  dump('sky', runSkyMaskModel(rgb, w, h), sw.elapsedMilliseconds);
  sw = Stopwatch()..start();
  dump('foreground', runForegroundMaskModel(rgb, w, h), sw.elapsedMilliseconds);
  sw = Stopwatch()..start();
  dump('depth', runDepthMapModel(rgb, w, h), sw.elapsedMilliseconds);
  sw = Stopwatch()..start();
  final embedding = runSubjectEmbedding(rgb, w, h);
  final embedMs = sw.elapsedMilliseconds;
  sw = Stopwatch()..start();
  dump(
    'subject',
    runSubjectMaskModel(
      embedding,
      const SubjectGeometry(startX: 0.5, startY: 0.65, endX: 0.5, endY: 0.65),
      w,
      h,
    ),
    sw.elapsedMilliseconds,
  );
  print('  subject embedding [$ep]: $embedMs ms');
  OnnxModel.releaseAll();
}
