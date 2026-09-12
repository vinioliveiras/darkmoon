// Runs the bundled LaMa model through the app's own removal geometry on
// a synthetic frame and checks the hole was filled and the rest left
// alone — the Dart side of what tool/lama_probe did in Python before the
// model was adopted (2026-09-12): tensor names read off the graph, the
// input range, the output range, the mask polarity.
//
// Usage (from flutter_app/):
//   DARKMOON_NATIVE_DIR=build/windows/x64/runner/Release \
//     dart run tool/inpaint_smoke_test.dart
//
// DARKMOON_NATIVE_DIR is where onnxruntime and models/ live — a built
// bundle. Exit code 1 on any failure.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:darkmoon/render/inpaint.dart';

void main() {
  const w = 640, h = 480;
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      rgb[i] = (255 * x / w).round();
      rgb[i + 1] = (255 * y / h).round();
      rgb[i + 2] = (127 + 100 * math.sin(x / 12.0)).round().clamp(0, 255);
    }
  }
  // The "object": a red block.
  for (var y = 200; y < 300; y++) {
    for (var x = 260; x < 370; x++) {
      final i = (y * w + x) * 3;
      rgb[i] = 255;
      rgb[i + 1] = 0;
      rgb[i + 2] = 0;
    }
  }
  final alpha = Float32List(w * h);
  for (var y = 190; y < 310; y++) {
    for (var x = 250; x < 380; x++) {
      alpha[y * w + x] = 1.0;
    }
  }

  stdout.writeln('darkmoon inpaint smoke test');
  final model = OnnxModel.forSpec(lamaInpaintModelSpec);
  stdout.writeln(
    '  provider: ${model.provider.label} (gpu=${model.usingGpu})'
    '${model.gpuError == null ? '' : ' — ${model.gpuError}'}',
  );
  stdout.writeln(
    '  inputs: ${model.inputNames}  outputs: ${model.outputNames}',
  );
  final size = lamaInpaintModelSpec.inputTileSize;
  final sw = Stopwatch()..start();
  double outMin = double.infinity, outMax = -double.infinity;
  final out = inpaintRegion(
    rgb,
    w,
    h,
    alpha,
    modelSize: size,
    runModel: (imageChw, maskHw) {
      final outputs = model.runGraph(
        {
          model.inputNames[0]: OnnxTensorData.float32([
            1,
            3,
            size,
            size,
          ], imageChw),
          model.inputNames[1]: OnnxTensorData.float32([
            1,
            1,
            size,
            size,
          ], maskHw),
        },
        [model.outputNames.first],
      );
      final painted = outputs[model.outputNames.first]!.floats!;
      for (final v in painted) {
        if (v < outMin) outMin = v;
        if (v > outMax) outMax = v;
      }
      return painted;
    },
  );
  sw.stop();
  stdout.writeln(
    '  run: ${sw.elapsedMilliseconds} ms, output range $outMin..$outMax',
  );

  var redLeft = 0;
  var white = 0;
  var holeSum = 0.0;
  var holeCount = 0;
  for (var y = 200; y < 300; y++) {
    for (var x = 260; x < 370; x++) {
      final i = (y * w + x) * 3;
      if (out[i] > 200 && out[i + 1] < 60) redLeft++;
      if (out[i] > 245 && out[i + 1] > 245 && out[i + 2] > 245) white++;
      holeSum += (out[i] + out[i + 1] + out[i + 2]) / 3;
      holeCount++;
    }
  }
  // The fill has to look like its surroundings: the mean of a ring just
  // outside the brush against the mean inside. WebGPU once returned a
  // flat white patch that passed every other check here.
  var ringSum = 0.0;
  var ringCount = 0;
  for (var y = 170; y < 330; y++) {
    for (var x = 230; x < 400; x++) {
      if (y >= 190 && y < 310 && x >= 250 && x < 380) continue;
      final i = (y * w + x) * 3;
      ringSum += (out[i] + out[i + 1] + out[i + 2]) / 3;
      ringCount++;
    }
  }
  final holeMean = holeSum / holeCount;
  final ringMean = ringSum / ringCount;
  stdout.writeln(
    '  hole mean ${holeMean.toStringAsFixed(1)}, ring mean '
    '${ringMean.toStringAsFixed(1)}, near-white pixels in the hole: $white',
  );
  var outsideChanged = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (y >= 190 && y < 310 && x >= 250 && x < 380) continue;
      final i = (y * w + x) * 3;
      if (out[i] != rgb[i] ||
          out[i + 1] != rgb[i + 1] ||
          out[i + 2] != rgb[i + 2]) {
        outsideChanged++;
      }
    }
  }
  final dump = Platform.environment['DARKMOON_PROBE_OUT'];
  if (dump != null) {
    final header = 'P6 $w $h 255${String.fromCharCode(10)}';
    File('$dump/smoke_out.ppm').writeAsBytesSync([...header.codeUnits, ...out]);
    File('$dump/smoke_in.ppm').writeAsBytesSync([...header.codeUnits, ...rgb]);
  }
  stdout.writeln('  red pixels left in the hole: $redLeft of ${100 * 110}');
  stdout.writeln('  pixels changed outside the brush: $outsideChanged');
  final ok =
      redLeft < 100 &&
      outsideChanged == 0 &&
      outMax > 1.5 &&
      outMax <= 255.5 &&
      white < 100 &&
      (holeMean - ringMean).abs() < 40;
  stdout.writeln(ok ? '  OK' : '  FAIL');
  OnnxModel.releaseAll();
  exit(ok ? 0 : 1);
}
