// End-to-end smoke test for the four AI mask models: loads each one,
// runs it on a real photo, and writes the resulting map out as a PNG so
// the result can be looked at rather than merely asserted to be non-empty.
//
// Exists because these four are the first models in the app that don't go
// through OnnxModel.runTile — one takes uint8, one takes six inputs, two
// have seven outputs, one returns rank 3 — so "the session loaded" is a
// long way from "the tensors were marshalled correctly", and a silently
// transposed or mis-normalized input produces a plausible-looking gray
// smear rather than an error.
//
// Usage:
//   set DARKMOON_NATIVE_DIR=windows/native
//   dart run tool/ai_mask_smoke_test.dart [image] [subjectX subjectY]
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/ai_mask_models.dart';
import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:darkmoon/render/mask.dart';
import 'package:image/image.dart' as img;

void log(String message) {
  // ignore: avoid_print
  print(message);
}

void main(List<String> args) {
  final imagePath = args.isNotEmpty ? args[0] : 'assets/splash/featured.jpg';
  final subjectX = args.length > 1 ? double.parse(args[1]) : 0.5;
  final subjectY = args.length > 2 ? double.parse(args[2]) : 0.5;

  final decoded = img.decodeImage(File(imagePath).readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $imagePath');
    exit(2);
  }
  final full = decoded.convert(format: img.Format.uint8, numChannels: 3);
  log('Source: $imagePath (${full.width}x${full.height})');

  // Same working-resolution downscale the real resolver does, so the
  // numbers below are the ones the app will actually see.
  final scale =
      aiMaskWorkingMaxDimension / (full.width > full.height ? full.width : full.height);
  final width = scale >= 1 ? full.width : (full.width * scale).round();
  final height = scale >= 1 ? full.height : (full.height * scale).round();
  final working = img.copyResize(full, width: width, height: height);
  final rgb = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = working.getPixel(x, y);
      final i = (y * width + x) * 3;
      rgb[i] = pixel.r.toInt();
      rgb[i + 1] = pixel.g.toInt();
      rgb[i + 2] = pixel.b.toInt();
    }
  }
  log('Working resolution: ${width}x$height');

  final outDir = Directory('build/ai_mask_smoke')..createSync(recursive: true);

  try {
    _run('sky', outDir, width, height, () => runSkyMaskModel(rgb, width, height));
    _run(
      'foreground',
      outDir,
      width,
      height,
      () => runForegroundMaskModel(rgb, width, height),
    );
    _run('depth', outDir, width, height, () => runDepthMapModel(rgb, width, height));
    _run('subject', outDir, width, height, () {
      final sw = Stopwatch()..start();
      final embedding = runSubjectEmbedding(rgb, width, height);
      log('  encoder: ${sw.elapsedMilliseconds}ms, '
          '${embedding.length} floats');
      return runSubjectMaskModel(
        embedding,
        SubjectGeometry(
          startX: subjectX,
          startY: subjectY,
          endX: subjectX,
          endY: subjectY,
        ),
        width,
        height,
      );
    });
    _run('subject-norefine', outDir, width, height, () {
      return runSubjectMaskModel(
        runSubjectEmbedding(rgb, width, height),
        SubjectGeometry(
          startX: subjectX,
          startY: subjectY,
          endX: subjectX,
          endY: subjectY,
        ),
        width,
        height,
        refine: false,
      );
    });
  } finally {
    OnnxModel.releaseAll();
  }
  log('\nWrote maps to ${outDir.path}');
}

void _run(
  String label,
  Directory outDir,
  int width,
  int height,
  AiMaskMap Function() body,
) {
  log('\n$label:');
  final sw = Stopwatch()..start();
  final AiMaskMap map;
  try {
    map = body();
  } catch (e) {
    log('  FAILED: $e');
    return;
  }
  final elapsed = sw.elapsedMilliseconds;

  var min = 255;
  var max = 0;
  var sum = 0;
  var covered = 0;
  for (final v in map.data) {
    if (v < min) min = v;
    if (v > max) max = v;
    sum += v;
    if (v > 127) covered++;
  }
  final mean = sum / map.data.length;
  final coverage = 100 * covered / map.data.length;
  log('  ${elapsed}ms  ${map.width}x${map.height}  '
      'min=$min max=$max mean=${mean.toStringAsFixed(1)}  '
      'coverage=${coverage.toStringAsFixed(1)}%');
  if (min == max) {
    log('  WARNING: map is flat — the model produced no signal at all');
  }

  final image = img.Image(width: map.width, height: map.height, numChannels: 1);
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      image.setPixelR(x, y, map.data[y * map.width + x]);
    }
  }
  File('${outDir.path}/$label.png').writeAsBytesSync(img.encodePng(image));
}
