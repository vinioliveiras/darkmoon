// Phase 0 of the GPU render-pipeline plan (see project_gpu_render_plan.md):
// answers the two architecture-defining questions the rest of the plan
// depends on, empirically, before any real shader math is written.
//
// Run with: flutter test integration_test/gpu_spike_test.dart -d windows
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Builds a tiny synthetic RGBA image (a horizontal gradient, distinct per
/// pixel so a round-trip bug shows up as a real diff, not a flat false
/// pass) and returns it as a real `ui.Image`.
Future<ui.Image> _makeSourceImage(int width, int height) async {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      bytes[i] = (x * 255 ~/ (width - 1)); // R: left-to-right ramp
      bytes[i + 1] = (y * 255 ~/ (height - 1)); // G: top-to-bottom ramp
      bytes[i + 2] = 128;
      bytes[i + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, (
    image,
  ) {
    completer.complete(image);
  });
  return completer.future;
}

/// Runs the source image through the passthrough shader and reads back the
/// result — the actual mechanics every later GPU phase depends on.
Future<Uint8List> _runPassthrough(ui.Image source) async {
  final program = await ui.FragmentProgram.fromAsset(
    'shaders/_spike_passthrough.frag',
  );
  final shader = program.fragmentShader();
  shader.setFloat(0, source.width.toDouble());
  shader.setFloat(1, source.height.toDouble());
  shader.setImageSampler(0, source);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  final outImage = await picture.toImage(source.width, source.height);
  final byteData = await outImage.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (byteData == null) {
    throw StateError('toByteData returned null');
  }
  return byteData.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shader asset loads and rootBundle is reachable', (
    tester,
  ) async {
    // Fails loudly (not silently returns null) if the `flutter: shaders:`
    // pubspec entry or the build's asset bundling is wrong — confirms the
    // "shader compile-time asset bundling correctness" risk from the plan
    // isn't a problem before anything else here is trusted.
    final data = await rootBundle.load('shaders/_spike_passthrough.frag');
    expect(data.lengthInBytes, greaterThan(0));
  });

  testWidgets('round-trip: source image -> shader -> readback matches', (
    tester,
  ) async {
    const width = 64, height = 64;
    final source = await _makeSourceImage(width, height);
    final result = await _runPassthrough(source);

    final expected = ByteData(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        expected.setUint8(i, x * 255 ~/ (width - 1));
        expected.setUint8(i + 1, y * 255 ~/ (height - 1));
        expected.setUint8(i + 2, 128);
        expected.setUint8(i + 3, 255);
      }
    }
    final expectedBytes = expected.buffer.asUint8List();

    expect(result.length, expectedBytes.length);
    var maxDiff = 0;
    for (var i = 0; i < result.length; i++) {
      final d = (result[i] - expectedBytes[i]).abs();
      if (d > maxDiff) maxDiff = d;
    }
    // ignore: avoid_print
    print('[gpu_spike] round-trip max byte diff: $maxDiff');
    expect(
      maxDiff,
      lessThanOrEqualTo(1),
      reason:
          'A passthrough shader (no math at all) should reproduce the '
          'source near-exactly. A bigger diff means the upload/readback '
          'path itself is lossy, before any real effect shader is written.',
    );
  });

  testWidgets(
    'the isolate-GPU-context constraint: does FragmentProgram/Canvas/Image '
    'work from inside Isolate.run?',
    (tester) async {
      const width = 8, height = 8;
      final source = await _makeSourceImage(width, height);
      // ui.Image itself isn't isolate-transferable, so this test can only
      // ask "can the whole shader pipeline (load asset, draw, rasterize,
      // read back) run inside a background isolate at all" using a source
      // built *inside* that isolate too — matching how render_gpu.dart
      // would actually need to work if this turns out to succeed (build
      // the source texture and do the GPU work in the same isolate).
      Object? caughtError;
      String? outcome;
      try {
        outcome = await Isolate.run(() async {
          final bytes = Uint8List(width * height * 4);
          for (var i = 0; i < bytes.length; i += 4) {
            bytes[i] = 200;
            bytes[i + 1] = 100;
            bytes[i + 2] = 50;
            bytes[i + 3] = 255;
          }
          final completer = Completer<ui.Image>();
          ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, (
            img,
          ) {
            completer.complete(img);
          });
          final img = await completer.future;
          final result = await _runPassthrough(img);
          return 'ran ${result.length} bytes back, first pixel r=${result[0]}';
        });
      } catch (e) {
        caughtError = e;
      }
      // ignore: avoid_print
      print(
        '[gpu_spike] Isolate.run GPU attempt -> '
        '${caughtError != null ? "THREW: $caughtError" : "SUCCEEDED: $outcome"}',
      );
      // Deliberately no assertion on the outcome itself — this test's
      // entire purpose is to observe and report what happens (see the
      // printed line above / the test runner's captured output), which
      // then gets written into project_gpu_render_plan.md's findings, not
      // to pass/fail on an assumption we don't have yet.
      expect(source.width, width); // keeps `source` from being unused
    },
  );
}
