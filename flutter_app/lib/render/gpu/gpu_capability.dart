import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Whether GPU rendering ([renderRgbGpu]) is safe to offer in the UI at
/// all on this machine — see `project_gpu_render_plan.md`'s Phase 6
/// "capability probe" exit criterion. Compiles the same tiny passthrough
/// shader Phase 0 verified (`shaders/_spike_passthrough.frag`), draws a
/// small known image through it, and confirms the readback matches —
/// exactly Phase 0's own round-trip test, run once at startup instead of
/// only in `integration_test/gpu_spike_test.dart`. Any failure (missing
/// shader asset, GPU/driver rejecting the pipeline, wildly wrong readback)
/// means silently falling back to the CPU render path rather than
/// offering a GPU toggle that would just fail later.
///
/// Cached after the first call — the probe does real GPU work (shader
/// compile + draw + readback), not free, and the answer can't change
/// during a single run of the app.
///
/// **Must be awaited from the main isolate** — same GPU-context
/// constraint as every other function in `lib/render/gpu/`.
Future<bool> isGpuRenderAvailable() async {
  return _cached ??= await _probe();
}

bool? _cached;

Future<bool> _probe() async {
  try {
    const width = 8, height = 8;
    final bytes = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        bytes[i] = x * 255 ~/ (width - 1);
        bytes[i + 1] = y * 255 ~/ (height - 1);
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
    final source = await completer.future;

    final program = await ui.FragmentProgram.fromAsset(
      'shaders/_spike_passthrough.frag',
    );
    final shader = program.fragmentShader();
    shader.setFloat(0, width.toDouble());
    shader.setFloat(1, height.toDouble());
    shader.setImageSampler(0, source);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..shader = shader,
    );
    final outImage = await recorder.endRecording().toImage(width, height);
    final byteData = await outImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      return false;
    }
    final result = byteData.buffer.asUint8List();
    if (result.length != bytes.length) {
      return false;
    }
    var maxDiff = 0;
    for (var i = 0; i < result.length; i++) {
      final d = (result[i] - bytes[i]).abs();
      if (d > maxDiff) maxDiff = d;
    }
    return maxDiff <= 1;
  } catch (_) {
    return false;
  }
}
